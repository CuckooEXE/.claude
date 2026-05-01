---
name: protocol-and-format-reversing
description: Conventions for reverse-engineering binary file formats, network protocols, and IPC wire formats — capture, hexdump-then-sketch-grammar workflow, Kaitai Struct / 010 Editor / ImHex / Wireshark dissectors, scapy for protocol fuzzing/replay, and how to produce parser code and writeup-grade artifacts. Sibling of `security-research-workflow`. Use this skill whenever the user is reversing a file format, dissecting a network protocol, building a parser for an undocumented format, or writing fuzz harnesses for one.
---

# Protocol and Format Reversing

This is a sibling of `security-research-workflow` for one specific class of work: figuring out the shape of bytes you didn't design. Common targets: vendor file formats, embedded firmware containers, custom binary protocols on TCP/UDP/USB/RF, IPC blobs, save files, save-game encryption layers.

## Phase model

Roughly the same phases as general security research, specialized:

1. **Capture** — collect representative samples or traffic.
2. **Survey** — `xxd`, `binwalk`, `entropy`, `strings`, magic-bytes lookup. Pattern-match before parsing.
3. **Sketch the grammar** — by hand, in a text file, comparing samples. Find length fields, magic numbers, fixed offsets.
4. **Formalize** — Kaitai Struct, 010 Editor template, or ImHex pattern. Now the grammar is machine-checkable against samples.
5. **Build the parser** — the "real" code that the project will use, based on the formalization.
6. **Validate / fuzz** — round-trip tests, then fuzz against the formalization.

## Capture

### Files
- Get **multiple** samples. One sample tells you nothing about which fields vary.
- Capture metadata: source, version, what created it, what consumed it. Without provenance the samples are noise.
- Store samples under `samples/` in the project, with a `samples/manifest.txt` describing each one.
- Don't normalize, don't decompress, don't pre-process. Keep originals byte-exact.

### Network protocols
- **Wireshark / tshark** for capture. PCAP format. Save the raw `.pcap`, not just screenshots.
- **mitmproxy** for HTTPS / HTTP/2 / gRPC where TLS interception is in scope.
- **Frida + send/recv hooks** for pulling decrypted plaintext out of a client without breaking TLS.
- For USB: `usbmon` (Linux) → Wireshark.
- For RF / SDR: capture as IQ samples at the lowest layer you can; demodulation can happen later.
- Capture **both directions** of a conversation. One side is half a protocol.

### IPC / shared memory / kernel
- `bpftrace`, `eBPF`, or `perf trace` to see syscalls and their payloads.
- For shared memory: a small ptrace-based tool or LD_PRELOAD shim that snapshots regions.

## Survey: what to do before opening a hex editor

Run these on every sample, save the output:

```
file <sample>
xxd <sample> | head -50
xxd <sample> | tail -50
binwalk -B <sample>           # signature scan
binwalk -E <sample>            # entropy graph
strings -n 6 <sample>           # printable strings
strings -el <sample>            # UTF-16LE strings (Windows artifacts often)
```

What to look for:
- **Magic bytes** at offset 0 — `file`/`binwalk` will tell you if it's a known format.
- **Container layers** — entropy graph with a flat-then-high transition often means header + compressed/encrypted body.
- **String tables** at the end — common pattern.
- **Repeated structures** — visible as visual patterns in `xxd`.
- **Length-then-data** patterns — the most common encoding decision in binary formats.

## Sketching the grammar by hand

Open a `notes/grammar.md`. For each sample, write:

```
sample: foo-v1.bin (size 0x4f30)

offset  size  field            value (hex)              meaning
------  ----  ---------------  -----------------------  -------------------
0x00    4     magic            "FOOO"                   header magic
0x04    2     version          0x0001                   v1
0x06    2     flags            0x0040                   bit 6 = "compressed"?
0x08    4     payload_offset   0x00000020               points to 0x20
0x0c    4     payload_size     0x00004f08               total minus header
0x10    16    reserved?        all zeros                ???
0x20    ...   payload
```

Then take a different sample and align the same table. Disagreements between samples are where the *real* fields are.

Color-code (or mark) categories:
- **Confirmed** — field meaning verified by mutating it and observing behavior change.
- **Probable** — pattern strongly suggests this meaning, but not yet verified.
- **Guess** — best effort but wobbly.
- **Unknown** — bytes we can't explain. Mark them. Don't paper over.

## Formalize with a parser definition

Once the grammar is roughly stable, encode it in a definition language.

### Kaitai Struct

`.ksy` YAML files. Generates parsers in many languages. Best when the format is stable enough to want code generation:

```yaml
meta:
  id: foo_format
  endian: le
seq:
  - id: magic
    contents: 'FOOO'
  - id: version
    type: u2
  - id: flags
    type: u2
  - id: payload_offset
    type: u4
  - id: payload_size
    type: u4
  - id: reserved
    size: 16
  - id: payload
    size: payload_size
```

Visualize with the Kaitai Web IDE — drag a sample in, watch the structure light up. Best feedback loop in this entire space.

### 010 Editor templates

`.bt` C-like. Best when you want a *visual* tree-view of a parsed file in 010 Editor (commercial, but cheap and excellent).

### ImHex patterns

`.hexpat` — open-source 010-style. ImHex is a great free alternative; the pattern language is nice.

### Wireshark dissectors

For network protocols, write a Lua dissector and drop it in `~/.local/lib/wireshark/plugins/`. Live decoding in Wireshark while you capture is unbeatable.

## Verifying the grammar

A grammar is unverified until you've done at least one of these:

1. **Round-trip a sample.** Parse it, reserialize, byte-for-byte compare. If it doesn't match, the grammar is wrong (or there's a CRC / hash field you missed).
2. **Mutate a field, observe behavior change.** Change `flags` and run the sample through the consumer. Does behavior match your guess?
3. **Cross-sample alignment.** Apply the grammar to N samples; if any fail, the grammar is incomplete.

Write these as actual scripts (in `scripts/`), not as one-off commands. A repeatable grammar test is gold for the writeup.

## Common encoding patterns to recognize on sight

- **TLV (Type-Length-Value)** — `[type:1][length:varint][value:length]`. Parsing one is the same loop in every protocol.
- **LV (Length-Value)** — Pascal-style strings, length-prefixed buffers.
- **Magic + version + offset table** — most container formats.
- **Length followed by data** — count fields, array headers.
- **CRC at the end of structure** — common; usually CRC32, sometimes CRC16. Compute candidates and check.
- **Checksum at the start** of the *rest* of the structure — Microsoft loves this.
- **Reserved/padding** to align to 4 or 8 bytes — assume padding before claiming a field.
- **Flags field** as a bitfield — single bytes/words where each bit toggles behavior. Correlate with sample mutations.
- **Variable-length integers (varint, ULEB128)** — common in modern formats and in protobuf-derived stuff.
- **UTF-16LE strings on Windows formats**, UTF-8 elsewhere.
- **Endianness** — most embedded is little-endian (ARM, x86); network protocols often big-endian; check both before assuming.

## Compression / encryption layers

Recognize when you're not looking at the raw format yet:

- **High entropy across the body** → compressed or encrypted. Try common compressors first: zlib (`78 9c`, `78 da`), LZMA (`5d 00 00`), LZ4 magic, Zstd magic.
- **Low entropy at the start, high after** → header + compressed body. Common.
- **Visible structure but values shifted** → simple XOR with a key. Try short keys (1, 2, 4 bytes) by XOR-ing against expected magic bytes.
- **Repeating block-sized patterns at exactly 16/32 bytes** → block cipher (AES) in ECB mode. Big tell.
- **Chains where flipping a byte changes only that byte's vicinity** → CBC (or stream cipher).

## scapy for network protocols

Once you have a grammar, `scapy` lets you:
- Reproduce a captured exchange (replay).
- Mutate fields and resend (mini-fuzzing).
- Build new packets that follow the protocol you reversed.

```python
class FooHeader(Packet):
    name = "Foo"
    fields_desc = [
        ShortField("version", 1),
        FlagsField("flags", 0, 16, ["a", "b", "c"]),
        IntField("length", 0),
    ]
bind_layers(TCP, FooHeader, dport=4242)
```

For non-IP protocols, scapy supports raw layers — useful for USB or serial reversing.

## Writing the parser

Once formalized, write a real parser in the project's language. Conventions:

- **One module per format.** `parsers/foo.py`, `parsers/foo.h` + `parsers/foo.c`. Don't sprawl.
- **Validate at the boundary.** Length fields → bounds-check before reading. Offsets → confirm they're inside the buffer. This is the trust boundary par excellence.
- **Fail loud.** A parser that returns silently on truncated input is worse than one that throws — silent failure on untrusted input is how RCEs happen.
- **Round-trip if possible.** A `parse()` + `serialize()` pair that produces identical bytes is a strong correctness check and helps with mutation-based fuzzing.
- **Don't trust the source.** Even if you wrote the producer, treat the bytes coming back as adversarial. The whole point of this skill's existence is that bytes lie.

## Fuzzing the parser

Anything you parse from untrusted input gets a fuzz harness. Default toolchain:

- **AFL++** for whole-program / file-format fuzzing.
- **libFuzzer** + **clang -fsanitize=fuzzer,address,undefined** for a function-level harness.
- **Atheris** for Python parsers.
- **boofuzz** for stateful network protocols.

Seed corpus = the samples you collected during reversing. Save the corpus to `fuzz/corpus/`. Crash artifacts → `fuzz/crashes/`. Triage every crash.

## Things to avoid

- **Premature parser code.** Sketch the grammar in markdown first. Code crystallizes mistakes.
- **Skipping samples.** A grammar derived from one sample is a hypothesis, not a parser.
- **Trusting field-name guesses.** Mark them as guesses until verified. Future-you will read your notes literally.
- **Overlooking endianness, signed/unsigned, alignment.** Every binary format has at least one trap here.
- **Building a parser without a fuzz harness** when the input is untrusted. Self-defeating.
- **Discarding the producer / consumer.** Even if you can't read the disassembly, you can mutate samples and observe the consumer's reaction — that's free oracle.

## Cross-references

- See `security-research-workflow` for note-taking layout, writeup structure, and PoC conventions.
- See `cli-tool-design` if the parser ships as a CLI.
- See `software-engineering-practices` for fuzzing as part of the test suite.
