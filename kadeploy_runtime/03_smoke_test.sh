#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT=/root/project
RUNTIME_DIR="$PROJECT/kadeploy_runtime"
VENV=/opt/ddos-rl-venv
RESULTS="$PROJECT/results"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$RESULTS/smoke_test_${STAMP}.log"
NEWER_MARKER="/tmp/ddos-rl-smoke-${STAMP}.marker"

info() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup_network() {
  pkill -f '/network/EntryPoint.py' >/dev/null 2>&1 || true
  mn -c >/dev/null 2>&1 || true
  rm -f "$NEWER_MARKER"
}
trap cleanup_network EXIT

[[ $EUID -eq 0 ]] || error "Run this script as root."
[[ -x "$VENV/bin/python3" ]] || error "Missing Python virtual environment: $VENV"
[[ -f "$PROJECT/reinforcement/Main.py" ]] || error "Missing training entrypoint."

# shellcheck disable=SC1091
source "$VENV/bin/activate"
export PATH="$VENV/bin:$PATH"
export PYTHON="$VENV/bin/python3"
export MPLBACKEND=Agg
export TF_CPP_MIN_LOG_LEVEL=2

if [[ -z "${DISPLAY:-}" ]]; then
  export DISPLAY=:99
  if ! pgrep -f 'Xvfb :99' >/dev/null 2>&1; then
    info "Starting headless X server on $DISPLAY"
    Xvfb "$DISPLAY" -screen 0 1280x800x24 >/tmp/ddos-rl-xvfb.log 2>&1 &
    sleep 2
  fi
fi

install -d "$RESULTS"
touch "$NEWER_MARKER"
cleanup_network
touch "$NEWER_MARKER"

info "Running real 1-episode, 1-step smoke test"
info "Log: $LOG"
cd "$PROJECT"

set +e
timeout --signal=TERM --kill-after=60s 20m \
  "$VENV/bin/python3" reinforcement/Main.py \
  -a '[h1]' -e 1 -s 1 --checkpoint-every 1 --keep-last-checkpoints 1 \
  2>&1 | tee "$LOG"
exit_code=${PIPESTATUS[0]}
set -e

smoke_output="$(find "$RESULTS" -mindepth 1 -maxdepth 1 -type d -name 'train_*' -newer "$NEWER_MARKER" -print | sort | tail -n 1)"
printf '%s\n' "$LOG" > "$RUNTIME_DIR/.last_smoke_log"
if [[ -n "$smoke_output" ]]; then
  printf '%s\n' "$smoke_output" > "$RUNTIME_DIR/.last_smoke_output"
  info "Smoke-test output: $smoke_output"
else
  rm -f "$RUNTIME_DIR/.last_smoke_output"
  info "No new train output directory was detected."
fi

if (( exit_code != 0 )); then
  printf '[ERROR] Smoke test failed with exit code %d. See %s\n' "$exit_code" "$LOG" >&2
  exit "$exit_code"
fi

info "Smoke test passed"
