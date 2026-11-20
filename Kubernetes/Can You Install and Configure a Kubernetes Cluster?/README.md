# Can You Install and Configure a Kubernetes Cluster?

## Complete Challenge Lab -- Step-by-Step Guide

**Kubernetes version:** v1.30\
**Operating system:** Ubuntu Linux\
**Container runtime:** Docker\
**Container network plugin:** Flannel\
**Nodes:** 3

------------------------------------------------------------------------

## 1. Lab environment

This lab creates a Kubernetes cluster with one control-plane node and
two worker nodes.

  Node            Role            Purpose
  --------------- --------------- --------------------------------
  `k8s-master1`   Control plane   Manages the Kubernetes cluster
  `k8s-worker1`   Worker          Runs application workloads
  `k8s-worker2`   Worker          Runs application workloads

``` text
                  Kubernetes Cluster
                         |
                    k8s-master1
                    Control Plane
                         |
              -----------------------
              |                     |
         k8s-worker1           k8s-worker2
          Worker Node           Worker Node
```

### Login details

  Parameter          Value
  ------------------ ------------------------------
  Windows Server     WS2019
  Linux username     `administrator`
  Linux password     `Passw0rd!`
  Master hostname    `k8s-master1`
  Worker hostnames   `k8s-worker1`, `k8s-worker2`

> Use the credentials supplied by your lab environment. Do not save the
> SSH password when MobaXterm prompts you.

## 2. Connect to the nodes using MobaXterm

Repeat these steps for all three Ubuntu virtual machines:

1.  Open **MobaXterm**.
2.  Select **Session**, then **SSH**.
3.  Enter the hostname, starting with `k8s-master1`.
4.  Enter username `administrator`.
5.  Connect and enter the lab password when prompted.
6.  When asked whether to save the password, select **No**.
7.  Repeat for `k8s-worker1` and `k8s-worker2`.

Linux does not display password characters while you type. This is
expected. Keep all three SSH sessions open in separate tabs.

------------------------------------------------------------------------

## 3. Install Docker on all three nodes

Perform every command in this section on `k8s-master1`, `k8s-worker1`,
and `k8s-worker2`.

### 3.1 Update the APT package index

``` bash
sudo apt-get update
```

Enter the sudo password when prompted.

`apt-get update` downloads current package metadata from the configured
repositories. It does not install or upgrade packages.

### 3.2 Install Docker

``` bash
sudo apt-get install -y docker.io
```

-   `install` installs the requested package.
-   `-y` automatically confirms the installation.
-   `docker.io` is the Docker package supplied by Ubuntu's repository.

### 3.3 Enable Docker at boot

``` bash
sudo systemctl enable docker
```

This configures Docker to start automatically when the operating system
boots.

### 3.4 Start Docker now

``` bash
sudo systemctl start docker
```

This starts the Docker service immediately.

### 3.5 Verify Docker

``` bash
sudo systemctl status docker
docker --version
```

The service status should show:

``` text
Active: active (running)
```

------------------------------------------------------------------------

## 4. Configure Docker to use the systemd cgroup driver

Kubernetes and the container runtime should use compatible cgroup
drivers. This lab asks Docker to use `systemd`.

Perform these steps on all three nodes.

### 4.1 Ensure the Docker configuration directory exists

``` bash
sudo mkdir -p /etc/docker
```

### 4.2 Create or edit the Docker daemon configuration

``` bash
sudo vi /etc/docker/daemon.json
```

Add:

``` json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

Save and exit Vim by pressing `Esc`, typing `:wq`, and pressing `Enter`.

Alternatively, if the file does not contain existing settings, create it
with:

``` bash
echo '{
  "exec-opts": ["native.cgroupdriver=systemd"]
}' | sudo tee /etc/docker/daemon.json
```

> If `daemon.json` already contains settings, preserve them and merge in
> the `exec-opts` entry. Do not overwrite existing configuration
> unintentionally.

### 4.3 Restart Docker

``` bash
sudo systemctl restart docker
```

Docker reads its daemon configuration when it starts. Restarting it
applies the updated setting.

`systemctl daemon-reload` is not required just because
`/etc/docker/daemon.json` was changed. That command reloads systemd unit
definitions, not Docker's daemon JSON configuration.

### 4.4 Verify the cgroup driver

``` bash
docker info | grep -i "Cgroup Driver"
```

Expected:

``` text
Cgroup Driver: systemd
```

------------------------------------------------------------------------

## 5. Configure the Kubernetes v1.30 APT repository

Perform all steps in this section on all three nodes.

### 5.1 Create the APT keyrings directory

``` bash
sudo mkdir -p -m 755 /etc/apt/keyrings
```

-   `mkdir` creates a directory.
-   `-p` creates missing parent directories and does not fail if the
    directory already exists.
-   `-m 755` sets permissions so the owner can read, write, and access
    the directory, while group and other users can read and access it.

Verify:

``` bash
ls -ld /etc/apt/keyrings
```

### 5.2 Download and convert the Kubernetes repository signing key

``` bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Command breakdown:

  -----------------------------------------------------------------------
  Part                                Purpose
  ----------------------------------- -----------------------------------
  `curl`                              Downloads content from a URL

  `-f`                                Fails on HTTP errors

  `-s`                                Silent mode

  `-S`                                Displays errors even in silent mode

  `-L`                                Follows redirects

  `\|`                                Sends the downloaded content to the
                                      next command

  `gpg --dearmor`                     Converts the ASCII-armored key into
                                      binary OpenPGP format

  `-o`                                Specifies the output file
  -----------------------------------------------------------------------

The keyring is saved to:

``` text
/etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Verify that it exists:

``` bash
ls -l /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Ensure it is readable by APT:

``` bash
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

### 5.3 Add the Kubernetes v1.30 repository

Create the repository file:

``` bash
sudo vi /etc/apt/sources.list.d/kubernetes.list
```

Add this exact line:

``` text
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
```

Save and exit with `Esc`, `:wq`, and `Enter`.

Alternatively, create the file directly:

``` bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

**Important:** The final space and `/` are part of the repository entry.
The final `/` is the distribution suite. Omitting it can cause an APT
malformed-entry error.

Check the file:

``` bash
cat /etc/apt/sources.list.d/kubernetes.list
```

### 5.4 Update the APT package index

``` bash
sudo apt-get update
```

APT reads the new repository entry and downloads the package metadata.

### Troubleshooting: `Malformed entry ... (Suite)`

If APT reports:

``` text
E: Malformed entry 1 in list file /etc/apt/sources.list.d/kubernetes.list (Suite)
E: The list of sources could not be read.
```

Rewrite the repository entry exactly:

``` bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Then run:

``` bash
sudo apt-get update
```

------------------------------------------------------------------------

## 6. Install Kubernetes components on all three nodes

### 6.1 Install kubelet, kubeadm, and kubectl

``` bash
sudo apt-get install -y kubelet kubeadm kubectl
```

  -----------------------------------------------------------------------
  Component                           Purpose
  ----------------------------------- -----------------------------------
  `kubeadm`                           Initializes and configures a
                                      Kubernetes cluster

  `kubelet`                           Runs on each node and manages Pods

  `kubectl`                           Command-line client for
                                      communicating with the Kubernetes
                                      API
  -----------------------------------------------------------------------

### 6.2 Hold the packages

``` bash
sudo apt-mark hold kubelet kubeadm kubectl
```

Holding packages prevents them from being automatically upgraded by
normal APT upgrade operations.

Expected output will indicate that each package has been set on hold.

### 6.3 Verify installation and holds

``` bash
kubeadm version
kubelet --version
kubectl version --client
```

Check installed packages:

``` bash
dpkg -l | grep -E 'kubelet|kubeadm|kubectl'
```

Check held packages:

``` bash
apt-mark showhold
```

Expected held package names:

``` text
kubeadm
kubectl
kubelet
```

> Installing kubelet does not mean the node has joined a cluster. The
> control plane is initialized and the worker nodes join in later steps.

------------------------------------------------------------------------

## 7. Disable swap on all three nodes

Kubernetes kubelet commonly requires swap to be disabled for this lab's
configuration. Perform this step on the master and both workers.

### 7.1 Disable active swap

``` bash
sudo swapoff -a
```

`swapoff` disables swap; `-a` applies the operation to all active swap
devices and files.

### 7.2 Verify swap is disabled

``` bash
free -h
```

The Swap row should show zero used and zero total, for example:

``` text
Swap:            0B          0B          0B
```

You can also run:

``` bash
swapon --show
```

No output indicates that no swap areas are currently active.

### 7.3 Optional: keep swap disabled after reboot

Inspect `/etc/fstab`:

``` bash
cat /etc/fstab
```

If it contains an active swap entry, comment out that entry by adding
`#` at the beginning of the line. This makes the change persistent
across reboots.

------------------------------------------------------------------------

## 8. Initialize the Kubernetes control plane on k8s-master1

Perform this section on **k8s-master1 only**.

### 8.1 Initialize the cluster with the Flannel Pod CIDR

``` bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

  -----------------------------------------------------------------------
  Argument                            Purpose
  ----------------------------------- -----------------------------------
  `kubeadm init`                      Initializes the Kubernetes control
                                      plane

  `--pod-network-cidr`                Sets the IP address range for Pods

  `10.244.0.0/16`                     Pod network range used by the
                                      Flannel configuration in this lab
  -----------------------------------------------------------------------

The initialization process can take several minutes.

### 8.2 Save the worker join command

At the end of a successful initialization, kubeadm prints a command
similar to:

``` bash
kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

Copy the **actual command printed by your master node**, including the
token and hash. Save it in a Notepad file on WS2019.

> The placeholders above are examples only. Do not run them literally.
> The token and hash are unique to your cluster.

------------------------------------------------------------------------

## 9. Configure kubectl access for the administrator

Perform this section on **k8s-master1**.

### 9.1 Go to the administrator's home directory

``` bash
cd /home/administrator
pwd
```

Expected:

``` text
/home/administrator
```

### 9.2 Create the hidden `.kube` directory

``` bash
mkdir -p /home/administrator/.kube
```

A directory beginning with `.` is hidden in normal directory listings.

Verify:

``` bash
ls -la /home/administrator
```

### 9.3 Copy the administrator kubeconfig

``` bash
sudo cp -i /etc/kubernetes/admin.conf /home/administrator/.kube/config
```

Enter the sudo password if prompted.

-   Source: `/etc/kubernetes/admin.conf`
-   Destination: `/home/administrator/.kube/config`
-   `-i` prompts before overwriting an existing destination.

### 9.4 Set ownership

``` bash
sudo chown administrator:administrator /home/administrator/.kube/config
```

The first `administrator` is the owner; the second is the group.

Verify:

``` bash
ls -l /home/administrator/.kube/config
```

The owner and group should both be `administrator`.

### 9.5 Verify kubectl access

``` bash
kubectl get nodes
```

Nodes may show `NotReady` at this point because the cluster network
plugin has not yet been installed. This is expected.

------------------------------------------------------------------------

## 10. Join the worker nodes to the cluster

Perform these steps on **k8s-worker1** and then repeat on
**k8s-worker2**.

### 10.1 Open a root interactive shell

``` bash
sudo -i
```

Enter the lab sudo password if prompted.

Verify:

``` bash
whoami
```

Expected:

``` text
root
```

### 10.2 Join k8s-worker1

Paste the actual `kubeadm join` command saved from the master
initialization output.

Its format is:

``` bash
kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

Wait for the command to complete successfully.

### 10.3 Join k8s-worker2

Switch to the `k8s-worker2` SSH tab and open a root shell:

``` bash
sudo -i
```

Run the same actual join command:

``` bash
kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

Wait for the command to complete successfully.

### 10.4 Exit the root shell

On both worker nodes:

``` bash
exit
```

This returns you to the `administrator` account.

------------------------------------------------------------------------

## 11. Verify worker registration on the master

Switch to **k8s-master1** and run:

``` bash
kubectl get nodes
```

Before installing Flannel, the nodes may show `NotReady`, for example:

``` text
NAME          STATUS     ROLES           AGE   VERSION
k8s-master1   NotReady   control-plane   ...   ...
k8s-worker1   NotReady   <none>          ...   ...
k8s-worker2   NotReady   <none>          ...   ...
```

This is expected before the Pod network plugin is installed. Confirm
that both worker nodes appear in the list.

------------------------------------------------------------------------

## 12. Install the Flannel network plugin

Perform this step on **k8s-master1**.

Flannel provides Pod networking across the Kubernetes nodes. The Pod
CIDR used during initialization (`10.244.0.0/16`) must be compatible
with the Flannel configuration.

### 12.1 Apply the Flannel manifest

The lab supplies this command:

``` bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

-   `kubectl` is the Kubernetes command-line client.
-   `apply` creates or updates Kubernetes resources.
-   `-f` specifies the manifest file.
-   The URL points to the Flannel Kubernetes YAML manifest.

### 12.2 Verify Flannel Pods

``` bash
kubectl get pods -n kube-flannel
```

Wait for the Flannel Pods to reach `Running`.

Check all namespaces:

``` bash
kubectl get pods -A
```

### 12.3 Verify the cluster nodes

``` bash
kubectl get nodes
```

If any node is still `NotReady`, wait a few minutes and check again.

Expected final state:

``` text
NAME          STATUS   ROLES           AGE   VERSION
k8s-master1   Ready    control-plane   ...   v1.30.x
k8s-worker1   Ready    <none>          ...   v1.30.x
k8s-worker2   Ready    <none>          ...   v1.30.x
```

All three nodes should show `Ready`.

### 12.4 Additional cluster verification

``` bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-flannel
kubectl cluster-info
```

------------------------------------------------------------------------

## 13. Troubleshooting

### 13.1 APT malformed repository entry

**Error:**

``` text
E: Malformed entry 1 in list file
/etc/apt/sources.list.d/kubernetes.list (Suite)
E: The list of sources could not be read.
```

**Fix:**

``` bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

Check that the repository line ends with a space and `/`.

### 13.2 APT or dpkg lock error

**Error:**

``` text
E: Could not get lock /var/lib/dpkg/lock-frontend
```

Another package process may be running.

**Fix:** Wait a few minutes and retry. Do not delete APT lock files
while package-management processes may be active.

### 13.3 Docker cgroup driver mismatch

Check:

``` bash
docker info | grep -i "Cgroup Driver"
```

Expected:

``` text
Cgroup Driver: systemd
```

Inspect the configuration:

``` bash
cat /etc/docker/daemon.json
```

Expected:

``` json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

Restart and verify:

``` bash
sudo systemctl restart docker
docker info | grep -i "Cgroup Driver"
```

### 13.4 Swap is still enabled

Check:

``` bash
swapon --show
```

Disable:

``` bash
sudo swapoff -a
```

Verify:

``` bash
free -h
```

### 13.5 Worker nodes remain NotReady

On the master, check:

``` bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n kube-flannel
```

Inspect a worker:

``` bash
kubectl describe node k8s-worker1
```

Check that:

-   Swap is disabled on all nodes.
-   Docker is running.
-   The worker successfully joined the cluster.
-   Flannel is deployed and its Pods are running.
-   The Pod CIDR matches the Flannel configuration.

### 13.6 kubeadm join token expired

On the master, generate a new join command:

``` bash
sudo kubeadm token create --print-join-command
```

Copy the newly generated command and run it on the worker that needs to
join.

### 13.7 Container runtime / CRI socket error

Docker Engine does not directly implement the Kubernetes Container
Runtime Interface (CRI). Kubernetes v1.30 needs a CRI-compatible
runtime.

If `kubeadm init` reports that it cannot connect to a CRI endpoint, the
`cri-dockerd` adapter may need to be installed and configured in the lab
environment. Check the runtime socket and kubeadm configuration rather
than assuming that installing Docker alone provides CRI support.

------------------------------------------------------------------------

## 14. Complete command reference

This section collects the main commands in execution order.

### A. Docker installation --- all three nodes

``` bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo mkdir -p /etc/docker
sudo vi /etc/docker/daemon.json
```

Configuration:

``` json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

Restart and verify:

``` bash
sudo systemctl restart docker
docker info | grep -i "Cgroup Driver"
```

### B. Kubernetes repository --- all three nodes

``` bash
sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
```

### C. Kubernetes installation --- all three nodes

``` bash
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Verify:

``` bash
kubeadm version
kubelet --version
kubectl version --client
apt-mark showhold
```

### D. Disable swap --- all three nodes

``` bash
sudo swapoff -a
free -h
swapon --show
```

### E. Initialize the cluster --- master only

``` bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

Save the actual `kubeadm join` command printed by the initialization
process.

### F. Configure kubectl --- master only

``` bash
mkdir -p /home/administrator/.kube

sudo cp -i /etc/kubernetes/admin.conf /home/administrator/.kube/config

sudo chown administrator:administrator /home/administrator/.kube/config
```

### G. Join workers --- both worker nodes

``` bash
sudo -i
```

Run the actual join command generated on the master:

``` bash
kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

Then exit the root shell:

``` bash
exit
```

### H. Install Flannel --- master only

``` bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

### I. Final verification --- master only

``` bash
kubectl get nodes
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-flannel
kubectl cluster-info
```

------------------------------------------------------------------------

## 15. Final lab completion checklist

  Task                               k8s-master1   k8s-worker1   k8s-worker2
  ---------------------------------- ------------- ------------- -------------
  SSH connection established         \[ \]         \[ \]         \[ \]
  APT package index updated          \[ \]         \[ \]         \[ \]
  Docker installed                   \[ \]         \[ \]         \[ \]
  Docker enabled                     \[ \]         \[ \]         \[ \]
  Docker started                     \[ \]         \[ \]         \[ \]
  Docker systemd cgroup configured   \[ \]         \[ \]         \[ \]
  Kubernetes keyring created         \[ \]         \[ \]         \[ \]
  Kubernetes repository configured   \[ \]         \[ \]         \[ \]
  Kubernetes packages installed      \[ \]         \[ \]         \[ \]
  Kubernetes packages held           \[ \]         \[ \]         \[ \]
  Swap disabled                      \[ \]         \[ \]         \[ \]
  Cluster initialized                \[ \]         ---           ---
  kubeconfig configured              \[ \]         ---           ---
  Joined cluster                     ---           \[ \]         \[ \]
  Flannel installed                  \[ \]         ---           ---
  Node Ready status verified         \[ \]         \[ \]         \[ \]

------------------------------------------------------------------------

## 16. What you accomplished

After completing this challenge lab, you will have learned how to:

1.  Connect to Linux virtual machines using MobaXterm.
2.  Install Docker on multiple Ubuntu nodes.
3.  Configure Docker to use the systemd cgroup driver.
4.  Configure Kubernetes APT repositories and GPG signing keys.
5.  Install kubeadm, kubelet, and kubectl.
6.  Hold Kubernetes packages to prevent automatic upgrades.
7.  Disable swap on Kubernetes nodes.
8.  Initialize a Kubernetes control plane using kubeadm.
9.  Configure Kubernetes administrator access.
10. Join worker nodes to a Kubernetes cluster.
11. Install the Flannel network plugin.
12. Verify Kubernetes nodes and cluster health.

### Expected final cluster status

Run on `k8s-master1`:

``` bash
kubectl get nodes -o wide
```

All three nodes should be in the `Ready` state, and the Flannel Pods
should be running successfully.

> **Important:** After all lab checks pass, select the lab's **Submit**
> button to record completion. Do not exit the lab before submitting.
> Once submitted, the lab cannot be reopened.

------------------------------------------------------------------------

## 17. Official documentation

  --------------------------------------------------------------------------------------------------------------------------------
  Topic                               Documentation
  ----------------------------------- --------------------------------------------------------------------------------------------
  Kubernetes kubeadm installation     https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

  Kubernetes cgroup drivers           https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers

  Docker daemon configuration         https://docs.docker.com/config/daemon/

  APT sources.list                    https://manpages.ubuntu.com/manpages/focal/en/man5/sources.list.5.html

  APT package management              https://manpages.ubuntu.com/manpages/focal/en/man8/apt-get.8.html

  APT package hold                    https://manpages.ubuntu.com/manpages/focal/en/man8/apt-mark.8.html

  kubeadm init                        https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/

  Flannel                             https://github.com/flannel-io/flannel

  Kubernetes addons                   https://kubernetes.io/docs/concepts/cluster-administration/addons/
  --------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

**Lab:** Can You Install and Configure a Kubernetes Cluster?\
**Kubernetes version:** v1.30\
**Environment:** Ubuntu Linux --- three nodes\
**Network plugin:** Flannel\
**Completion criterion:** All three nodes are `Ready`.
