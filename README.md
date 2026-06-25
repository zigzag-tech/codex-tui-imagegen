# codex-tui-imagegen

**Generate raster images for free** by driving [Codex](https://github.com/openai/codex)'s
**interactive TUI** inside a `tmux` pane to reach its built-in `image_gen` tool
(OpenAI's image model) — the tool that headless `codex exec` **can't see**.
**No `OPENAI_API_KEY`, no fal-ai, no paid image API.**

Use it for slide illustrations, hero images, concept art, mockups, textures,
sprites — anywhere you'd otherwise reach for a paid image endpoint.

It ships as an **agent skill** (`SKILL.md`) so coding agents like Claude Code,
Codex, Cursor, and others can invoke it automatically, but the underlying
`scripts/codex-imagegen.sh` is a plain CLI you can run by hand.

---

## The one gotcha that defines this whole tool

**The native `image_gen` tool only exists in the interactive Codex TUI.**
`codex exec` (headless) cannot see it and will fall back to writing code or
refusing. So the only reliable path is to keep a **real Codex TUI alive in a
`tmux` pane** and feed it prompts with `tmux send-keys`. That's exactly what
`scripts/codex-imagegen.sh` automates: `start` once, `gen` as many times as you
like, `stop` when done.

## Prerequisites

- **[Codex CLI](https://github.com/openai/codex)** installed and signed in
  (ChatGPT account or API key — the `image_gen` tool itself needs no extra key).
- **`tmux`**.
- **GNU coreutils** — the script uses `stat -c`, so it targets **Linux**. On
  macOS, install coreutils (`brew install coreutils`) and put GNU `stat` on
  `PATH`, or run it on a Linux box / container.
- A **trusted** launch directory in `~/.codex/config.toml`
  (`trust_level = "trusted"`) so full-auto needs no approval prompt. `/tmp` and
  `~` are already trusted by default; the script launches in `/tmp` unless you
  set `CIG_CWD`.

## Install

Clone anywhere, then optionally symlink it into your agent's skills directory:

```bash
git clone https://github.com/zigzag-tech/codex-imagegen.git
cd codex-imagegen

# Optional: link SKILL.md into ~/.codex/skills, ~/.claude/skills, ~/.cursor/skills, etc.
./scripts/install-skill-links.sh
```

`install-skill-links.sh` symlinks the skill into whichever known agent skill
directories already exist on your machine (Codex, Claude, Cursor, pi-agent, …).

## Usage

```bash
SKILL=./scripts/codex-imagegen.sh

# 1. spin up the long-lived Codex TUI (idempotent — safe to call repeatedly)
"$SKILL" start

# 2. generate one image and copy it to a named path
"$SKILL" gen "A friendly cartoon robot reading a paper receipt, flat vector \
style, warm gold-on-black palette, minimal background" \
  ./assets/ill-robot.png

# 3. when done with the whole batch
"$SKILL" stop
```

`gen` prints the destination path on stdout (or the raw `exec-*.png` path if you
omit the destination), so you can capture it:

```bash
OUT=$("$SKILL" gen "a glowing terminal window, isometric, gold accents" /tmp/term.png)
```

### Subcommands

| Command | What it does |
|---|---|
| `start` | Spin up the tmux session + Codex TUI (idempotent). |
| `gen "PROMPT" [out.png]` | Generate one image, wait for it, copy newest PNG to `out` (or print its path). |
| `status` | Show session state + last generated images. |
| `stop` | Kill the tmux session. |

### Environment knobs

| Var | Default | Meaning |
|---|---|---|
| `CIG_SESSION` | `codex-imagegen` | tmux session name. |
| `CIG_CWD` | `/tmp` | cwd Codex launches in — must be trusted in `~/.codex/config.toml`. |
| `CIG_TIMEOUT` | `360` | Per-image wait, seconds. Generous because a flaky connection can burn 1–2 min on stream reconnects before inference even starts. |

### Generating a batch

The same TUI session is reused, so `start` happens once:

```bash
"$SKILL" start
declare -A imgs=(
  [ill-engine]="a stylized engine block labeled LLM, gold-on-black, flat vector"
  [ill-context]="a window filling up with colored blocks, memory metaphor, gold-on-black"
  [ill-verify]="a magnifying glass over a checklist, gentle humor, gold-on-black"
)
for name in "${!imgs[@]}"; do
  "$SKILL" gen "${imgs[$name]}" "./assets/${name}.png"
done
"$SKILL" stop
```

## How it works

Output lands at `~/.codex/generated_images/<session-uuid>/exec-*.png`. The script
gates on a PNG whose mtime is newer than the pre-existing newest one and whose
size has stopped changing, then copies it to your destination. A batch of N
images can take ~7–15 min; each single image is ~30–120s of inference.

Hard-won facts baked into the script:

- `codex -p` is `--profile`, **not** a prompt flag — don't use it to pass prompts.
- Long/multiline prompts get captured by the TUI as a single `[Pasted Content]`
  chunk that **does not auto-submit** — the script always sends an extra Enter.
- If a `gen` times out but the pane shows "Generated Image", the connection
  dropped the image bytes mid-download — just re-run `gen` (a fresh `start`
  clears a wedged reconnect state).

## Verify what you got — don't trust it blind

The model can crop, misread, or stylize wrong. **Always look at the output**
before wiring it into a deck or page. For themed batches, repeat the
palette/style clause in every prompt (e.g. `warm gold #f8ba00 on near-black
background, flat vector, minimal`) — the model has no memory across calls beyond
the conversation in the pane, so being explicit each time keeps a batch coherent.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `gen` times out, no new PNG | `tmux attach -t codex-imagegen` and look — likely an approval prompt (cwd not trusted) or the model answered in prose. Trust the cwd in `~/.codex/config.toml`, or re-run `start` with `CIG_CWD=/tmp`. |
| Prompt sat as `[Pasted Content]`, never ran | The script's extra-Enter handles this; if attaching manually, press Enter twice. |
| Model wrote code instead of an image | The prompt must say *use the image_gen tool*; the script forces this. |
| Picks up an old image | The script gates on mtime newer than the pre-existing newest PNG; if confused, `stop` then `start` fresh. |

Detach from an attached pane with `Ctrl-b d` (never `Ctrl-c` — that kills Codex).

## License

[MIT](./LICENSE) © Zigzag Technologies, Inc.
