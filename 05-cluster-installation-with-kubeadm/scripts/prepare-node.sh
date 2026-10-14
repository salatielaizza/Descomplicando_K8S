#!/usr/bin/env bash
# prepare-node.sh — run on EVERY node (control plane and workers) before kubeadm init/join.
#
# Tested targets: Ubuntu 22.04/24.04 and Debian 12 (amd64/arm64).
# Usage:  sudo KUBE_MINOR=v1.36 ./prepare-node.sh
#
# What it does:
#   1. disables swap (now and on reboot)
#   2. loads overlay + br_netfilter kernel modules
#   3. sets the sysctls Kubernetes networking needs
#   4. installs containerd (Docker apt repo) and switches it to the systemd cgroup driver
#   5. installs kubelet, kubeadm, kubectl from pkgs.k8s.io and pins them
set -euo pipefail

KUBE_MINOR="${KUBE_MINOR:-v1.36}"   # Kubernetes minor version; check https://kubernetes.io/releases/

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
  ubuntu|debian) ;;
  *) echo "Unsupported distro: ${ID}. Use Ubuntu or Debian." >&2; exit 1 ;;
esac

echo ">> 1/5 Disabling swap"
swapoff -a
sed -ri '/\sswap\s/ s/^#?/#/' /etc/fstab

echo ">> 2/5 Loading kernel modules"
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo ">> 3/5 Setting sysctls"
cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo ">> 4/5 Installing containerd"
apt-get update -q
apt-get install -y -q ca-certificates curl gpg apt-transport-https
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get install -y -q containerd.io

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
if grep -q 'SystemdCgroup' /etc/containerd/config.toml; then
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
else
  echo "!! SystemdCgroup key not found in the default config of this containerd version."
  echo "!! Add 'SystemdCgroup = true' under the runc runtime options, see:"
  echo "!! https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd"
fi
systemctl restart containerd
systemctl enable containerd >/dev/null

echo ">> 5/5 Installing kubelet, kubeadm, kubectl (${KUBE_MINOR})"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -y -q kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable --now kubelet

echo
echo "Node ready for kubeadm. kubelet will crash-loop until 'kubeadm init' or 'kubeadm join' runs — that is expected."
kubeadm version -o short
