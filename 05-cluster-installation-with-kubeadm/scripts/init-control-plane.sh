#!/usr/bin/env bash
# init-control-plane.sh — run ONCE on the control-plane node, after prepare-node.sh.
#
# Usage:  sudo ADVERTISE_IP=192.168.122.10 ./init-control-plane.sh
#
#   ADVERTISE_IP  IP the API server announces to the other nodes (required)
#   POD_CIDR      Pod network; must match the CNI (Flannel default: 10.244.0.0/16)
#   CNI           flannel (default) or none (install your own, e.g. Calico/Cilium)
set -euo pipefail

: "${ADVERTISE_IP:?Set ADVERTISE_IP to the control-plane IP reachable by the workers}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
CNI="${CNI:-flannel}"
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo ">> kubeadm init (advertise ${ADVERTISE_IP}, pod CIDR ${POD_CIDR})"
kubeadm init \
  --apiserver-advertise-address="${ADVERTISE_IP}" \
  --pod-network-cidr="${POD_CIDR}"

echo ">> Configuring kubectl for ${TARGET_USER}"
mkdir -p "${TARGET_HOME}/.kube"
cp -f /etc/kubernetes/admin.conf "${TARGET_HOME}/.kube/config"
chown "$(id -u "${TARGET_USER}"):$(id -g "${TARGET_USER}")" "${TARGET_HOME}/.kube/config"
chmod 600 "${TARGET_HOME}/.kube/config"
export KUBECONFIG=/etc/kubernetes/admin.conf

if [[ "${CNI}" == "flannel" ]]; then
  echo ">> Installing Flannel CNI"
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
fi

echo
echo ">> Run this on each worker (as root) to join it:"
kubeadm token create --print-join-command
