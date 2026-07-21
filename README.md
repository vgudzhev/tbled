# 🔆 glowbar

**Your Claude Code sessions, glowing on the MacBook Pro Touch Bar.**

![glowbar live on the Touch Bar](assets/keyled.png)

One colored tile per session. A single glance tells you which Claude is heads-down,
which is waiting on *you*, and which is already done — no more `Cmd-Tab`-ing through
a stack of terminals to find the one that needs you.

| | Colour | Means |
|--|--------|-------|
| 🔴 | red | **working** — thinking, running tools, editing |
| 🟡 | yellow | **waiting on you** — a permission prompt or a question |
| 🟢 | green | **ready** — turn finished, idle |
| ⚪ | dim | **stale** — quiet for 20+ min, probably abandoned |

▶️ **[Watch the 20-second demo](assets/demo.mp4)**

> Inspired by [cled](https://github.com/latent-spaces/cled) (same idea for RGB
> keyboards). glowbar drives it from **Claude Code hooks** — no terminal scraping,
> no polling, no daemon.

---

## ⚡ Install — one command

You'll need a Mac with a Touch Bar, [Claude Code](https://claude.com/claude-code),
`jq`, and Xcode Command Line Tools (`xcode-select --install`).

```sh
curl -fsSL https://raw.githubusercontent.com/vgudzhev/glowbar/main/install.sh | bash
```

That clones glowbar to a temp dir, wires the hooks into **every** `~/.claude*`
config dir it finds, builds + signs the Touch Bar app on *your* machine, turns it
on, then deletes the clone. Re-runnable.

Prefer to read before you pipe? Same thing, in two lines:

```sh
curl -fsSL https://raw.githubusercontent.com/vgudzhev/glowbar/main/install.sh -o glowbar-install.sh
bash glowbar-install.sh
```

**Homebrew?** Put the commands on your PATH, then one line finishes setup:

```sh
brew install vgudzhev/tools/glowbar
glowbar setup      # wire hooks + build the app + turn it on
```

Start a Claude Code session — a tile appears. **That's it.** ✨

<details>
<summary><b>Or install by hand (three steps)</b></summary>

```sh
git clone https://github.com/vgudzhev/glowbar
cd glowbar

# 1. Wire glowbar into Claude Code (backs up your settings first, re-runnable)
./bin/glowbar install --config-dir ~/.claude

# 2. Build the Touch Bar app (one-time, ~2 min)
./bin/glowbar-app build ./app

# 3. Light it up
./bin/glowbar-app on
```

> Using custom config dirs? Pass them (repeatably):
> `--config-dir ~/.claude-personal --config-dir ~/.claude-work`.
</details>

> **Why not a `.dmg`?** glowbar is half CLI (hooks that merge into your
> `settings.json`) and half app — a drag-to-Applications DMG can't do the hook
> half. And building on your own Mac is what lets the app's Accessibility grant
> stick. So a script that builds locally beats a prebuilt download here.

**Make it one word** — drop this in your `~/.zshrc`:

```sh
export PATH="$HOME/.glowbar/bin:$PATH"
alias gb='glowbar-app toggle'
```

Now **`gb`** flips glowbar on and off from anywhere.

---

## 🎯 Use it

- **Tap a tile** → jump straight to that session's terminal — Terminal, iTerm, VS
  Code, IntelliJ, whatever — even across a fullscreen Space. *(First tap asks for
  Accessibility + Automation; allow once — see below.)*
- **`gb`** → toggle the whole strip on/off.
- **`glowbar status`** → the same tiles, right in your terminal.
- **Same repo, two sessions?** Tiles show each session's name and honour `/rename`,
  so they never look like twins.
- **Started a session *before* installing?** It still shows up — `glowbar sync`
  reads Claude's own live session list too.

### 🔑 Permissions (for tap-to-focus)

System Settings → Privacy & Security:

- **Accessibility** — add **glowbar** (`~/.glowbar/glowbar.app`) and toggle it on.
  Required to jump across fullscreen / Spaces.
- **Automation** — no setup; macOS just prompts the first time you tap a Terminal
  or iTerm tile. Click **Allow**.

---

## 🧠 How it works

```
Claude Code sessions            glowbar
   │ hooks write state             │ reads + renders
   ▼                               ▼
~/.glowbar/sessions/*.json  ◄──  Touch Bar · menu bar · glowbar status
```

Claude Code fires a hook on every event (start, prompt, tool use, notification,
stop). A tiny script maps it to a state and writes the session's JSON file; the
renderers just read it. No daemon, no scraping.

The careful part is **refusing to lie**: a subagent finishing mid-turn, or a
context compaction, must never flip a red "working" tile to green. Those are
treated as keep-alive only.

---

## 🛠 More

<details>
<summary><b>Touch Bar layout & the menu-bar mirror</b></summary>

By default glowbar takes over the Touch Bar's **app region** (replacing the focused
app's own buttons). Prefer a compact dot in the Control Strip? `GLOWBAR_TOUCHBAR_MODE=strip glowbar-app on`.

It also mirrors the tiles as coloured dots + names in the **menu bar** — the
always-works fallback, and handy on Macs without a Touch Bar.
</details>

<details>
<summary><b>No compiling: the MTMR widget</b></summary>

Don't want to build the Swift app? A one-line [MTMR](https://github.com/Toxblh/MTMR)
shell widget renders the same strip with zero compilation — see
[`mtmr/README.md`](mtmr/README.md).
</details>

<details>
<summary><b>CLI reference</b></summary>

```
glowbar setup       one-shot: wire hooks (all ~/.claude* dirs) + build + on
glowbar status      live session tiles in the terminal (auto-syncs)
glowbar sync        import Claude's own live sessions (works without hooks)
glowbar install     wire hooks into settings.json (backs up, idempotent)
glowbar uninstall   remove them again
glowbar reap        drop dead / expired session files
glowbar dir         print the state dir (~/.glowbar)

glowbar-app on|off|toggle|restart|status
glowbar-app build ./app     build + sign the .app bundle
```

Uninstall everything: `./bin/glowbar uninstall --config-dir ~/.claude` then
`rm -rf ~/.glowbar`.
</details>

<details>
<summary><b>Tuning (environment variables)</b></summary>

| Variable | Default | Meaning |
|----------|---------|---------|
| `GLOWBAR_DIR` | `~/.glowbar` | state directory |
| `GLOWBAR_STALE_SECS` | `1200` | inactivity → dim |
| `GLOWBAR_HIDE_SECS` | `7200` | inactivity → hidden |
| `GLOWBAR_TOUCHBAR_MODE` | `app` | `app` (takeover) or `strip` (control-strip dot) |
</details>

<details>
<summary><b>Layout</b></summary>

```
bin/glowbar        CLI: status / sync / install / uninstall / reap
bin/glowbar-hook   the hook handler (one script, all events)
bin/glowbar-app    build + on/off control for the native app
mtmr/              MTMR Touch Bar widget (no build)
app/               native SwiftPM app (GlowbarCore + CDFR shim)
```
</details>

---

*Built for the Touch Bar Apple abandoned and I apparently never will.*
