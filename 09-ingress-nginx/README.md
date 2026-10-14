# 09 — Ingress with ingress-nginx

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 9
> **Lab environment:** a kind cluster with ports 80/443 mapped to the host (config below), Docker, `curl`.

## Learning objectives

By the end of this module you should be able to:

- Explain what an **Ingress** is, and why it needs an **Ingress controller** to do anything.
- Install the **ingress-nginx** controller on kind and expose it on `localhost:80/443`.
- Deploy a two-tier app (**giropops-senhas** Flask app + Redis) and publish it through an Ingress.
- Route traffic by **path** (`Prefix` vs `Exact`) and by **host** (virtual hosting).
- Understand `ingressClassName`, the default IngressClass, and the `rewrite-target` annotation (and the static-assets problem it causes).
- Know the current state of the ecosystem: **ingress-nginx is retired** and the **Gateway API** is the successor.

### Why it matters in production

One external load balancer + one Ingress/Gateway controller is how almost every cluster publishes HTTP services: TLS termination, host/path routing, redirects, rate limiting and auth all happen there. Misrouted paths, broken rewrites and "default backend 404" are daily troubleshooting for platform teams — and migrating off ingress-nginx is on many 2026 roadmaps.

> **Heads-up — ingress-nginx retirement.** The Kubernetes project [announced in November 2025](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) that the community **ingress-nginx** controller would be retired, with best-effort maintenance only until March 2026 and no further releases or security fixes afterwards ([follow-up statement, Jan 2026](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)). It is still perfect for learning the `Ingress` API in a lab, but new production clusters should use a **Gateway API** implementation (Envoy Gateway, Cilium, Istio, NGINX Gateway Fabric, Traefik…) or a maintained Ingress controller. The `Ingress` resource itself is not going away.

---

## Module layout

```
09-ingress-nginx/
├── README.md                          # this file
├── commands.md                        # kubectl / kind / curl cheat sheet
├── kind/
│   └── kind-com-ingress.yaml          # kind cluster config as written in class — DOES NOT WORK as is (see Known issues)
└── manifests/
    ├── giropops-senhas/               # the application
    │   ├── redis-deployment.yaml      # Redis (port 6379)
    │   ├── redis-service.yaml         # Service redis-service (ClusterIP)
    │   ├── app-deployment.yaml        # linuxtips/giropops-senhas:1.0, 2 replicas, REDIS_HOST=redis-service
    │   └── app-service.yaml           # Service giropops-senhas :5000 (ClusterIP)
    ├── nginx/                         # a second backend for host-based routing
    │   ├── nginx.yaml                 # Pod nginx (label run=nginx)
    │   └── nginx-service.yaml         # Service nginx :80
    └── ingress/                       # the Ingress, step by step
        ├── ingress-1.yaml             # path /giropops-senhas → app, rewrite-target /
        ├── ingress-2.yaml             # path /static → app (fixes CSS/JS of step 1)
        ├── ingress-3.yaml             # path / → app (replaces ingress-1, same name)
        ├── ingress-4.yaml             # host giropops.nginx.io → nginx
        ├── ingress-5.yaml             # path / → app with explicit ingressClassName: nginx
        └── ingress-6.yaml             # host giropops.salatielaizza.com → app (base for TLS in module 10)
```

> **Note:** the YAML files are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests). `ingress-1`, `-3`, `-5` and `-6` all create the **same** Ingress (`giropops-senhas`): each one *replaces* the previous version — apply them in order and watch the behaviour change.

---

## Key concepts

### Ingress vs. Ingress controller

- **Ingress** — a Kubernetes object with HTTP(S) routing rules: *host + path → Service:port*, plus optional TLS.
- **Ingress controller** — a reverse proxy running in the cluster (ingress-nginx, Traefik, HAProxy, Contour…) that watches Ingress objects and configures itself. **Without a controller, Ingress objects do nothing** (no `ADDRESS`).
- **IngressClass** — links Ingresses to a controller (`spec.ingressClassName`). One class can be marked default (`ingressclass.kubernetes.io/is-default-class: "true"`); Ingresses created *without* a class then get it assigned.

```
           ┌────────── kind node (control-plane) ──────────┐
curl ──► localhost:80 ─► hostPort 80 ─► ingress-nginx Pod ──┬─► Service giropops-senhas:5000 ─► app Pods ─► redis-service:6379
                                                            └─► Service nginx:80 (Host: giropops.nginx.io)
```

### Path matching

| `pathType` | `/giropops-senhas` matches | Notes |
|---|---|---|
| `Prefix` | `/giropops-senhas`, `/giropops-senhas/`, `/giropops-senhas/x` (not `/giropops-senhasX`) | Element-wise prefix on `/` boundaries |
| `Exact` | Only `/giropops-senhas` | |
| `ImplementationSpecific` | Controller-defined | Avoid — not portable |

Longest match wins; host rules beat rules without a host.

### `rewrite-target`

`nginx.ingress.kubernetes.io/rewrite-target: /` rewrites the request path before sending it to the backend. With `path: /giropops-senhas`, a request for `/giropops-senhas` reaches the app as `/`. The catch: the HTML the app returns references `/static/style.css` — a path the Ingress doesn't route. That is why `ingress-2.yaml` exists, and why apps behind a sub-path usually need to know their base URL.

### Host-based routing

Several hostnames on the same IP; the controller picks the rule by the HTTP `Host` header (and SNI for TLS). Test without DNS with `curl -H 'Host: …'` or `curl --resolve host:port:127.0.0.1`.

---

## Hands-on lab

### 0. Cluster with ports 80/443 on localhost

`kind/kind-com-ingress.yaml` documents what was typed in class, but kind rejects it (typos — see [Known issues](#known-issues-in-the-manifests)):

```bash
cd 09-ingress-nginx
kind create cluster --name ingress --config kind/kind-com-ingress.yaml    # fails: invalid role "control-pane"
```

Use this working equivalent (not stored as a file to keep the course files unchanged):

```bash
cat <<'EOF' | kind create cluster --name ingress --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  labels:
    ingress-ready: "true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
kubectl cluster-info --context kind-ingress
```

> Ports 80/443 must be free on your machine (stop any local Apache/nginx first).

### 1. Install ingress-nginx (kind flavour)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl get ingressclass                         # "nginx"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   # 404 from the controller's default backend = it works
```

Make `nginx` the default class **before** creating Ingresses, so the ones without `ingressClassName` (1 to 4) are picked up:

```bash
kubectl annotate ingressclass nginx ingressclass.kubernetes.io/is-default-class="true"
```

### 2. Deploy the application

```bash
kubectl apply -f manifests/giropops-senhas/
kubectl rollout status deploy/redis-deployment
kubectl rollout status deploy/giropops-senhas
kubectl get pods,svc

# Direct test, bypassing the Ingress
kubectl port-forward svc/giropops-senhas 5000:5000 &
curl -s localhost:5000 | head -5; kill %1
```

### 3. Path-based routing and the rewrite problem — `ingress-1`, `ingress-2`

```bash
kubectl apply -f manifests/ingress/ingress-1.yaml
kubectl get ingress giropops-senhas -w          # wait for ADDRESS (localhost), Ctrl+C
curl -s http://localhost/giropops-senhas | grep -o '/static/[^"]*' | head -3   # the page asks for /static/...
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/static/css/style.css  # 404 → page renders without CSS
```

Open http://localhost/giropops-senhas in a browser: content but no styles. Add the static route:

```bash
kubectl apply -f manifests/ingress/ingress-2.yaml
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/static/css/style.css  # 200
```

(The exact asset path may differ; take one from the `grep` output above.)

### 4. Serve the app at `/` — `ingress-3`

```bash
kubectl apply -f manifests/ingress/ingress-3.yaml     # replaces ingress-1 (same name)
kubectl describe ingress giropops-senhas | sed -n '/Rules/,/Annotations/p'
curl -s http://localhost/ | head -5
```

Generate a password in the browser at http://localhost/ — it is stored in Redis:

```bash
kubectl exec deploy/redis-deployment -- redis-cli KEYS '*'
```

### 5. Host-based routing — `ingress-4`

```bash
kubectl apply -f manifests/nginx/
kubectl apply -f manifests/ingress/ingress-4.yaml
curl -s -H 'Host: giropops.nginx.io' http://localhost/ | grep -i '<title>'      # Welcome to nginx!
curl -s http://localhost/ | grep -i '<title>'                                   # still giropops-senhas
```

Optionally add `127.0.0.1 giropops.nginx.io` to `/etc/hosts` and open it in the browser.

### 6. Explicit IngressClass — `ingress-5`

```bash
kubectl apply -f manifests/ingress/ingress-5.yaml
kubectl get ingress giropops-senhas -o jsonpath='{.spec.ingressClassName}{"\n"}'   # nginx
```

### 7. Real hostname — `ingress-6`

```bash
kubectl apply -f manifests/ingress/ingress-6.yaml
curl -s --resolve giropops.salatielaizza.com:80:127.0.0.1 http://giropops.salatielaizza.com/ | head -5
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/                      # 404 — the rule now needs that Host
```

This is the starting point of module 10 (TLS with cert-manager). Keep the cluster if you continue there.

### 8. Look inside the controller

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=20          # access log lines per request
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -A3 'server_name giropops'
```

### Cleanup

```bash
kubectl delete -f manifests/ingress/ -f manifests/nginx/ -f manifests/giropops-senhas/ --ignore-not-found
kind delete cluster --name ingress      # if you are not continuing with module 10
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| `kind create cluster` fails with `invalid role` / unknown field | Typos in `kind/kind-com-ingress.yaml` | Use the working config in step 0 |
| `curl localhost` → connection refused | No `extraPortMappings`, or controller not scheduled on the node with the ports | `docker ps` (ports 80/443 on the control-plane container); `kubectl -n ingress-nginx get pods -o wide` |
| Controller Pod `Pending` | Node lacks `ingress-ready=true` label | `kubectl get nodes --show-labels` |
| Ingress has no `ADDRESS` and requests 404 | No class and no default IngressClass → controller ignores it | Set `ingressClassName: nginx` or annotate the class as default, then recreate the Ingress |
| `404 Not Found` from nginx | No rule matches host/path | `kubectl describe ingress`; check `Host` header and `pathType` |
| `503 Service Temporarily Unavailable` | Backend Service has no Ready endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` |
| `502 Bad Gateway` | Wrong Service port / app not listening on `targetPort` | `kubectl describe svc`; port-forward to the Service directly |
| Page loads without CSS/JS | Sub-path + `rewrite-target`, assets requested at `/static` | Add a `/static` route (ingress-2) or serve the app at `/` |
| `admission webhook "validate.nginx.ingress.kubernetes.io" denied the request` | Conflicting host/path already defined by another Ingress, or invalid annotation | Read the message; check `kubectl get ingress -A` |
| Old Ingress rules still active after "replacing" | Applied a file with a **different** `metadata.name` | `kubectl get ingress`; delete the old object |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, `kind create cluster`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `kind/kind-com-ingress.yaml` | `role: control-pane` (typo of `control-plane`) | kind refuses the config | `control-plane` |
| `kind/kind-com-ingress.yaml` | `KubeletExtraArgs` (capital K) and label `Ingress-ready=true` (capital I) | Unknown field / wrong label → ingress-nginx's `nodeSelector: ingress-ready: "true"` never matches | `kubeletExtraArgs`, `ingress-ready=true` — or the simpler `labels:` field (step 0) |
| `kind/kind-com-ingress.yaml` | Last `extraPortMappings` entry has only `containerPort: 443` | No `hostPort` → HTTPS not reachable from the host | Add `hostPort: 443`, `protocol: TCP` |
| `ingress/ingress-1,3,5,6.yaml` | Same `metadata.name: giropops-senhas` | Each apply replaces the previous one (intended as steps) | One file per environment/version in Git, not per experiment |
| `ingress/ingress-1…4.yaml` | No `ingressClassName` | Ignored by ingress-nginx unless a default IngressClass exists | Always set `ingressClassName` |
| `ingress/ingress-3,5,6.yaml` | `rewrite-target: /` on path `/` | Every sub-path (`/api/x`) is rewritten to `/` — app routes beyond `/` break | Drop the annotation when no rewrite is needed, or use capture groups (`/(.*)` → `/$1`) |
| `ingress/ingress-5.yaml` | Commented-out `host` line mis-indented; trailing space after the name | Cosmetic | `yamllint` in CI |
| `ingress/ingress-6.yaml` | Real public hostname | Works locally only with `--resolve` / `/etc/hosts` | Parameterise per environment |
| `nginx/nginx.yaml` | Generated stub (`resources: {}`, `status: {}`), untagged image, bare Pod | BestEffort, no self-healing | Deployment, pinned tag, requests/limits |
| `nginx/nginx-service.yaml` | Selector `run: nginx` relies on the label `kubectl run` adds; Spanish inline comment | Fragile coupling | Standard `app.kubernetes.io/name` labels |
| `giropops-senhas/app-deployment.yaml` | No requests/limits, no probes; `imagePullPolicy: Always` with a fixed tag | BestEffort; traffic before the app is ready; pull on every start | Add resources + readiness/liveness; `IfNotPresent` |
| `giropops-senhas/redis-deployment.yaml` | Untagged `redis`, no persistence | Data lost on restart | Pin tag; StatefulSet + PVC if data matters |

---

## Interview questions

<details>
<summary>1. What is the difference between an Ingress and an Ingress controller?</summary>

The Ingress is just a declarative routing object stored in the API. The controller is the actual proxy (a Deployment/DaemonSet) that watches Ingress objects and translates them into its own config (nginx.conf, Envoy xDS…). Without a controller an Ingress has no effect.
</details>

<details>
<summary>2. Ingress vs. Service of type LoadBalancer — when do you use each?</summary>

A LoadBalancer Service gives one external L4 endpoint per Service. An Ingress (behind a single LoadBalancer for the controller) gives L7 routing — many hostnames/paths, TLS termination, redirects — for many Services at once, which is cheaper and centralises policy. Non-HTTP protocols (databases, MQTT, gRPC without HTTP/2 routing) usually go through LoadBalancer/NodePort or Gateway API TCP/UDP routes.
</details>

<details>
<summary>3. Requests return 503 from the Ingress. What do you check?</summary>

503 from ingress-nginx means "no healthy upstream": the Service has no Ready endpoints. Check `kubectl get endpointslices` for the Service, Pod readiness, that the Service selector matches the Pods, and that the Ingress backend references the right Service name and port.
</details>

<details>
<summary>4. Explain `pathType: Prefix` vs `Exact`, and which rule wins when several match.</summary>

`Exact` matches the path literally; `Prefix` matches on `/`-separated elements (`/foo` matches `/foo/bar` but not `/foobar`). Rules with a matching host take precedence over host-less rules, and among paths the longest match wins; on ties, `Exact` beats `Prefix`.
</details>

<details>
<summary>5. ingress-nginx is retired. What would you migrate to and how?</summary>

To the **Gateway API** (GatewayClass / Gateway / HTTPRoute) with a maintained implementation — Envoy Gateway, Cilium, Istio, NGINX Gateway Fabric, Traefik, or a cloud-native gateway. Steps: inventory Ingresses and especially nginx-specific annotations (rewrites, auth, rate limits, snippets), map them to HTTPRoute filters/policies (the `ingress2gateway` tool helps), run both side by side on different IPs, shift DNS gradually, then remove ingress-nginx.
</details>

<details>
<summary>6. Why can the Gateway API be considered an improvement over Ingress?</summary>

Role separation (infra team owns GatewayClass/Gateway, app teams own Routes, cross-namespace attachment is explicit), portable features that Ingress only had as vendor annotations (header matching, traffic splitting/weights, redirects, rewrites), and support for more protocols (TCP, UDP, TLS passthrough, gRPC).
</details>

<details>
<summary>7. How does a request for `giropops.nginx.io` reach the nginx Pod on kind?</summary>

curl → `localhost:80` → Docker port mapping into the kind node container → `hostPort: 80` of the ingress-nginx controller Pod → nginx matches `server_name giropops.nginx.io` and location `/` → upstream = endpoints of Service `nginx` (ingress-nginx proxies directly to Pod IPs, bypassing kube-proxy) → nginx Pod.
</details>

---

## References

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [kind — Ingress](https://kind.sigs.k8s.io/docs/user/ingress/)
- [Ingress NGINX Retirement: What You Need to Know (Nov 2025)](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- [Ingress NGINX: Statement from the Steering and Security Response Committees (Jan 2026)](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Gateway API](https://gateway-api.sigs.k8s.io/) · [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
