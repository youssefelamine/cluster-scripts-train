# Testbed Setup Guide 

## Overview

This guide documents the process of setting up the testbed for running the RL-based DDoS countermeasure model locally on modern hardware and software. The original project was designed for **Ubuntu 20.04 LTS** with specific older versions of each tool. Since we are now running **Ubuntu 24.04 LTS (Noble Numbat)**. Several adaptations were necessary to make the environment compatible.

A key aspect of this adaptation concerns the pre-trained DDQN teacher model. Rather than attempting to load the original `.h5` model file directly, which would require resolving Keras 2/3 serialization incompatibilities, we adopt a **weights-only loading strategy**. The teacher architecture is reconstructed manually in the modern stack, and only the numerical weight matrices are loaded from the checkpoint file via `model.load_weights()`. This approach is fully version-agnostic: weight arrays carry no framework metadata, making them portable across Keras versions without any compatibility shims or downgrade requirements.

---

## Original System Requirements

The original README specifies the following requirements:

| Tool | Original Version |
|---|---|
| Ubuntu | 20.04 LTS |
| Python | v3.8 |
| Mininet | v2.2.2 |
| Apache Maven | 3.6.3 |
| Gradle | 4.4.1 |
| JDK | v1.8 (OpenJDK 1.8.0_422) |
| CICFlowMeter | v4.0 |
| MHDDoS | v2.4.1 |
| TShark | 3.2.3 |

These versions were tested together on Ubuntu 20.04 LTS, which reached **End of Life in April 2025** and no longer receives security updates. Running the testbed on a more recent Ubuntu release requires addressing compatibility gaps across several of these components.

---

## Adapted System Requirements

| Tool | Adapted Version |
|---|---|
| Ubuntu | 24.04 LTS (Noble Numbat) |
| Python | v3.12 |
| Mininet | v2.3.1b4 |
| Apache Maven | 3.8.7 |
| Gradle (system) | 4.4.1 |
| Gradle (CICFlowMeter wrapper) | 4.2 |
| JDK | OpenJDK 1.8.0_482 |
| CICFlowMeter | v4.0 |
| MHDDoS | v2.4 |
| TShark | 4.2.2 |

> **Note:** JDK, Maven, and Gradle are not standalone testbed components — they are build
> dependencies required exclusively to compile and run CICFlowMeter v4.0. Their versions are
> dictated by CICFlowMeter's build system and are documented in full in the CICFlowMeter
> section below.

---

## Ubuntu: From 20.04 to 24.04

The original project targets **Ubuntu 20.04 LTS**. We chose to run on **Ubuntu 24.04 LTS** instead for the following reasons:

- Ubuntu 20.04 reached End of Life in April 2025 and no longer receives security patches.
- Ubuntu 24.04 LTS is supported until 2029 and ships with a modern kernel (6.8+) that provides better hardware support.
- All project dependencies can be made compatible with 24.04 with minor adaptation.

### Key difference: Python packaging policy

Ubuntu 24.04 enforces **PEP 668**, which means the system Python environment (`/usr/lib/python3.12`) is marked as externally managed and blocks direct `pip install` calls system-wide. This affects any legacy installer that assumes unrestricted `pip` access.

---

## Mininet: From v2.2.2 to v2.3.1b4

### Original requirement

The README specifies **Mininet v2.2.2**, which was the stable release at the time of the project. The Ubuntu 24.04 apt repository packages **Mininet 2.3.0**, a newer but still outdated version.

### Why we went beyond the apt package

We needed a version beyond 2.3.0 for bug fixes available in the upstream GitHub repository. The apt-packaged version cannot be upgraded to a newer patch release through `apt` alone, so the installation was done from source via the official Mininet GitHub repository.

### Compatibility issues encountered on Ubuntu 24.04

Installing Mininet from source on Ubuntu 24.04 Noble revealed two distinct compatibility problems:

#### Issue 1 — `pep8` package renamed to `pycodestyle`

Mininet's `util/install.sh` script references the `pep8` apt package, which no longer exists on Ubuntu 24.04. It has been replaced by `pycodestyle`. The install script fails immediately with:

```
E: Package 'pep8' has no installation candidate
```

**Fix:** Patch the install script using `sed` to replace every occurrence of `pep8` with `pycodestyle` before running it:

```bash
sed -i 's/\bpep8\b/pycodestyle/g' util/install.sh
sudo apt install -y pycodestyle python3-pycodestyle
```

#### Issue 2 — PEP 668: externally managed Python environment

Mininet's installer internally calls `python3 -m pip install .` and `python3 -m pip uninstall` to install the Mininet Python package. Ubuntu 24.04 blocks these calls system-wide due to the externally managed environment policy introduced by PEP 668. The error shown is:

```
error: externally-managed-environment
× This environment is externally managed
```

All approaches involving environment variable overrides (`PIP_BREAK_SYSTEM_PACKAGES=1`) and `sudo -E` failed to propagate the override into the installer's subshell context.

**Fix:** Remove the Ubuntu-managed marker file that enforces this restriction. This is a deliberate one-time override for the purposes of installing a legacy application that predates the PEP 668 policy:

```bash
sudo rm /usr/lib/python3.12/EXTERNALLY-MANAGED
```

After removing this file, the Mininet installer completes successfully.



### Final working install sequence

```bash
# Install system dependencies
sudo apt install -y git python3-pip pycodestyle python3-pycodestyle \
    openvswitch-switch openvswitch-common openvswitch-testcontroller

# Clone the Mininet repository
cd ~
git clone https://github.com/mininet/mininet
cd mininet
git checkout master

# Patch the pep8 → pycodestyle rename
sed -i 's/\bpep8\b/pycodestyle/g' util/install.sh

# Lift the PEP 668 system pip restriction
sudo rm /usr/lib/python3.12/EXTERNALLY-MANAGED

# Run the Mininet installer
sudo ./util/install.sh -nfv

# Verify
mn --version
```

Expected output:
```
2.3.1b4
```

### Note on OpenFlow build warnings

During the install, the OpenFlow reference implementation (triggered by the `-f` flag) fails to compile due to a `strlcpy` type conflict between the legacy OpenFlow C code and modern GCC/glibc on Ubuntu 24.04. This error is **non-blocking** for Mininet itself since Open vSwitch (OVS 3.3.4) is the active switch backend and does not depend on the OpenFlow reference build. The warnings and errors from that step can be safely ignored.

### Verify Mininet + OVS

```bash
sudo systemctl start openvswitch-switch
sudo systemctl enable openvswitch-switch
sudo mn --test pingall
```

---

## Python Environment

### Strategy

The original project's `requirements.txt` pins `tensorflow==2.12.0` and `keras==2.12.0`, which have no published wheels for Python 3.12. Rather than creating a dedicated legacy virtualenv, we use the general-purpose `~/myenv` environment (Python 3.12) already present on the machine and install all missing dependencies into it at their latest compatible versions.

This approach is made possible by the weights-only loading strategy described in the Overview: since we never call `keras.models.load_model()` on the original checkpoint, there is no requirement to match the Keras version used during the original training run. The modern stack is fully sufficient.

### Environment in use

All project work runs inside `~/myenv`:

| Package | Version installed |
|---|---|
| Python | 3.12.3 |
| TensorFlow | 2.21.0 |
| Keras | 3.13.2 |
| NumPy | 2.4.4 |
| Mininet | 2.3.0.dev6 |
| Scapy | 2.7.0 |
| OVS (Python bindings) | 3.7.1 |

### Compatibility audit

A full audit of the project codebase for compatibility issues between the
original stack (Python 3.8 / TensorFlow 2.12 / Keras 2.12) and the adapted
stack (Python 3.12 / TensorFlow 2.21 / Keras 3.13) is ongoing. All
identified changes will be documented here as they are discovered and
resolved.

**Change 1 — Keras optimizer argument rename**

The original `build_model()` function uses the Keras 2 argument name `lr=`,
which was renamed to `learning_rate=` in Keras 3:

```python
# Original — raises TypeError on Keras 3
keras.optimizers.Adam(lr=self.learning_rate)

# Corrected — compatible with Keras 3
keras.optimizers.Adam(learning_rate=self.learning_rate)
```

This applies only when building student models. The teacher model is never
compiled — only `load_weights()` and `predict()` are called on it.

### Packages installed

All packages required by the project are present in `~/myenv`. The
environment was built incrementally: a general-purpose base (TensorFlow,
Keras, NumPy, Jupyter, pandas, scikit-learn, Flask, Scapy, OVS bindings,
Mininet) was already in place, and the remaining project-specific
dependencies were added in four groups. The full installed set is
summarised by category below.

| Category | Key packages |
|---|---|
| ML / numerics | tensorflow 2.21.0, keras 3.13.2, numpy 2.4.4, scipy 1.17.1, scikit-learn 1.8.0, jax 0.9.2, pandas 3.0.2 |
| SDN / network emulation | mininet 2.3.0.dev6, ovs 3.7.1, scapy 2.7.0, netifaces, pydot, overrides |
| Network capture / analysis | dpkt 1.9.8, dnspython 2.8.0, icmplib 3.0.4, maxminddb 3.1.1 |
| Attack tooling (MHDDoS deps) | impacket 0.13.0, cloudscraper 1.2.71, pycryptodomex 3.23.0, ldap3 2.9.1, ldapdomaindump 0.10.0 |
| Auth / crypto | cryptography 46.0.6, bcrypt 5.0.0, paramiko 4.0.0, pyOpenSSL 26.0.0, pyasn1 0.6.3, oauthlib 3.3.1 |
| Web / HTTP | Flask 3.1.3, requests 2.33.1, httpx 0.28.1, cloudscraper 1.2.71 |
| Jupyter / visualisation | jupyterlab 4.5.6, matplotlib 3.10.8, seaborn 0.13.2 |
| Utilities | pytest 9.0.2, pyyaml 6.0.3, tqdm, colorama 0.4.6, distro 1.9.0 |


```

> Note: The `ipmininet==1.0` package in the original `requirements.txt` fails to install on Python 3.12 due to a `ModuleNotFoundError: No module named 'pkg_resources'` in its legacy `setup.py`. The package is not imported anywhere in the project codebase and was therefore skipped.
```

---

## TShark: From v3.2.3 to v4.2.2

### Original requirement

The README specifies **TShark 3.2.3**, which shipped with Ubuntu 20.04. TShark is used by the project to perform live packet capture on Mininet's virtual interfaces during each RL environment step, producing `.pcap` files that are subsequently processed by CICFlowMeter.

### Installation on Ubuntu 24.04

The Ubuntu 24.04 apt repository provides **TShark 4.2.2**, which is the version installed. No PPA or manual build was required. The command-line interface for packet capture has not changed in any breaking way between versions 3.2.3 and 4.2.2; all `tshark` invocations used by the project remain valid.

During installation, the system prompts whether non-superusers should be able to capture packets. Selecting **Yes** is required: TShark must be able to capture on Mininet's virtual interfaces without `sudo`, as the project's `CmdManager` invokes it from within a non-root Python process.

```bash
sudo apt update
sudo apt install tshark

# Allow the current user to capture without sudo
sudo usermod -aG wireshark $USER
newgrp wireshark
```

### Verification

```bash
tshark --version
```

Expected output (first line):
```text
TShark (Wireshark) 4.2.2 (Git v4.2.2 packaged as 4.2.2-1.1build3).
```

The installed build includes all libraries required by the project: `libpcap` with `TPACKET_V3` for high-performance ring-buffer capture, `MaxMind` for GeoIP resolution, and `PCRE2` for display filter matching.

---

## MHDDoS

### Original requirement

The README specifies **MHDDoS v2.4.1** as the DDoS attack simulator used
to generate attack traffic during each RL environment step. The project's
`HttpClient` triggers attack sessions against the victim server via the
MHDDoS `start.py` script, using Layer 4 and Layer 7 methods over a
configurable duration.

### Installation

MHDDoS is not distributed as a pip package. It is cloned directly from
the official GitHub repository and run as a standalone Python script.

```bash
cd ~/Documents
git clone https://github.com/MatrixTM/MHDDoS.git
cd MHDDoS
```

All dependencies listed in MHDDoS's own `requirements.txt` were already
present in `~/myenv` from the Python environment setup, with the exception
of `pyroxy`, which is installed directly from its GitHub source:

```bash
pip install git+https://github.com/MatrixTM/PyRoxy.git
```

### Verification

```bash
cd ~/Documents/MHDDoS
python start.py --help
```

Expected output (first line): 

```
MHDDoS - DDoS Attack Script With 57 Methods
```

---

### CICFlowMeter

### Original Requirement

The README specifies CICFlowMeter v4.0 as the network flow feature extractor. It processes
packet captures (`.pcap` files) and outputs CSV files containing 80+ flow-level features used
as input to the RL environment. The original project specifies JDK v1.8 (OpenJDK 1.8.0_422)
and Gradle 4.4.1 as build dependencies. Since v4.0 remains the most recent stable release of
CICFlowMeter and is still the version most widely referenced in the research literature, no
version adaptation was necessary — v4.0 is retained as-is.

### Java Version

The adapted environment plan initially targeted OpenJDK 21 LTS as the system JDK. However,
CICFlowMeter v4.0 strictly requires Java 8 for its Gradle build, and no other tool in the
testbed requires a newer JVM. OpenJDK 1.8.0_482 was therefore installed as the sole JDK and
confirmed as the active version:

```bash
sudo apt install openjdk-8-jdk
java -version
# openjdk version "1.8.0_482"
```



### Installation

CICFlowMeter is built from source using its bundled Gradle wrapper. The `jnetpcap` native
library is not available on Maven Central and must be installed manually from the copy bundled
inside the repository before the build can succeed.

```bash
# Install dependencies
sudo apt install maven libpcap-dev

# Clone the repository
cd ~/Documents
git clone https://github.com/ahlashkari/CICFlowMeter.git
cd CICFlowMeter

# Install jnetpcap into the local Maven repository
cd jnetpcap/linux/jnetpcap-1.4.r1425
mvn install:install-file -Dfile=jnetpcap.jar \
    -DgroupId=org.jnetpcap -DartifactId=jnetpcap \
    -Dversion=1.4.1 -Dpackaging=jar

# Copy native libraries to system path
sudo cp libjnetpcap.so /usr/lib/
sudo cp libjnetpcap-pcap100.so /usr/lib/
sudo ldconfig

# Build
cd ~/Documents/CICFlowMeter
chmod +x gradlew
./gradlew build
```

### Verification

```bash
./gradlew execute   # launches GUI
./gradlew exeCMD    # launches CLI mode used by the testbed
```

Expected output: `BUILD SUCCESSFUL` followed by the CICFlowMeter interface launching
without `UnsatisfiedLinkError`. The CLI mode confirms correct operation with:
