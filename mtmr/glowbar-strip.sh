#!/usr/bin/env bash
#
# glowbar-strip.sh — renders the live Claude Code sessions as a compact emoji
# strip for an MTMR (My TouchBar My Rules) shell-script widget.
#
#   🔴 my-api  🟡 webapp  🟢 infra
#
# MTMR runs this on a timer and shows stdout as a Touch Bar button. It is fully
# self-contained and fast so it can refresh every 1–2 s. Consumes the same
# ~/.glowbar/sessions state the hooks write — no Swift, no compilation required.

GLOWBAR_DIR="${GLOWBAR_DIR:-$HOME/.glowbar}"
SESSIONS_DIR="$GLOWBAR_DIR/sessions"
STALE_SECS="${GLOWBAR_STALE_SECS:-1200}"   # 20 min → ⚪
HIDE_SECS="${GLOWBAR_HIDE_SECS:-7200}"     # 2 h   → hidden
MAXLEN="${GLOWBAR_NAME_MAXLEN:-10}"

# Import Claude's own live sessions (best effort) so any running session shows,
# even without hooks installed. Creates the sessions dir on first run.
[ -x "$HOME/.glowbar/bin/glowbar" ] && "$HOME/.glowbar/bin/glowbar" sync 2>/dev/null

[ -d "$SESSIONS_DIR" ] || { printf '💤'; exit 0; }

now=$(date -u +%s)
iso_to_epoch() { date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0; }

rows=""
for f in "$SESSIONS_DIR"/*.json; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in .tmp.*) continue;; esac
  rec=$(jq -r '[.name,.state,(.updated_at//""),(.created_at//""),(.pid//0)]|@tsv' "$f" 2>/dev/null) || continue
  [ -n "$rec" ] || continue
  IFS=$'\t' read -r name state updated created pid <<<"$rec"
  age=$(( now - $(iso_to_epoch "$updated") ))
  (( age < 0 )) && age=0
  # skip hidden (very old) and dead (pid gone) sessions
  (( age > HIDE_SECS )) && continue
  if [ "${pid:-0}" -gt 0 ] 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then continue; fi
  crt=$(iso_to_epoch "$created")
  rows+="${crt}"$'\t'"${state}"$'\t'"${age}"$'\t'"${name}"$'\n'
done

[ -n "$rows" ] || { printf '💤'; exit 0; }

printf '%s' "$rows" | sort -t$'\t' -k1,1n | awk -F'\t' -v stale="$STALE_SECS" -v maxlen="$MAXLEN" '
  {
    state=$2; age=$3; name=$4
    if (age > stale)          dot="⚪"
    else if (state=="working") dot="🔴"
    else if (state=="waiting") dot="🟡"
    else if (state=="ready")   dot="🟢"
    else                       dot="⚪"
    if (length(name) > maxlen) name=substr(name,1,maxlen-1) "…"
    printf "%s%s %s", (NR>1?"  ":""), dot, name
  }
'
