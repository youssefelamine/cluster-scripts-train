#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT=/root/project
RUNTIME_DIR="$PROJECT/kadeploy_runtime"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Run this script as root."
[[ -d "$PROJECT" ]] || error "Expected project directory $PROJECT."

info "Cleaning stale Mininet and training processes"
pkill -f '/network/EntryPoint.py' >/dev/null 2>&1 || true
pkill -f 'Xvfb :99' >/dev/null 2>&1 || true
mn -c >/dev/null 2>&1 || warn "Mininet cleanup returned a warning."

if [[ -f "$RUNTIME_DIR/.last_smoke_output" ]]; then
  smoke_output="$(cat "$RUNTIME_DIR/.last_smoke_output")"
  case "$smoke_output" in
    "$PROJECT"/results/train_*)
      info "Removing tracked smoke-test output: $smoke_output"
      rm -rf -- "$smoke_output"
      ;;
    *)
      warn "Refusing to remove unexpected smoke output path: $smoke_output"
      ;;
  esac
fi

if [[ -f "$RUNTIME_DIR/.last_smoke_log" ]]; then
  smoke_log="$(cat "$RUNTIME_DIR/.last_smoke_log")"
  case "$smoke_log" in
    "$PROJECT"/results/smoke_test_*.log)
      info "Removing tracked smoke-test log: $smoke_log"
      rm -f -- "$smoke_log"
      ;;
    *)
      warn "Refusing to remove unexpected smoke log path: $smoke_log"
      ;;
  esac
fi
rm -f "$RUNTIME_DIR/.last_smoke_output" "$RUNTIME_DIR/.last_smoke_log"

clean_contents() {
  local directory=$1
  if [[ -d "$directory" ]]; then
    find "$directory" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
}

info "Cleaning project temporary directories"
clean_contents "$PROJECT/tmp"
clean_contents "$PROJECT/reinforcement/tmp"

info "Cleaning Python bytecode and test caches"
find "$PROJECT" -type d \( -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf -- {} +
find "$PROJECT" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete

info "Cleaning apt, pip, /tmp, and /var/tmp caches"
apt-get clean
rm -rf /root/.cache/pip
clean_contents /tmp
clean_contents /var/tmp

info "Final disk usage"
df -h /
du -sh "$PROJECT" /opt/ddos-rl-venv /opt/ddos-rl-tools 2>/dev/null || true
info "Cleanup complete; project code, virtualenv, tools, and untracked real results were preserved."
