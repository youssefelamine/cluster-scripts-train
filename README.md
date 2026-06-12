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
