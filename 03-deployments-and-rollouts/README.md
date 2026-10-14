# 03 — Deployments, Rollouts & Rollbacks

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 3
> **Lab environment:** any local cluster (kind, minikube). The multi-node kind cluster from [`01-kubernetes-fundamentals`](../01-kubernetes-fundamentals/) is ideal for watching Pods spread across nodes.

## Learning objectives

By the end of this module you should be able to:

- Explain the **Deployment → ReplicaSet → Pod** ownership chain and why you almost never create ReplicaSets or bare Pods in production.
- Write a Deployment manifest from scratch, or generate one with `kubectl create deployment --dry-run=client -o yaml`.
- Choose between the two update **strategies**: `RollingUpdate` (default, zero downtime) and `Recreate` (downtime, never two versions at once).
- Drive a rollout with `kubectl rollout status | history | undo | pause | resume | restart`.
- Roll back to a specific revision and record *why* each revision exists.
- Isolate workloads with a **Namespace**.

### Why it matters in production

Deployments are the standard way to run stateless applications. Every release you ship is a rollout; every bad release is a rollback. Knowing exactly which ReplicaSet is live, how many old revisions are kept, and how fast you can go back to the last good version is what keeps an incident short.

---

## Module layout

```
03-deployments-and-rollouts/
├── README.md                         # this file
├── commands.md                       # kubectl cheat sheet for the day
├── manifests/
│   ├── namespace.yaml                # Namespace "giropops"
│   ├── deployment.yaml               # rollback-banana: 14 × nginx:1.17.0, strategy Recreate
│   ├── rollback-deployment-yaml      # identical copy of deployment.yaml (note: no ".yaml" extension)
│   └── novo-deployment.yaml          # novo-deployment: 10 × nginx:1.14.0, strategy Recreate
├── reference/
│   └── temp.yaml                     # a live Deployment exported with `kubectl get -o yaml` (NOT meant to be applied)
├── challenge/
│   └── README.md                     # rollback drill
└── Descomplicando_Kubernetes-Day3.pdf   # course material (see note at the end)
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests).

---

## Key concepts

### Deployment → ReplicaSet → Pod

```
Deployment (desired state + update strategy + revision history)
   └── ReplicaSet  (one per revision of the Pod template; keeps N replicas alive)
         └── Pod   (the actual containers)
```

- The **ReplicaSet** only guarantees *"N Pods matching this selector exist"*. It cannot update them.
- The **Deployment** creates a **new ReplicaSet every time the Pod template (`spec.template`) changes** and scales the old one down. Changing only `replicas` does **not** create a new revision.
- The ReplicaSet name is `<deployment>-<pod-template-hash>`; the Pods are `<replicaset>-<random>`. The `pod-template-hash` label ties them together.

### Selector and labels

`spec.selector.matchLabels` **must match** `spec.template.metadata.labels`, and it is **immutable** after creation. If you need to change it, you delete and recreate the Deployment.

### Update strategies

| Strategy | How it works | Downtime | Use it when |
|---|---|---|---|
| `RollingUpdate` (default) | Replaces Pods gradually, bounded by `maxSurge` (extra Pods allowed) and `maxUnavailable` (Pods allowed to be down). Defaults: 25% / 25%. | No (if readiness probes are correct) | Stateless apps that tolerate two versions running side by side |
| `Recreate` | Scales the old ReplicaSet to 0, **then** creates the new one | **Yes** | The app cannot run two versions at once (DB schema changes, exclusive locks, a single-writer volume) |

Both manifests in this module use `Recreate` so you can *see* the gap: all Pods go `Terminating` before the new ones start.

### Revisions and rollback

- Each ReplicaSet kept by the Deployment is a **revision** (`deployment.kubernetes.io/revision` annotation).
- `spec.revisionHistoryLimit` (default **10**) controls how many old ReplicaSets are kept — they are your rollback targets.
- `kubectl rollout undo` does not "go back in time": it copies the template of the old revision into the Deployment, which produces a **new** revision number.
- Annotate each change with `kubernetes.io/change-cause` so `rollout history` tells you *why* it happened (`--record` is deprecated).

### Namespace

A virtual partition of the cluster for names, RBAC, quotas and NetworkPolicies. Object names must be unique **per namespace and kind**. Both manifests here target the `giropops` namespace, which must exist first.

### `kubectl create` vs `kubectl apply`

| | `create` | `apply` |
|---|---|---|
| Style | Imperative | Declarative |
| Object exists | Error `AlreadyExists` | Computes a patch and updates it |
| Tracks last config | No | Yes (`kubectl.kubernetes.io/last-applied-configuration` annotation — visible in `reference/temp.yaml`) |

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl cluster-info
cd 03-deployments-and-rollouts
```

> **Capacity check:** `deployment.yaml` asks for 14 × 300m CPU = **4.2 vCPU** of requests, `novo-deployment.yaml` for 10 × 300m = **3 vCPU**. On a small cluster some Pods will stay `Pending` with `Insufficient cpu` — that is a lesson in itself (see Troubleshooting). Scale down with `kubectl scale` if needed.

### 1. Generate a Deployment manifest

```bash
kubectl create deployment nginx-deployment --image=nginx:1.27 --replicas=3 \
  --dry-run=client -o yaml > /tmp/nginx-deployment.yaml
less /tmp/nginx-deployment.yaml
```

### 2. Namespace + first Deployment

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/deployment.yaml

kubectl -n giropops get deploy,rs,pods -l app=rollback -o wide
kubectl -n giropops rollout status deployment rollback-banana
kubectl -n giropops describe deployment rollback-banana | grep -E 'Image|StrategyType|Replicas'
```

Look at the names: the ReplicaSet `rollback-banana-<hash>` owns all 14 Pods.

```bash
kubectl -n giropops get pods -l app=rollback --show-labels | head -3   # pod-template-hash label
```

### 3. Update with the `Recreate` strategy

Open a second terminal to watch the Pods:

```bash
kubectl -n giropops get pods -l app=rollback -w
```

Now change the image (the container is named `mginx`):

```bash
kubectl -n giropops set image deployment/rollback-banana mginx=nginx:1.18.0
kubectl -n giropops annotate deployment/rollback-banana kubernetes.io/change-cause="upgrade nginx to 1.18.0" --overwrite
kubectl -n giropops rollout status deployment rollback-banana
```

In the watch terminal you will see **all** Pods terminate before any new one is created — that is the downtime window of `Recreate`.

```bash
kubectl -n giropops get rs -l app=rollback          # two ReplicaSets: old one at 0, new one at 14
kubectl -n giropops exec deploy/rollback-banana -- nginx -v
```

### 4. History and rollback

```bash
kubectl -n giropops rollout history deployment rollback-banana
kubectl -n giropops rollout history deployment rollback-banana --revision=1

kubectl -n giropops rollout undo deployment rollback-banana                 # back to the previous revision
kubectl -n giropops rollout undo deployment rollback-banana --to-revision=2 # or to a specific one
kubectl -n giropops exec deploy/rollback-banana -- nginx -v
```

`manifests/rollback-deployment-yaml` is the same manifest as `deployment.yaml`. Re-applying it is the **GitOps-style rollback**: the cluster goes back to whatever is declared in Git.

```bash
kubectl apply -f manifests/rollback-deployment-yaml     # kubectl accepts explicit files without .yaml
```

### 5. Pause, resume, restart

```bash
kubectl -n giropops rollout pause deployment rollback-banana
kubectl -n giropops set image deployment/rollback-banana mginx=nginx:1.19.0   # nothing happens yet
kubectl -n giropops set resources deployment/rollback-banana -c mginx --limits=memory=128Mi
kubectl -n giropops rollout resume deployment rollback-banana                  # both changes roll out as ONE revision

kubectl -n giropops rollout restart deployment rollback-banana                 # new Pods, same spec (e.g. to reload a Secret)
```

### 6. Second Deployment and scaling

```bash
kubectl apply -f manifests/novo-deployment.yaml
kubectl -n giropops get deploy
kubectl -n giropops scale deployment novo-deployment --replicas=3     # no new revision
kubectl -n giropops rollout history deployment novo-deployment
```

### 7. Reading a live object — `reference/temp.yaml`

`temp.yaml` is what `kubectl get deployment nginx-deployment -o yaml` returns: your spec **plus** everything the API server fills in — defaults (`progressDeadlineSeconds`, `revisionHistoryLimit`, `rollingUpdate` 25%/25%, `terminationMessagePath`…), metadata (`uid`, `resourceVersion`, `creationTimestamp`) and the `status` block. Compare it with `manifests/deployment.yaml` to learn which fields you actually need to write. Do **not** apply it as is (see Known issues).

### 8. Challenge

Go to [`challenge/README.md`](challenge/README.md): ship a broken release on purpose and recover from it.

### Cleanup

```bash
kubectl delete namespace giropops        # deletes everything inside it
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| `namespaces "giropops" not found` | Namespace not created yet | `kubectl apply -f manifests/namespace.yaml` first |
| Some Pods `Pending`, event `Insufficient cpu` | Total requests (14 × 300m) exceed node capacity | `kubectl describe node` → *Allocated resources*; `kubectl scale --replicas=N` |
| `rollout status` hangs, then `exceeded its progress deadline` | New Pods never become Ready (bad image, failing probe, no capacity) | `kubectl describe rs <new-rs>`; `kubectl get events --sort-by=.lastTimestamp`; `rollout undo` |
| `ImagePullBackOff` after `set image` | Tag does not exist / typo | `kubectl describe pod` → *Events*; `rollout undo` |
| `error: unable to find container named "nginx"` | The container in these manifests is called `mginx` | `kubectl get deploy X -o jsonpath='{.spec.template.spec.containers[*].name}'` |
| `field is immutable` on `spec.selector` | Selector changed in the manifest | Delete and recreate the Deployment |
| `rollout history` shows `<none>` in CHANGE-CAUSE | No `kubernetes.io/change-cause` annotation | Annotate after each change |
| Applying `reference/temp.yaml` fails with a conflict | It contains `resourceVersion`/`uid` from another cluster | Strip server-side fields, or use `kubectl create deploy … --dry-run=client -o yaml` |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `manifests/rollback-deployment-yaml` | Missing dot in the extension; byte-identical duplicate of `deployment.yaml` | Skipped by `kubectl apply -f manifests/`, by editors' YAML tooling and by linters | Rename to `rollback-deployment.yaml` or drop the duplicate |
| `manifests/deployment.yaml`, `novo-deployment.yaml` | Container named `mginx` (typo of `nginx`) | Confusing in `set image` / `logs -c` | `name: nginx` |
| `manifests/deployment.yaml`, `novo-deployment.yaml` | `replicas: 14` / `10` with 300m CPU requests each | Pending Pods on laptops / small clusters | Size replicas to the environment (Kustomize overlays, HPA) |
| `manifests/deployment.yaml`, `novo-deployment.yaml` | Very old images (`nginx:1.17.0`, `nginx:1.14.0`, EOL, many CVEs) | Fine for a rollout demo, not for real use | Use a supported tag, ideally pinned by digest |
| `manifests/deployment.yaml`, `novo-deployment.yaml` | No readiness/liveness probes | Pods count as Ready as soon as the process starts | Add probes (module 04) |
| `manifests/deployment.yaml`, `novo-deployment.yaml` | CPU written as numbers (`0.5`, `0.3`) | Valid; normalised by the API to `500m` / `300m` (see `temp.yaml`) | Prefer the millicore form for consistency |
| `manifests/namespace.yaml` | Generated stubs `spec: {}` and `status: {}` | Harmless noise from `--dry-run=client -o yaml` | Remove |
| `reference/temp.yaml` | Server-side fields (`uid`, `resourceVersion`, `creationTimestamp`, `status`, `last-applied-configuration`) and untagged `nginx` image | Not portable; apply can fail or behave unexpectedly | Keep only as a reference; never commit live exports as manifests |
| several | Trailing spaces after `Recreate` | Cosmetic (yamllint) | Run `yamllint` in CI |

---

## Interview questions

<details>
<summary>1. What is the relationship between a Deployment, a ReplicaSet and a Pod?</summary>

The Deployment manages ReplicaSets; each ReplicaSet manages identical Pods. A new ReplicaSet is created for every change in the Pod template, and the Deployment moves replicas from the old ReplicaSet to the new one following its strategy. Old ReplicaSets (scaled to 0) are kept as rollback targets up to `revisionHistoryLimit`.
</details>

<details>
<summary>2. RollingUpdate vs Recreate — when would you choose Recreate?</summary>

When two versions must never run at the same time: incompatible database migrations, an app holding an exclusive lock, or a `ReadWriteOnce` volume that only one Pod can mount. You accept downtime in exchange for consistency. Everything else should use RollingUpdate.
</details>

<details>
<summary>3. Explain `maxSurge` and `maxUnavailable` with 10 replicas and 25%/25%.</summary>

`maxSurge` 25% → up to 3 extra Pods (rounded up), so at most 13 Pods. `maxUnavailable` 25% → at most 2 Pods unavailable (rounded down), so at least 8 Ready. `maxSurge: 0, maxUnavailable: 1` is the conservative "no extra capacity" variant; `maxSurge: 100%, maxUnavailable: 0` is close to blue/green.
</details>

<details>
<summary>4. Does scaling a Deployment create a new revision?</summary>

No. Only changes to `spec.template` create a new ReplicaSet/revision. `replicas`, `strategy` or `revisionHistoryLimit` changes are applied to the existing one.
</details>

<details>
<summary>5. A release is failing. How do you roll back quickly and how do you know what you are rolling back to?</summary>

`kubectl rollout history deploy/X` (with change-cause annotations) and `--revision=N` to inspect a template, then `kubectl rollout undo deploy/X [--to-revision=N]` and `rollout status` to confirm. In GitOps setups, revert the commit instead so Git and the cluster stay in sync — otherwise the next sync re-applies the broken version.
</details>

<details>
<summary>6. `rollout status` says "exceeded its progress deadline". What happened and what does Kubernetes do?</summary>

The new ReplicaSet did not reach availability within `progressDeadlineSeconds` (default 600s). Kubernetes sets the `Progressing` condition to `False` with reason `ProgressDeadlineExceeded` — it does **not** roll back automatically. Your CD tooling or you must react (undo, fix image, fix probes, add capacity).
</details>

<details>
<summary>7. Why would you use `kubectl rollout restart`?</summary>

To recreate all Pods with the same spec — typically to pick up a changed ConfigMap/Secret consumed as environment variables, or to clear a bad in-memory state. It patches an annotation in the Pod template (`kubectl.kubernetes.io/restartedAt`), so it follows the normal rollout strategy and creates a new revision.
</details>

---

## References

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [`kubectl rollout`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)

> **Course material:** the PDF is LinuxTips course content. Keeping it in a public repository is an open decision (see the root README).
