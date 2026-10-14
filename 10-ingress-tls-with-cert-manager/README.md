# 10 — HTTPS for Ingress with cert-manager & Let's Encrypt

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 10 (continuation of the Ingress lessons)
> **Lab environment:** the kind cluster from [`09-ingress-nginx`](../09-ingress-nginx/) with ingress-nginx and the giropops-senhas app running. Real Let's Encrypt certificates additionally need a **publicly reachable** cluster and a DNS record you control.

## Learning objectives

By the end of this module you should be able to:

- Explain how TLS termination works on an Ingress (`spec.tls`, `secretName`, SNI).
- Install **cert-manager** and describe its objects: `Issuer` / `ClusterIssuer` → `Certificate` → `CertificateRequest` → `Order` → `Challenge`.
- Configure an **ACME** issuer for Let's Encrypt **staging** and **production** with the **HTTP-01** solver.
- Get certificates issued automatically from Ingress **annotations** (`cert-manager.io/issuer` vs `cert-manager.io/cluster-issuer`).
- Debug a certificate that never becomes `Ready` by walking the object chain.
- Issue certificates from a private CA when ACME is not possible (local/air-gapped clusters).

### Why it matters in production

Every public endpoint needs a valid certificate, and certificates expire (Let's Encrypt: 90 days, moving to shorter lifetimes). cert-manager is the de-facto standard to automate issuance and renewal in Kubernetes; an expired certificate is one of the most common — and most avoidable — outages. Knowing how to read `Certificate` / `Order` / `Challenge` status is what turns "HTTPS is broken" into a five-minute fix.

---

## Module layout

```
10-ingress-tls-with-cert-manager/
├── README.md                       # this file
├── commands.md                     # cert-manager / openssl / curl cheat sheet
└── manifests/
    ├── letsencrypt-issuers.yaml    # Issuer (namespaced) letsencrypt-staging — ACME staging, HTTP-01 via ingress class nginx
    ├── ingress-6.yaml              # Ingress giropops-senhas: host giropops.salatielaizza.com + tls secret giropops-salatiel-aizza-tls
    └── production-issuer.yaml      # despite its name: the SAME Ingress as ingress-6.yaml (plus a comment) — no issuer inside
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). As they are, **no certificate is ever issued** — the annotation key has a typo and points to an issuer that doesn't exist. The lab uses that on purpose as a debugging exercise and then fixes the *live* objects. Details in [Known issues in the manifests](#known-issues-in-the-manifests).

---

## Key concepts

### TLS on an Ingress

```yaml
spec:
  tls:
  - hosts: [giropops.salatielaizza.com]
    secretName: giropops-salatiel-aizza-tls   # kubernetes.io/tls Secret with tls.crt / tls.key
```

The controller terminates TLS with the certificate in that Secret (chosen by SNI) and forwards plain HTTP to the backend. If the Secret doesn't exist, ingress-nginx serves its built-in **"Kubernetes Ingress Controller Fake Certificate"**.

### cert-manager objects

```
Ingress (annotation) ──ingress-shim──► Certificate ──► CertificateRequest ──► Order (ACME) ──► Challenge(s)
                                           │                                                       │
                                           └──────────── Secret (tls.crt / tls.key) ◄──────────────┘ once validated
Issuer / ClusterIssuer: who signs (ACME, CA, self-signed, Vault, Venafi…)
```

| Object | Scope | Purpose |
|---|---|---|
| `Issuer` | Namespace | Signs certificates only for its own namespace |
| `ClusterIssuer` | Cluster | Usable from any namespace — the usual choice for Let's Encrypt |
| `Certificate` | Namespace | Desired cert: DNS names, issuer, target Secret. Renewed automatically (default ⅔ of lifetime) |
| `CertificateRequest`, `Order`, `Challenge` | Namespace | Internal steps — where the error messages live |

### Ingress annotations (ingress-shim)

| Annotation | Refers to |
|---|---|
| `cert-manager.io/issuer: <name>` | An `Issuer` **in the Ingress's namespace** |
| `cert-manager.io/cluster-issuer: <name>` | A `ClusterIssuer` |

With one of them and a `spec.tls` block, cert-manager creates a `Certificate` named after `secretName` automatically.

### ACME and HTTP-01

Let's Encrypt asks you to prove control of the domain. With **HTTP-01**, cert-manager creates a temporary Pod + Service + Ingress that serves a token at `http://<domain>/.well-known/acme-challenge/<token>`; Let's Encrypt fetches it **from the internet on port 80**. Therefore: public DNS for the name → your ingress' public IP, port 80 open. No wildcards. Behind a firewall or for wildcards, use **DNS-01** (cert-manager writes a TXT record via your DNS provider's API).

| Environment | ACME URL | Certs trusted? | Rate limits |
|---|---|---|---|
| Staging | `https://acme-staging-v02.api.letsencrypt.org/directory` | No (fake root) | Generous — use it to test |
| Production | `https://acme-v02.api.letsencrypt.org/directory` | Yes | Strict (e.g. 50 certs/registered domain/week, 5 duplicate certs/week) |

---

## Hands-on lab

### 0. Prerequisites

Cluster, ingress-nginx and the app from module 09:

```bash
kubectl get ingressclass nginx
kubectl get deploy giropops-senhas redis-deployment
cd 10-ingress-tls-with-cert-manager
```

### 1. Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=180s
kubectl get crds | grep cert-manager.io
```

(Helm alternative: `helm install cert-manager oci://quay.io/jetstack/charts/cert-manager -n cert-manager --create-namespace --set crds.enabled=true`.)

### 2. The staging Issuer

```bash
kubectl apply -f manifests/letsencrypt-issuers.yaml
kubectl get issuer letsencrypt-staging -w          # READY True once the ACME account is registered (needs internet egress)
kubectl describe issuer letsencrypt-staging | sed -n '/Status/,$p'
```

### 3. The Ingress as written — why nothing happens

```bash
kubectl apply -f manifests/ingress-6.yaml
kubectl get certificate                            # No resources found
kubectl get secret giropops-salatiel-aizza-tls     # NotFound
curl -kv --resolve giropops.salatielaizza.com:443:127.0.0.1 https://giropops.salatielaizza.com/ 2>&1 | grep -E 'subject:|issuer:'
#   subject: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
```

Diagnosis (read the annotations): `cert-manager.io/cluster.issuer` is **not** a cert-manager annotation (it is `cluster-issuer`, with a dash), so cert-manager ignores the Ingress. Even with the right key, `letsencrypt-prod` doesn't exist — the only issuer is the namespaced `Issuer` `letsencrypt-staging`. And `production-issuer.yaml` is the same Ingress, not an issuer:

```bash
kubectl apply -f manifests/production-issuer.yaml  # "configured" (only the annotation comment differs) — still no Certificate
```

### 4. Fix the live Ingress → watch the ACME flow

```bash
kubectl annotate ingress giropops-senhas cert-manager.io/cluster.issuer- cert-manager.io/issuer=letsencrypt-staging
kubectl get certificate,certificaterequest,order,challenge
kubectl describe certificate giropops-salatiel-aizza-tls | sed -n '/Events/,$p'
kubectl describe challenge | sed -n '/Status/,$p'
```

On a laptop the Challenge stays `pending`: cert-manager's self-check (and Let's Encrypt itself) can't reach `http://giropops.salatielaizza.com/.well-known/acme-challenge/…` on **your** cluster, because the public DNS name doesn't point to it. You will also see the temporary solver resources:

```bash
kubectl get pods,svc,ingress | grep acme
```

That *is* the lesson: HTTP-01 needs a public endpoint. Clean the attempt up:

```bash
kubectl delete certificate giropops-salatiel-aizza-tls
kubectl annotate ingress giropops-senhas cert-manager.io/issuer-
```

### 5. Get a real certificate locally — private CA issuer

When the cluster isn't public (labs, internal services), sign with your own CA. Bootstrap a CA with cert-manager itself (applied inline so the course files stay unchanged):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: lab-root-ca
  secretName: lab-root-ca
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {name: selfsigned-bootstrap, kind: ClusterIssuer}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca
spec:
  ca:
    secretName: lab-root-ca
EOF
kubectl get clusterissuer                          # selfsigned-bootstrap, lab-ca → READY True
```

Point the Ingress at it (correct annotation key this time):

```bash
kubectl annotate ingress giropops-senhas cert-manager.io/cluster-issuer=lab-ca
kubectl get certificate giropops-salatiel-aizza-tls -w     # READY True within seconds
kubectl get secret giropops-salatiel-aizza-tls

kubectl -n cert-manager get secret lab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/lab-ca.crt
curl --cacert /tmp/lab-ca.crt --resolve giropops.salatielaizza.com:443:127.0.0.1 https://giropops.salatielaizza.com/ | head -5
openssl s_client -connect 127.0.0.1:443 -servername giropops.salatielaizza.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Valid HTTPS, verified against your CA, issued and renewed by cert-manager.

### 6. The real Let's Encrypt flow (public cluster)

On a cluster with a public LoadBalancer IP and a DNS A record `giropops.<your-domain>` → that IP, create **ClusterIssuers** with the names the Ingress expects:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@example.com               # expiry notices go here
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx
EOF
kubectl annotate ingress giropops-senhas cert-manager.io/cluster-issuer=letsencrypt-prod --overwrite
kubectl get certificate -w
```

Always test against **staging** first (same manifest with the staging URL), then switch: failed production attempts count against the rate limits.

### Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
kubectl delete clusterissuer lab-ca selfsigned-bootstrap --ignore-not-found
kubectl -n cert-manager delete certificate lab-root-ca --ignore-not-found
kubectl delete secret giropops-salatiel-aizza-tls letsencrypt-staging --ignore-not-found
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml   # optional
```

---

## Troubleshooting

Walk the chain **Ingress → Certificate → CertificateRequest → Order → Challenge**; the first object that isn't Ready has the error.

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| No `Certificate` created for the Ingress | Missing/misspelled annotation (`cluster.issuer`), or no `spec.tls` | `kubectl get ingress -o yaml`; use `cert-manager.io/cluster-issuer` or `cert-manager.io/issuer` |
| Certificate `False`, `IssuerNotFound` / `issuer … not found` | Name wrong, or `issuer` annotation pointing to a ClusterIssuer (or vice versa) | `kubectl get issuer,clusterissuer -A` |
| Issuer not Ready, ACME registration error | No egress to Let's Encrypt, invalid email | `kubectl describe issuer`; cert-manager logs |
| Challenge `pending`: `Waiting for HTTP-01 challenge propagation: failed to perform self check … connection refused / no such host` | DNS doesn't point to the cluster, or port 80 not reachable | `dig +short <host>`; `curl http://<host>/.well-known/acme-challenge/test` from outside |
| Challenge `invalid` with 404 | Solver Ingress not picked up (wrong `ingressClassName` in the solver) or a redirect/auth in front | `kubectl get ingress` — the `cm-acme-http-solver-*` Ingress must have the right class |
| Browser warns *Fake Certificate* | Secret missing → ingress-nginx default cert | `kubectl get secret <secretName>`; check Certificate status |
| Browser warns *untrusted issuer (STAGING)* | Using the staging issuer | Switch to production once staging works |
| `too many certificates already issued` | Let's Encrypt rate limit | Wait, reuse existing certs, test on staging |
| Certificate Ready but old cert served | Ingress points to a different `secretName` | Compare `spec.tls[].secretName` with `Certificate.spec.secretName` |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `ingress-6.yaml`, `production-issuer.yaml` | Annotation `cert-manager.io/cluster.issuer` (dot) | Not a cert-manager annotation → **no Certificate is ever created** | `cert-manager.io/cluster-issuer` |
| `ingress-6.yaml`, `production-issuer.yaml` | References `letsencrypt-prod`, which is not defined anywhere | Even with the right key: `IssuerNotFound` | Add a `ClusterIssuer` `letsencrypt-prod` |
| `letsencrypt-issuers.yaml` | Namespaced `Issuer` (staging only), while the Ingress asks for a cluster issuer | Kind mismatch | `ClusterIssuer` for both staging and prod, or use `cert-manager.io/issuer` |
| `production-issuer.yaml` | File name says *issuer*, content is the Ingress (duplicate of `ingress-6.yaml`) | Misleading; the production issuer is missing | Rename/remove; put the prod `ClusterIssuer` in this file |
| `ingress-6.yaml`, `production-issuer.yaml` | `rewrite-target: /` on path `/` | Rewrites every path to `/` (see module 09) | Remove the annotation |
| `ingress-6.yaml`, `production-issuer.yaml` | Same name as module 09's Ingress (`giropops-senhas`) | Applying either replaces the other — intended evolution, but implicit | One source of truth per environment |
| `letsencrypt-issuers.yaml` | Personal email committed | Public address in a public repo (spam) | Parameterise or use a team alias |
| all | Trailing spaces after names/secretName; long comment line | Cosmetic (yamllint) | `yamllint` in CI |

---

## Interview questions

<details>
<summary>1. Explain the objects cert-manager creates when an annotated Ingress appears.</summary>

The ingress-shim creates a `Certificate` (name = `secretName`, DNS names from `spec.tls.hosts`). The Certificate controller creates a `CertificateRequest` with a CSR. For ACME issuers that becomes an `Order`, which has one `Challenge` per domain; the Challenge creates the solver (HTTP-01 Pod/Service/Ingress or DNS-01 TXT record). When Let's Encrypt validates, the Order is fulfilled and the signed certificate + key are stored in the Secret; renewal repeats the process before expiry.
</details>

<details>
<summary>2. Issuer vs ClusterIssuer?</summary>

An `Issuer` is namespaced and can only issue certificates in its namespace; a `ClusterIssuer` is cluster-wide. Use ClusterIssuers for shared CAs like Let's Encrypt; use Issuers for per-team CAs or when tenants must manage their own credentials (e.g. DNS-provider API keys in their namespace). The Ingress annotation must match the kind (`issuer` vs `cluster-issuer`).
</details>

<details>
<summary>3. HTTP-01 vs DNS-01 — when do you need DNS-01?</summary>

HTTP-01 needs the domain to resolve to the cluster and port 80 open to the internet; it can't do wildcards. DNS-01 proves control by writing a TXT record through the DNS provider's API: works for private/internal clusters, wildcards (`*.example.com`) and when port 80 is blocked — at the cost of giving cert-manager DNS API credentials.
</details>

<details>
<summary>4. A certificate has been "not ready" for an hour. How do you debug it?</summary>

`kubectl describe certificate` → find the CertificateRequest → `describe order` → `describe challenge`; the deepest object has the real reason (DNS, self-check, 404 on the token, rate limit, issuer not ready). Check `kubectl -n cert-manager logs deploy/cert-manager`. For HTTP-01, `curl` the `/.well-known/acme-challenge/` URL from outside the network.
</details>

<details>
<summary>5. Why use Let's Encrypt staging first?</summary>

Production has strict rate limits (per registered domain, per duplicate certificate, per failed validation). Misconfigurations can lock you out for days. Staging has the same flow with generous limits; its certificates are untrusted, so you switch the issuer to production only once staging issues successfully.
</details>

<details>
<summary>6. How would you monitor certificate expiry in a cluster?</summary>

cert-manager exposes Prometheus metrics such as `certmanager_certificate_expiration_timestamp_seconds` and `certmanager_certificate_ready_status`; alert when a certificate is not Ready or expires in less than, say, 14 days. Externally, blackbox-exporter probes of the public endpoints catch certificates managed outside cert-manager too.
</details>

<details>
<summary>7. Where does TLS terminate in this setup, and how would you get end-to-end encryption?</summary>

At the ingress controller: client ↔ ingress-nginx is HTTPS, ingress-nginx ↔ Pod is plain HTTP inside the cluster network. For end-to-end encryption: re-encrypt to the backend (`nginx.ingress.kubernetes.io/backend-protocol: HTTPS` with a cert on the Pod, possibly also from cert-manager), use TLS passthrough, or a service mesh (Istio, Linkerd, Cilium) providing mTLS between workloads.
</details>

---

## References

- [cert-manager documentation](https://cert-manager.io/docs/)
- [Securing Ingress resources (annotations)](https://cert-manager.io/docs/usage/ingress/)
- [ACME HTTP-01](https://cert-manager.io/docs/configuration/acme/http01/) · [DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/)
- [CA issuer / bootstrapping a CA](https://cert-manager.io/docs/configuration/ca/)
- [Troubleshooting certificates](https://cert-manager.io/docs/troubleshooting/)
- [Let's Encrypt — staging environment](https://letsencrypt.org/docs/staging-environment/) · [rate limits](https://letsencrypt.org/docs/rate-limits/)
- [Ingress — TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
