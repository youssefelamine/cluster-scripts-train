# Operational Guide for OAR and Kadeploy on the Lab Cluster

## 1. Introduction

Using the lab’s cluster for the first time can be confusing. The workflow is not always obvious, and the available documentation may not answer the practical questions you face when you actually need to reserve a node, deploy an environment, and start working.

This documentation is meant to make that process clearer.

It focuses specifically on the **OAR deploy reservation and Kadeploy workflow**. This is the workflow you need when you want to deploy an operating-system environment on a reserved node and obtain root access inside that deployed system..

A normal reservation and a deploy reservation are not the same. A normal reservation gives you access to compute resources, but a deploy reservation allows Kadeploy to reinstall the node with a selected environment.

By the end, you should be able to:

```text
connect to the cluster
request a deploy reservation
identify the allocated node
list and inspect Kadeploy environments
deploy an environment
SSH into the deployed node
validate the deployed system
understand what is temporary and what is persistent
capture a customized image when needed
avoid the mistakes that can waste time or destroy temporary work
```

Commands are shown with the shell context where they should be executed. Pay attention to the prompt: commands run from YOUR_LOGIN@cluster, YOUR_LOGIN@kadeploy, and root@NODE_NAME are not interchangeable.

---

## 2. Cluster Access

Before connecting, you need to be on the LIP6 network or connected through the official LIP6 SSH gateway/VPN method. The host:

```text
cluster.lip6.fr
```

is only reachable from the LIP6 network.

From your local machine, connect with:

```bash
ssh YOUR_LOGIN@cluster.lip6.fr
```

Replace `YOUR_LOGIN` with your actual cluster login.

Example:

```bash
ssh elamine@cluster.lip6.fr
```

### First SSH connection

The first time you connect from your laptop, SSH may show a warning like this:

```text
The authenticity of host 'cluster.lip6.fr (132.227.xxx.xxx)' can't be established.
ECDSA key fingerprint is SHA256:xxxxqsJuDltWG8KQKYR/alOJH7UexxxxxxxxxxxI0.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type:

```text
yes
```

What it means:

```text
Your laptop has not seen cluster.lip6.fr before.
SSH is asking whether to trust and save this server identity.
After you type yes, the host key is stored in ~/.ssh/known_hosts.
```

Expected next output:

```text
Warning: Permanently added 'cluster.lip6.fr' ... to the list of known hosts.
```

After that, SSH asks for your password:

```text
YOUR_LOGIN@cluster.lip6.fr's password:
```

Use your LIP6 account password. In our case, this was the same password used for Wi-Fi access, not the GitLab or email password.

After a successful login, the prompt should look like:

```text
YOUR_LOGIN@cluster:~$
```

Example:

```text
elamine@cluster:~$
```

This is the cluster login host. It is the place where you start OAR reservations and access your persistent home directory. It is not the deployed experiment node.

### Locale warnings

After login, you may see warnings such as:

```text
-bash: warning: setlocale: LC_CTYPE: cannot change locale (UTF-8): No such file or directory
```

This is not blocking. It means your local terminal sent a locale setting that the cluster shell does not have configured exactly.

To silence the warnings for the current shell, run:

```bash
export LC_CTYPE=C
export LANG=C
```

Expected output:

```text
No output.
```

Interpretation:

```text
No output is normal. The shell variables were set successfully.
```

---

## 3. OAR Reservations

OAR is the resource manager used to reserve nodes on the cluster. Before deploying an environment, you need an OAR reservation of type `deploy`.

### Checking the cluster state

You can run:

```bash
oarstat
```

Purpose:

```text
Show currently running or waiting jobs.
Give a general idea of whether the cluster is busy.
```

This command is read-only. It does not reserve or cancel anything.

### Requesting a deploy reservation

To request any available deploy-capable node, run:

```bash
oarsub -t deploy -l /nodes=1 -I
```

Explanation:

```text
oarsub
Submit a job to OAR.

-t deploy
Request a deploy reservation. This is required for Kadeploy deployments.

-l /nodes=1
Request one node.

-I
Interactive mode. When the reservation starts, you get a shell.
```

This command asks for any available deploy-capable node. In practice, asking for any available node is usually faster than restricting the reservation to a specific node family.

### Requesting a specific node family

If you need a specific type of node, you can add a property constraint. For example:

```bash
oarsub -t deploy -l /nodes=1 -p "host like 'tall%'" -I
```

This restricts the reservation to hosts whose names match `tall%`.

Risk:

```text
A restrictive request may wait much longer than a general request.
```

During our work, restricting the request to a specific host pattern produced a very long start prediction. The safer default is to request any deploy-capable node unless the experiment really requires a specific node type.

### Start prediction and job ID

After submitting an interactive job, OAR may show something like:

```text
OAR_JOB_ID=1293089
# Interactive mode: waiting...
# [2026-06-08 14:22:09] Start prediction: 2026-09-05 12:16:37 (R=24,W=2:0:0,J=I,T=deploy ...)
```

Interpretation:

```text
OAR_JOB_ID is the unique identifier of your reservation.
Start prediction estimates when the job may start.
The estimate can be short or very long depending on cluster availability and constraints.
```

The OAR job ID is important because it is reused later by environment variables and node-list files.

### Walltime

If you do not specify walltime, OAR uses the cluster default. In our session, the default appeared to be about:

```text
2 hours
```

For longer deployment or image work, explicitly request more time:

```bash
oarsub -t deploy -l /nodes=1,walltime=4:00:00 -I
```

This requests one deploy node for four hours.

You can also request a longer time if allowed by policy, for example:

```bash
oarsub -t deploy -l /nodes=1,walltime=6:00:00 -I
```

Important note:

```text
Interactive walltime may be limited by cluster policy. In our notes, the maximum interactive walltime was understood to be 24 hours.
```

Why this matters:

```text
Anything stored only on the deployed node is temporary. If the reservation expires before you copy important files out, the work may be lost.
```

### Successful allocation

When the job starts successfully, your prompt changes to something like:

```text
YOUR_LOGIN@kadeploy:~$
```

Example:

```text
elamine@kadeploy:~$
```

This means you are now on the Kadeploy host attached to your deploy reservation.

You can confirm the context with:

```bash
hostname
```

Expected output:

```text
kadeploy
```

### Recovering the job ID

If you did not write down the job ID, run:

```bash
echo "$OAR_JOBID"
```

Example output:

```text
1293109
```



### Finding the allocated node

Run:

```bash
cat /tmp/deploynodes.${OAR_JOBID}
```

Example output:

```text
big10
```

Purpose:

```text
Show the node allocated to your deploy reservation.
This node name is used later with SSH and Kadeploy validation commands.
```

### Cancelling a waiting or active job

To cancel a job intentionally, run:

```bash
oardel YOUR_OAR_JOB_ID
```

Be careful with this command.

During our work, an earlier job ended with messages similar to:

```text
FRAG_JOB_REQUEST: User elamine requested to frag the job
EXTERMINATE_JOB: [Leon] Exterminate job
```

Interpretation:

```text
The job was explicitly cancelled/fragged by the user.
This was not a Kadeploy failure.
This was not an operating-system failure.
Any node-local changes were lost because the reservation ended.
```

Operational rule:

```text
Do not run oardel unless you intentionally want to end the reservation.
```

---

## 4. Kadeploy Environments

Kadeploy environments are the operating-system images that can be deployed onto reserved nodes. A typical workflow is:

```text
reserve a deploy node
deploy an existing environment
connect to the deployed node
install the tools and dependencies needed for your work
reboot and validate the setup
capture the customized system as a new image
copy the image to persistent storage
reuse that image in future sessions
```

The important point is that deployment modifies the reserved node, not the original shared environment.

### Listing available environments

From the Kadeploy host:

```text
YOUR_LOGIN@kadeploy:~$
```

run:

```bash
kaenv3 -l
```

Purpose:

```text
List environments already registered in Kadeploy.
```

Example output:

```text
Name                  Version User        Description
####                  ####### ####        ###########
debian-testing        6       root        Debian testing basic installation
debian10              9       root        Debian 10 basic installation
debian11              7       root        Debian 11 basic installation
debian12              7       root        Debian 12 basic installation
debian13              2       root        Debian 13 basic installation
debian9               13      root        Debian 9 basic installation
```

If your desired environment is registered, it should appear in this list.

### Inspecting an environment

To inspect a registered environment:

```bash
kaenv3 -p ENVIRONMENT_NAME
```

Purpose:

```text
Print the full descriptor of the environment.
This shows the image path, compression type, boot kernel, initrd, filesystem, and visibility.
```

### Finding environment files manually

Sometimes an environment may not appear in `kaenv3 -l`, but descriptor files may exist on disk.

To search for environment descriptors:

```bash
find /deploy/public_env -type f -name '*.env' 2>/dev/null
```

For a broader search, for example when looking for a distribution name:

```bash
find /deploy -type f \( -iname '*ubuntu*' -o -iname '*jammy*' -o -iname '*noble*' \) 2>/dev/null | head -50
```

Purpose:

```text
Locate environment descriptor files or image archives that may not be listed directly by kaenv3 -l.
```

You can adapt the search terms depending on what you need.

### Deploying an environment from a descriptor file

If you located a descriptor file, deploy it with:

```bash
kadeploy3 -a /deploy/public_env/env-name.env -f /tmp/deploynodes.${OAR_JOBID}
```

Explanation:

```text
kadeploy3
Run a Kadeploy deployment.

-a /path/to/file.env
Use an environment descriptor file directly.

-f /tmp/deploynodes.${OAR_JOBID}
Use the node list associated with the current OAR deploy reservation.
```

This does not modify the original recorded environment. It uses the shared descriptor and image archive as a source, then writes a deployed copy onto your reserved node.

Example:

```bash
kadeploy3 -a /deploy/public_env/ubuntu2204.env -f /tmp/deploynodes.${OAR_JOBID}
```

Expected output is long. A successful deployment may include:

```text
Deployment #D-b145a544-2905-42eb-b2b1-c004ab2f25ac started
Grab the tarball file /deploy/public_env/ubuntu2204.tar.xz
Grab the postinstall file /deploy/public_env/user_post_install_ubuntu2204.tgz
Launching a deployment of ubuntu2204:1 on big1
Performing a Deploy[SetDeploymentEnvUntrusted] step
  switch_pxe
  reboot
  wait_reboot
  create_partition_table
  format_deploy_part
  mount_deploy_part
End of step Deploy[SetDeploymentEnvUntrusted] after 280s
Performing a Deploy[BroadcastEnvKascade] step
  send_environment
  manage_admin_post_install
  manage_user_post_install
  check_kernel_files
  sync
End of step Deploy[BroadcastEnvKascade] after 122s
Performing a Deploy[BootNewEnvClassical] step
  switch_pxe
  umount_deploy_part
  reboot_from_deploy_env
  wait_reboot
End of deployment on cluster big after 719s
Deployment #D-b145a544-2905-42eb-b2b1-c004ab2f25ac done

The deployment is successful on nodes
big1
```

This can take several minutes. Do not interrupt it unless you are sure the job is stuck or failing.

What success proves:

```text
The environment descriptor was accepted.
The image archive was found.
The node was partitioned/formatted/deployed.
The node rebooted into the deployed environment.
```

### Deploying a registered environment by name

If the environment is already registered in `kaenv3`, deploy it with:

```bash
kadeploy3 -e ENVIRONMENT_NAME -f /tmp/deploynodes.${OAR_JOBID}
```

Explanation:

```text
-e ENVIRONMENT_NAME
Use a registered Kadeploy environment by name.
```

This is generally cleaner than deploying from a descriptor path when the environment is already registered.

### SSH into the deployed node

After deployment succeeds, remove any old SSH host key entry for the node:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
```

Example:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R big10
```

Purpose:

```text
Kadeploy redeploys the node, so the SSH host key may change.
This command removes the old key from your local known_hosts file on the Kadeploy host.
It does not modify the node itself.
```

Then connect:

```bash
ssh root@NODE_NAME
```

Example:

```bash
ssh root@big10
```

The first SSH connection may show:

```text
The authenticity of host 'big10 (192.168.xxx.xx)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type:

```text
yes
```

Expected next output:

```text
Warning: Permanently added 'big10' (ED25519) to the list of known hosts.
root@big10's password:
```

Use the Kadeploy root password:

```text
kadeploy
```

After a successful login, the prompt becomes:

```text
root@NODE_NAME:~#
```

Example:

```text
root@big10:~#
```

### Understanding the shell context

This distinction matters:

```text
YOUR_LOGIN@cluster:~$     cluster login host
YOUR_LOGIN@kadeploy:~$    Kadeploy/OAR deployment host
root@big10:~#             deployed node
```

Commands such as `kaenv3` and `kadeploy3` belong on:

```text
YOUR_LOGIN@kadeploy:~$
```

not inside:

```text
root@big10:~#
```

We encountered this exact mistake:

```text
root@big10:~# kaenv3 --help
kaenv3: command not found
```

The fix is simply:

```bash
exit
```

which returns from the deployed node to the Kadeploy host.

### Basic connectivity validation inside the deployed node

Once inside the deployed node, test internal cluster/DNS connectivity:

```bash
ping -c 3 cluster.lip6.fr
```

Expected output should look similar to:

```text
PING cluster.common.lip6.fr (132.227.198.206) 56(84) bytes of data.
64 bytes from cluster.common.lip6.fr (132.227.198.206): icmp_seq=1 ttl=64 time=7.69 ms
64 bytes from cluster.common.lip6.fr (132.227.198.206): icmp_seq=2 ttl=64 time=0.201 ms
64 bytes from cluster.common.lip6.fr (132.227.198.206): icmp_seq=3 ttl=64 time=0.173 ms

--- cluster.common.lip6.fr ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

Interpretation:

```text
DNS resolution works.
The node can reach the cluster frontend/internal service.
Network connectivity is functional.
```

### Installing tools and customizing the node

At this point, the deployed node can be configured for your work. You may install packages, libraries, drivers, experiment code, or monitoring tools depending on your project.

Before capturing a new image, it is usually a good idea to reboot once and validate that the system still works after reboot.

From inside the node:

```bash
reboot
```

You will be disconnected. Back on the Kadeploy host, wait and reconnect:

```bash
sleep 120
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
ping -c 3 NODE_NAME
ssh root@NODE_NAME
```

Important behavior:

```text
Ping may succeed before SSH is ready.
If SSH says Connection refused, wait another minute and try again.
```

A common mistake is merging commands accidentally:

```bash
sleep 120 ssh-keygen -f ~/.ssh/known_hosts -R big10
```

This fails with:

```text
sleep: invalid option -- 'f'
```

Correct form:

```bash
sleep 120
ssh-keygen -f ~/.ssh/known_hosts -R big10
```

### Capturing a customized image

After setting up the node, locate the image capture script:

```bash
ls -lah /root
```

Expected relevant file:

```text
-rwxr-xr-x 1 root root 3.5K Mar  5  2025 create_custom_image.sh
```

The script is:

```text
/root/create_custom_image.sh
```

Run it with your desired image name:

```bash
/root/create_custom_image.sh IMAGE_NAME.tar.bz2
```

Example:

```bash
/root/create_custom_image.sh my-custom-env.tar.bz2
```

Purpose:

```text
Capture the current deployed system into a deployable archive.
```

This can take several minutes because it compresses the root filesystem. Depending on image size and compression speed, 10–20 minutes is normal, and larger systems may take longer.

Expected successful output includes:

```text
Compressing current system to /image/IMAGE_NAME.tar.bz2...done.
Verifying integrity of archive /image/IMAGE_NAME.tar.bz2...done.

CONGRATULATIONS !!
Your new deployable environment is available in /image
```

If the script fails with:

```text
/bin/sh: 1: bzip2: not found
```

install the missing dependency:

```bash
apt update
apt install -y bzip2
```

Then rerun the capture script.

### Saving the captured image

The directory:

```text
/image
```

is temporary on the deployed node. The image must be copied out before the OAR job ends.

First check the captured image:

```bash
ls -lh /image/IMAGE_NAME.tar.bz2
```

Expected example:

```text
-rw-r--r-- 1 root root 2.3G Jun  8 15:06 /image/IMAGE_NAME.tar.bz2
```

Then copy it to persistent home storage:

```bash
scp /image/IMAGE_NAME.tar.bz2 YOUR_LOGIN@cluster.common.lip6.fr:~
```

Example:

```bash
scp /image/my-custom-env.tar.bz2 elamine@cluster.common.lip6.fr:~
```

This is the critical save step.

Once the file is copied to your home directory, it is safe to exit the deployed node or let the OAR job end. Without this copy, the image may be lost when the reservation ends.

From the cluster login host, verify:

```bash
ls -lh ~/IMAGE_NAME.tar.bz2
```

Expected:

```text
The file exists and has the expected size.
```

---

## 5. Persistent vs temporary storage

### 5.1 Persistent home directory

The user’s home directory is persistent:

```text
/home/YOUR_LOGIN/
```

Example from this work:

```text
/home/elamine/ubuntu2404-base.tar.bz2
```

Files copied here remain after the OAR reservation ends.

### 5.2 Kadeploy environment directory

The public Kadeploy environment directory is:

```text
/deploy/public_env/
```

It stores environment image archives and related files.

The validated Ubuntu 24.04 image is stored at:

```text
/deploy/public_env/ubuntu2404-base.tar.bz2
```

### 5.3 Temporary deployed-node storage

Inside a deployed node, directories such as:

```text
/image/
```

are temporary in practice. In the image-capture workflow, `/image` is created by the capture script and mounted as a temporary filesystem.

Example temporary image path:

```text
/image/image-name.tar.bz2
```

This is not safe until copied out to persistent storage.

Operational rule:

```text
If a file only exists inside root@NODE, assume it may be lost when the OAR job ends.
```  

---

## 6. Ubuntu 24.04 LTS

If your experiment requires Ubuntu 24.04 LTS, a clean base environment is already registered and usable:

```text
ubuntu2404-base
```

It was created, redeploy-tested, updated, cleaned, rebooted, and validated. It is intended as a clean base image for future work.

### Listing the environment

From the Kadeploy host:

```bash
kaenv3 -l
```

Expected output includes:

```text
Name                  Version User        Description
####                  ####### ####        ###########
debian-testing        6       root        Debian testing basic installation
debian10              9       root        Debian 10 basic installation
debian11              7       root        Debian 11 basic installation
debian12              7       root        Debian 12 basic installation
debian13              2       root        Debian 13 basic installation
debian9               13      root        Debian 9 basic installation
ubuntu2404-base       1       elamine     Ubuntu Server 24.04 LTS clean base ...
```

### Inspecting the environment

Run:

```bash
kaenv3 -p ubuntu2404-base
```

Confirmed descriptor:

```yaml
---
name: ubuntu2404-base
version: 1
description: Ubuntu Server 24.04 LTS clean base 
author: elamine
visibility: shared
destructive: true
os: linux
image:
  file: "/deploy/public_env/ubuntu2404-base.tar.bz2"
  kind: tar
  compression: bzip2
boot:
  kernel: "/boot/vmlinuz"
  initrd: "/boot/initrd.img"
  kernel_params: console=tty0 console=ttyS1,115200n8 net.ifnames=0 biosdevname=0
filesystem: ext4
partition_type: 131
multipart: false
```

Note:

```text
partition_type: 131 is the decimal representation of 0x83.
```

### Deploying the Ubuntu 24.04 environment

After reserving a deploy node and identifying it with:

```bash
cat /tmp/deploynodes.${OAR_JOBID}
```

run:

```bash
kadeploy3 -e ubuntu2404-base -f /tmp/deploynodes.${OAR_JOBID}
```

Expected result:

```text
The deployment is successful on nodes
NODE_NAME
```

Then connect:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
ssh root@NODE_NAME
```

Use password:

```text
kadeploy
```

### Health checks after deployment

Inside the deployed node, run:

```bash
cat /etc/os-release
uname -r
ip route
lsmod | grep bnx2
apt update
dpkg --audit
```

Expected healthy state:

```text
OS: Ubuntu 24.04.4 LTS / Noble
Kernel: 6.8.0-124-generic
Default route: via eth1
Public network: 132.227.198.0/24 on eth1
Private/deploy network: 192.168.198.0/24 on eth0
bnx2 driver: loaded
APT mirror reachable: LIP6 noble repository
dpkg --audit: no output
```

Example validated output:

```text
PRETTY_NAME="Ubuntu 24.04.4 LTS"
VERSION_ID="24.04"
VERSION_CODENAME=noble
6.8.0-124-generic
default via 132.227.198.254 dev eth1 proto dhcp src 132.227.198.54 metric 100
192.168.198.0/24 dev eth0 proto kernel scope link src 192.168.198.54 metric 100
bnx2                  122880  0
```

APT should end with either:

```text
All packages are up to date.
```

or it may report available upgrades. Available upgrades are not a deployment failure; they only mean the repositories have newer packages.

To update the deployed node:

```bash
apt upgrade -y
```

Then verify:

```bash
dpkg --audit
apt upgrade -y
```

Expected clean state:

```text
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```

and `dpkg --audit` should print nothing.

### Validated status of `ubuntu2404-base`

The environment was validated with the following checks:

```text
private redeploy test: passed
shared registration: confirmed
SSH access: passed
Ubuntu version check: passed
kernel check: passed
network route check: passed
bnx2 driver check: passed
APT update: passed
APT upgrade: passed
autoremove cleanup: passed
reboot test: passed
post-reboot validation: passed
dpkg audit: clean
```

The environment is ready to be used as a base system. After deployment, you can proceed with your project-specific setup.

---

## 7. When the Required Environment Is Not Available

If the environment you need is not available in `kaenv3 -l`, and you cannot find a suitable descriptor or image under `/deploy/public_env`, then you need to create a new Kadeploy environment.

There are two different cases.

The first case is when the environment you need is close to an existing one. For example, you may need another version of Ubuntu or Debian, or you may need the same operating system with a different software stack. In this case, the practical workflow is to deploy the closest available environment, customize it on the reserved node, capture the resulting system, and register it as a new environment.

The second case is when the environment you need is not close to any available environment. For example, it may be a different Linux distribution, a non-Debian-based system, or a system layout that is not already provided on the cluster. In that case, you cannot simply rely on the existing Debian or Ubuntu environments. You need to build or obtain a Kadeploy-compatible image yourself, then create a descriptor that correctly describes how Kadeploy should deploy and boot it.

In both cases, the final result must be the same: an image archive that Kadeploy can access, and a matching `.env` descriptor.

The general method is:

```text
1. Check registered environments with `kaenv3 -l`.
2. Check available descriptors and images under `/deploy/public_env`.
3. Decide whether an existing environment can be used as a base.
4. If a suitable base exists, deploy it and customize it on a reserved node.
5. If no suitable base exists, build or obtain a Kadeploy-compatible image for the target system.
6. Validate the system before capturing or registering it.
7. Capture or package the system into an image archive.
8. Copy the archive to persistent storage before the OAR job ends.
9. Place the archive somewhere Kadeploy can access it, usually `/deploy/public_env`.
10. Create a new `.env` descriptor matching the image.
11. Register the environment privately first.
12. Redeploy-test the environment from scratch.
13. Reboot-test and validate it again.
14. Only after successful validation, consider making it shared.
```

The important point is that Kadeploy does not only need an archive. It also needs a correct descriptor. The descriptor must match the actual image: image path, compression type, filesystem, boot kernel, initrd, and partition layout must all be consistent. If the descriptor and the image do not match, deployment may fail, or the node may deploy but fail to boot correctly.

### Why start private?

A new environment should be registered as private until it has been tested. Sharing an untested environment can waste other users' time if it fails to boot, lacks network drivers, has broken package state, points to the wrong image path, or uses a descriptor that does not match the image.

The recommended workflow is:

```text
private first
redeploy-test
reboot-test
validate
then consider shared
```

Do not use a shared visibility tag as a shortcut. Sharing should be the last step, not the first.

### Creating a descriptor

A descriptor has this general form:

```yaml
---
name: my-custom-env
version: 1
description: Short description of the environment
author: YOUR_LOGIN
visibility: private
destructive: true
os: linux
image:
    file: /deploy/public_env/my-custom-env.tar.bz2
    kind: tar
    compression: bzip2
boot:
    kernel: /boot/vmlinuz
    initrd: /boot/initrd.img
    kernel_params: "console=tty0 console=ttyS1,115200n8 net.ifnames=0 biosdevname=0"
filesystem: ext4
partition_type: 0x83
multipart: false
```

Important fields:

```text
name
The environment name used later with `kadeploy3 -e`.

visibility
Use `private` while testing. Change to `shared` only after validation.

image.file
The path to the image archive. The file must exist and be readable from the Kadeploy host.

compression
Must match the archive format. For `.tar.bz2`, use `bzip2`. For `.tar.xz`, use `xz`.

boot.kernel and boot.initrd
Paths used by Kadeploy to boot the deployed system. These paths must exist inside the image.

filesystem
Must match the filesystem expected in the image.

partition_type
For a standard Linux partition, `0x83` is commonly used. In printed Kadeploy output, this may appear as `131`, which is the decimal representation of `0x83`.

multipart
Use `false` for a single-partition image unless the image was explicitly built as multipart.
```

A descriptor is not only metadata. It is part of the deployment mechanism. If the descriptor is wrong, the environment may be registered but still fail during deployment or boot.

### Registering the environment

Environment registration is done from the Kadeploy host, not from inside the deployed node.

Correct context:

```text
YOUR_LOGIN@kadeploy:~$
```

Command:

```bash
kaenv3 -a ~/my-custom-env.env
```

Verify registration:

```bash
kaenv3 -l | grep my-custom-env
kaenv3 -p my-custom-env
```

What to check in `kaenv3 -p`:

```text
name
version
author
visibility
image.file
image.compression
boot.kernel
boot.initrd
filesystem
partition_type
multipart
```

If `kaenv3` is not found, you are probably in the wrong shell. For example, this is wrong:

```text
root@NODE_NAME:~# kaenv3
kaenv3: command not found
```

Go back to the Kadeploy host before using `kaenv3`.

### Deploy-testing the new environment

Deploy the environment on a fresh deploy reservation:

```bash
kadeploy3 -e my-custom-env -f /tmp/deploynodes.${OAR_JOBID}
```

A successful deployment should report that the deployment completed successfully on the reserved node.

Then remove the old SSH host key for the node:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
```

Connect to the deployed system:

```bash
ssh root@NODE_NAME
```

Inside the node, validate the system:

```bash
cat /etc/os-release
uname -r
ip route
apt update
dpkg --audit
```

For this cluster, if the node uses Broadcom network hardware, also check the `bnx2` driver:

```bash
lsmod | grep bnx2
```

Expected output:

```text
bnx2 ...
```

`dpkg --audit` should print nothing. No output is the expected clean result.

### Network and post-install concerns

Network configuration is one of the most important parts of a deployable environment. An image that boots but does not bring up networking is usually not usable in practice.

From our validation work, the expected interface layout was:

```text
eth0: private/deploy network, 192.168.198.0/24
eth1: public network, default route via 132.227.198.254
```

A typical correct route table includes:

```text
default via 132.227.198.254 dev eth1
192.168.198.0/24 dev eth0
```

Some administrator post-install logic may expect traditional network configuration behavior. In the validated environment, networking was handled by `systemd-networkd`, not `ifupdown`.

A non-blocking issue observed during validation was:

```text
systemd-networkd-wait-online may fail or time out, while actual networking still works.
```

Therefore, do not rely only on service status. Validate real connectivity:

```bash
ip route
ping -c 3 cluster.lip6.fr
apt update
```

If these work, the deployed system has functional networking even if a wait-online service reported a timeout.

### Reboot validation

A deploy test is not enough by itself. A new environment should also survive reboot.

From inside the deployed node:

```bash
reboot
```

After the node reboots, reconnect from the Kadeploy host:

```bash
sleep 120
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
ping -c 3 NODE_NAME
ssh root@NODE_NAME
```

If ping works but SSH returns `Connection refused`, wait and retry:

```bash
sleep 60
ssh root@NODE_NAME
```

This usually means the network is up before `sshd` has finished starting.

After reconnecting, repeat the validation checks:

```bash
cat /etc/os-release
uname -r
ip route
apt update
dpkg --audit
```

For Broadcom-based nodes:

```bash
lsmod | grep bnx2
```

The environment should boot again, keep networking, keep SSH access, and remain in a clean package state.

### Making the environment shared

After a successful redeploy test, reboot test, network test, APT test, and `dpkg --audit` check, the environment can be considered for sharing.

Check current visibility:

```bash
kaenv3 -p my-custom-env | grep visibility
```

Change visibility to shared:

```bash
kaenv3 -t shared --set-visibility-tag my-custom-env
```

Verify:

```bash
kaenv3 -p my-custom-env | grep visibility
kaenv3 -l | grep my-custom-env
```

Important:

```text
Only make an environment shared if cluster or lab policy allows it.
If unsure, ask the administrator or your supervisor before publishing it for other users.
```

### Final operational rule

Before ending an OAR job, make sure every important artifact exists outside the deployed node.

At minimum, verify that:

```text
the image archive has been copied to persistent storage
the `.env` descriptor has been saved
the environment has been registered or the descriptor is stored safely
the registered environment has been checked with `kaenv3 -l` or `kaenv3 -p`
any validation notes or commands needed for reproducibility have been saved
```

If the only copy of your work is still inside `root@NODE_NAME`, it is not safe. The deployed node is temporary, and its local state can disappear when the OAR reservation ends.

##  Appendix A — Validated `ubuntu2404-base` outputs

###  `kaenv3 -l`

```text
Name                  Version User        Description
####                  ####### ####        ###########
debian-testing        6       root        Debian testing basic installation
debian10              9       root        Debian 10 basic installation
debian11              7       root        Debian 11 basic installation
debian12              7       root        Debian 12 basic installation
debian13              2       root        Debian 13 basic installation
debian9               13      root        Debian 9 basic installation
ubuntu2404-base       1       elamine     Ubuntu Server 24.04 LTS clean base ...
```

###  `kaenv3 -p ubuntu2404-base`

```yaml
---
name: ubuntu2404-base
version: 1
description: Ubuntu Server 24.04 LTS clean base 
author: elamine
visibility: shared
destructive: true
os: linux
image:
  file: "/deploy/public_env/ubuntu2404-base.tar.bz2"
  kind: tar
  compression: bzip2
boot:
  kernel: "/boot/vmlinuz"
  initrd: "/boot/initrd.img"
  kernel_params: console=tty0 console=ttyS1,115200n8 net.ifnames=0 biosdevname=0
filesystem: ext4
partition_type: 131
multipart: false
```

###  OS

```text
PRETTY_NAME="Ubuntu 24.04.4 LTS"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
VERSION_CODENAME=noble
```

###  Kernel

```text
6.8.0-124-generic
```

###  Routes

```text
default via 132.227.198.254 dev eth1 proto dhcp src 132.227.198.54 metric 100
132.227.198.0/24 dev eth1 proto kernel scope link src 132.227.198.54 metric 100
192.168.198.0/24 dev eth0 proto kernel scope link src 192.168.198.54 metric 100
```

###  Driver

```text
bnx2                  122880  0
```

###  APT clean state

```text
All packages are up to date.
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```

###  dpkg

```text
dpkg --audit printed nothing
```

---

##  Appendix B — Commands by context

### Run from local machine

```bash
ssh YOUR_LOGIN@cluster.lip6.fr
```

### Run from `YOUR_LOGIN@cluster`

```bash
oarstat
oarsub -t deploy -l /nodes=1,walltime=4:00:00 -I
oardel OAR_JOB_ID
```

### Run from `YOUR_LOGIN@kadeploy`

```bash
hostname
echo "$OAR_JOBID"
cat /tmp/deploynodes.${OAR_JOBID}
kaenv3 -l
kaenv3 -p ENV_NAME
kadeploy3 -e ENV_NAME -f /tmp/deploynodes.${OAR_JOBID}
kadeploy3 -a /path/to/env.env -f /tmp/deploynodes.${OAR_JOBID}
ssh-keygen -f ~/.ssh/known_hosts -R NODE_NAME
ssh root@NODE_NAME
```

### Run from `root@NODE_NAME`

```bash
cat /etc/os-release
uname -r
ip route
lsmod | grep bnx2
apt update
dpkg --audit
apt upgrade -y
apt autoremove -y
reboot
/root/create_custom_image.sh IMAGE_NAME.tar.bz2
ls -lh /image/IMAGE_NAME.tar.bz2
scp /image/IMAGE_NAME.tar.bz2 YOUR_LOGIN@cluster.common.lip6.fr:~
```

---

##  Appendix C — Operational checklist

Before deployment:

- [ ] connected from LIP6 network or official remote-access method;
- [ ] locale warnings handled if needed;
- [ ] deploy reservation granted;
- [ ] current prompt is `YOUR_LOGIN@kadeploy`;
- [ ] `OAR_JOBID` is known;
- [ ] node name identified through `/tmp/deploynodes.${OAR_JOBID}`.

During deployment:

- [ ] correct environment selected;
- [ ] `kadeploy3` run from Kadeploy host;
- [ ] deployment output says successful.

After deployment:

- [ ] stale SSH key removed;
- [ ] SSH to `root@NODE_NAME` succeeds;
- [ ] OS version validated;
- [ ] kernel validated;
- [ ] routes validated;
- [ ] `bnx2` loaded;
- [ ] APT works;
- [ ] `dpkg --audit` clean.

Before sharing an image:

- [ ] image redeploys successfully;
- [ ] SSH works;
- [ ] post-reboot validation passes;
- [ ] APT clean;
- [ ] `dpkg` clean;
- [ ] image copied to persistent `/deploy/public_env`;
- [ ] descriptor inspected with `kaenv3 -p`;
- [ ] visibility intentionally set;
- [ ] lab policy respected.

---


