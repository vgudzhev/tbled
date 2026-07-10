# glowbar — Claude Code status lights on the MacBook Pro Touch Bar

One coloured tile per Claude Code session, live on the Touch Bar (or the menu
bar, or MTMR). Inspired by [cled](https://github.com/latent-spaces/cled), which
does the same for RGB keyboards via OpenRGB — glowbar adapts the idea to the 2019
MacBook Pro Touch Bar and drives it from **Claude Code hooks** instead of
scraping terminals.

```
🔴 my-api    🟡 webapp    🟢 infra
 working      waiting      ready
```

| Colour | State    | Meaning                                                    |
|--------|----------|------------------------------------------------------------|
| 🔴 red    | working  | Claude is mid-turn (thinking, running tools, editing)      |
| 🟡 yellow | waiting  | blocked on you (permission prompt / question)              |
| 🟢 green  | ready    | turn finished, session idle                                |
| ⚪ dim    | stale    | no activity for > 20 min (probably abandoned)              |

## Features

- **Live status at a glance** — Know the state of all Claude Code sessions without switching windows
- **Multiple sessions** — Track 3+ projects simultaneously with color-coded tiles
- **Smart state detection** — Automatically detects working/waiting/ready/stale states from hook events
- **Touch Bar + Menu Bar** — Renders on Touch Bar (primary) with menu bar fallback for non-Touch-Bar Macs
- **Session names** — Tiles show each session's name (honours `/rename`; otherwise Claude's derived name), so two sessions in the same repo stay distinct
- **Catches every session** — `glowbar sync` also reads Claude's own live session files, so sessions started *before* you installed the hooks (or in a config dir without them) still show up (busy/waiting/idle → 🔴/🟡/🟢)
- **Tap to focus** — Click a tile to jump to that session's terminal — Terminal/iTerm select the exact tab; VS Code, IntelliJ and other hosts focus the app window (found by walking the session's process tree). Crosses Spaces and fullscreen via the Accessibility API
- **Zero overhead** — State stored in files (no daemon), hooks integrate with Claude Code's native event system

## How it works

Two decoupled halves talking through a state directory — no sockets, no daemon:

```
Claude Code session(s)                         renderer
  │ hooks (glowbar-hook)                            │ reads
  ▼                                               ▼
~/.glowbar/sessions/<session_id>.json  ◄─────  glowbar status  (CLI)
                                             MTMR widget    (Touch Bar, today)
                                             glowbar-touchbar (native app)
```

Each hook event maps to a state and the hook writes the session's JSON file
atomically. The event → state mapping:

| Hook event                              | Effect                                  |
|-----------------------------------------|-----------------------------------------|
| `SessionStart`                          | create file, `ready`                    |
| `UserPromptSubmit`                      | `working`                               |
| `PreToolUse` / `PostToolUse` / batch    | `working` + keep-alive                  |
| `Notification` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) | `waiting` |
| `Notification` (`idle_prompt`)          | `ready`                                 |
| `Notification` (other, e.g. `agent_completed`) | keep-alive only — never repaints  |
| `Stop`                                  | `ready`                                 |
| `SessionEnd`                            | delete file                             |

The last row matters: a subagent finishing mid-turn fires `agent_completed`, and
we deliberately *don't* let that flip a red (working) tile to yellow.

## Quick start

```sh
# 1. Wire the hooks into whichever Claude config dir(s) you use.
./bin/glowbar install --config-dir ~/.claude-personal --config-dir ~/.claude-work

# 2. In another terminal, watch live status:
watch -n1 ./bin/glowbar status      # or: while true; do clear; ./bin/glowbar status; sleep 1; done

# 3. Start Claude Code sessions in a few repos and watch the colours change.
```

`install` backs up each `settings.json` first, is idempotent (safe to re-run),
and copies `glowbar-hook` + `glowbar` into `~/.glowbar/bin`. Remove everything with:

```sh
./bin/glowbar uninstall --config-dir ~/.claude-personal --config-dir ~/.claude-work
```

`install`/`uninstall` default to `$CLAUDE_CONFIG_DIR` (or `~/.claude`) when you
pass no `--config-dir`.

### CLI

```
glowbar status      pretty-print the live session tiles (auto-runs sync)
glowbar sync        import Claude's own live sessions (works without hooks)
glowbar install     wire hooks into settings.json (backs up, idempotent)
glowbar uninstall   remove them again
glowbar reap        delete session files for dead / expired sessions
glowbar dir         print the state directory (~/.glowbar)
```

## Renderers

### MTMR (Touch Bar, works today)

The fastest path to real Touch Bar tiles with zero compilation — see
[`mtmr/README.md`](mtmr/README.md). A one-line shell widget renders the strip.

### Native app (`app/`)

A SwiftPM menu-bar agent that draws a persistent Control-Strip item plus an
expandable strip of named tiles, and mirrors them as coloured dots in the menu
bar (the always-works fallback, useful on non-Touch-Bar Macs). Touch Bar access
uses the same private `DFRFoundation` recipe as [Pock](https://github.com/pigigaldi/Pock)
and MTMR, isolated in a small ObjC shim and guarded so it degrades to no-ops
where those entry points are unavailable.

```sh
cd app
swift build -c release       # needs a working Swift toolchain (see caveat)
swift run glowbar-selftest     # verify the GlowbarCore logic (works under CLT-only)
swift test                   # full XCTest suite (needs Xcode for XCTest)
```

#### Run it — one-word on/off

`glowbar-app` builds and controls the running app. `glowbar install` stages it to
`~/.glowbar/bin`; you can also run it straight from `./bin/glowbar-app`.

```sh
# one-time: build + assemble a signed glowbar.app at ~/.glowbar/glowbar.app
./bin/glowbar-app build ./app

# then control it with one word
glowbar-app on                 # launch (Touch Bar tiles + menu-bar mirror)
glowbar-app off                # stop
glowbar-app toggle             # flip on/off
glowbar-app status             # on / off
glowbar-app restart
```

`build` assembles a minimal, ad-hoc-signed `.app` bundle (stable bundle id
`com.glowbar.touchbar`). The signature matters: a bare `swift build` binary has no
stable TCC identity, so macOS won't reliably honour its Accessibility grant —
the bundle fixes that, and the grant then persists across rebuilds.

By default it takes over the Touch Bar's **app region** (replacing the focused
app's own bar). For a compact dot in the **Control Strip** (right, by brightness)
instead, set the mode:

```sh
GLOWBAR_TOUCHBAR_MODE=strip glowbar-app on
```

#### Permissions (for tap-to-focus)

Tap-to-focus asks macOS to bring another app's window forward, which needs:

- **Accessibility** — required to cross Spaces / fullscreen (the `AXRaise`).
  System Settings → Privacy & Security → **Accessibility** → enable **glowbar**.
- **Automation** — only for selecting the exact Terminal/iTerm tab; prompted on
  first tap. (VS Code / IntelliJ focus needs just Accessibility.)

#### Add to `~/.zshrc`

Put `~/.glowbar/bin` on your `PATH` and alias the toggle, so you can flip it from
anywhere by typing `tb`:

```sh
# glowbar — Touch Bar status lights
export PATH="$HOME/.glowbar/bin:$PATH"
alias tb='glowbar-app toggle'
```

Reload with `source ~/.zshrc` (or open a new terminal), then just type **`tb`**.
For a global hotkey, add a *Run Shell Script* action running
`$HOME/.glowbar/bin/glowbar-app toggle` in **Shortcuts.app** and assign it a key.

Auto-start on login via `packaging/com.glowbar.app.plist` (a LaunchAgent template).

## Configuration

Thresholds are environment-overridable (read by the CLI and MTMR widget):

| Variable            | Default | Meaning                         |
|---------------------|---------|---------------------------------|
| `GLOWBAR_DIR`         | `~/.glowbar` | state directory               |
| `GLOWBAR_STALE_SECS`  | `1200`  | inactivity → dim/stale          |
| `GLOWBAR_HIDE_SECS`   | `7200`  | inactivity → hidden / reaped    |

## Verification status (what's actually been tested)

Being precise about this, because parts run on hardware I can drive and parts
don't:

- **Pipeline (`bin/glowbar-hook`, `bin/glowbar`) — verified.** The full state
  machine was exercised with real hook payloads (ready→working→waiting→ready,
  the `agent_completed`-stays-working rule, dedup, stale/dead detection, reap,
  and idempotent install/uninstall that preserves existing hooks). A **real
  headless Claude Code session** confirmed the two things simulation can't: the
  installed (argv-less) hook receives the event via **stdin** and writes the
  correct state, and the recorded PID is the **durable Claude Code process**
  (so `kill -0` liveness is reliable, not a transient shell). The working/waiting
  *colour* transitions were later confirmed **live**, against a real interactive
  session running with the hooks installed. Requires **bash 3.2+** and `jq`
  (both stock on macOS).

- **MTMR widget — verified logic, needs your Touch Bar to see.** The renderer
  was tested against fixture state (colours, truncation, empty `💤` case). The
  actual Touch Bar display depends on your MTMR install.

- **Native app — compiles and its logic is tested; Touch Bar rendering not yet
  verified.** The whole package **builds cleanly** (`swift build` → a linked
  `glowbar-touchbar` binary; the ObjC DFR shim compiles and links). `GlowbarCore`
  (parsing / stale / PID / dedup — the bug-prone part) passes **12/12 checks**
  via `swift run glowbar-selftest`, an XCTest-free runner that works under Command
  Line Tools alone. (The XCTest suite in `Tests/` needs full Xcode.) What is
  *not* yet verified is the actual on-screen rendering: the menu-bar mirror and
  the private-API Touch Bar path have not been observed running on this macOS
  version — the private entry points are faithful to Pock/MTMR and guarded to
  degrade to no-ops, with the menu-bar mirror as the fallback.

## Layout

```
bin/glowbar-hook        hook handler (one script, all events; atomic writes)
bin/glowbar             CLI: status / install / uninstall / reap / dir
mtmr/glowbar-strip.sh   MTMR Touch Bar widget (+ mtmr/README.md)
app/                  native SwiftPM Touch Bar app (GlowbarCore + CDFR shim)
packaging/            LaunchAgent template
```
