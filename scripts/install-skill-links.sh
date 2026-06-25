#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

candidate_dirs=(
  "$HOME/.codex/skills"
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
  "$HOME/.cursor/skills-cursor"
  "$HOME/.cursor/skills"
  "$HOME/.pi/skills"
  "$HOME/.config/pi-agent/skills"
)

linked=0
for dir in "${candidate_dirs[@]}"; do
  if [[ -d "$dir" ]]; then
    target="$dir/$SKILL_NAME"
    if [[ -L "$target" || ! -e "$target" ]]; then
      ln -sfn "$SKILL_DIR" "$target"
      echo "linked $target -> $SKILL_DIR"
      linked=1
    else
      echo "skipped existing non-symlink: $target" >&2
    fi
  fi
done

if [[ "$linked" == "0" ]]; then
  echo "No known agent skill directories found. Create one, then rerun this script." >&2
  exit 1
fi
