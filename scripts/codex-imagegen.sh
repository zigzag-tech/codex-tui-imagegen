#!/usr/bin/env bash
# codex-imagegen.sh — generate images with Codex's built-in image_gen tool by
# driving a real Codex TUI inside a tmux pane.
#
# WHY a tmux pane and not `codex exec`: the native `image_gen` tool (the free,
# no-API-key OpenAI image model exposed through Codex's system `imagegen` skill)
# is ONLY available in the interactive TUI. `codex exec` cannot see it. So we
# keep a long-lived Codex TUI alive in a tmux pane and feed it prompts.
#
# Subcommands:
#   start                         spin up the tmux session + Codex TUI (idempotent)
#   gen "PROMPT" /path/out.png    generate one image, wait, copy newest PNG to out
#   status                        show session state + last generated images
#   stop                          kill the tmux session
#
# Env knobs:
#   CIG_SESSION   tmux session name        (default: codex-imagegen)
#   CIG_CWD       cwd Codex launches in     (default: /tmp)  — must be a trusted
#                 project in ~/.codex/config.toml so YOLO/full-auto needs no prompt
#   CIG_TIMEOUT   per-image wait, seconds   (default: 360 — generous because a
#                 flaky connection can burn 1–2 min on stream reconnects before
#                 inference even starts; bump higher for batches on bad networks)
set -uo pipefail

SESSION="${CIG_SESSION:-codex-imagegen}"
PANE="${SESSION}:0.0"
CWD="${CIG_CWD:-/tmp}"
TIMEOUT="${CIG_TIMEOUT:-360}"
GENDIR="$HOME/.codex/generated_images"

# Portable stat: GNU coreutils (Linux) uses `-c`, BSD (macOS) uses `-f`.
# Detect once so the script runs natively on both with no coreutils install.
if stat -c %Y . >/dev/null 2>&1; then
  _mtime(){ stat -c %Y "$1" 2>/dev/null || echo 0; }
  _size(){  stat -c %s "$1" 2>/dev/null || echo 0; }
else
  _mtime(){ stat -f %m "$1" 2>/dev/null || echo 0; }
  _size(){  stat -f %z "$1" 2>/dev/null || echo 0; }
fi

log(){ printf '%s\n' "$*" >&2; }

# Codex writes generated images as either exec-*.png (older) or ig_*.png (newer
# image_gen tool output). Match both, else gen() waits forever on a wrong glob.
newest_png(){ ls -t "$GENDIR"/*/exec-*.png "$GENDIR"/*/ig_*.png 2>/dev/null | head -1; }

session_live(){ tmux has-session -t "$SESSION" 2>/dev/null; }

cmd_start(){
  if session_live; then log "session '$SESSION' already up"; return 0; fi
  log "starting Codex TUI in tmux session '$SESSION' (cwd=$CWD)"
  # --dangerously-bypass-approvals-and-sandbox == full-auto / YOLO: no approval
  # prompts, so send-keys prompts run unattended. Requires the cwd be trusted.
  tmux new-session -d -s "$SESSION" -x 220 -y 50 -c "$CWD" \
    "codex --dangerously-bypass-approvals-and-sandbox"
  # Wait for the composer to be ready.
  for _ in $(seq 1 60); do
    sleep 1
    tmux capture-pane -p -t "$PANE" 2>/dev/null | grep -qiE 'send a message|ctrl|▌|⏎' && break
  done
  log "Codex TUI ready."
}

# Submit text to the composer. Long/multiline text is captured by the TUI as a
# single "[Pasted Content]" chunk that does NOT auto-submit — so we always send
# an explicit extra Enter after a short beat.
submit(){
  local text="$1"
  tmux send-keys -t "$PANE" -l "$text"
  sleep 0.4
  tmux send-keys -t "$PANE" Enter
  sleep 1.2
  # second Enter clears the "[Pasted Content]" staged-paste case
  tmux send-keys -t "$PANE" Enter
}

cmd_gen(){
  local prompt="$1" out="${2:-}"
  [ -n "$prompt" ] || { log "usage: gen \"PROMPT\" [/path/out.png]"; return 2; }
  session_live || cmd_start

  local before; before="$(newest_png)"
  local before_mtime=0
  [ -n "$before" ] && before_mtime="$(_mtime "$before")"

  # Force the image_gen path explicitly so the model doesn't answer in prose.
  submit "Use the image_gen tool to generate this image now. Do not write code, do not ask questions. Prompt: ${prompt}"

  log "waiting for a new image (timeout ${TIMEOUT}s)..."
  # Poll every 2s (was 4s): halves both detection latency and the post-write
  # stability wait, so a typical image returns ~4s sooner per call — adds up
  # across a batch.
  local found="" stable=0 last_size=-1 elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep 2; elapsed=$((elapsed+2))
    local cand; cand="$(newest_png)"
    if [ -n "$cand" ]; then
      local m; m="$(_mtime "$cand")"
      if [ "$m" -gt "$before_mtime" ]; then
        # wait until the file size stops changing (write finished)
        local sz; sz="$(_size "$cand")"
        if [ "$sz" = "$last_size" ] && [ "$sz" -gt 0 ]; then
          stable=$((stable+1))
          [ "$stable" -ge 2 ] && { found="$cand"; break; }
        else
          stable=0
        fi
        last_size="$sz"
      fi
    fi
  done

  [ -n "$found" ] || { log "TIMEOUT: no new image after ${TIMEOUT}s. Check: tmux attach -t $SESSION"; return 1; }
  log "generated: $found"

  if [ -n "$out" ]; then
    mkdir -p "$(dirname "$out")"
    cp "$found" "$out"
    log "copied -> $out"
    printf '%s\n' "$out"
  else
    printf '%s\n' "$found"
  fi
}

cmd_status(){
  if session_live; then log "session '$SESSION': UP"; else log "session '$SESSION': down"; fi
  log "latest generated images:"; ls -t "$GENDIR"/*/exec-*.png "$GENDIR"/*/ig_*.png 2>/dev/null | head -5 >&2 || log "  (none)"
}

cmd_stop(){ tmux kill-session -t "$SESSION" 2>/dev/null && log "killed '$SESSION'" || log "no session '$SESSION'"; }

case "${1:-}" in
  start)  cmd_start ;;
  gen)    shift; cmd_gen "${1:-}" "${2:-}" ;;
  status) cmd_status ;;
  stop)   cmd_stop ;;
  *) log "usage: codex-imagegen.sh {start|gen \"PROMPT\" [out.png]|status|stop}"; exit 2 ;;
esac
