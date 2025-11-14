#!/usr/bin/env bash
# Sudo keepalive functions

## Spawn sudo in background subshell to refresh the sudo timestamp
prevent_sudo_timeout() {
  # Spawn background loop to refresh sudo timestamp
  # Note: Don't redirect stdin - sudo -v uses the cached credentials
  ( while true; do
      sudo -n -v 2>/dev/null || true
      sleep 40
    done ) &

  sudo_loop_PID=$!
  readonly sudo_loop_PID

  # Trap to kill the background refresher when the script exits or is terminated
  trap 'if [ -n "$sudo_loop_PID" ] && kill -0 "$sudo_loop_PID" 2>/dev/null; then
          kill "$sudo_loop_PID" 2>/dev/null || true
          wait "$sudo_loop_PID" 2>/dev/null || true
        fi' EXIT INT TERM HUP
}

start_sudo_keepalive() {
  echo "Starting background sudo refresh..."
  prevent_sudo_timeout
  readonly sudo_loop_PID # Make PID readonly for security

  # Give the background loop a moment to start and verify it's running
  sleep 1
  if kill -0 "$sudo_loop_PID" 2>/dev/null; then
    echo "✓ Sudo refresh started (PID: $sudo_loop_PID)"
  else
    echo "⚠ Warning: Sudo refresh loop may not have started properly"
  fi
  echo ""
}

