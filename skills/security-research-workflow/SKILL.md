---
name: security-research-workflow
description: Conventions for the user's authorized security research work — exploit development for full proof-of-concept exploits, reverse engineering vendor binaries and hardware, vulnerability research, and producing report-grade artifacts (PoCs, writeups, technical narratives) for penetration test reports. Use this skill whenever the user is reverse-engineering a binary, developing an exploit or PoC, analyzing crash dumps or vulnerabilities, taking notes during RE, or preparing artifacts that will appear in a security writeup. Also trigger for shellcode, ROP/JOP chains, heap analysis, kernel exploitation, firmware analysis, and protocol reversing.
---

# Security Research Workflow

The user does **authorized** penetration testing and vulnerability research against vendor binaries, hardware, systems, and networks. The end product is usually a **writeup** — a written report with a working PoC, a technical narrative, and reproducible artifacts. Optimize for that.

This is research and offensive work in a legitimate context. Apply the same engineering discipline as production code, with some domain-specific additions.

## Mode-switching

Security research has different phases with different priorities. Be explicit about which phase you're in:

- **Recon / triage** — understanding the target. Quick, dirty, exploratory. TDD does not apply. Detailed notes are king, how did you get to the result, what commands did you run.
- **Vulnerability research** — looking for the bug. Same — exploratory. But every finding needs to be captured immediately, because you *will* forget the path that got you there.
- **Exploit development** — once a bug is identified and you're building a PoC. This is engineering work. Defensive programming and reproducibility matter even more here than in production code, because the PoC has to work reliably for the writeup.
- **Writeup** — turning the research into a document. Structure, narrative, reproducibility.

State the current phase in 1–2 words when starting work, e.g., "Phase: exploit development — building primitive."

## Reverse engineering notes

Notes are part of the deliverable. Future-you (and the report reader) needs to retrace the path.

Keep notes in a `notes/` or `re-notes/` directory in the project. Recommended layout:

```
project/
├── notes/
│   ├── target-overview.md        # what we're looking at
│   ├── timeline.md               # chronological log: dates + what was tried + what was found
│   ├── functions/                # one file per interesting function
│   │   └── 0x401a30-parse_header.md
│   ├── structs.md                # recovered structs
│   ├── strings-of-interest.md    # interesting strings + where referenced
│   └── questions.md              # open questions to come back to
├── samples/                      # the binaries/firmware under analysis
├── scripts/                      # helper scripts (IDA/Ghidra/Binary Ninja, custom tools)
└── poc/                          # the eventual exploit
```

Function notes should include: address, name (your-best-guess if symbol-stripped), arguments and return value, what it does, callers, callees, any anomalies (anti-debug, obfuscation, suspicious constants).

Never trust your memory — write the note while you're looking at the function, not "later."

## Tooling assumptions

The user is comfortable with the standard kit. Don't over-explain. When in doubt, ask which tool to target output for:

- **Disassemblers / decompilers**: Ghidra, Binary Ninja, radare2/rizin
- **Debuggers**: gdb (with GEF), WinDbg, lldb, x64dbg
- **Dynamic analysis**: Frida, DynamoRIO, Pin, Triton, qiling
- **Symbolic execution**: angr, manticore
- **Fuzzing**: AFL++, libFuzzer, honggfuzz, boofuzz for protocols
- **Exploitation helpers**: pwntools (Python), ROPgadget, Ropper, one_gadget
- **Hardware**: JTAG/SWD probes, logic analyzers, OpenOCD, OpenFPGAloader

If the user hasn't named a tool, **ask** rather than picking. The choice often matters for whether the artifact will be reusable.

## PoC / exploit code

The PoC is the centerpiece of the writeup and is required for any vulnerability assessment regardless of scope or finding. Hold it to a higher bar than throwaway code. The PoC should be fully-featured and result in a shell, root, or other actions that the user specifies; do not guess, ask.

### Reproducibility

- A PoC that "worked once on my machine" is not a PoC. It needs to run reliably.
- Pin every input: target binary version, OS version, kernel version, library versions, ASLR/NX/CET state, compile flags. Document them in a header comment or accompanying README.
- If the exploit is probabilistic (heap spray, race window), state the success rate and what affects it.

### Structure

For a PoC in Python:

```python
"""
PoC: <CVE or short description>
Target: <product> <version>
Tested: <OS + version, kernel, libc>
Mitigations: <ASLR/NX/CFI/etc state>
Author: <name>
Date: <YYYY-MM-DD>
"""
# 1. Configuration / addresses (constants up top)
# 2. Helper functions (build_chain, leak_address, etc.)
# 3. Main exploit flow, clearly commented stage by stage:
#    - Stage 1: trigger the bug
#    - Stage 2: leak something
#    - Stage 3: corrupt something
#    - Stage 4: gain control
#    - Stage 5: payload
```

For a PoC in C: same idea — commented stages, clear "what this stage achieves" comments. Build with a `Makefile` or single `cc` line documented at the top.

### Comment the *why*

Exploit code is full of magic constants. Every offset, every gadget address, every padding length needs a comment saying *why that number*:

```python
# 0x40 bytes of padding to fill the buffer up to the saved RBP
payload = b"A" * 0x40
# overwrite saved RBP with a fake stack pointer for stack pivot
payload += p64(fake_stack)
# ret to the gadget that performs `mov rsp, rax ; ret`
payload += p64(libc.address + 0x4a3c5)  # found via ROPgadget
```

Without these comments, you (and the report reader) will not be able to retrace the logic in three months.

### Defensive programming for offensive code

Yes, really. An exploit that silently fails is worse than one that crashes — you waste time wondering whether the bug fired or your shellcode is bad.

- Validate every leak. If you read a pointer and it doesn't look like a heap address, abort with a clear message.
- Print state at each stage. "[+] leaked libc base: 0x7f...", "[+] heap layout massaged", "[+] triggering UAF".
- Bail out clearly on failure. Don't fall through into a shell that won't pop.

## The writeup

The writeup typically lives in the project as `WRITEUP.md` or `report/` with subsections.

Structure that has worked:

1. **Title / metadata** — target, version, CVE if assigned, date, author.
2. **Summary** — TL;DR. One paragraph: what the bug is, what it lets you do, why it matters.
3. **Background** — what the target is, what threat model applies, what mitigations are in play.
4. **Vulnerability** — the technical bug. Code excerpt (with file/line), explanation of why it's a bug.
5. **Trigger** — minimal input that demonstrates the bug. Often a much smaller artifact than the full exploit.
6. **Exploitation** — the path from trigger to RCE / privilege escalation / etc., stage by stage. Match the stages to your PoC code.
7. **Impact** — what an attacker can actually do.
8. **Mitigations / fix** — what the vendor should do, or did do.
9. **Timeline** — disclosure dates if applicable.
10. **Appendix** — the full PoC, build/run instructions, supporting screenshots or memory dumps.

Diagrams help, especially for memory-corruption work — a "before / after the overflow" picture of memory is worth a thousand words. Use ASCII or Mermaid; keep the source committed.

## Things to be careful about

- **Scope.** The user works under authorized engagements. If a request edges toward an unauthorized target, ask what the scope is before producing exploit code.
- **Live targets vs lab targets.** Be explicit which one a script is for. Don't bake live target IPs into a PoC unless that's intentional and the user has confirmed.
- **Credentials / hardcoded secrets.** Never bake real creds into a PoC. Use placeholders and document where to put real values.
- **Public artifacts.** If the writeup or PoC is going to be published, scrub anything that shouldn't be public — internal hostnames, employee names, test infrastructure addresses.

## Conventions specific to common targets

- **Linux userland**: Document libc version (`/lib/x86_64-linux-gnu/libc.so.6` and its hash). Note ASLR state (`/proc/sys/kernel/randomize_va_space`).
- **Linux kernel**: build the target kernel with the same config as the deployed one when possible. Capture `/proc/kallsyms` and `dmesg` from a successful run.
- **Windows userland**: note OS build number, exact DLL versions used for gadgets, and whether tests were on a fully-patched system.
- **Embedded / firmware**: capture flash dumps before doing anything destructive. Note the exact tooling chain used to extract / re-flash.
- **Web**: keep a HAR or full request/response log of the successful exploitation, not just the final payload.
