# Kadeploy Runtime Workflow

These scripts prepare and validate a reusable Ubuntu 24.04 Kadeploy image for
the repository's real Mininet/DDQN training workflow.

## Path Layout

```text
/root/project                         cloned project, retained in the image
/root/project/kadeploy_runtime        these scripts
/root/project/results                 training logs and train_<timestamp> runs
/root/project/tmp                     temporary PCAP/flow processing data
/opt/ddos-rl-venv                     Python virtual environment
/opt/ddos-rl-tools/MHDDoS             MHDDoS checkout
/opt/ddos-rl-tools/CICFlowMeter       built CICFlowMeter checkout
```

Setup also creates compatibility symlinks required by hardcoded project paths:

```text
/home/user12/myenv                    -> /opt/ddos-rl-venv
/home/user12/Documents/CICFlowMeter   -> /opt/ddos-rl-tools/CICFlowMeter
/root/MHDDoS                          -> /opt/ddos-rl-tools/MHDDoS
```

D-ITG and `tcpdump` are not installed because the active training path uses the
project's TCP client/server, MHDDoS, and TShark instead.

## Build And Capture

Run reservation and deployment commands from the Kadeploy/OAR host:

```bash
oarsub -t deploy -l /nodes=1,walltime=6:00:00 -I
NODE="$(cat /tmp/deploynodes.${OAR_JOBID})"
kaenv3 -p ubuntu2404-base
kadeploy3 -e ubuntu2404-base -f /tmp/deploynodes.${OAR_JOBID}
ssh-keygen -f ~/.ssh/known_hosts -R "$NODE"
ssh root@"$NODE"
```

On the deployed node, clone the repository at the required path:

```bash
git clone REPOSITORY_URL /root/project
cd /root/project
```

Run the image workflow as root:

```bash
/root/project/kadeploy_runtime/01_setup_image.sh
/root/project/kadeploy_runtime/02_check_image.sh
/root/project/kadeploy_runtime/03_smoke_test.sh
/root/project/kadeploy_runtime/04_clean_before_capture.sh
```

The smoke test runs the real entrypoint with one episode and one step:

```bash
/opt/ddos-rl-venv/bin/python3 reinforcement/Main.py \
  -a '[h1]' -e 1 -s 1 --checkpoint-every 1 --keep-last-checkpoints 1
```

It takes several minutes because the project performs real Mininet traffic,
packet capture, CICFlowMeter processing, and network-metric calculation.
`04_clean_before_capture.sh` removes only the tracked smoke run/log and
temporary caches. It preserves code, tools, the virtualenv, and any other
results.

Capture the cleaned node:

```bash
/root/create_custom_image.sh ddos-rl-ubuntu2404.tar.bz2
ls -lh /image/ddos-rl-ubuntu2404.tar.bz2
scp /image/ddos-rl-ubuntu2404.tar.bz2 YOUR_LOGIN@cluster.common.lip6.fr:~
```

The archive under `/image` is temporary. Copy it to persistent storage before
the OAR reservation ends. Register a matching private `.env` descriptor from
the Kadeploy host, then redeploy-test it before considering shared visibility.
See `/root/project/clusterdoc.md` for the descriptor and registration details.

## Later Training

Inside a node deployed from the captured image, start a default project run:

```bash
/root/project/kadeploy_runtime/start_training.sh
```

Pass normal entrypoint arguments through whitespace-separated `TRAIN_ARGS`:

```bash
TRAIN_ARGS="-a [h1] -e 50 -s 100 --checkpoint-every 5" \
  /root/project/kadeploy_runtime/start_training.sh
```

A non-interactive deploy job can deploy the captured environment and invoke the
same command over SSH. This assumes Kadeploy injects your SSH key for root
access; verify that `ssh -o BatchMode=yes root@NODE true` works before relying
on unattended jobs.

```bash
oarsub -t deploy -l /nodes=1,walltime=12:00:00 \
  'set -e
   NODE="$(cat /tmp/deploynodes.${OAR_JOBID})"
   kadeploy3 -e ddos-rl-ubuntu2404 -f /tmp/deploynodes.${OAR_JOBID}
   ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$NODE" || true
   set +e
   ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@"$NODE" \
     "TRAIN_ARGS='\''-a [h1] -e 50 -s 100 --checkpoint-every 5'\'' /root/project/kadeploy_runtime/start_training.sh"
   TRAIN_EXIT=$?
   scp -o BatchMode=yes -o StrictHostKeyChecking=no -r \
     root@"$NODE":/root/project/results "$HOME/ddos-rl-results-${OAR_JOBID}" || true
   exit "$TRAIN_EXIT"'
```

Adjust walltime and training arguments for the experiment. Results stored only
on the deployed node are temporary, so the example copies the complete results
directory to persistent home storage before the job ends.

## Logs And Results

The project creates each run under:

```text
/root/project/results/train_<timestamp>/
```

That directory contains figures, CSV data, CICFlowMeter outputs, model weights
and checkpoints, RL statistics, and configuration output. `start_training.sh`
moves its console log into the detected run directory as `training.log` and
writes `status.txt` plus `exit_code.txt` there. If training fails before the
project creates a run directory, those files remain in `/root/project/results`.

## Build Log: Successful Ubuntu 24.04 Image Capture

This section records the successful interactive build and capture session for the
custom DDOS-RL Ubuntu 24.04 image.

### Completed Work

- Deployed the clean Ubuntu 24.04 base environment and cloned the project to:

  ```text
  /root/project
  ```

- Ran the image setup script:

  ```bash
  ./kadeploy_runtime/01_setup_image.sh
  ```

  The setup installed and configured the Python environment, Mininet, Open
  vSwitch, Java, Gradle, CICFlowMeter, MHDDoS, TShark, and other required
  dependencies.

- Fixed Java 8 registration. Java 8 was installed, but it was not registered
  with `update-alternatives`, so `java` and `javac` were registered and selected
  manually. The validated Java version was:

  ```text
  Java 1.8.0_492
  ```

- Successfully ran the image validation script:

  ```bash
  ./kadeploy_runtime/02_check_image.sh
  ```

  It confirmed the required Python imports and validated Mininet, Open vSwitch,
  TShark, Java 8, `javac`, Maven, Gradle, CICFlowMeter, MHDDoS, `libpcap`,
  `jnetpcap`, and the required compatibility links.

- Ran the first smoke test. The test successfully created the Mininet network,
  generated TCP traffic, ran the ICMP attack, and captured packets. It later
  timed out with exit code `124` while invoking CICFlowMeter.

- Tested and fixed CICFlowMeter independently using:

  ```text
  /tmp/tshark_out.pcap
  ```

  Initially, Gradle printed:

  ```text
  Please select pcap!
  ```

  The project was passing the source and destination PCAP paths as Gradle
  properties, while CICFlowMeter expected command arguments. A Gradle
  compatibility configuration was added so those properties are passed correctly
  to the `exeCMD` task. The Gradle daemon was also disabled. After the fix, the
  exact project-style command succeeded and generated:

  ```text
  tshark_out.pcap_Flow.csv
  ```

- Diagnosed a Mininet cgroup failure on Ubuntu 24.04. Ubuntu 24.04 uses cgroup
  v2, while the virtualenv originally contained Mininet `2.3.0.dev6`, whose
  cgroup detection only supported cgroup v1. This caused:

  ```text
  cgroups not mounted on /sys/fs/cgroup
  ```

- Upgraded the Mininet package inside the virtualenv to the current upstream
  version. Final versions:

  ```text
  System Mininet:      2.3.0
  Virtualenv Mininet:  2.3.1b4
  ```

  The new virtualenv Mininet correctly supports cgroup v2.

- Fixed headless X terminal support. The project uses Mininet terminal commands
  for traffic generation and MHDDoS. On the headless node, `xhost` was missing
  or hanging, so the required X utilities were installed and a virtual display
  was started with:

  ```bash
  export DISPLAY=:99
  Xvfb :99 -ac -screen 0 1280x800x24
  ```

  The `-ac` option allowed Mininet terminal processes to start without X
  authorization problems.

- Cleaned stale processes between attempts, including suspended smoke-test jobs,
  Flask/EntryPoint processes, port `5000`, Mininet state, Open vSwitch state,
  and Gradle daemon processes.

- Successfully completed the smoke training. The final smoke test completed and
  printed:

  ```text
  (Reinforcement) ================> Main Ended
  ```

  The smoke test used one episode and one reinforcement-learning step. It
  successfully produced network traffic and attack data, CICFlowMeter results,
  network metrics, CSV files, training figures, model weights, and checkpoints.

- Copied the successful smoke-test result directory to persistent cluster
  storage using `scp`.

- Cleaned the node before capture with:

  ```bash
  ./kadeploy_runtime/04_clean_before_capture.sh
  ```

  This preserved the project code, Python virtualenv, installed tools, and
  required dependencies.

- Captured and copied the customized Ubuntu image. The image was captured as:

  ```text
  /image/ddos-rl-ubuntu2404.tar.bz2
  ```

  It was approximately `3.4 GB` and was copied to persistent storage at:

  ```text
  /home/elamine/ddos-rl-ubuntu2404.tar.bz2
  ```

  The image-creation process successfully verified the archive integrity.

### Notes For Future Rebuilds

- Do not treat an early smoke-test timeout as an installation failure if the log
  shows that Mininet, traffic generation, packet capture, and the attack all ran.
  Check CICFlowMeter and shutdown behavior first.
- Keep Java 8 explicitly registered with `update-alternatives`.
- Keep the virtualenv Mininet version at `2.3.1b4` or newer for Ubuntu 24.04
  cgroup v2 compatibility.
- Keep the Xvfb `:99` display configuration for headless Mininet terminal
  support.
- Disable the Gradle daemon for CICFlowMeter reliability in short smoke-test and
  non-interactive job contexts.
- Before capturing, always clean stale Mininet, Open vSwitch, Flask, Gradle,
  `tcpdump`/TShark, MHDDoS, and training processes.
