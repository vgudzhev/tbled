#!/usr/bin/env bash
#
# glowbar one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/vgudzhev/glowbar/main/install.sh | bash
#
# Wraps the three manual steps (wire hooks · build app · turn on) into one.
# It clones glowbar to a throwaway temp dir, stages everything into ~/.glowbar,
# then deletes the clone — nothing is left in your working tree. Re-runnable.
#
# Two touchpoints stay manual by nature (the script tells you when it hits them):
#   • Xcode Command Line Tools — a GUI prompt, can't be scripted silently.
#   • Accessibility grant       — a System Settings toggle you flip once.

set -euo pipefail

REPO="${GLOWBAR_REPO:-https://github.com/vgudzhev/glowbar.git}"
REF="${GLOWBAR_REF:-main}"

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; dim=$'\033[2m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s▸ %s%s\n' "$bold" "$*" "$reset"; }
ok()   { printf '%s✓ %s%s\n' "$green" "$*" "$reset"; }
die()  { printf '%sglowbar install: %s%s\n' "$yellow" "$*" "$reset" >&2; exit 1; }

# ---- preflight -------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "glowbar is macOS-only (Touch Bar)."

command -v git >/dev/null 2>&1 || die "git not found."
command -v jq  >/dev/null 2>&1 || die "jq not found — install it: brew install jq"

# Swift/Xcode CLT: a missing toolchain triggers a GUI installer we can't drive.
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  say "${yellow}Xcode Command Line Tools are required to build the Touch Bar app.${reset}"
  say "Run this, complete the popup, then re-run the installer:"
  say "  ${bold}xcode-select --install${reset}"
  # Kick off the GUI prompt for them, best-effort.
  xcode-select --install >/dev/null 2>&1 || true
  die "install Command Line Tools, then re-run."
fi

# ---- fetch (throwaway clone) ----------------------------------------------

TMP="$(mktemp -d "${TMPDIR:-/tmp}/glowbar.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

step "Fetching glowbar…"
# When piped (`curl … | bash`) there is no source file, so BASH_SOURCE is unset —
# guard it under `set -u` or the script aborts here. Empty → not a checkout → clone.
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$(dirname "$self")/bin/glowbar" ]; then
  # Running from inside a checkout (e.g. ./install.sh) — use it directly.
  SRC="$(cd "$(dirname "$self")" && pwd)"
  ok "using local checkout at $SRC"
else
  git clone --depth 1 --branch "$REF" "$REPO" "$TMP/glowbar" >/dev/null 2>&1 \
    || die "could not clone $REPO (ref $REF)."
  SRC="$TMP/glowbar"
  ok "cloned $REPO"
fi

# ---- wire hooks + build app + turn on (single source of truth) ------------
# `glowbar setup` auto-detects every ~/.claude* config dir, builds + signs the
# app from the sources beside it, and starts it. Same command the Homebrew tap's
# caveats point you to.

step "Wiring hooks, building the app (~2 min, one time), and lighting it up…"
"$SRC/bin/glowbar" setup

# ---- next steps ------------------------------------------------------------

BIN="$HOME/.glowbar/bin"
step "Done. ${green}glowbar is live.${reset}"
say ""
say "Start a Claude Code session — a tile appears on the Touch Bar. ✨"
say ""
say "${bold}Two quick things:${reset}"
say ""
say "  ${bold}1. Put glowbar on your PATH${reset} — add to your ~/.zshrc:"
say "       ${dim}export PATH=\"\$HOME/.glowbar/bin:\$PATH\"${reset}"
say "       ${dim}alias gb='glowbar-app toggle'${reset}"
say "     Then ${bold}gb${reset} toggles the strip, ${bold}glowbar status${reset} shows tiles in the terminal."
say ""
say "  ${bold}2. Enable tap-to-focus${reset} (tap a tile → jump to that terminal):"
say "     System Settings → Privacy & Security → Accessibility →"
say "     add ${bold}~/.glowbar/glowbar.app${reset} and toggle it on."
# Open the pane for them (best-effort; the toggle is still theirs to flip).
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
say ""
say "${dim}Uninstall: $BIN/glowbar uninstall  &&  rm -rf ~/.glowbar${reset}"
