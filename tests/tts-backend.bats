#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_isolated_home
  FAKE_BIN="$(mktemp -d)"
}

teardown() {
  teardown_isolated_home
  rm -rf "$FAKE_BIN"
}

@test "detects a backend when a supported TTS binary is on PATH" {
  cat > "$FAKE_BIN/say" <<'EOF'
#!/bin/bash
EOF
  cat > "$FAKE_BIN/espeak-ng" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$FAKE_BIN/say" "$FAKE_BIN/espeak-ng"

  # Prepend to the real PATH (not replace it) so `uname` and other utilities
  # the script needs still resolve normally.
  run env PATH="$FAKE_BIN:$PATH" "$SCRIPTS_DIR/tts-backend.sh" detect
  [ "$status" -eq 0 ]
  case "$(uname -s)" in
    Darwin) [ "$output" = "macos" ] ;;
    MINGW*|MSYS*|CYGWIN*) [ "$output" = "windows" ] ;;
    *) [ "$output" = "espeak" ] ;;
  esac
}

@test "detects the windows backend under Git Bash when powershell.exe is on PATH" {
  cat > "$FAKE_BIN/uname" <<'EOF'
#!/bin/bash
echo "MINGW64_NT-10.0"
EOF
  cat > "$FAKE_BIN/powershell.exe" <<'EOF'
#!/bin/bash
EOF
  chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/powershell.exe"

  run env PATH="$FAKE_BIN:$PATH" "$SCRIPTS_DIR/tts-backend.sh" detect
  [ "$status" -eq 0 ]
  [ "$output" = "windows" ]
}

@test "reports unsupported on an unrecognized OS" {
  # Faking PATH down to nothing would also break `uname` itself (it's a real
  # binary, not a builtin), producing a spurious "command not found" instead
  # of exercising the actual fallback branch. Fake `uname` deterministically
  # instead, and prepend it to the real PATH so everything else still works.
  cat > "$FAKE_BIN/uname" <<'EOF'
#!/bin/bash
echo "SunOS"
EOF
  chmod +x "$FAKE_BIN/uname"

  run env PATH="$FAKE_BIN:$PATH" "$SCRIPTS_DIR/tts-backend.sh" detect
  [ "$status" -ne 0 ]
  [ "$output" = "unsupported" ]
}

@test "list-voices returns a non-empty list against the real installed backend" {
  # Uses whatever real TTS backend is actually installed on this machine/CI
  # runner (not a fake one) to confirm the real output format still parses.
  backend="$("$SCRIPTS_DIR/tts-backend.sh" detect)" || skip "no supported backend installed on this machine"
  run "$SCRIPTS_DIR/tts-backend.sh" list-voices
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "validate-voice accepts a real installed voice and rejects a bogus one" {
  backend="$("$SCRIPTS_DIR/tts-backend.sh" detect)" || skip "no supported backend installed on this machine"
  case "$backend" in
    macos) real_voice="Samantha" ;;
    espeak) real_voice="en-us" ;;
  esac

  run "$SCRIPTS_DIR/tts-backend.sh" validate-voice "$real_voice"
  [ "$status" -eq 0 ]

  run "$SCRIPTS_DIR/tts-backend.sh" validate-voice "definitely-not-a-real-voice-xyz"
  [ "$status" -ne 0 ]
}
