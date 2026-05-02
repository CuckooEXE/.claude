#!/usr/bin/env bash
# install-global.sh — install this claude-template into ~/.claude/.
#
# Idempotent: safe to re-run after pulling template updates. Files identical
# to source are skipped; existing CLAUDE.md and settings.json are backed up
# with a timestamp suffix before being replaced.
#
# What gets installed:
#   - CLAUDE.md                          -> ~/.claude/CLAUDE.md
#   - settings.json (with path rewrite)  -> ~/.claude/settings.json
#   - hooks/*.sh                         -> ~/.claude/hooks/   (chmod +x)
#   - skills/*/SKILL.md                  -> ~/.claude/skills/
#   - commands/*.md (init-claude.md and  -> ~/.claude/commands/
#     timeline.md get path rewrites)
#   - agents/*.md                        -> ~/.claude/agents/
#   - templates/*                        -> ~/.claude/templates/
#
# What's preserved (never touched):
#   - ~/.claude/projects/                (per-project sessions / memory)
#   - ~/.claude/memory/                  (auto-memory)
#   - ~/.claude/MEMORY.md
#   - ~/.claude/settings.local.json
#   - any files inside ~/.claude/{commands,skills,agents,templates,hooks}/
#     that aren't also present in this template (custom additions stay)
#
# Path rewrites:
#   - settings.json:           $CLAUDE_PROJECT_DIR/.claude/hooks/  ->  $HOME/.claude/hooks/
#   - commands/init-claude.md: `templates/`                        ->  `$HOME/.claude/templates/`
#   - commands/timeline.md:    `templates/`                        ->  `$HOME/.claude/templates/`
#
# Flags:
#   --dry-run    show what would change, don't apply
#   --force      skip the interactive confirmation
#   -h, --help   show this header

set -euo pipefail

DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            echo "usage: $0 [--dry-run] [--force]" >&2
            exit 2
            ;;
    esac
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${HOME}/.claude"
TS="$(date +%Y%m%d-%H%M%S)"

# Sanity: we should be at the template worktree root.
for required in CLAUDE.md settings.json hooks skills commands agents templates; do
    if [ ! -e "$SRC/$required" ]; then
        echo "error: $SRC does not look like a claude-template worktree (missing $required)" >&2
        exit 1
    fi
done

declare -a actions=()
note() { actions+=("$1"); }

# Run a command, or just print it under --dry-run.
do_cmd() {
    if [ "$DRY_RUN" = 1 ]; then
        printf 'DRY: '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# Copy src -> dst only if different. Optionally back up dst before overwriting.
# Args: src dst [backup=0|1]
copy_with_backup() {
    local src="$1" dst="$2" backup="${3:-0}" name
    name="${dst#$DEST/}"
    if [ -f "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            note "$name unchanged"
            return 0
        fi
        if [ "$backup" = 1 ]; then
            do_cmd cp "$dst" "$dst.bak.$TS"
            note "$name updated (backup at $name.bak.$TS)"
        else
            note "$name updated"
        fi
    else
        note "$name installed"
    fi
    do_cmd cp "$src" "$dst"
}

# Confirmation prompt.
if [ "$DRY_RUN" = 0 ] && [ "$FORCE" = 0 ]; then
    echo "Source: $SRC"
    echo "Target: $DEST"
    echo
    echo "CLAUDE.md and settings.json will be backed up with .bak.$TS suffix"
    echo "if they exist and differ. Other directories are merge-installed."
    echo
    read -r -p "Continue? [y/N] " confirm
    case "$confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "aborted"; exit 0 ;;
    esac
fi

do_cmd mkdir -p "$DEST"

# --- 1. CLAUDE.md (with backup) ---
copy_with_backup "$SRC/CLAUDE.md" "$DEST/CLAUDE.md" 1

# --- 2. settings.json (with backup + path rewrite) ---
# Rewrite hook paths from project-style ($CLAUDE_PROJECT_DIR/.claude/hooks/)
# to user-style ($HOME/.claude/hooks/).
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
sed 's#\$CLAUDE_PROJECT_DIR/\.claude/hooks/#\$HOME/.claude/hooks/#g' \
    "$SRC/settings.json" > "$TMP"
copy_with_backup "$TMP" "$DEST/settings.json" 1
rm -f "$TMP"
trap - EXIT

# --- 3. hooks/ (chmod +x after) ---
do_cmd mkdir -p "$DEST/hooks"
for hook in "$SRC"/hooks/*.sh; do
    [ -e "$hook" ] || continue
    name="$(basename "$hook")"
    copy_with_backup "$hook" "$DEST/hooks/$name" 0
    do_cmd chmod +x "$DEST/hooks/$name"
done

# --- 4. skills/ (preserve dir-per-skill) ---
do_cmd mkdir -p "$DEST/skills"
for skill_dir in "$SRC"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    do_cmd mkdir -p "$DEST/skills/$skill_name"
    if [ -f "$skill_dir/SKILL.md" ]; then
        copy_with_backup "$skill_dir/SKILL.md" "$DEST/skills/$skill_name/SKILL.md" 0
    fi
done

# --- 5. commands/ (patch init-claude.md and timeline.md) ---
do_cmd mkdir -p "$DEST/commands"
for cmd in "$SRC"/commands/*.md; do
    [ -e "$cmd" ] || continue
    name="$(basename "$cmd")"
    case "$name" in
        init-claude.md|timeline.md)
            TMP="$(mktemp)"
            trap 'rm -f "$TMP"' EXIT
            sed 's#`templates/#`$HOME/.claude/templates/#g' "$cmd" > "$TMP"
            copy_with_backup "$TMP" "$DEST/commands/$name" 0
            rm -f "$TMP"
            trap - EXIT
            ;;
        *)
            copy_with_backup "$cmd" "$DEST/commands/$name" 0
            ;;
    esac
done

# --- 6. agents/ ---
do_cmd mkdir -p "$DEST/agents"
for agent in "$SRC"/agents/*.md; do
    [ -e "$agent" ] || continue
    name="$(basename "$agent")"
    copy_with_backup "$agent" "$DEST/agents/$name" 0
done

# --- 7. templates/ ---
do_cmd mkdir -p "$DEST/templates"
for tpl in "$SRC"/templates/*; do
    [ -e "$tpl" ] || continue
    name="$(basename "$tpl")"
    copy_with_backup "$tpl" "$DEST/templates/$name" 0
done

# --- Summary ---
echo
echo "================================================================="
if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN — nothing was applied. Re-run without --dry-run to install."
else
    echo "Install summary:"
fi
echo "================================================================="
if [ "${#actions[@]}" -eq 0 ]; then
    echo "  (no changes)"
else
    printf '  %s\n' "${actions[@]}"
fi
echo
if [ "$DRY_RUN" = 0 ]; then
    echo "Source: $SRC"
    echo "Target: $DEST"
    echo
    echo "Path rewrites applied to:"
    echo "  $DEST/settings.json"
    echo "  $DEST/commands/init-claude.md"
    echo "  $DEST/commands/timeline.md"
    echo
    echo "Existing CLAUDE.md / settings.json (if any) backed up with .bak.$TS suffix."
    echo "Old backups can be removed manually: ls $DEST/*.bak.*"
fi
