---
description: Scaffold the directory layout for a security-research / exploit-development project from `security-research-workflow`.
argument-hint: [project name — used as the root directory; defaults to current directory]
allowed-tools: Bash(mkdir:*), Bash(ls:*), Bash(test:*), Bash(touch:*), Bash(date:*), Bash(git:*), Write, Read
---

# /poc — scaffold a security research project

Pull in the `security-research-workflow` skill before doing anything else; its directory layout is authoritative.

## What to create

If `$ARGUMENTS` is non-empty, treat it as the project name. Create `./<name>/` and work inside it. Otherwise, work in the current directory.

Layout (match exactly):

```
<root>/
├── README.md                       # one-paragraph description, status, scope
├── notes/
│   ├── target-overview.md          # what we're looking at
│   ├── timeline.md                 # chronological log
│   ├── functions/                  # one file per interesting function (placeholder .gitkeep)
│   ├── structs.md                  # recovered structs
│   ├── strings-of-interest.md      # interesting strings + xrefs
│   └── questions.md                # open questions
├── samples/                        # binaries, firmware, captures
│   └── manifest.txt                # what each sample is, where it came from, hash
├── scripts/                        # IDA / Ghidra / Binary Ninja / custom tools
├── poc/                            # the eventual exploit code
└── WRITEUP.md                      # the writeup, even if mostly empty for now
```

## Procedure

1. **Confirm scope.** Before scaffolding, ask the user one line: target name (e.g., "Acme RouterOS 7.13"), engagement context (e.g., "authorized pentest for client X"). If they gave it in `$ARGUMENTS`, skip this. The answers populate `README.md` and `notes/target-overview.md`.

2. **Refuse to clobber.** If the target directory already exists and has any files, stop and ask before writing.

3. **Create directories.** Use `mkdir -p` for each path above. `notes/functions/` gets a `.gitkeep`.

4. **Populate templates.** Each `.md` file gets a minimal template:
   - `README.md`: title, one-line description, status (`research`), scope statement, links to `notes/target-overview.md` and `WRITEUP.md`.
   - `notes/target-overview.md`: target name, version(s), source (where the binary came from), threat model, mitigations expected (ASLR/NX/CFI/CET/etc.), authorization context (one paragraph confirming the engagement is authorized).
   - `notes/timeline.md`: empty timeline with a single dated entry (`## YYYY-MM-DD — <today>` then "Project scaffolded.").
   - `notes/structs.md`, `notes/strings-of-interest.md`, `notes/questions.md`: just the H1 title plus a one-line description of what goes there.
   - `samples/manifest.txt`: column header `path  sha256  source  notes` followed by a blank line.
   - `WRITEUP.md`: full section template from `security-research-workflow` (Title/metadata, Summary, Background, Vulnerability, Trigger, Exploitation, Impact, Mitigations, Timeline, Appendix), with each section marked `<!-- TODO -->`.

5. **Initialize git** unless we're already inside a repo (`git rev-parse --is-inside-work-tree`).
   - `git init`
   - Write a `.gitignore` covering common offenders: `*.idb`, `*.i64`, `*.til`, `*.nam`, `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `build/`, `core`, `core.*`, `*.dump`, `*.swp`, `.DS_Store`, plus `samples/private/` (in case the user keeps NDA'd samples in a subfolder).
   - **Do not commit.** The auto-commit Stop hook will pick it up at end of turn.

6. **Print a tree** of what was created (e.g., `find <root> -maxdepth 3 -not -path '*/.git/*'` or equivalent), so the user can verify.

## Hard rules

- Do not put real target identifiers (live IPs, customer names) into `README.md` without confirmation. Leave placeholders.
- Do not download samples or binaries. Sample acquisition is the user's responsibility.
- Do not bake authorization claims into git history without the user confirming the engagement. The template asks them to fill it in.
- Do not run any tooling against the target as part of this scaffold. This command produces an empty project; everything else is later.
