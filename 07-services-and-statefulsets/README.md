# 07 — Services & StatefulSets

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 7
> **Lab environment:** a multi-node kind cluster (e.g. from [`01-kubernetes-fundamentals`](../01-kubernetes-fundamentals/)) with its default `standard` StorageClass. The LoadBalancer part needs [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) (kind) or `minikube tunnel`.

## Learning objectives

By the end of this module you should be able to:

- Explain why Pods need a **Service** in front of them (ephemeral IPs, load balancing, discovery).
- Choose between **ClusterIP**, **NodePort**, **LoadBalancer**, **ExternalName** and **headless** Services.
- Read how a Service finds its Pods: label **selector** → **EndpointSlices** → kube-proxy rules.
- Use cluster **DNS** names (`<svc>.<ns>.svc.cluster.local`, `<pod>.<svc>…`).
- Run a **StatefulSet**: stable names, ordered start/stop, one PVC per replica via `volumeClaimTemplates`.
- Explain when to use a StatefulSet instead of a Deployment.

### Why it matters in production

Every request inside a cluster goes through a Service, and most "the app can't reach X" incidents are a Service whose selector doesn't match, a wrong `targetPort`, or DNS. StatefulSets are how databases, Kafka, Zookeeper, Elasticsearch and similar clustered systems get stable identities and their own disks — and how they lose data when someone treats them like a Deployment.

---

## Module layout

```
07-services-and-statefulsets/
├── README.md                              # this file
├── commands.md                            # kubectl cheat sheet for the day
└── manifests/
    ├── services/
    │   ├── nginx-deployment.yaml          # Deployment nginx: 3 replicas, labels app=nginx, env=dev, port "http" 80
    │   ├── nginx-clusterip-service.yaml   # Service nginx            — ClusterIP
    │   ├── nginx-nodeport-svc.yaml        # Service nginx-nodeport   — NodePort 32000
    │   └── nginx-loadbalancer-svc.yaml    # Service nginx-loadbalancer — LoadBalancer
    └── statefulset/
        ├── nginx-headless-svc.yaml        # Service nginx            — headless (clusterIP: None)
        └── statefulset-nginx.yaml         # StatefulSet nginx: 3 replicas, 1Gi PVC each
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte), only grouped in two folders because the two groups **cannot run at the same time** (both create a Service called `nginx`, and all Pods share the label `app=nginx`). See [Known issues in the manifests](#known-issues-in-the-manifests).

---

## Key concepts

### Service

A stable virtual IP (ClusterIP) and DNS name in front of a **set of Pods selected by labels**. The control plane keeps **EndpointSlices** with the IPs of the **Ready** Pods that match the selector; kube-proxy (or the CNI's eBPF replacement) on every node programs rules that send traffic for the ClusterIP to one of those endpoints.

```
client ──► nginx.default.svc.cluster.local ──► ClusterIP 10.96.x.y:80 ──► kube-proxy rules ──► Pod IP:targetPort
                                                                         (only Ready Pods matching the selector)
```

`port` = the Service's port; `targetPort` = the container port (number or **name**, e.g. `http`); `nodePort` = the port opened on every node.

### Service types

| Type | Reachable from | How | Typical use |
|---|---|---|---|
| `ClusterIP` (default) | Inside the cluster | Virtual IP | Service-to-service traffic |
| `NodePort` | Outside, via `<any-node-IP>:30000-32767` | ClusterIP + a port on every node | Labs, on-prem behind an external LB |
| `LoadBalancer` | Outside, via an external IP | NodePort + a cloud/MetalLB load balancer | Exposing a service on a cloud provider |
| `ExternalName` | Inside | DNS CNAME to an external name | Alias for an external DB/API |
| Headless (`clusterIP: None`) | Inside | **No virtual IP**; DNS returns the Pod IPs directly | StatefulSets, client-side load balancing |

Each type builds on the previous one: a LoadBalancer Service also has a NodePort and a ClusterIP.

### DNS names

| Name | Resolves to |
|---|---|
| `nginx` (same namespace) / `nginx.default` / `nginx.default.svc.cluster.local` | ClusterIP (or Pod IPs if headless) |
| `nginx-0.nginx.default.svc.cluster.local` | The IP of Pod `nginx-0` (StatefulSet + headless Service only) |

### StatefulSet vs. Deployment

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | Random (`nginx-7c9d…-x2k4p`) | Ordinal and stable (`nginx-0`, `nginx-1`, `nginx-2`) |
| Start / stop order | All in parallel | In order 0→N, scale down N→0 (default `OrderedReady`) |
| Storage | All replicas share the volumes in the template | `volumeClaimTemplates` → **one PVC per replica**, re-attached to the same ordinal |
| Network identity | Through the Service only | Per-Pod DNS name via the headless `serviceName` |
| On delete | — | PVCs are **kept** by default (`persistentVolumeClaimRetentionPolicy`) |
| Use for | Stateless apps | Databases, brokers, anything with identity or per-replica data |

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl get nodes -o wide
kubectl get sc                 # a default class is needed for part B (kind: "standard")
cd 07-services-and-statefulsets
```

## Part A — Deployment + Service types

### A1. Deployment and ClusterIP

```bash
kubectl apply -f manifests/services/nginx-deployment.yaml
kubectl apply -f manifests/services/nginx-clusterip-service.yaml
kubectl get svc nginx
kubectl get endpointslices -l kubernetes.io/service-name=nginx     # 3 Pod IPs
kubectl get pods -l app=nginx -o wide                              # same IPs

# From inside the cluster: Service name, FQDN and DNS
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh -c \
  'wget -qO- http://nginx | head -4; nslookup nginx.default.svc.cluster.local'
```

Selectors in action — take a Pod out of the Service by changing its label:

```bash
POD=$(kubectl get pods -l app=nginx -o name | head -1)
kubectl label $POD app=debug --overwrite
kubectl get endpointslices -l kubernetes.io/service-name=nginx     # 3 IPs again — but one is a NEW Pod
kubectl get pods --show-labels                                     # the ReplicaSet created a replacement; the relabelled Pod is now orphaned
kubectl delete $POD
```

### A2. NodePort

```bash
kubectl apply -f manifests/services/nginx-nodeport-svc.yaml
kubectl get svc nginx-nodeport                     # 80:32000/TCP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -sI http://$NODE_IP:32000 | head -1           # from your Linux host (kind node IPs are reachable)
```

Any node works, even one without an nginx Pod — kube-proxy forwards the traffic.

### A3. LoadBalancer

```bash
kubectl apply -f manifests/services/nginx-loadbalancer-svc.yaml
kubectl get svc nginx-loadbalancer -w              # EXTERNAL-IP <pending> without a LB implementation
```

On kind, run cloud-provider-kind in another terminal and the external IP appears:

```bash
go install sigs.k8s.io/cloud-provider-kind@latest && sudo ~/go/bin/cloud-provider-kind   # or see its README for the container image
LB_IP=$(kubectl get svc nginx-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sI http://$LB_IP | head -1
```

On minikube: `minikube tunnel`. On a cloud provider it just works (and costs money).

### A4. Expose imperatively and clean up

```bash
kubectl expose deployment nginx --name=nginx-expose --port=8080 --target-port=http --dry-run=client -o yaml
kubectl delete -f manifests/services/
```

## Part B — StatefulSet + headless Service

### B1. Create

```bash
kubectl apply -f manifests/statefulset/nginx-headless-svc.yaml
kubectl apply -f manifests/statefulset/statefulset-nginx.yaml
kubectl get pods -l app=nginx -w                    # nginx-0, then nginx-1, then nginx-2 — in order
kubectl get pvc                                     # nginx-persistent-storage-nginx-0/1/2, one per Pod
kubectl get svc nginx                               # CLUSTER-IP None
```

### B2. Stable identity and per-Pod DNS

```bash
for i in 0 1 2; do kubectl exec nginx-$i -- sh -c "echo I am nginx-$i > /usr/share/nginx/html/index.html"; done

kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh -c \
  'nslookup nginx; for i in 0 1 2; do wget -qO- http://nginx-$i.nginx; done'
```

`nslookup nginx` returns **three** A records (Pod IPs) — no virtual IP.

### B3. Pod deleted → same name, same disk

```bash
kubectl get pod nginx-1 -o wide                     # note IP
kubectl delete pod nginx-1
kubectl get pod nginx-1 -o wide -w                  # recreated as nginx-1 (IP may change)
kubectl exec nginx-1 -- cat /usr/share/nginx/html/index.html   # "I am nginx-1" — same PVC
```

### B4. Scale and delete

```bash
kubectl scale statefulset nginx --replicas=5        # nginx-3, nginx-4 created in order, new PVCs
kubectl scale statefulset nginx --replicas=2        # nginx-4, then nginx-3, then nginx-2 removed
kubectl get pvc                                     # PVCs 2, 3, 4 still exist — data kept for a scale-up

kubectl delete -f manifests/statefulset/
kubectl get pvc                                     # still there!
kubectl delete pvc -l app=nginx                     # PVCs inherit the StatefulSet selector labels
```

### Cleanup

```bash
kubectl delete -f manifests/services/ -f manifests/statefulset/ --ignore-not-found
kubectl get pvc
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| Service exists but `curl` hangs / connection refused | Selector doesn't match Pod labels → no endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`; compare with `kubectl get pods --show-labels` |
| Endpoints exist but connection refused | Wrong `targetPort` (or named port not defined on the container) | `kubectl describe svc`; check `containerPort`/`name` |
| Endpoints list is empty although Pods run | Pods not Ready (readiness probe) | `kubectl get pods` READY column |
| `nslookup` fails for the Service | Wrong namespace, or CoreDNS down | Use `<svc>.<ns>`; `kubectl -n kube-system get pods -l k8s-app=kube-dns` |
| `EXTERNAL-IP <pending>` forever | No LoadBalancer implementation (kind, bare metal) | cloud-provider-kind, MetalLB, `minikube tunnel` |
| `provided port is already allocated` | Another Service already uses that `nodePort` | Pick another or omit it (auto-assigned) |
| `spec.clusterIP: Invalid value: "None": field is immutable` | Applying the headless Service over the existing ClusterIP Service `nginx` | Delete the ClusterIP Service first |
| StatefulSet stuck at `nginx-0` Pending | PVC can't be provisioned (no default StorageClass) | `kubectl get sc`; `kubectl describe pvc` |
| StatefulSet Pod stuck after node failure | StatefulSets don't force-replace a Pod on an unreachable node (to avoid two writers) | Confirm the node is really dead, then `kubectl delete pod --force` |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `services/nginx-clusterip-service.yaml` vs `statefulset/nginx-headless-svc.yaml` | Both create Service **`nginx`** | Can't coexist; `clusterIP` is immutable, so applying one over the other fails | Distinct names (`nginx` / `nginx-headless`) |
| `services/nginx-deployment.yaml` vs `statefulset/statefulset-nginx.yaml` | Both Pod templates use only `app: nginx` | Every Service in the module selects **both** Deployment and StatefulSet Pods | Add a distinguishing label (`app.kubernetes.io/name`, `component`) |
| `services/nginx-deployment.yaml` | No `metadata.labels` on the Deployment; Service labels `env: dev` but selector only `app` | Harder to find with `-l`; harmless | Consistent recommended labels |
| all workloads | Untagged `nginx` image, no resources, no probes | Non-reproducible, BestEffort, traffic to non-ready Pods | Pin tag, requests/limits, readiness probe |
| `statefulset/statefulset-nginx.yaml` | No `storageClassName` in `volumeClaimTemplates` | Uses whatever class is default — fine on kind, surprising elsewhere | Set the class explicitly |
| `statefulset/nginx-headless-svc.yaml` | No `targetPort` (defaults to `port`, 80) | Works; implicit | Set `targetPort: http` |
| `services/nginx-nodeport-svc.yaml` | Fixed `nodePort: 32000` | Clashes if another Service uses it | Let Kubernetes allocate unless you need a fixed port |
| several | Double space after `env:`, long comment line, trailing blank lines | Cosmetic (yamllint) | `yamllint` in CI |

---

## Interview questions

<details>
<summary>1. How does a Service know which Pods to send traffic to?</summary>

Through its label **selector**. The EndpointSlice controller continuously lists Pods matching the selector and records the IPs of the **Ready** ones; kube-proxy on every node watches EndpointSlices and programs iptables/IPVS/nftables rules (or eBPF maps with Cilium) that DNAT the ClusterIP to one of those Pod IPs.
</details>

<details>
<summary>2. ClusterIP vs NodePort vs LoadBalancer?</summary>

ClusterIP: internal virtual IP only. NodePort: additionally opens the same port (30000-32767) on every node. LoadBalancer: additionally asks a cloud controller (or MetalLB) for an external load balancer that forwards to the NodePorts/Pods. In production you usually expose HTTP through an **Ingress/Gateway** behind a single LoadBalancer rather than one LB per Service.
</details>

<details>
<summary>3. What is a headless Service and why does a StatefulSet need one?</summary>

A Service with `clusterIP: None`: no virtual IP, DNS returns the Pod IPs directly. With a StatefulSet (`serviceName`), it also creates a stable DNS record per Pod (`nginx-0.nginx.<ns>.svc.cluster.local`), which clustered software uses to find specific peers (primary vs. replica, Kafka brokers, etcd members).
</details>

<details>
<summary>4. Why not just run a database as a Deployment with a PVC?</summary>

All replicas would share one PVC (and with RWO they can't run on different nodes), names change on every restart, and rollouts may start the new Pod before the old one stops — two writers on one data directory. A StatefulSet gives each replica its own PVC, a stable name, and ordered, one-at-a-time updates. (Even better for databases: an operator such as CloudNativePG.)
</details>

<details>
<summary>5. You scale a StatefulSet from 3 to 1 and back to 3. What happens to the data?</summary>

Scale-down removes `nginx-2` then `nginx-1` but keeps their PVCs (default `whenScaled: Retain`). On scale-up, the new `nginx-1` and `nginx-2` re-attach to their old PVCs, so the data is still there. To delete PVCs automatically, set `persistentVolumeClaimRetentionPolicy`.
</details>

<details>
<summary>6. A Service has no endpoints. Walk through the checks.</summary>

1) `kubectl get pods --show-labels` vs. `kubectl get svc -o yaml` selector — typo or different label key? 2) Are the Pods in the same namespace as the Service? 3) Are they Ready (readiness probe)? 4) Does `targetPort` match the container port/name? Then test from inside: `kubectl run tmp --rm -it --image=busybox -- wget -qO- <podIP>:<port>` directly vs. via the Service.
</details>

<details>
<summary>7. What is `externalTrafficPolicy: Local` for?</summary>

For NodePort/LoadBalancer Services, it only routes to Pods on the node that received the traffic, which **preserves the client source IP** and avoids an extra hop — at the cost of uneven load and nodes without Pods failing LB health checks (which is how the LB learns to skip them).
</details>

---

## References

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind)
