#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT=/root/project
RUNTIME_DIR="$PROJECT/kadeploy_runtime"
VENV=/opt/ddos-rl-venv
TOOLS=/opt/ddos-rl-tools
MHDDOS="$TOOLS/MHDDoS"
CIC="$TOOLS/CICFlowMeter"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'printf "[ERROR] Setup failed at line %s\n" "$LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || error "Run this script as root."
[[ -d "$PROJECT" ]] || error "Expected project directory $PROJECT."
[[ -f "$PROJECT/requirements.txt" ]] || error "Missing $PROJECT/requirements.txt."
[[ -f "$RUNTIME_DIR/01_setup_image.sh" ]] || error "Missing runtime scripts under $RUNTIME_DIR."

export DEBIAN_FRONTEND=noninteractive

info "Installing Ubuntu system packages"
printf 'wireshark-common wireshark-common/install-setuid boolean true\n' | debconf-set-selections
apt-get update
if ! apt-cache show mininet >/dev/null 2>&1 || ! apt-cache show openjdk-8-jdk >/dev/null 2>&1; then
  info "Enabling the Ubuntu universe repository for Mininet and Java 8"
  apt-get install -y software-properties-common
  add-apt-repository -y universe
  apt-get update
fi
apt-get install -y \
  bzip2 build-essential ca-certificates curl git gradle iproute2 libgomp1 \
  libffi-dev libpcap-dev libssl-dev lsof maven mininet net-tools \
  openvswitch-common openvswitch-switch pkg-config procps psmisc python3 \
  python3-dev python3-pip \
  python3-venv tshark unzip wget wireshark-common xterm xvfb

if apt-cache show openjdk-8-jdk >/dev/null 2>&1; then
  apt-get install -y openjdk-8-jdk
else
  error "openjdk-8-jdk is unavailable. CICFlowMeter requires Java 8; check the Ubuntu 24.04 apt sources."
fi

JAVA8_BIN="$(find /usr/lib/jvm -path '*java-8-openjdk*/bin/java' -print -quit)"
JAVAC8_BIN="$(find /usr/lib/jvm -path '*java-8-openjdk*/bin/javac' -print -quit)"
[[ -n "$JAVA8_BIN" && -n "$JAVAC8_BIN" ]] || error "Java 8 binaries were not found after installation."
update-alternatives --set java "$JAVA8_BIN"
update-alternatives --set javac "$JAVAC8_BIN"
export JAVA_HOME
JAVA_HOME="$(dirname "$(dirname "$JAVA8_BIN")")"

info "Enabling Open vSwitch"
systemctl enable --now openvswitch-switch
ovs-vsctl show >/dev/null

info "Creating Python virtual environment at $VENV"
if [[ ! -x "$VENV/bin/python3" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python3" -m pip install --upgrade pip setuptools wheel
"$VENV/bin/python3" -m pip install -r "$PROJECT/requirements.txt"

install -d "$TOOLS"

clone_if_missing() {
  local url=$1
  local destination=$2
  local marker=$3

  if [[ -e "$destination/$marker" ]]; then
    info "Using existing $destination"
    return
  fi
  [[ ! -e "$destination" ]] || error "$destination exists but is incomplete; inspect or remove it before retrying."
  info "Cloning $url into $destination"
  git clone --depth 1 "$url" "$destination"
  [[ -e "$destination/$marker" ]] || error "Expected $destination/$marker after clone."
}

clone_if_missing "https://github.com/MatrixTM/MHDDoS.git" "$MHDDOS" "start.py"
clone_if_missing "https://github.com/ahlashkari/CICFlowMeter.git" "$CIC" "gradlew"

info "Installing CICFlowMeter jnetpcap libraries"
JNETPCAP_DIR="$CIC/jnetpcap/linux/jnetpcap-1.4.r1425"
[[ -f "$JNETPCAP_DIR/jnetpcap.jar" ]] || error "Missing CICFlowMeter jnetpcap.jar."
(
  cd "$JNETPCAP_DIR"
  mvn -q install:install-file \
    -Dfile=jnetpcap.jar \
    -DgroupId=org.jnetpcap \
    -DartifactId=jnetpcap \
    -Dversion=1.4.1 \
    -Dpackaging=jar
  install -m 0644 libjnetpcap.so libjnetpcap-pcap100.so /usr/lib/
)
ldconfig

info "Building CICFlowMeter"
chmod +x "$CIC/gradlew"
(
  cd "$CIC"
  ./gradlew --no-daemon build
)

create_compat_link() {
  local target=$1
  local link=$2
  if [[ -e "$link" && ! -L "$link" ]]; then
    error "Cannot create compatibility link $link because a non-symlink path already exists."
  fi
  ln -sfn "$target" "$link"
}

info "Creating compatibility paths required by the project"
install -d /home/user12/Documents
create_compat_link "$VENV" /home/user12/myenv
create_compat_link "$CIC" /home/user12/Documents/CICFlowMeter
create_compat_link "$MHDDOS" /root/MHDDoS

info "Creating minimal runtime directories"
install -d "$PROJECT/results" "$PROJECT/tmp" "$PROJECT/reinforcement/tmp"

info "Cleaning any stale Mininet state"
mn -c >/dev/null 2>&1 || warn "Mininet cleanup returned a warning."

info "Setup complete"
info "Next: $RUNTIME_DIR/02_check_image.sh"
