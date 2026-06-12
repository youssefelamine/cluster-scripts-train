#!/usr/bin/env bash
set -uo pipefail

PROJECT=/root/project
VENV=/opt/ddos-rl-venv
TOOLS=/opt/ddos-rl-tools
MHDDOS="$TOOLS/MHDDoS"
CIC="$TOOLS/CICFlowMeter"
failures=0

pass() { printf '[INFO] PASS: %s\n' "$*"; }
fail() { printf '[ERROR] FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

check_file() {
  [[ -f "$1" ]] && pass "File exists: $1" || fail "Missing file: $1"
}

check_dir() {
  [[ -d "$1" ]] && pass "Directory exists: $1" || fail "Missing directory: $1"
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1 && pass "Command available: $1" || fail "Missing command: $1"
}

check_link() {
  local link=$1
  local expected=$2
  [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$expected")" ]] \
    && pass "Compatibility link: $link -> $expected" \
    || fail "Expected compatibility link: $link -> $expected"
}

[[ $EUID -eq 0 ]] && pass "Running as root" || fail "This workflow must run as root"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] \
    && pass "OS is Ubuntu 24.04" \
    || fail "Expected Ubuntu 24.04, found ${PRETTY_NAME:-unknown}"
else
  fail "Cannot read /etc/os-release"
fi

check_dir "$PROJECT"
check_file "$PROJECT/reinforcement/Main.py"
check_file "$PROJECT/network/EntryPoint.py"
check_file "$PROJECT/reinforcement/Configuration.py"
check_file "$PROJECT/input-data/hosts-toplogy-6hosts.json"
check_file "$PROJECT/requirements.txt"
check_dir "$PROJECT/results"
check_dir "$PROJECT/tmp"
check_dir "$PROJECT/reinforcement/tmp"

check_file "$VENV/bin/python3"
if [[ -x "$VENV/bin/python3" ]]; then
  if "$VENV/bin/python3" - <<'PY'
import flask
import matplotlib
import mininet
import numpy
import requests
import scapy
import tensorflow
print("important imports succeeded")
PY
  then
    pass "Important Python imports"
  else
    fail "One or more important Python imports failed"
  fi
fi

for command in git mn ovs-ofctl ovs-vsctl tshark editcap java javac mvn gradle xterm Xvfb timeout; do
  check_cmd "$command"
done

if systemctl is-active --quiet openvswitch-switch; then
  pass "Open vSwitch service is active"
else
  fail "Open vSwitch service is not active"
fi

ovs-vsctl show >/dev/null 2>&1 && pass "Open vSwitch database responds" || fail "ovs-vsctl show failed"
mn --version >/dev/null 2>&1 && pass "Mininet command responds" || fail "Mininet command failed"
tshark -D >/dev/null 2>&1 && pass "TShark can list capture interfaces" || fail "TShark cannot list capture interfaces"

java_version="$(java -version 2>&1 | head -n 1)"
[[ "$java_version" == *'"1.8.'* ]] && pass "Java 8 active: $java_version" || fail "CICFlowMeter requires Java 8; active version: $java_version"

check_file "$MHDDOS/start.py"
check_file "$CIC/gradlew"
check_dir "$CIC/build"
library_cache="$(ldconfig -p)"
if [[ "$library_cache" == *libjnetpcap* ]]; then
  pass "jnetpcap native libraries are registered"
else
  fail "jnetpcap native libraries are missing"
fi
if [[ "$library_cache" == *libpcap* ]]; then
  pass "libpcap is registered"
else
  fail "libpcap is missing"
fi

check_link /home/user12/myenv "$VENV"
check_link /home/user12/Documents/CICFlowMeter "$CIC"
check_link /root/MHDDoS "$MHDDOS"

if [[ -x "$VENV/bin/python3" && -f "$MHDDOS/start.py" ]]; then
  timeout 30 "$VENV/bin/python3" "$MHDDOS/start.py" --help >/dev/null 2>&1 \
    && pass "MHDDoS help command responds" \
    || fail "MHDDoS help command failed"
fi

if (( failures > 0 )); then
  printf '[ERROR] Image check failed with %d problem(s).\n' "$failures" >&2
  exit 1
fi

printf '[INFO] Image check passed. The node is ready for the smoke test.\n'
