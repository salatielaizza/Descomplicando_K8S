# 05 — Building a Multi-Node Cluster with kubeadm

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 5
> **Lab environment:** 3 Linux machines — 1 control plane + 2 workers (VMs on KVM/libvirt, VirtualBox, Multipass, or cloud instances). Ubuntu 22.04/24.04 or Debian 12, **2 vCPU / 2 GB RAM minimum each**.

## Learning objectives

By the end of this module you should be able to:

- Describe what runs on a **control-plane** node and on a **worker** node, and how the components talk to each other.
- Prepare a Linux host for Kubernetes: swap, kernel modules, sysctls, container runtime, cgroup driver.
- Bootstrap a cluster with **`kubeadm init`**, join workers with **`kubeadm join`**, and regenerate an expired join token.
- Explain the **kubeconfig** file (`admin.conf`): clusters, users, contexts, and why it must be protected.
- Explain what a **CNI plugin** is, why nodes stay `NotReady` without one, and how to pick one.
- Inspect nodes (`kubectl describe node`): capacity vs. allocatable, conditions, taints.

### Why it matters in production

Managed services (EKS, GKE, AKS) hide the control plane, but the moment something breaks — certificates expire, a node is `NotReady`, the kubelet can't reach the API server, a cluster upgrade fails — you need to know what kubeadm built and where it lives (`/etc/kubernetes/`, static Pods, `/var/lib/kubelet`). The CKA exam is built around a kubeadm cluster. Self-managed clusters on bare metal and on-prem VMs (common in telcos and regulated industries) are mostly kubeadm-based or Kubespray/Ansible-based, which uses kubeadm underneath.

---

## Module layout

```
05-cluster-installation-with-kubeadm/
├── README.md                    # this file
├── commands.md                  # command cheat sheet (node prep, kubeadm, kubeconfig, nodes)
├── scripts/
│   ├── prepare-node.sh          # run on every node: swap, modules, sysctl, containerd, kubelet/kubeadm/kubectl
│   └── init-control-plane.sh    # run on the control plane: kubeadm init + kubeconfig + Flannel + join command
└── course-notes-pt-br.md        # original course notes (Portuguese), kept unchanged for reference
```

This day has **no manifests**: it is all about building the cluster itself. The scripts automate the steps you should first run **by hand** at least once.

> The original course notes use the legacy `apt.kubernetes.io` repository and Weave Net. Both are gone — see [Known issues in the course notes](#known-issues-in-the-course-notes). The scripts and this README use the current community repository `pkgs.k8s.io` and Flannel.

---

## Key concepts

### Cluster anatomy

```
              ┌──────────────── control plane (k8s-01) ────────────────┐
 kubectl ───► │ kube-apiserver :6443 ◄─┬─ kube-scheduler                 │
              │        │               ├─ kube-controller-manager        │
              │        ▼               │                                 │
              │      etcd :2379-2380   │   (all four run as static Pods) │
              │ kubelet + containerd + kube-proxy + CNI agent            │
              └──────────────────────────────────────────────────────────┘
                        ▲ HTTPS (TLS client certs)
         ┌──────────────┴──────────────┐
  ┌──── worker (k8s-02) ────┐   ┌──── worker (k8s-03) ────┐
  │ kubelet :10250          │   │ kubelet :10250          │
  │ containerd, kube-proxy  │   │ containerd, kube-proxy  │
  │ CNI agent, your Pods    │   │ CNI agent, your Pods    │
  └─────────────────────────┘   └─────────────────────────┘
```

| Component | Role |
|---|---|
| **kube-apiserver** | The only entry point: authenticates, authorizes, validates and persists every request. Everything else talks to it. |
| **etcd** | Distributed key-value store holding the whole cluster state. Back it up. |
| **kube-scheduler** | Picks a node for each new Pod (requests, taints, affinity…). |
| **kube-controller-manager** | Runs the control loops (Deployment, ReplicaSet, Node, Job…) that move current state toward desired state. |
| **kubelet** | Agent on every node; starts containers through the CRI and reports status. Not a Pod — a systemd service. |
| **container runtime** | containerd / CRI-O, speaking the CRI. Docker Engine is no longer supported directly (dockershim removed in 1.24). |
| **kube-proxy** | Programs iptables/IPVS/nftables rules so Service IPs reach Pods. Some CNIs (Cilium) can replace it. |
| **CNI plugin** | Gives each Pod an IP and routes Pod-to-Pod traffic across nodes. |
| **CoreDNS** | Cluster DNS (`<svc>.<ns>.svc.cluster.local`). |

### Static Pods

kubeadm writes the control-plane components as manifests in **`/etc/kubernetes/manifests/`**. The kubelet watches that directory and runs them directly, without the API server — which is how the API server can run "inside" the cluster it serves. Edit a file there and the kubelet restarts the component.

### Host prerequisites — and why

| Step | Why |
|---|---|
| `swapoff -a` | The kubelet's memory accounting and QoS assume no swap; kubeadm preflight fails if swap is on (swap support exists since 1.28 but needs explicit config). |
| `overlay` module | Filesystem used by containerd for image layers. |
| `br_netfilter` + `bridge-nf-call-iptables=1` | Lets iptables see bridged Pod traffic, required by kube-proxy and most CNIs. |
| `ip_forward=1` | Nodes must route packets between Pods and Services. |
| `SystemdCgroup = true` | kubelet and runtime **must use the same cgroup driver**; kubeadm configures the kubelet for `systemd`. A mismatch causes Pods restarting randomly. |
| `apt-mark hold` | Prevents an `apt upgrade` from upgrading Kubernetes behind your back — upgrades go through `kubeadm upgrade`. |

### Required ports

| Node | Port | Protocol | Used by |
|---|---|---|---|
| Control plane | 6443 | TCP | kube-apiserver (everyone) |
| Control plane | 2379-2380 | TCP | etcd client / peer |
| Control plane | 10257, 10259 | TCP | controller-manager, scheduler (localhost) |
| All | 10250 | TCP | kubelet API (control plane → node: logs, exec) |
| Workers | 30000-32767 | TCP/UDP | NodePort Services |
| All | 8472 | UDP | Flannel VXLAN (Calico BGP: 179/TCP; Cilium VXLAN: 8472/UDP) |

### kubeconfig (`admin.conf`)

```yaml
apiVersion: v1
kind: Config
clusters:        # WHERE: API server URL + CA certificate
- name: kubernetes
  cluster: {server: https://<ip>:6443, certificate-authority-data: <base64 CA>}
users:           # WHO: client certificate + key (or token, or exec plugin)
- name: kubernetes-admin
  user: {client-certificate-data: <base64>, client-key-data: <base64>}
contexts:        # cluster + user (+ namespace) combinations
- name: kubernetes-admin@kubernetes
  context: {cluster: kubernetes, user: kubernetes-admin}
current-context: kubernetes-admin@kubernetes
```

`admin.conf` holds a **cluster-admin client certificate** (group `kubeadm:cluster-admins`): whoever has the file owns the cluster. Copy it with `chmod 600`, never commit it, and create per-user credentials (RBAC) for anything beyond the lab. The source certificates live in `/etc/kubernetes/pki/`.

### CNI

Kubernetes defines the network model (every Pod gets its own IP, every Pod can reach every other Pod without NAT) but does not implement it. Until a CNI plugin is installed, nodes are **`NotReady`** and CoreDNS stays `Pending`.

| Plugin | In one line |
|---|---|
| **Flannel** | Simplest overlay (VXLAN). No NetworkPolicy. Great for labs. |
| **Calico** | BGP or overlay, full NetworkPolicy, very common on-prem. |
| **Cilium** | eBPF data plane, NetworkPolicy L3-L7, can replace kube-proxy, observability (Hubble). Default in many managed offerings. |
| ~~Weave Net~~ | Used in the course; **archived** after Weaveworks shut down (2024). Do not use for new clusters. |

The Pod CIDR passed to `kubeadm init --pod-network-cidr` must match what the CNI expects (Flannel's default manifest: `10.244.0.0/16`) and must not overlap with your LAN or the Service CIDR (`10.96.0.0/12`).

---

## Hands-on lab

### 0. Machines

| Hostname | Role | Example IP |
|---|---|---|
| k8s-01 | control plane | 192.168.122.10 |
| k8s-02 | worker | 192.168.122.11 |
| k8s-03 | worker | 192.168.122.12 |

Requirements: unique hostname, MAC and `product_uuid` on each machine (`cat /sys/class/dmi/id/product_uuid` — cloned VMs often share it), full network connectivity between them, and the ports above open.

```bash
# On each machine — set the hostname and make names resolvable
sudo hostnamectl set-hostname k8s-01        # k8s-02, k8s-03 on the others
cat <<EOF | sudo tee -a /etc/hosts
192.168.122.10 k8s-01
192.168.122.11 k8s-02
192.168.122.12 k8s-03
EOF
```

### 1. Prepare every node

Run the steps by hand once following [`commands.md`](commands.md), or use the script:

```bash
# On k8s-01, k8s-02 and k8s-03
sudo KUBE_MINOR=v1.36 ./scripts/prepare-node.sh
```

Check:

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
grep SystemdCgroup /etc/containerd/config.toml
systemctl is-active containerd
kubeadm version -o short
```

### 2. Initialise the control plane

```bash
# On k8s-01 only
sudo ADVERTISE_IP=192.168.122.10 ./scripts/init-control-plane.sh
```

The manual equivalent is:

```bash
sudo kubeadm init --apiserver-advertise-address=192.168.122.10 --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes                          # k8s-01   NotReady   control-plane  ← no CNI yet
kubectl -n kube-system get pods            # coredns Pending
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl get nodes -w                       # → Ready
```

Look at what kubeadm created:

```bash
sudo ls /etc/kubernetes/ /etc/kubernetes/manifests/ /etc/kubernetes/pki/
kubectl -n kube-system get pods -o wide    # etcd, apiserver, scheduler, controller-manager = static Pods (suffix -k8s-01)
sudo kubeadm certs check-expiration        # certificates are valid for 1 year
```

### 3. Join the workers

The script prints the join command. Tokens expire after 24 h; generate a fresh one any time:

```bash
# On k8s-01
kubeadm token create --print-join-command
```

```bash
# On k8s-02 and k8s-03
sudo kubeadm join 192.168.122.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

```bash
# On k8s-01
kubectl get nodes -o wide
kubectl label node k8s-02 k8s-03 node-role.kubernetes.io/worker=     # optional: show "worker" in ROLES
```

### 4. Smoke test

```bash
kubectl create deployment nginx --image=nginx:1.27 --replicas=3
kubectl get pods -o wide                    # Pods spread over k8s-02 / k8s-03, IPs from 10.244.x.0/24
kubectl expose deployment nginx --port=80
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://nginx | head -4   # Service + DNS + CNI work
kubectl delete deployment,svc nginx
```

### 5. Inspect the nodes

```bash
kubectl describe node k8s-01 | sed -n '/Taints/p;/Conditions/,/Addresses/p;/Capacity/,/System Info/p'
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory,PODCIDR:.spec.podCIDR
kubectl config view                         # kubeconfig with secrets redacted
kubectl config get-contexts
```

### 6. Homework (from the course)

Rebuild the cluster with a **different CNI** (e.g. Calico or Cilium) and compare: install effort, Pods it adds to `kube-system`, and whether `NetworkPolicy` objects take effect. Use `sudo kubeadm reset -f` on every node to start over (see `commands.md`).

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| `kubeadm init` preflight: `[ERROR Swap]` | Swap enabled | `swapoff -a` and comment the swap line in `/etc/fstab` |
| Preflight: `/proc/sys/net/bridge/bridge-nf-call-iptables does not exist` / `ip_forward` not 1 | `br_netfilter` not loaded / sysctls not applied | `modprobe br_netfilter && sysctl --system` |
| Preflight: `container runtime is not running` | containerd stopped, or CRI plugin disabled in `config.toml` (`disabled_plugins = ["cri"]` from the distro default) | Regenerate with `containerd config default`, restart containerd |
| Nodes `NotReady`, CoreDNS `Pending` | No CNI installed | `kubectl apply` the CNI manifest |
| Flannel Pods `CrashLoopBackOff`: `failed to acquire lease … no podCIDR` | `--pod-network-cidr` missing or different from the CNI config | Re-init with `10.244.0.0/16` or edit `net-conf.json` in the Flannel ConfigMap |
| Control-plane Pods restarting every few minutes | cgroup driver mismatch (containerd `cgroupfs`, kubelet `systemd`) | `SystemdCgroup = true`, restart containerd + kubelet |
| `kubeadm join`: `token id … is invalid` / expired | Token older than 24 h | `kubeadm token create --print-join-command` |
| `kubeadm join` hangs on preflight | Port 6443 blocked or wrong `--apiserver-advertise-address` | `nc -vz <cp-ip> 6443` from the worker; firewall / security group |
| `The connection to the server localhost:8080 was refused` | kubectl has no kubeconfig | Copy `admin.conf` to `~/.kube/config` or `export KUBECONFIG` |
| `kubectl logs/exec` fail with `dial tcp <node>:10250` | Port 10250 blocked between control plane and node | Open 10250 |
| Two nodes with the same name / IP clashes | Cloned VMs (same hostname, MAC, `product_uuid`, machine-id) | Regenerate them before joining |
| `x509: certificate has expired` after a year | kubeadm certs are valid 1 year | `kubeadm certs renew all` (upgrades renew them automatically) |

---

## Known issues in the course notes

`course-notes-pt-br.md` is kept unchanged. When following it, be aware of:

| Topic | In the notes | Current state | Use instead |
|---|---|---|---|
| Package repo | `apt.kubernetes.io` / `packages.cloud.google.com` + `apt-key` | Legacy repos **frozen in Sept 2023 and removed in 2024**; `apt-key` deprecated | `pkgs.k8s.io` per-minor repos with a keyring (see `scripts/prepare-node.sh`) |
| CNI | Weave Net v2.8.1 | Project archived, no maintainers | Flannel, Calico or Cilium |
| Ports | "10250-10255 kubelet, 10255 read-only" | The read-only port 10255 is disabled by default; scheduler/controller-manager use 10259/10257 | See the [ports table](#required-ports) |
| Ports | "2380 is used only for election" | 2380 is etcd **peer** traffic (replication + Raft) | — |
| Pod CIDR | `10.10.0.0/16` | Fine for Weave; with Flannel's default manifest use `10.244.0.0/16`; check it doesn't overlap your LAN | — |
| Docker repo | `arch=amd64` hard-coded, Ubuntu-only URL | Breaks on ARM and on Debian | `$(dpkg --print-architecture)` and `$ID` from `/etc/os-release` |
| Sample output | Join token and CA hash printed in the notes | Example values from the instructor's lab — never publish real ones | — |

---

## Interview questions

<details>
<summary>1. What happens, step by step, when you run `kubectl apply -f deployment.yaml`?</summary>

kubectl sends the object to the **API server**, which authenticates, authorizes (RBAC), runs admission controllers and validates it, then stores it in **etcd**. The Deployment controller (controller-manager) sees it and creates a ReplicaSet; the ReplicaSet controller creates Pods. The **scheduler** assigns each Pod to a node. The **kubelet** on that node sees the Pod, asks the runtime (containerd via CRI) to pull the image and start containers, calls the **CNI** to set up networking, and reports status back to the API server.
</details>

<details>
<summary>2. Why are nodes NotReady right after `kubeadm init`?</summary>

There is no CNI plugin yet, so the kubelet reports `NetworkReady=false` (`cni plugin not initialized`). CoreDNS also stays Pending. Installing a CNI (Flannel, Calico, Cilium) fixes it.
</details>

<details>
<summary>3. How does the API server run as a Pod if the API server is needed to create Pods?</summary>

It is a **static Pod**: the kubelet reads manifests from `/etc/kubernetes/manifests/` and runs them directly, without the API server. Once the API server is up, the kubelet registers read-only "mirror Pods" so you can see them with `kubectl`.
</details>

<details>
<summary>4. Why must swap be disabled, and why `SystemdCgroup = true`?</summary>

The kubelet's memory guarantees, QoS and eviction assume memory can't be silently swapped (swap is now supported only with explicit configuration). The kubelet and the container runtime must use the same cgroup driver; on systemd distros both should use `systemd`, otherwise two managers fight over cgroups and Pods become unstable.
</details>

<details>
<summary>5. The join token expired. How do you add a new worker?</summary>

On the control plane: `kubeadm token create --print-join-command`, then run the printed command on the new node. The CA hash in the command lets the worker verify it is talking to the right control plane (protects against MITM).
</details>

<details>
<summary>6. What is in a kubeconfig, and what is a context?</summary>

Three lists — clusters (API URL + CA), users (credentials), contexts (cluster + user + optional namespace) — and a `current-context`. Switching context (`kubectl config use-context`) switches which cluster/identity kubectl uses. `admin.conf` is cluster-admin: protect it like a root password.
</details>

<details>
<summary>7. How would you back up a kubeadm cluster?</summary>

Snapshot etcd (`etcdctl snapshot save` with the certs from `/etc/kubernetes/pki/etcd/`) and back up `/etc/kubernetes/pki` (the CA). With those you can rebuild the control plane. Workloads should also be reproducible from Git (GitOps), and persistent volumes need their own backup (e.g. Velero).
</details>

<details>
<summary>8. kubeadm vs Kubespray vs a managed service — when would you pick each?</summary>

kubeadm: learning, CKA, small self-managed clusters, building block for other tools. Kubespray (Ansible over kubeadm): repeatable, multi-node, HA on-prem/bare-metal installs. Managed (EKS/GKE/AKS): when you don't want to operate the control plane — upgrades, etcd, HA and certificates are the provider's job; you pay for it and lose some control.
</details>

---

## References

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container runtimes — containerd and the systemd cgroup driver](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Ports and protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
- [Kubernetes package repositories (pkgs.k8s.io)](https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/)
- [Cluster networking / CNI add-ons](https://kubernetes.io/docs/concepts/cluster-administration/addons/)
- [Organizing cluster access using kubeconfig files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)

> **Course material:** `course-notes-pt-br.md` is LinuxTips course content. Keeping it in a public repository is an open decision (see the root README).
