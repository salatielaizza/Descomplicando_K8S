# Day 5 — Command cheat sheet

Manual version of `scripts/prepare-node.sh` and `scripts/init-control-plane.sh`, plus day-2 operations.

## Prepare every node (as root)

```bash
# Swap
swapoff -a
sed -ri '/\sswap\s/ s/^#?/#/' /etc/fstab

# Kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

# Sysctls
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# containerd (Docker apt repo; Ubuntu shown — use "debian" on Debian)
apt-get update && apt-get install -y ca-certificates curl gpg apt-transport-https
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y containerd.io
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# kubelet / kubeadm / kubectl (pkgs.k8s.io — one repo per minor version)
KUBE_MINOR=v1.36
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBE_MINOR/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBE_MINOR/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update && apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet
```

## Control plane

```bash
kubeadm config images pull                         # optional: pre-pull images
kubeadm init --apiserver-advertise-address=<CP_IP> --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

## Workers

```bash
kubeadm token create --print-join-command          # on the control plane
kubeadm join <CP_IP>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>   # on each worker
```

## Inspect

```bash
kubectl get nodes -o wide
kubectl describe node <node>
kubectl -n kube-system get pods -o wide
kubectl config view
kubectl config get-contexts
kubectl config use-context <name>
kubeadm token list
kubeadm certs check-expiration
journalctl -u kubelet -f                           # kubelet logs (on the node)
crictl ps                                          # containers seen by the runtime (on the node)
```

## Start over

```bash
kubeadm reset -f                                   # on every node
rm -rf /etc/cni/net.d $HOME/.kube/config
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X   # kubeadm reset does not clean these
```
