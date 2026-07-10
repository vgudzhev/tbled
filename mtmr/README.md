# glowbar × MTMR (Phase 2 — works today, no compilation)

[MTMR](https://github.com/Toxblh/MTMR) ("My TouchBar My Rules") is a free, open
Touch Bar customiser. A single shell-script widget renders the live Claude Code
sessions straight onto the Touch Bar — no Swift, no build step. This is the
fastest way to see glowbar on real hardware.

```
🔴 my-api   🟡 webapp   🟢 infra
```

## Setup

1. **Install the pipeline** (writes the state the widget reads):

   ```sh
   ./bin/glowbar install --config-dir ~/.claude-personal
   ```

   This also stages the widget script to `~/.glowbar/mtmr/glowbar-strip.sh`.

2. **Install MTMR**: `brew install --cask mtmr` (or download a release).

3. **Add the widget** to `~/Library/Application Support/MTMR/items.json`.
   Add this object to the top-level array:

   ```json
   {
     "type": "shellScriptTitledButton",
     "source": { "filePath": "~/.glowbar/mtmr/glowbar-strip.sh" },
     "refreshInterval": 2,
     "align": "left"
   }
   ```

4. **Reload MTMR** (menu-bar icon → *Preferences* re-reads the file, or quit and
   relaunch). The strip appears; start a Claude Code session and watch it turn
   red while working, yellow on a permission prompt, green when idle, and ⚪ when
   stale.

## Tuning

The script honours the same environment overrides as `glowbar` (set them in the
MTMR launch environment or edit the top of the script):

| Variable              | Default | Meaning                         |
|-----------------------|---------|---------------------------------|
| `GLOWBAR_STALE_SECS`    | `1200`  | seconds of inactivity → ⚪       |
| `GLOWBAR_HIDE_SECS`     | `7200`  | seconds of inactivity → hidden  |
| `GLOWBAR_NAME_MAXLEN`   | `10`    | truncate names to N glyphs      |

When there are no sessions the widget shows `💤`.
