# 06 — Persistent Storage: StorageClasses, PVs & PVCs

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 6
> **Lab environment:** kind or minikube for the hostPath part; an NFS server reachable from the nodes for the optional NFS part.

## Learning objectives

By the end of this module you should be able to:

- Explain why container filesystems and `emptyDir` are not enough for stateful data.
- Describe the **PersistentVolume (PV)** / **PersistentVolumeClaim (PVC)** / **StorageClass** model and who owns each object (admin vs. developer).
- Bind a PVC to a specific PV with `storageClassName` and a **label selector**.
- Explain **static vs. dynamic provisioning**, `volumeBindingMode: WaitForFirstConsumer`, **access modes** and **reclaim policies**.
- Mount a PVC in a Pod and a Deployment, and prove the data survives Pod deletion.
- Recover a `Released` PV with `Retain` policy.

### Why it matters in production

Databases, queues, uploaded files and caches all need storage that outlives a Pod. Getting the PVC/StorageClass details wrong shows up as Pods stuck in `Pending`, data written to the wrong node, volumes that can't be attached to a Pod on another availability zone, or — with `Delete` reclaim policy — data destroyed when someone removes a PVC.

---

## Module layout

```
06-persistent-volumes-and-storage/
├── README.md                     # this file
├── commands.md                   # kubectl cheat sheet for the day
└── manifests/
    ├── storageclass.yaml         # StorageClass "giropops": no-provisioner, Retain, WaitForFirstConsumer
    ├── pv.yaml                   # PV meu-pv: hostPath /mnt/data, 1Gi RWO, label storage=lento
    ├── pv-nfs.yaml               # PV meu-pv-nfs: NFS 192.168.1.133:/mnt/nfs, 1Gi RWO, label storage=nfs
    ├── pvc.yaml                  # PVC meu-pvc: 1Gi RWO, class giropops, selector storage=nfs
    ├── nginx-pod.yaml            # Pod nginx-pod mounting meu-pvc at /usr/share/nginx/html
    ├── redis-deployment.yaml     # Deployment redis-deployment mounting meu-pvc at /data
    └── nginx-deployment.yaml     # Deployment nginx-deployment (probes) declaring meu-pvc as a volume
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests). In particular, `pvc.yaml` only matches the **NFS** PV; the lab shows how to bind it to the hostPath PV by relabelling the live object.

---

## Key concepts

### The model

```
 Developer                         Cluster admin / CSI driver
 ─────────                         ───────────────────────────
 Pod ──uses──► PVC  ──binds 1:1──► PV  ──points to──► real storage (disk, NFS, EBS, Ceph…)
                │                   ▲
                └─ storageClassName ┴─ StorageClass (how to provision, reclaim, bind)
```

| Object | Scope | Who creates it | What it is |
|---|---|---|---|
| **StorageClass** | Cluster | Admin | A "type" of storage: provisioner, parameters, reclaim policy, binding mode |
| **PersistentVolume** | Cluster | Admin (static) or provisioner (dynamic) | A piece of real storage with a size, access modes and a reclaim policy |
| **PersistentVolumeClaim** | Namespace | Developer | A request: "1Gi, RWO, class X" (optionally with a selector) |

A PVC binds to **one** PV that satisfies size, access mode, class and selector. Binding is exclusive: a bound PV can't be claimed by another PVC, even if it is larger than needed.

### Static vs. dynamic provisioning

- **Static** — the admin pre-creates PVs; PVCs bind to existing ones. This module's StorageClass uses `kubernetes.io/no-provisioner`, so it is static only.
- **Dynamic** — a provisioner (CSI driver) creates a PV on demand when a PVC appears. kind ships `standard` (rancher local-path), minikube ships `standard` (hostpath), clouds ship EBS/PD/Azure Disk classes. Module 07's StatefulSet uses it.

### Binding mode

| `volumeBindingMode` | When the PVC binds | Why |
|---|---|---|
| `Immediate` | As soon as the PVC is created | Simple, but the volume may be in a zone/node where the Pod can't run |
| `WaitForFirstConsumer` | When a Pod using it is scheduled | The scheduler picks the node first, then a compatible volume — required for local volumes and multi-zone clusters |

With `WaitForFirstConsumer`, a PVC **without a Pod** stays `Pending` forever — that is normal.

### Access modes

| Mode | Short | Meaning |
|---|---|---|
| ReadWriteOnce | RWO | Read-write by **one node** (several Pods on that node can share it) |
| ReadOnlyMany | ROX | Read-only by many nodes |
| ReadWriteMany | RWX | Read-write by many nodes (NFS, CephFS, EFS…) |
| ReadWriteOncePod | RWOP | Read-write by **one Pod** in the whole cluster |

### Reclaim policy

| Policy | When the PVC is deleted |
|---|---|
| `Retain` | PV becomes `Released`; data kept; an admin must clean it and clear `spec.claimRef` to reuse it |
| `Delete` | PV **and the underlying storage** are deleted (default for most dynamic classes) |

### Volume types used here

- **hostPath** — a directory on the node. Data stays on *that* node only; no scheduling guarantees; security risk (gives Pods access to the host FS). OK for single-node labs, never for multi-node production. For node-local production storage use `local` PVs with `nodeAffinity`.
- **nfs** — a share mounted from an NFS server; supports RWX; nodes need an NFS client (`nfs-common` / `nfs-utils`).

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl get sc                  # kind/minikube already have a default "standard" class
cd 06-persistent-volumes-and-storage
```

On **kind**, create the hostPath directory inside every node container (each kind node is a Docker container):

```bash
for n in $(kind get nodes --name <cluster-name>); do docker exec "$n" mkdir -p /mnt/data; done
```

### 1. StorageClass and PV

```bash
kubectl apply -f manifests/storageclass.yaml
kubectl apply -f manifests/pv.yaml
kubectl get sc giropops
kubectl get pv meu-pv --show-labels        # STATUS Available, CLAIM empty, label storage=lento
```

### 2. PVC — and why it doesn't bind

```bash
kubectl apply -f manifests/pvc.yaml
kubectl get pvc meu-pvc                     # Pending
kubectl describe pvc meu-pvc | tail -3      # "waiting for first consumer to be created before binding"
```

Two reasons it stays `Pending`:

1. `WaitForFirstConsumer` — no Pod uses it yet.
2. The PVC selector asks for `storage: nfs`; the only PV has `storage: lento`. Even with a Pod it would not bind.

See reason 2 for yourself:

```bash
kubectl apply -f manifests/nginx-pod.yaml
kubectl get pod nginx-pod                   # Pending
kubectl describe pod nginx-pod | tail -3    # "didn't find available persistent volumes to bind"
```

Fix it **on the live object** (the manifest stays untouched) by relabelling the PV:

```bash
kubectl label pv meu-pv storage=nfs --overwrite
kubectl get pvc meu-pvc -w                  # → Bound to meu-pv (Ctrl+C)
kubectl get pod nginx-pod -o wide           # Running — note the NODE
```

### 3. Data survives the Pod

```bash
kubectl exec nginx-pod -- sh -c 'echo "Persisted on $(date)" > /usr/share/nginx/html/index.html'
kubectl exec nginx-pod -- curl -s localhost
kubectl delete pod nginx-pod
kubectl apply -f manifests/nginx-pod.yaml
kubectl exec nginx-pod -- curl -s localhost # same content
```

On kind you can see the file on the node itself:

```bash
NODE=$(kubectl get pod nginx-pod -o jsonpath='{.spec.nodeName}')
docker exec "$NODE" cat /mnt/data/index.html
```

### 4. Sharing an RWO volume: Redis

```bash
kubectl apply -f manifests/redis-deployment.yaml
kubectl get pods -o wide -l app=redis
```

Both Pods now use `meu-pvc`. RWO allows it **only if they are on the same node** — and because `hostPath` has no attach step, Kubernetes does not even enforce that: if Redis lands on a different node, it silently gets a *different* `/mnt/data`. Check:

```bash
kubectl exec deploy/redis-deployment -- ls /data       # index.html visible only if same node as nginx-pod
kubectl exec deploy/redis-deployment -- redis-cli SET curso descomplicando
kubectl exec deploy/redis-deployment -- redis-cli SAVE  # writes /data/dump.rdb
```

### 5. Deployment declaring the claim — `nginx-deployment.yaml`

```bash
kubectl apply -f manifests/nginx-deployment.yaml
kubectl get pods -l app=nginx-deployment
kubectl exec deploy/nginx-deployment -- ls /usr/share/nginx/html   # default nginx page, NOT index.html from the PV
```

The Deployment lists `meu-pvc` under `volumes` but **no container mounts it** (`volumeMounts` is missing), so the Pod waits for the PVC but never uses it. Compare with `nginx-pod.yaml`.

### 6. Retain policy: what happens on delete

```bash
kubectl delete -f manifests/nginx-deployment.yaml -f manifests/redis-deployment.yaml -f manifests/nginx-pod.yaml
kubectl delete -f manifests/pvc.yaml
kubectl get pv meu-pv                       # STATUS Released — data kept, but not reusable yet
kubectl get pv meu-pv -o jsonpath='{.spec.claimRef.name}{"\n"}'    # still points to meu-pvc

kubectl patch pv meu-pv --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pv meu-pv                       # Available again
```

### 7. Optional — NFS PV (`pv-nfs.yaml`)

Requires an NFS server at `192.168.1.133` exporting `/mnt/nfs` (the instructor's/author's lab IP — adapt your server to it, or follow along with the manifest as reference). On Debian/Ubuntu:

```bash
# On the NFS server
sudo apt-get install -y nfs-kernel-server
sudo mkdir -p /mnt/nfs && sudo chown nobody:nogroup /mnt/nfs
echo "/mnt/nfs *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ar

# On every Kubernetes node (kind: inside each node container)
sudo apt-get install -y nfs-common
#   kind:  for n in $(kind get nodes --name <cluster-name>); do docker exec "$n" bash -c 'apt-get update -q && apt-get install -y -q nfs-common'; done
```

```bash
kubectl apply -f manifests/pv-nfs.yaml
kubectl apply -f manifests/pvc.yaml -f manifests/nginx-pod.yaml
kubectl get pvc meu-pvc     # Bound to meu-pv-nfs (if meu-pv is not also labelled storage=nfs)
```

### 8. Compare with dynamic provisioning

```bash
kubectl get sc                              # "standard (default)"  provisioner rancher.io/local-path (kind)
kubectl describe sc standard | grep -E 'Provisioner|ReclaimPolicy|VolumeBindingMode'
```

Module 07's StatefulSet creates one PVC per replica against this default class — no PV written by hand.

### Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
```

PVs with `Retain` keep data on the node/NFS share: remove `/mnt/data` or the NFS files by hand if needed.

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| PVC `Pending`, "waiting for first consumer" | `WaitForFirstConsumer` and no Pod yet | Normal — create the Pod |
| Pod `Pending`, "didn't find available persistent volumes to bind" | No PV matches size / access mode / class / **selector** | `kubectl get pv --show-labels`; compare with `kubectl get pvc -o yaml` |
| Pod `Pending`, "persistentvolumeclaim not found" | PVC not created, or in another namespace | PVCs are namespaced — create it in the Pod's namespace |
| PV `Released`, new PVC won't bind | `Retain` + stale `claimRef` | Clean data, remove `spec.claimRef` |
| `ContainerCreating`, event `mount failed: exit status 32` / `bad option` (NFS) | NFS client missing on the node | Install `nfs-common` / `nfs-utils` |
| `mount.nfs: access denied` / timeout | Export rules, firewall, wrong server IP | `showmount -e <server>` from the node |
| Data "disappears" after rescheduling | `hostPath` on another node | Use `local` PV with `nodeAffinity`, NFS, or a CSI driver |
| `Multi-Attach error` on a cloud disk | RWO volume still attached to the old node | Wait for detach, or use RWX storage / `Recreate` strategy |
| PVC stuck `Terminating` | `kubernetes.io/pvc-protection` finalizer — a Pod still uses it | Delete the Pod first |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `manifests/pvc.yaml` vs `pv.yaml` | PVC selector `storage: nfs`, hostPath PV labelled `storage: lento` | PVC never binds to the hostPath PV (lab relabels the live PV) | Match labels, or drop the selector and rely on the class |
| `manifests/nginx-deployment.yaml` | `meu-pvc` declared in `volumes` but no `volumeMounts`; `volumes` list indented 8 spaces | Volume unused; Pod still blocked until the PVC binds | Add `volumeMounts`, fix indentation |
| `manifests/nginx-pod.yaml`, `redis-deployment.yaml`, `nginx-deployment.yaml` | All three use the same RWO claim `meu-pvc` | Only safe on one node; Redis and nginx write into the same directory | One PVC per workload |
| `manifests/pv.yaml` | `hostPath` without `type` and without `nodeAffinity` | Directory may not exist; data tied to an arbitrary node | Use a `local` PV with `nodeAffinity`, or dynamic provisioning |
| `manifests/pv-nfs.yaml` | Hard-coded LAN IP `192.168.1.133`; NFS PV only RWO | Not portable; NFS could offer RWX | Parameterise (Kustomize/Helm); use RWX for shared data |
| `manifests/nginx-pod.yaml`, `redis-deployment.yaml` | Untagged images (`nginx`, `redis`); no resources | Non-reproducible, BestEffort | Pin tags, add requests/limits |
| `manifests/redis-deployment.yaml` | Redis as a Deployment with a shared RWO volume | Two replicas would corrupt the dataset | StatefulSet (module 07) |
| several | Trailing spaces, extra blank lines | Cosmetic (yamllint) | `yamllint` in CI |

---

## Interview questions

<details>
<summary>1. What is the difference between a PV, a PVC and a StorageClass?</summary>

PV: a cluster-scoped piece of actual storage. PVC: a namespaced request for storage by an application. StorageClass: a template that tells a provisioner how to create PVs dynamically (and sets reclaim policy and binding mode). Pods only reference PVCs, which decouples apps from storage implementation.
</details>

<details>
<summary>2. A PVC is stuck in Pending. How do you troubleshoot it?</summary>

`kubectl describe pvc`: if it says "waiting for first consumer", create the Pod (`WaitForFirstConsumer`). Otherwise check that a PV or a provisioner exists for its `storageClassName` (`kubectl get sc`, is there a default?), that size/access modes match, that any `selector` matches PV labels, and the provisioner/CSI controller logs for dynamic classes.
</details>

<details>
<summary>3. Why does `WaitForFirstConsumer` exist?</summary>

With `Immediate` binding the volume is created/bound before the scheduler places the Pod, so it may end up in a zone or node the Pod can't use (zonal disks, local volumes). Delaying binding lets the scheduler choose the node first and then provision/bind compatible storage.
</details>

<details>
<summary>4. Retain vs Delete reclaim policy — which would you use for a production database?</summary>

`Retain` (or at least a backup strategy and a `Retain` class for critical data), so deleting a PVC by mistake doesn't destroy the disk. The cost is manual cleanup of `Released` volumes. Many teams keep `Delete` as default and create a separate `Retain` class for stateful workloads.
</details>

<details>
<summary>5. RWO vs RWX vs RWOP?</summary>

RWO: one node can mount read-write (several Pods on that node can share it). RWX: many nodes read-write — needs a shared filesystem (NFS, CephFS, EFS, Azure Files). RWOP (GA in 1.29): exactly one Pod in the whole cluster — the safe choice for single-writer databases.
</details>

<details>
<summary>6. Why is hostPath discouraged?</summary>

Data is tied to whichever node the Pod lands on, with no scheduling awareness, and it exposes the host filesystem to the Pod — a common privilege-escalation vector (Pod Security Standards "baseline" forbids it). Use `local` PVs with node affinity or a CSI driver instead.
</details>

<details>
<summary>7. You deleted a PVC with Retain policy. How do you get the data back into a new PVC?</summary>

The PV is `Released` and keeps a `claimRef` to the old PVC. Remove `spec.claimRef` (or set it to the new PVC's name/namespace) so it becomes `Available`, then create a PVC that matches it (class, size, access mode, optionally `volumeName: <pv>` to pin it).
</details>

---

## References

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volumes — hostPath, nfs, local](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Configure a Pod to use a PersistentVolume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)
- [kind — local-path-provisioner](https://github.com/rancher/local-path-provisioner)
