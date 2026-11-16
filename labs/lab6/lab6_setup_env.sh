#!/usr/bin/env bash
#
# install-kubernetes.sh
# Installs Docker, cri-dockerd, and Kubernetes (kubelet/kubeadm/kubectl)
# on Ubuntu 22.04 / 24.04.
#
# Based on: https://github.com/mialeevs/kubernetes_installation_docker
#
# This installs and configures the packages/prerequisites on a node.
# It does NOT run `kubeadm init` or `kubeadm join` — those need
# node-specific values (IPs, tokens) and are left for you to run
# afterwards. See the notes printed at the end.
#
# Usage:
#   chmod +x install-kubernetes.sh
#   ./install-kubernetes.sh          # run as a normal user with sudo rights
#
set -euo pipefail
 
# ---- Configuration ---------------------------------------------------------
# Kubernetes minor version stream (packages track this, e.g. v1.31, v1.32).
K8S_VERSION="${K8S_VERSION:-v1.31}"
 
# Whether to create a cluster on this node (set to "false" for worker nodes,
# which should run `kubeadm join` instead — see notes at the end).
INIT_CLUSTER="${INIT_CLUSTER:-true}"
 
# Pod network CIDR. Flannel's default manifest expects 10.244.0.0/16; change
# both this AND the Flannel net-conf if you use a different range.
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
 
# IP the API server advertises. Auto-detected from the default route; override
# with CONTROL_PLANE_IP=<ip> if the guess is wrong.
CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')}"
 
# Flannel CNI manifest.
FLANNEL_MANIFEST="${FLANNEL_MANIFEST:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}"
 
# ---- Helpers ---------------------------------------------------------------
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
 
# ---- Pre-flight checks -----------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
    die "Please run this script as a normal user (it uses sudo where needed), not as root."
fi
 
if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required but not installed."
fi
 
if ! command -v lsb_release >/dev/null 2>&1; then
    log "Installing lsb-release..."
    sudo apt-get update -y
    sudo apt-get install -y lsb-release
fi
 
UBUNTU_CODENAME="$(lsb_release -cs)"
log "Detected Ubuntu codename: ${UBUNTU_CODENAME}"
 
# ---- 1. Base packages ------------------------------------------------------
log "Installing base packages..."
sudo apt-get update -y
sudo apt-get install -y git wget curl socat conntrack ca-certificates gnupg apt-transport-https
 
# ---- 2. Docker repository + Docker Engine ----------------------------------
log "Setting up the Docker GPG key and repository..."
wget -O - https://download.docker.com/linux/ubuntu/gpg > /tmp/docker.key
gpg --no-default-keyring --keyring /tmp/docker.gpg --import /tmp/docker.key
gpg --no-default-keyring --keyring /tmp/docker.gpg --export > /tmp/docker-archive-keyring.gpg
sudo mv /tmp/docker-archive-keyring.gpg /etc/apt/trusted.gpg.d/
rm -f /tmp/docker.key /tmp/docker.gpg
 
sudo add-apt-repository -y \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
 
log "Installing Docker Engine..."
sudo apt-get update -y
sudo apt-get install -y docker-ce
 
# ---- 3. cri-dockerd --------------------------------------------------------
# Docker Engine does not implement the CRI required by Kubernetes,
# so cri-dockerd bridges that gap.
log "Installing cri-dockerd..."
VER="$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest \
    | grep tag_name | cut -d '"' -f 4 | sed 's/v//g')"
[[ -n "$VER" ]] || die "Could not determine the latest cri-dockerd version."
log "Latest cri-dockerd version: ${VER}"
 
TMPDIR="$(mktemp -d)"
pushd "$TMPDIR" >/dev/null
 
wget "https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.amd64.tgz"
tar xvf "cri-dockerd-${VER}.amd64.tgz"
sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
 
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
sudo mv cri-docker.socket cri-docker.service /etc/systemd/system/
sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' \
    /etc/systemd/system/cri-docker.service
 
sudo systemctl daemon-reload
sudo systemctl enable cri-docker.service
sudo systemctl enable --now cri-docker.socket
 
popd >/dev/null
rm -rf "$TMPDIR"
 
# ---- 4. Kubernetes repository + packages -----------------------------------
log "Setting up the Kubernetes GPG key and repository (${K8S_VERSION})..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
 
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list
 
log "Installing kubelet, kubeadm and kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
 
# Prevent accidental upgrades of these packages.
sudo apt-mark hold docker-ce kubelet kubeadm kubectl
 
# ---- 5. Kernel modules + sysctl (iptables bridge) --------------------------
log "Enabling kernel modules and sysctl parameters..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
 
sudo modprobe overlay
sudo modprobe br_netfilter
 
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
 
sudo sysctl --system
 
# ---- 6. Disable swap -------------------------------------------------------
log "Disabling swap..."
sudo swapoff -a
# Comment out any swap entries in /etc/fstab so it stays off across reboots.
sudo sed -i.bak -E 's@^([^#].*\bswap\b.*)$@# \1@' /etc/fstab
 
# ---- 7. Create the cluster + untaint + Flannel CNI -------------------------
if [[ "${INIT_CLUSTER}" == "true" ]]; then
    [[ -n "$CONTROL_PLANE_IP" ]] || \
        die "Could not auto-detect the control plane IP; re-run with CONTROL_PLANE_IP=<ip>."
 
    log "Initializing the control plane (advertise ${CONTROL_PLANE_IP}, pod CIDR ${POD_CIDR})..."
    sudo kubeadm init \
        --apiserver-advertise-address="${CONTROL_PLANE_IP}" \
        --cri-socket unix:///var/run/cri-dockerd.sock \
        --pod-network-cidr="${POD_CIDR}"
 
    # Configure kubectl for the current (non-root) user.
    log "Configuring kubectl for the current user..."
    mkdir -p "$HOME/.kube"
    sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
 
    # Wait for the node to register with the API server.
    log "Waiting for the node to register..."
    for _ in $(seq 1 30); do
        kubectl get nodes >/dev/null 2>&1 && break
        sleep 5
    done
 
    # Untaint the control-plane node so it can also run workloads
    # (needed for a single-node cluster). Both taint keys are tried to
    # cover different Kubernetes versions.
    log "Untainting the master/control-plane node..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
    kubectl taint nodes --all node-role.kubernetes.io/master-        2>/dev/null || true
 
    # Install the Flannel CNI.
    log "Installing the Flannel CNI..."
    kubectl apply -f "${FLANNEL_MANIFEST}"
 
    log "Waiting for the node to become Ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=180s || \
        warn "Node not Ready yet — check 'kubectl get pods -n kube-flannel' and 'kubectl get nodes'."
else
    log "INIT_CLUSTER is not 'true' — skipping cluster creation (worker-node mode)."
fi
 
# ---- Done ------------------------------------------------------------------
log "Installation complete."
 
if [[ "${INIT_CLUSTER}" == "true" ]]; then
cat <<'NOTE'
 
Single-node cluster is up. Verify with:
    kubectl get nodes
    kubectl get pods -A
 
To add WORKER nodes: run this script on them with INIT_CLUSTER=false, then
grab a join command from THIS control-plane node:
    kubeadm token create --print-join-command
 
...and append the cri-dockerd socket when joining:
    sudo kubeadm join <control_plane_ip>:6443 \
      --cri-socket unix:///var/run/cri-dockerd.sock \
      --token <token> \
      --discovery-token-ca-cert-hash sha256:<hash>
 
NOTE
else
cat <<'NOTE'
 
Worker-node prerequisites installed. Join it to the cluster with the command
printed on the control plane (`kubeadm token create --print-join-command`),
adding the cri-dockerd socket:
    sudo kubeadm join <control_plane_ip>:6443 \
      --cri-socket unix:///var/run/cri-dockerd.sock \
      --token <token> \
      --discovery-token-ca-cert-hash sha256:<hash>
 
NOTE