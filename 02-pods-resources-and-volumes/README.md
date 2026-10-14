# 02 — Pods in Depth: Multi-Container, Resources & Volumes

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 2
> **Lab environment:** any local cluster (kind, minikube) — e.g. the clusters from [`01-kubernetes-fundamentals`](../01-kubernetes-fundamentals/)

## Learning objectives

By the end of this module you should be able to:

- Explain what a **Pod** is and what its containers share (network namespace / IP, volumes, lifecycle).
- Create Pods imperatively (`kubectl run`) and declaratively (`kubectl apply -f`), and know when `create` vs `apply` fails.
- Run and debug **multi-container Pods** (`-c <container>`, `exec` vs `attach`, `logs`).
- Set **requests and limits** for CPU and memory, and predict the result: throttling (CPU) vs. **OOMKilled** (memory).
- Read the **QoS class** Kubernetes assigns to a Pod and explain why it matters under node pressure.
- Mount an **emptyDir** volume and know its lifecycle and size limits.

### Why it matters in production

Almost every production incident involving a single workload ends up at the Pod: a container stuck in `CrashLoopBackOff`, an `OOMKilled` restart loop after a traffic spike, a node evicting `BestEffort` Pods first, or a sidecar that cannot see the files written by the main container. Sizing requests/limits correctly is also the basis of cluster capacity planning and cost control.

---

## Module layout

```
02-pods-resources-and-volumes/
├── README.md                     # this file
├── commands.md                   # kubectl cheat sheet for the day
├── manifests/
│   ├── pod.yaml                  # multi-container Pod: nginx + busybox (BestEffort QoS)
│   ├── pod-limitado.yaml         # ubuntu with CPU/memory requests & limits (Burstable)
│   ├── pod-emptydir.yaml         # nginx + emptyDir mounted at /giropops
│   └── pod-complete-day2.yaml    # everything together: limits + emptyDir + labels
├── challenge/
│   ├── README.md                 # the "hungry Pod" challenge and its solution
│   ├── pod-desafio-day2.yaml     # pod-faminto: memory limit too low → OOMKilled
│   └── pod-comportado.yaml       # pod-comportado: fixed limit → Running
└── day2 - Descomplicando o Kubernetes - Expert Mode.pdf   # course material (see note at the end)
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests) instead of being silently fixed, so this module also works as a "spot the problem" review exercise.

---

## Key concepts

### Pod
The smallest deployable unit in Kubernetes: a wrapper around **one or more containers** that are always scheduled together on the same node and share:

| Shared | Consequence |
|---|---|
| Network namespace (one IP) | Containers talk over `localhost`; two containers cannot bind the same port. |
| Volumes declared in `spec.volumes` | Each container chooses where (and whether) to mount them. |
| Lifecycle | The Pod is created, scheduled and deleted as a unit. |

Not shared by default: the filesystem of each image, and the process namespace (unless `shareProcessNamespace: true`).

### Multi-container Pods
Used for tightly coupled helpers: **sidecars** (log shippers, proxies), **adapters** and **ambassadors**. A container whose image has no long-running foreground process (alpine, busybox, ubuntu) exits immediately and the Pod goes into `CrashLoopBackOff` — that is why the manifests run `sleep`.

### `exec` vs `attach`

| Command | What it does | Typical use |
|---|---|---|
| `kubectl exec -it <pod> -c <ctr> -- sh` | Starts a **new process** inside the container | Debugging, inspecting files |
| `kubectl attach <pod> -c <ctr>` | Connects to the **main process** (PID 1) stdin/stdout | Rare; interactive main processes |

### Requests and limits

| Field | CPU | Memory |
|---|---|---|
| `requests` | Used by the **scheduler** to find a node with enough free capacity; guarantees a share of CPU | Used by the scheduler; the memory the container is expected to need |
| `limits` | Hard cap enforced by CFS — the container is **throttled**, never killed | Hard cap — exceeding it gets the container **OOMKilled** (exit code 137) |

Units: CPU `1` = 1 vCPU, `"0.5"` = `500m`; memory `Mi`/`Gi` (powers of 2) vs `M`/`G` (powers of 10).

### QoS classes
Assigned automatically from requests/limits; they decide **eviction order** when a node runs out of memory.

| QoS class | Rule | Evicted |
|---|---|---|
| `Guaranteed` | Every container has requests **=** limits for CPU and memory | Last |
| `Burstable` | At least one request or limit set, but not Guaranteed | Middle |
| `BestEffort` | No requests or limits at all | **First** |

In this module: `pod.yaml` → BestEffort, every other manifest → Burstable.

### emptyDir
A scratch volume created **empty when the Pod is scheduled** on a node and **deleted when the Pod is removed** (it survives container restarts, not Pod deletion). Backed by the node disk by default, or by RAM with `medium: Memory`. `sizeLimit` makes the kubelet evict the Pod if the volume grows beyond it. Main use: sharing files between containers of the same Pod, caches, temp space.

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl cluster-info          # a running cluster
cd 02-pods-resources-and-volumes
```

For `kubectl top` (section 3) you need metrics-server. On kind:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### 1. Imperative vs. declarative

```bash
kubectl run giropops --image=nginx:1.30 --port=80
kubectl get pods -o wide
kubectl get pod giropops -o yaml | less      # spec + status filled in by the cluster
kubectl delete pod giropops

# Generate a manifest without creating anything
kubectl run giropops --image=nginx:1.30 --port=80 --dry-run=client -o yaml > /tmp/pod-generated.yaml
```

### 2. Multi-container Pod — `manifests/pod.yaml`

```bash
kubectl apply -f manifests/pod.yaml
kubectl get pod girus                               # READY 2/2
kubectl describe pod girus                          # two containers: nginx, busybox

# Same network namespace: busybox reaches nginx on localhost
kubectl exec girus -c busybox -- wget -qO- http://localhost | head -n 4

kubectl logs girus -c nginx
kubectl get pod girus -o jsonpath='{.status.qosClass}{"\n"}'    # BestEffort
kubectl delete -f manifests/pod.yaml
```

> `busybox` runs `sleep 600`: after 10 minutes it exits, gets restarted and the `RESTARTS` counter grows. That is expected for this demo.

### 3. Requests and limits — `manifests/pod-limitado.yaml`

```bash
kubectl apply -f manifests/pod-limitado.yaml
kubectl describe pod giropops | grep -A6 -E 'Limits|Requests'
kubectl get pod giropops -o jsonpath='{.status.qosClass}{"\n"}'    # Burstable

# Burn CPU and watch it being throttled at the 500m limit
kubectl exec giropops -- bash -c 'timeout 60 yes > /dev/null &'
kubectl top pod giropops                            # CPU ~500m, never above

kubectl delete -f manifests/pod-limitado.yaml       # same Pod name is reused in step 4
```

### 4. emptyDir — `manifests/pod-emptydir.yaml`

```bash
kubectl apply -f manifests/pod-emptydir.yaml
kubectl exec -it giropops -c webserver -- sh -c 'touch /giropops/FUNCIONAAAAAA && ls -l /giropops && df -h /giropops'

# Survives a container restart...
kubectl exec giropops -c webserver -- sh -c 'kill 1'
kubectl get pod giropops -w                          # RESTARTS 1, Ctrl+C to stop
kubectl exec giropops -c webserver -- ls /giropops  # file still there

# ...but not the Pod
kubectl delete -f manifests/pod-emptydir.yaml
```

### 5. All together — `manifests/pod-complete-day2.yaml`

```bash
kubectl apply -f manifests/pod-complete-day2.yaml
kubectl get pod salatux --show-labels
kubectl get pods -l service=webserver
kubectl exec salatux -- ls -ld /salatux-volume
kubectl delete -f manifests/pod-complete-day2.yaml
```

### 6. Challenge

Go to [`challenge/README.md`](challenge/README.md): make a Pod get **OOMKilled** on purpose, explain why, and fix it.

### Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
kubectl delete namespace treinamento-ch2 --ignore-not-found
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| `CrashLoopBackOff` on alpine/busybox/ubuntu | No foreground process; container exits | `kubectl logs <pod> -c <ctr> --previous`; add `sleep`/a real command |
| `OOMKilled`, exit code `137` | Memory usage > `limits.memory` | `kubectl describe pod` → *Last State*; raise the limit or fix the leak |
| Pod stuck in `Pending`, event `Insufficient cpu/memory` | Requests larger than free capacity on every node | `kubectl describe node` → *Allocated resources*; lower requests or add nodes |
| App slow, no restarts, CPU flat at the limit | CPU throttling | `kubectl top pod`; raise `limits.cpu` or remove the CPU limit |
| `Error from server (AlreadyExists)` | `kubectl create` on an existing object, or two manifests with the same `metadata.name` | Use `apply`, or delete the old Pod first |
| `error: a container name must be specified` | Multi-container Pod without `-c` | Add `-c <container>` |
| Pod `Evicted`, message about `ephemeral-storage` / `emptyDir` | emptyDir grew beyond `sizeLimit` | `kubectl describe pod`; clean up the data or raise the limit |
| `namespaces "treinamento-ch2" not found` | Namespace not created | `kubectl create namespace treinamento-ch2` |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `challenge/pod-comportado.yaml`, `challenge/pod-desafio-day2.yaml` | Key `args` appears **twice** in the same container (an empty `args:` and the real one) | Invalid YAML for strict parsers: `kubeconform` errors, and recent `kubectl` (strict field validation) may reject it with a *duplicate field* error | Delete the empty `args:` line |
| all manifests | Untagged images (`nginx`, `ubuntu`, `busybox`, `polinux/stress`) → `:latest` | Non-reproducible; `imagePullPolicy: Always` by default | Pin tags, e.g. `nginx:1.30` |
| `manifests/pod-limitado.yaml` | Label typo `runl: giropops` | `kubectl get pods -l run=giropops` does not match it | `run: giropops` |
| `manifests/pod-limitado.yaml`, `manifests/pod-emptydir.yaml` | Both create a Pod named `giropops` | Cannot run at the same time | Unique names |
| `manifests/pod.yaml` | No requests/limits; `resources: {}` on nginx | `BestEffort` → first to be evicted | Add requests/limits |
| `manifests/pod-emptydir.yaml`, `pod-complete-day2.yaml` | Empty `args:` key | Harmless (`null`), but noise | Remove it |
| several | Trailing spaces, extra spaces after `-`, trailing blank line | Cosmetic (yamllint) | Run `yamllint` in CI |
| challenge files | Namespace `treinamento-ch2` has no manifest | `apply` fails until it exists | Add a `Namespace` manifest or create it first |

---

## Interview questions

<details>
<summary>1. What do containers in the same Pod share, and what don't they share?</summary>

They share the network namespace (same IP and port space, `localhost` communication), the volumes declared in the Pod, and IPC. Each keeps its own root filesystem from its image and, by default, its own PID namespace. They are always co-scheduled on the same node.
</details>

<details>
<summary>2. What happens when a container exceeds its CPU limit? And its memory limit?</summary>

CPU is compressible: the container is **throttled** by the CFS quota and keeps running, only slower. Memory is not compressible: the kernel OOM killer terminates the process, the status shows `OOMKilled` with exit code 137, and the kubelet restarts it according to `restartPolicy`.
</details>

<details>
<summary>3. What is the difference between requests and limits? Can a Pod use more than its request?</summary>

Requests are what the scheduler reserves on a node; limits are the runtime ceiling. Yes — a Pod can use more than its request up to its limit if the node has spare capacity (that is exactly the `Burstable` QoS class). If there is no limit, it can use whatever is free on the node.
</details>

<details>
<summary>4. Name the three QoS classes and how Kubernetes decides which Pods to evict first.</summary>

`Guaranteed` (requests = limits for CPU and memory in every container), `Burstable` (some requests/limits), `BestEffort` (none). Under memory pressure the kubelet evicts BestEffort first, then Burstable Pods that exceed their requests, and Guaranteed last.
</details>

<details>
<summary>5. A Pod is Pending with "0/3 nodes are available: 3 Insufficient memory". The nodes show plenty of free memory in `top`. Why?</summary>

The scheduler looks at **requests already allocated**, not real usage. Nodes can be fully *reserved* by other Pods' requests while actually being idle. Check `kubectl describe node` → *Allocated resources*, and right-size the requests of the existing workloads.
</details>

<details>
<summary>6. When does an emptyDir lose its data?</summary>

When the Pod is removed from the node (deleted, evicted, rescheduled). A container crash or restart does **not** wipe it. For data that must survive the Pod you need a PersistentVolume (module on storage).
</details>

<details>
<summary>7. `kubectl exec` vs `kubectl attach` — which one would you use to debug and why?</summary>

`exec`, because it starts a new process (e.g. a shell) without touching the main process. `attach` binds to PID 1's stdio — on nginx you would just see its output and could disrupt it with Ctrl+C if it reads stdin.
</details>

<details>
<summary>8. Should you always set a CPU limit?</summary>

It is debated. CPU limits protect neighbours but cause throttling even when the node is idle, which hurts latency-sensitive apps. A common practice: always set CPU **requests** and memory requests = limits, and set CPU limits only where noisy-neighbour isolation or strict multi-tenancy matters (or where a LimitRange/policy requires it).
</details>

---

## References

- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Resource management for Pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Pod Quality of Service classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Volumes — emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)
- [Debug running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

> **Course material:** the PDF is LinuxTips course content. Keeping it in a public repository is an open decision (see the root README).
