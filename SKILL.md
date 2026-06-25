---
name: codex-imagegen
description: >
  Generate illustrations/images for free using Codex's built-in image_gen
  tool (OpenAI's latest image model) by driving a Codex TUI inside a tmux
  pane. Use when you need raster images — slide illustrations, hero images,
  concept art, mockups, textures, sprites — and want to avoid paid APIs
  (fal-ai, gpt-image API). No OPENAI_API_KEY needed.
  Triggers: "generate an image/illustration", "make a picture", "用 codex
  生成图片/插图", "give the deck some illustrations", "draw me a ...".
---

# Codex image generation (via tmux pane)

Codex ships a system `imagegen` skill that exposes a **built-in `image_gen`
tool** — OpenAI's latest image model, **free, no `OPENAI_API_KEY`, no fal-ai**.
This is the preferred way to make raster illustrations.

## The one gotcha that defines this whole skill

**The native `image_gen` tool only exists in the interactive Codex TUI.**
`codex exec` (headless) cannot see it and will fall back to writing code or
refusing. So the only reliable path is: keep a **real Codex TUI alive in a
tmux pane** and feed it prompts with `tmux send-keys`. That's what the helper
script automates.

Other hard-won facts:
- `codex -p` is `--profile`, **not** a prompt flag. Don't use it to pass prompts.
- Long/multiline prompts get captured by the TUI as a single `[Pasted Content]`
  chunk that **does not auto-submit** — you must send an **extra Enter**. The
  script always does this.
- Output lands at `~/.codex/generated_images/<session-uuid>/`, named either
  `exec-*.png` (older Codex) or `ig_*.png` (newer `image_gen` tool). The helper
  matches **both** globs; if you copy by hand, glob both. (A stale `exec-*`-only
  match is what made `gen` hang forever while the pane already showed "Generated".)
- A batch of N images can take ~7–15 min; each single image ~30–120s of
  inference — but a flaky connection can add 1–2 min of stream reconnects
  *before* inference starts, so the per-image wait defaults to 360s. If a `gen`
  times out but the pane shows "Generated Image", the connection dropped the
  image bytes mid-download — just re-run `gen` (a fresh `start` clears a wedged
  reconnect state).
- Codex must launch in a **trusted** cwd (see `~/.codex/config.toml`,
  `trust_level = "trusted"`) so full-auto/YOLO needs no approval prompt.
  `/tmp` and `~` are already trusted.

## Quick start

```bash
SKILL=~/xc-setup/skills/codex-imagegen/scripts/codex-imagegen.sh

# 1. spin up the long-lived Codex TUI (idempotent — safe to call repeatedly)
"$SKILL" start

# 2. generate one image and copy it to a named path
"$SKILL" gen "A friendly cartoon robot reading a paper receipt, flat vector \
style, warm gold-on-black palette, minimal background" \
  /home/ubuntu/myproject/assets/ill-robot.png

# 3. when done with the whole batch
"$SKILL" stop
```

`gen` prints the destination path on stdout (or the raw `exec-*.png` path if you
omit the destination), so you can capture it:

```bash
OUT=$("$SKILL" gen "a glowing terminal window, isometric, gold accents" /tmp/term.png)
```

## Generating a batch

Call `gen` in a loop — the same TUI session is reused, so `start` happens once:

```bash
"$SKILL" start
declare -A imgs=(
  [ill-engine]="a stylized engine block labeled LLM, gold-on-black, flat vector"
  [ill-context]="a window filling up with colored blocks, memory metaphor, gold-on-black"
  [ill-verify]="a magnifying glass over a checklist, gentle humor, gold-on-black"
)
for name in "${!imgs[@]}"; do
  "$SKILL" gen "${imgs[$name]}" "/home/ubuntu/myproject/assets/${name}.png"
done
"$SKILL" stop
```

## Verify what you got — don't trust it blind

The model can crop, misread, or stylize wrong. **Always look at the output**
before wiring it into a deck/page. Either open it with the Read tool (it renders
images) or, for slides, render the page and view it with `agent-browser`. A
common failure: a landscape image placed in a `![bg right:N%]` Marp slot gets
cover-cropped — check for cut-off subjects and switch to a contained `![w:...]`
two-column layout if so.

## Style consistency

For a themed deck, repeat the palette/style clause in every prompt (e.g.
`warm gold #f8ba00 on near-black background, flat vector, minimal`). The model
has no memory of earlier images across calls beyond the conversation in the
pane, so being explicit each time keeps a batch coherent.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `gen` times out, no new PNG | `tmux attach -t codex-imagegen` and look — likely an approval prompt (cwd not trusted) or the model answered in prose. Add the cwd to `~/.codex/config.toml` as trusted, or re-run `start` with `CIG_CWD=/tmp`. |
| Prompt sat as `[Pasted Content]`, never ran | The script's extra-Enter handles this; if attaching manually, press Enter twice. |
| Model wrote code instead of an image | The prompt must say *use the image_gen tool*; the script forces this. |
| Picks up an old image | The script gates on mtime newer than the pre-existing newest PNG, so this shouldn't happen; if confused, `stop` then `start` fresh. |

Detach from an attached pane with `Ctrl-b d` (never `Ctrl-c` — that kills Codex).
