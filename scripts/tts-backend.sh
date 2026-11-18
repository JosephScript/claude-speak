#!/bin/bash
# Detects the available TTS backend and exposes voice listing/validation in
# a backend-agnostic way. Shared by speak-say.sh (actual speech) and
# /speak-voice (listing/validating voice names). Rate (-r / -s) needs no
# translation between backends — both take words-per-minute directly — but
# voice *names* are backend-specific namespaces (macOS "Daniel" vs espeak's
# "en-us"), so a stored voice preference only makes sense on the backend it
# was set against.
#
# Supported backends:
#   macos  — macOS `say`
#   espeak — espeak-ng (or the older `espeak`) on Linux
#   windows — Windows SAPI (System.Speech) via powershell.exe, from Git Bash

# Runs the SAPI helper in Windows PowerShell. Inline (-Command) rather than a
# .ps1 file so it works under the default Restricted execution policy. Input
# comes from env vars: CS_ACTION (list|validate|speak), CS_VOICE, CS_RATE
# (words per minute), CS_TEXT_FILE (UTF-8 file, deleted after speaking).
sapi() {
  powershell.exe -NoProfile -NonInteractive -Command '
    $ErrorActionPreference = "Stop"
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voices = $s.GetInstalledVoices() |
      Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like "en*" } |
      ForEach-Object { $_.VoiceInfo }
    switch ($env:CS_ACTION) {
      "list" { $voices | ForEach-Object { "{0}  ({1})" -f $_.Name, $_.Culture.Name } }
      "validate" { if ($voices | Where-Object { $_.Name -eq $env:CS_VOICE }) { exit 0 } else { exit 1 } }
      "speak" {
        if ($env:CS_VOICE) { $s.SelectVoice($env:CS_VOICE) }
        # SAPI rate is -10..10 with 0 about 180 wpm; approximate 15 wpm per step.
        if ($env:CS_RATE) { $s.Rate = [Math]::Max(-10, [Math]::Min(10, [int][Math]::Round(([double]$env:CS_RATE - 180) / 15))) }
        $t = [IO.File]::ReadAllText($env:CS_TEXT_FILE, [Text.Encoding]::UTF8)
        Remove-Item $env:CS_TEXT_FILE -Force
        $s.Speak($t)
      }
    }
  ' | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

espeak_bin() {
  command -v espeak-ng >/dev/null 2>&1 && { echo "espeak-ng"; return 0; }
  command -v espeak >/dev/null 2>&1 && { echo "espeak"; return 0; }
  return 1
}

detect_backend() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      command -v powershell.exe >/dev/null 2>&1 && { echo "windows"; return 0; }
      ;;
    Darwin)
      command -v say >/dev/null 2>&1 && { echo "macos"; return 0; }
      ;;
    Linux)
      espeak_bin >/dev/null 2>&1 && { echo "espeak"; return 0; }
      ;;
  esac
  echo "unsupported"
  return 1
}

list_voices() {
  backend="$(detect_backend)"
  case "$backend" in
    macos) say -v '?' | grep -E '^\S+\s+en' ;;
    espeak) "$(espeak_bin)" --voices=en | tail -n +2 ;;
    windows) CS_ACTION=list sapi ;;
    *)
      echo "claude-speak: no supported TTS backend found (need macOS \`say\`, Linux \`espeak-ng\`/\`espeak\`, or Windows PowerShell)" >&2
      return 1
      ;;
  esac
}

validate_voice() {
  name="$1"
  backend="$(detect_backend)"
  case "$backend" in
    macos) say -v '?' | awk '{print $1}' | grep -qx "$name" ;;
    espeak) "$(espeak_bin)" --voices=en | tail -n +2 | awk '{print $2}' | grep -qx "$name" ;;
    windows) CS_ACTION=validate CS_VOICE="$name" sapi ;;
    *) return 1 ;;
  esac
}

case "$1" in
  detect) detect_backend ;;
  list-voices) list_voices ;;
  validate-voice) validate_voice "$2" ;;
  sapi-speak) CS_ACTION=speak sapi ;;  # env: CS_TEXT_FILE, CS_RATE, CS_VOICE
  *)
    echo "usage: $(basename "$0") {detect|list-voices|validate-voice <name>}" >&2
    exit 2
    ;;
esac
