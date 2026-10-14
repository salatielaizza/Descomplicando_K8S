# 04 — ReplicaSets, DaemonSets, Update Strategies & Probes

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 4
> **Lab environment:** a **multi-node** kind cluster (e.g. from [`01-kubernetes-fundamentals`](../01-kubernetes-fundamentals/)) — DaemonSets only make sense with more than one node.

## Learning objectives

By the end of this module you should be able to:

- Explain what a **ReplicaSet** guarantees, and why you use it through a Deployment rather than directly.
- Run one Pod per node with a **DaemonSet** and explain why it skips the control-plane node by default.
- Tune a **RollingUpdate** with `maxSurge` / `maxUnavailable`, and compare it with `Recreate` in practice.
- Configure the three probes — **startup**, **liveness**, **readiness** — with `httpGet`, `tcpSocket` and `exec` handlers, and predict what happens when each one fails.
- Diagnose a Pod stuck in `CrashLoopBackOff` / `0/1 READY` caused by a bad probe.

### Why it matters in production

Probes are what make "zero-downtime deploy" real: without a readiness probe a Service sends traffic to Pods that are still booting; with a wrong liveness probe the kubelet restarts healthy containers in a loop, often under load, which turns a slowdown into an outage. DaemonSets are how every node gets its log shipper, metrics exporter, CNI agent or security agent.

---

## Module layout

```
04-replicasets-daemonsets-and-probes/
├── README.md                          # this file
├── commands.md                        # kubectl cheat sheet for the day
├── manifests/
│   ├── nginx-replicaset.yaml          # ReplicaSet nginx-replicaset: 3 × nginx:1.19.2
│   ├── nginx-daemonset.yaml           # DaemonSet node-exporter (with metadata labels)
│   ├── jeff-nginx-daemonset.yaml      # same DaemonSet as written by the instructor (no metadata labels)
│   ├── limits.yaml                    # Deployment limits-deploy: RollingUpdate 20%/20%, requests/limits
│   ├── strategies.yaml                # Deployment strategy-deploy: Recreate
│   └── probes.yaml                    # Deployment probes-deploy: startup + liveness + readiness
└── challenge/
    ├── README.md                      # "why is my Pod never Ready?" troubleshooting challenge
    └── nginx-deployment.yaml          # Deployment with a broken startupProbe
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests). Despite their file names, both `*-daemonset.yaml` files run **node-exporter**, not nginx.

---

## Key concepts

### ReplicaSet

Keeps **N Pods matching a label selector** running. If a Pod dies, it creates another; if there are too many (e.g. you created a matching Pod by hand), it deletes one. It **does not update** existing Pods when you change its template — only newly created Pods get the new template. That is why Deployments exist: they create a new ReplicaSet per template version.

### DaemonSet

Runs **one Pod per eligible node**, and automatically adds one when a node joins. Typical uses: node-exporter, Fluent Bit, CNI agents (Calico, Cilium), kube-proxy itself.

- Nodes with **taints** (e.g. the control plane: `node-role.kubernetes.io/control-plane:NoSchedule`) are skipped unless the Pod has a matching **toleration**.
- `nodeSelector` / `affinity` restrict it to a subset of nodes.
- Updates: `RollingUpdate` (default, `maxUnavailable: 1`) or `OnDelete`.
- `hostNetwork: true` + `hostPort` (as in node-exporter) make the Pod listen directly on the node's IP — useful for agents, but it means one Pod per node per port.

### Deployment update strategies (recap from module 03)

| Field | Meaning | `limits.yaml` (10 replicas, 20%/20%) |
|---|---|---|
| `maxSurge` | Extra Pods allowed above `replicas` during the update (rounded **up**) | 2 → up to 12 Pods |
| `maxUnavailable` | Pods allowed to be not Ready (rounded **down**) | 2 → at least 8 Ready |

`strategies.yaml` uses `Recreate`: everything stops, then everything starts.

### Probes

| Probe | Question it answers | On failure | Runs |
|---|---|---|---|
| `startupProbe` | "Has the app finished starting?" | Container is **killed and restarted** after `failureThreshold` failures | First; liveness and readiness are **disabled until it succeeds** |
| `livenessProbe` | "Is the process still healthy, or stuck?" | Container is **restarted** | Whole lifetime, after startup |
| `readinessProbe` | "Can it receive traffic right now?" | Pod removed from Service **endpoints** (no restart) | Whole lifetime, after startup |

Handlers: `httpGet` (2xx/3xx = success), `tcpSocket` (port accepts a connection), `exec` (exit code 0), `grpc`.

Timing fields: `initialDelaySeconds`, `periodSeconds` (default 10), `timeoutSeconds` (default 1), `failureThreshold` (default 3), `successThreshold` (default 1; **must be 1** for liveness and startup).

Max time a startup probe allows ≈ `initialDelaySeconds + failureThreshold × periodSeconds`.

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl get nodes          # ideally 1 control plane + 2 workers
cd 04-replicasets-daemonsets-and-probes
```

### 1. ReplicaSet — self-healing, but no updates

```bash
kubectl apply -f manifests/nginx-replicaset.yaml
kubectl get rs nginx-replicaset
kubectl get pods -l app=nginx-app -o wide

# Self-healing: delete a Pod, a new one appears
kubectl delete pod $(kubectl get pods -l app=nginx-app -o name | head -1)
kubectl get pods -l app=nginx-app

# Change the image: existing Pods are NOT updated
kubectl set image rs/nginx-replicaset nginx=nginx:1.27
kubectl get pods -l app=nginx-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
kubectl delete pod $(kubectl get pods -l app=nginx-app -o name | head -1)   # only the replacement gets 1.27
kubectl get pods -l app=nginx-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

kubectl delete -f manifests/nginx-replicaset.yaml
```

### 2. DaemonSet — one Pod per node

```bash
kubectl apply -f manifests/nginx-daemonset.yaml
kubectl get ds node-exporter                       # DESIRED = number of worker nodes
kubectl get pods -l app=node-exporter -o wide      # one per worker, none on the control plane

# Why not on the control plane?
kubectl describe node $(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name) | grep Taints

# hostNetwork: the exporter listens on the node IP
NODE_IP=$(kubectl get pod -l app=node-exporter -o jsonpath='{.items[0].status.hostIP}')
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://$NODE_IP:9100/metrics | head
```

Add a node and watch the DaemonSet follow it — on kind you can't add nodes to a running cluster, so instead *remove* eligibility and watch it go:

```bash
WORKER=$(kubectl get pods -l app=node-exporter -o jsonpath='{.items[0].spec.nodeName}')
kubectl taint node $WORKER demo=true:NoExecute     # the Pod on that node is evicted
kubectl get pods -l app=node-exporter -o wide
kubectl taint node $WORKER demo=true:NoExecute-    # remove the taint, the Pod comes back

kubectl delete -f manifests/nginx-daemonset.yaml
```

`jeff-nginx-daemonset.yaml` creates the **same** DaemonSet (same name) — apply one or the other, not both.

### 3. RollingUpdate vs Recreate

Terminal A — watch:

```bash
kubectl get pods -l 'app in (limits-deploy,strategy-deploy)' -w
```

Terminal B:

```bash
# RollingUpdate 20%/20%
kubectl apply -f manifests/limits.yaml
kubectl rollout status deploy/limits-deploy
kubectl set image deploy/limits-deploy nginx=nginx:1.18
kubectl rollout status deploy/limits-deploy       # old and new Pods overlap; ≥ 8 Ready at all times

# Recreate
kubectl apply -f manifests/strategies.yaml
kubectl rollout status deploy/strategy-deploy
kubectl set image deploy/strategy-deploy nginx=nginx:1.15
kubectl rollout status deploy/strategy-deploy     # all 10 terminate first, then 10 start

kubectl delete -f manifests/limits.yaml -f manifests/strategies.yaml
```

> 10 replicas × 300m CPU = 3 vCPU of requests for `limits-deploy`. Scale down if Pods stay `Pending`.

### 4. Probes — `manifests/probes.yaml`

```bash
kubectl apply -f manifests/probes.yaml
kubectl get pods -l app=probes-deploy -w          # 0/1 for ~10-15 s (startup + readiness), then 1/1
kubectl describe pod $(kubectl get pods -l app=probes-deploy -o name | head -1) | grep -E 'Liveness|Readiness|Startup'
```

Break **readiness** (no restart, traffic stops):

```bash
POD=$(kubectl get pods -l app=probes-deploy -o name | head -1)
kubectl exec $POD -- rm /usr/share/nginx/html/index.html     # GET / now returns 403
kubectl get $POD -w                                           # READY 0/1, RESTARTS unchanged
kubectl describe $POD | grep -A2 Readiness                    # "Readiness probe failed: HTTP probe failed with statuscode: 403"
```

Break **liveness** (container restart) — patch the live object so the probe checks a closed port (the file is not touched):

```bash
kubectl patch deploy probes-deploy --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/tcpSocket/port","value":8080}]'
kubectl get pods -l app=probes-deploy -w     # new Pods become Ready, then RESTARTS +1 every ~10 s (2 failures × 5 s)
kubectl get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp | tail -3
kubectl rollout undo deploy/probes-deploy    # back to the healthy revision
```

Two lessons: liveness failures cause **restarts, not unreadiness** — the rollout even completes, because readiness passed; and a `kill`/`nginx -s stop` of PID 1 is *not* a liveness test — the container simply exits and `restartPolicy` restarts it.

```bash
kubectl delete -f manifests/probes.yaml
```

### 5. Challenge

Go to [`challenge/README.md`](challenge/README.md): a Deployment that never becomes Ready. Find out why using only `kubectl`.

### Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
kubectl delete -f challenge/nginx-deployment.yaml --ignore-not-found
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| Pod `Running` but `READY 0/1`, `RESTARTS` 0 | Readiness probe failing | `kubectl describe pod` → *Events* `Readiness probe failed` |
| `RESTARTS` growing, `CrashLoopBackOff`, event `Liveness probe failed` / `Startup probe failed` | Probe hits the wrong port/path, or `initialDelay`/threshold too short for the app's boot time | Check the port in the probe vs. `containerPort`; give startup more time (`failureThreshold × periodSeconds`) |
| Probe fails with `executable file not found` | `exec` probe uses a binary not in the image (e.g. `curl` in distroless/alpine) | Use `httpGet` instead, or a binary that exists |
| Liveness restarts under load | `timeoutSeconds` (default 1 s) too low, or liveness checks dependencies (DB) | Liveness should only check the process itself; raise timeout |
| DaemonSet `DESIRED` lower than node count | Tainted nodes (control plane) | Add a toleration if the agent must run there |
| DaemonSet Pod `Pending`, event about ports | `hostPort`/`hostNetwork` port already in use on the node | Only one Pod per node per host port; delete the duplicate DaemonSet |
| Changed a ReplicaSet image but Pods still old | ReplicaSets don't roll out | Use a Deployment |
| Rolling update stuck with old and new Pods | New Pods never Ready (see probes) | `kubectl rollout undo` |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `challenge/nginx-deployment.yaml` | `startupProbe` checks **port 81**, nginx listens on 80 | Startup probe never succeeds → container killed every ~40 s, never Ready, `CrashLoopBackOff` (that is the challenge) | `port: 80` (module 06 contains the fixed copy) |
| `manifests/nginx-daemonset.yaml`, `jeff-nginx-daemonset.yaml` | File names say *nginx* but they deploy **node-exporter**; both create the same DaemonSet `node-exporter` | Confusing; applying both just overwrites | Name files after what they run; keep one |
| `manifests/*-daemonset.yaml` | `prom/node-exporter:latest`, no resources, no tolerations, no `hostPID`/`--path.procfs` args | Not reproducible; metrics read the container's `/proc` view unless args point at `/host/proc`; skips the control plane | Pin a tag, add `args: [--path.procfs=/host/proc, --path.sysfs=/host/sys]`, requests/limits, control-plane toleration |
| `manifests/nginx-replicaset.yaml` | `memory: 126Mi` request | Valid, but probably a typo for 128Mi | Use round values |
| `manifests/strategies.yaml` | No requests/limits; commented `rollingUpdate` block is mis-indented | `BestEffort` Pods; uncommenting the block as-is produces invalid YAML | Add resources; indent `rollingUpdate` under `strategy` |
| `manifests/limits.yaml`, `probes.yaml`, `strategies.yaml` | `matchLabels` value indented 5 spaces; trailing spaces after `nginx`; trailing blank lines | Cosmetic (valid YAML) | `yamllint` in CI |
| `manifests/probes.yaml` | `successThreshold` comment says "failures" (copy-paste) | Misleading comment | `successThreshold`: consecutive **successes** needed |
| `manifests/probes.yaml` | `timeoutSeconds:  5` (two spaces) | Cosmetic | — |
| several | Old nginx images (1.14, 1.17, 1.19) | EOL images with CVEs; fine for demos | Use supported tags |

---

## Interview questions

<details>
<summary>1. What is the difference between liveness, readiness and startup probes?</summary>

Startup: "has it finished booting?" — gates the other two and kills the container if it never succeeds. Liveness: "is it stuck?" — restarts the container. Readiness: "can it take traffic now?" — removes the Pod from Service endpoints without restarting it. Readiness can flip back and forth during the Pod's life; liveness failure is terminal for that container instance.
</details>

<details>
<summary>2. Why is a liveness probe that checks the database a bad idea?</summary>

If the database goes down, every Pod's liveness fails at the same time and the kubelet restarts all of them — adding a restart storm on top of a database outage, without fixing anything. Dependency checks belong (carefully) in readiness, or nowhere; liveness should only verify the process itself.
</details>

<details>
<summary>3. A Java app takes 90 s to start and gets killed in a loop. What do you change?</summary>

Add (or lengthen) a `startupProbe`, e.g. `periodSeconds: 10, failureThreshold: 12` (120 s budget). Liveness only starts after the startup probe succeeds, so you can keep liveness aggressive for the steady state instead of inflating `initialDelaySeconds`.
</details>

<details>
<summary>4. How does a DaemonSet differ from a Deployment with `replicas` = number of nodes?</summary>

The DaemonSet guarantees exactly one Pod per eligible node and reacts to nodes joining/leaving; a Deployment's scheduler may put two replicas on one node and none on another, and does not scale with the node count. DaemonSets also have node-oriented update semantics (`maxUnavailable` per node, `OnDelete`).
</details>

<details>
<summary>5. Your DaemonSet shows DESIRED 2 on a 3-node cluster. Why?</summary>

One node is not eligible — usually the control plane with its `NoSchedule` taint, or a `nodeSelector`/affinity that excludes it, or the node is cordoned/not Ready. Check `kubectl describe node` for taints and add a toleration if the agent must run there.
</details>

<details>
<summary>6. With 10 replicas, `maxSurge: 0` and `maxUnavailable: 0`, what happens on update?</summary>

The API server rejects it: both cannot be zero, because the Deployment would have no way to make progress. At least one must allow movement.
</details>

<details>
<summary>7. Pod is Running, 0/1 Ready, 0 restarts. Where do you look first?</summary>

`kubectl describe pod` events for `Readiness probe failed` (the message includes the HTTP status / exit code), then check that the probe's port/path matches what the app actually serves (`kubectl exec … -- wget -qO- localhost:<port><path>` or `kubectl port-forward`).
</details>

---

## References

- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Deployment strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
- [Liveness, readiness and startup probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [Configure probes (task)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
