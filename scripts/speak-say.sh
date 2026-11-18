#!/bin/bash
# Speaks stdin text via the detected TTS backend (macOS `say`, or espeak-ng/
# espeak on Linux — see tts-backend.sh), applying the persisted rate (words
# per minute) from ~/.claude/claude-speak/rate and voice from
# ~/.claude/claude-speak/voice if set — see /speak-rate and /speak-voice.
# Shared by speak-format.sh (mechanical path) and /speak's llm mode, so both
# stay consistent across backends.
#
# The backend is launched fully detached (own process group via `set -m`,
# plus disown) rather than awaited inline. A hook's "async" flag keeps it
# from blocking the turn, but the process can still be reaped once the
# turn/session ends — which cuts speech off mid-sentence on any response
# long enough to still be talking when the next message is sent. Detaching
# it lets it keep playing independently of this script's own lifetime.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

text="$(cat)"
[ -n "$text" ] || exit 0

RATE_FILE="$HOME/.claude/claude-speak/rate"
VOICE_FILE="$HOME/.claude/claude-speak/voice"

rate=""
[ -s "$RATE_FILE" ] && rate="$(cat "$RATE_FILE")"
voice=""
[ -s "$VOICE_FILE" ] && voice="$(cat "$VOICE_FILE")"

backend="$("$DIR/tts-backend.sh" detect)"

set -m
case "$backend" in
  macos)
    args=()
    [ -n "$rate" ] && args+=(-r "$rate")
    [ -n "$voice" ] && args+=(-v "$voice")
    say "${args[@]}" "$text" >/dev/null 2>&1 &
    ;;
  espeak)
    espeak_bin=$(command -v espeak-ng || command -v espeak)
    args=()
    [ -n "$rate" ] && args+=(-s "$rate")
    [ -n "$voice" ] && args+=(-v "$voice")
    "$espeak_bin" "${args[@]}" "$text" >/dev/null 2>&1 &
    ;;
  windows)
    # Text goes through a temp file (UTF-8 safe, no quoting); the PowerShell
    # helper reads it and deletes it. Rate is words per minute, mapped to
    # SAPI's -10..10 scale there.
    tmp="$(mktemp)"
    printf '%s' "$text" > "$tmp"
    CS_TEXT_FILE="$(cygpath -w "$tmp")" CS_RATE="$rate" CS_VOICE="$voice" \
      "$DIR/tts-backend.sh" sapi-speak >/dev/null 2>&1 &
    ;;
  *)
    echo "claude-speak: no supported TTS backend found (need macOS \`say\`, Linux \`espeak-ng\`/\`espeak\`, or Windows PowerShell)" >&2
    exit 0
    ;;
esac
disown
exit 0
