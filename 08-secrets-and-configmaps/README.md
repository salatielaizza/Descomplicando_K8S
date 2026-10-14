# 08 — Secrets & ConfigMaps

> **Course:** Descomplicando Kubernetes – Expert Mode (LinuxTips), Day 8
> **Lab environment:** any local cluster (kind, minikube), `openssl`, and a Docker Hub account for the private-registry part.

## Learning objectives

By the end of this module you should be able to:

- Explain why configuration and credentials must live **outside the container image**.
- Create **Secrets** (generic/Opaque, TLS, docker-registry) imperatively and declaratively, and explain why base64 is **not** encryption.
- Create **ConfigMaps** from literals, files and manifests.
- Consume both as **environment variables** and as **mounted files** (including `subPath` and `items`).
- Pull from a **private registry** with `imagePullSecrets`.
- Serve HTTPS from nginx using a TLS Secret and a ConfigMap-provided `nginx.conf`.
- Describe how Secrets are protected in production (RBAC, encryption at rest, external secret managers).

### Why it matters in production

Leaked credentials in Git, images or CI logs are one of the most common causes of security incidents. Twelve-factor apps read config from the environment so the **same image** runs in dev, staging and prod. Knowing how updates propagate (env vars never update; mounted files do, except with `subPath`) explains a whole class of "I changed the ConfigMap and nothing happened" tickets.

---

## Module layout

```
08-secrets-and-configmaps/
├── README.md                              # this file
├── commands.md                            # kubectl / openssl cheat sheet for the day
├── config/
│   ├── nginx.conf                         # nginx config with HTTP + HTTPS server (see Known issues)
│   └── certificado.crt                    # self-signed certificate (public part only, O=Salatux, valid until Jan 2027)
└── manifests/
    ├── primeiro-secret.yaml               # Secret giropops-secret: username/password (base64)
    ├── pod-secret.yaml                    # Pod giropops-pod: Secret keys as env vars USERNAME / PASSWORD
    ├── configmap.yaml                     # ConfigMap nginx-config: nginx.conf with TLS on 443
    ├── pod-configmap-secret.yaml          # Pod giropops-pod: nginx.conf from ConfigMap + cert/key from a TLS Secret
    ├── secret-meu-servico-web-tls.yaml    # EMPTY file — the TLS Secret is created with kubectl (see lab)
    └── pod-usando-imagem-privada.yaml     # Pod meu-pod: private image + imagePullSecrets dockerhub-secret
```

> **Note:** the YAML manifests are kept **exactly as written during the course** (byte-for-byte). Their quirks are documented in [Known issues in the manifests](#known-issues-in-the-manifests).
>
> ⚠️ `primeiro-secret.yaml` contains base64-encoded credentials. Anyone can decode them (`echo bHV0cml4 | base64 -d`). If they were ever used for anything real, rotate them. The private key matching `certificado.crt` is **not** in the repository (and must never be — the root `.gitignore` excludes `*.key`).

---

## Key concepts

### ConfigMap vs Secret

| | ConfigMap | Secret |
|---|---|---|
| For | Non-sensitive config (URLs, feature flags, config files) | Passwords, tokens, keys, certificates |
| Stored as | Plain text (`data`) | base64 (`data`) or plain text you write in `stringData` |
| Size limit | 1 MiB | 1 MiB |
| Extra protection | None | Can be **encrypted at rest** in etcd; mounted on tmpfs (never written to node disk); separate RBAC is common |

**base64 is an encoding, not encryption.** A Secret is only as safe as the RBAC that guards `get secrets`, etcd encryption, and whoever can create Pods in the namespace (a Pod can mount any Secret in its namespace).

### Secret types

| Type | Keys | Created with |
|---|---|---|
| `Opaque` (default) | Anything | `kubectl create secret generic` |
| `kubernetes.io/tls` | `tls.crt`, `tls.key` | `kubectl create secret tls` |
| `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | `kubectl create secret docker-registry` |
| `kubernetes.io/basic-auth`, `ssh-auth`, `service-account-token`… | Fixed per type | YAML |

### Consuming them

| Method | Syntax | Updates when the object changes? |
|---|---|---|
| Single env var | `env[].valueFrom.secretKeyRef` / `configMapKeyRef` | **No** — restart the Pod |
| All keys as env | `envFrom[].secretRef` / `configMapRef` | **No** |
| Volume (whole object) | `volumes[].secret` / `configMap` | **Yes**, eventually (kubelet sync, ~1 min) |
| Volume, selected keys | `items: [{key, path}]` | Yes |
| Single file with `subPath` | `volumeMounts[].subPath` | **No** — `subPath` mounts are never updated |

`pod-configmap-secret.yaml` uses both styles: `nginx.conf` with `subPath` (so it can sit next to the image's other files in `/etc/nginx/`), and the TLS Secret with `items` to rename `tls.crt`/`tls.key` to the file names nginx expects.

### imagePullSecrets

The kubelet (not the container) pulls images, so registry credentials are given to the Pod spec (`imagePullSecrets`) or attached to the ServiceAccount, as a `kubernetes.io/dockerconfigjson` Secret in the **same namespace**.

---

## Hands-on lab

### 0. Prerequisites

```bash
kubectl cluster-info
cd 08-secrets-and-configmaps
```

### 1. Opaque Secret as environment variables

```bash
kubectl apply -f manifests/primeiro-secret.yaml
kubectl get secret giropops-secret -o yaml                     # data is base64
kubectl get secret giropops-secret -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret giropops-secret -o jsonpath='{.type}{"\n"}' # "opaque" — see Known issues

kubectl apply -f manifests/pod-secret.yaml
kubectl exec giropops-pod -- sh -c 'echo "$USERNAME / $PASSWORD"'
kubectl delete -f manifests/pod-secret.yaml                    # frees the name giropops-pod for step 3
```

The imperative way (and how to generate YAML without hand-encoding base64):

```bash
kubectl create secret generic demo-secret --from-literal=username=admin --from-literal=password='S3cr3t!' \
  --dry-run=client -o yaml
```

### 2. TLS Secret

The repo only has the public certificate, so generate a fresh key pair (outside the repo):

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/chave-privada.key -out /tmp/certificado.crt \
  -subj "/C=ES/L=Madrid/O=Salatux/CN=giropops.local"

kubectl create secret tls meu-servico-web-tls-secret --cert=/tmp/certificado.crt --key=/tmp/chave-privada.key
kubectl describe secret meu-servico-web-tls-secret              # type kubernetes.io/tls, keys tls.crt / tls.key
```

Inspect the certificate that *is* in the repo:

```bash
openssl x509 -in config/certificado.crt -noout -subject -issuer -dates
```

> `manifests/secret-meu-servico-web-tls.yaml` is empty. Generating it with `kubectl create secret tls … --dry-run=client -o yaml > secret-….yaml` would put the **private key** in Git — keeping it empty (or deleting it) is the right call. Use Sealed Secrets / SOPS / External Secrets if Secrets must live in Git.

### 3. ConfigMap + TLS Secret → nginx over HTTPS

```bash
kubectl apply -f manifests/configmap.yaml
kubectl describe configmap nginx-config

kubectl apply -f manifests/pod-configmap-secret.yaml
kubectl get pod giropops-pod
kubectl exec giropops-pod -- ls -l /etc/nginx/nginx.conf /etc/nginx/tls/

kubectl port-forward pod/giropops-pod 8443:443 8080:80 &
curl -k https://localhost:8443          # Ola terraqueos e extraterrestres!
curl    http://localhost:8080
curl -kv https://localhost:8443 2>&1 | grep -E 'subject:|expire'
kill %1
```

### 4. Updates: volume vs subPath vs env

```bash
kubectl create configmap demo-cm --from-literal=color=blue
kubectl run cm-demo --image=busybox:1.36 --restart=Never --overrides='
{"spec":{"containers":[{"name":"c","image":"busybox:1.36","command":["sleep","3600"],
  "envFrom":[{"configMapRef":{"name":"demo-cm"}}],
  "volumeMounts":[{"name":"cm","mountPath":"/cfg"}]}],
  "volumes":[{"name":"cm","configMap":{"name":"demo-cm"}}]}}'
kubectl wait --for=condition=Ready pod/cm-demo

kubectl create configmap demo-cm --from-literal=color=green --dry-run=client -o yaml | kubectl apply -f -
sleep 70
kubectl exec cm-demo -- sh -c 'echo "env: $color"; echo "file: $(cat /cfg/color)"'   # env: blue / file: green
kubectl delete pod cm-demo; kubectl delete configmap demo-cm
```

Changing `nginx-config` would **not** reach `giropops-pod`, because `nginx.conf` is mounted with `subPath` — and nginx would need a reload anyway. The usual fix is a rollout (`kubectl rollout restart`) triggered by a config hash annotation (Helm/Kustomize do this).

### 5. Private registry

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<your-user> \
  --docker-password=<access-token>          # use a Docker Hub access token, not your password

kubectl apply -f manifests/pod-usando-imagem-privada.yaml
kubectl get pod meu-pod
```

`salatielaizza/teste-privado:1.0` is the author's private image: anyone else will see `ErrImagePull` / `pull access denied` — which is exactly what a missing or wrong `imagePullSecret` looks like. To test with your own private image without editing the file:

```bash
kubectl set image pod/meu-pod meu-container=<your-user>/<private-repo>:<tag>
kubectl describe pod meu-pod | sed -n '/Events/,$p'
```

### Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
kubectl delete secret meu-servico-web-tls-secret dockerhub-secret --ignore-not-found
rm -f /tmp/chave-privada.key /tmp/certificado.crt
```

---

## Troubleshooting

| Symptom | Likely cause | How to confirm / fix |
|---|---|---|
| Pod `CreateContainerConfigError`: `secret "X" not found` / `couldn't find key` | Secret/key missing or in another namespace | `kubectl get secret X -o yaml`; create it in the Pod's namespace |
| Pod `ContainerCreating`, event `MountVolume.SetUp failed … secret "X" not found` | Volume references a missing Secret/ConfigMap | Create it, or mark it `optional: true` |
| `AlreadyExists` for `giropops-pod` | `pod-secret.yaml` and `pod-configmap-secret.yaml` use the same Pod name | Delete the first Pod |
| nginx `CrashLoopBackOff`: `no "events" section in configuration` | ConfigMap created from `config/nginx.conf` (no `events {}` block) | Use `manifests/configmap.yaml`, or add `events {}` |
| nginx: `cannot load certificate "/etc/nginx/tls/certificado.crt"` | TLS Secret missing / `items` paths don't match `ssl_certificate*` | `kubectl exec … ls /etc/nginx/tls` |
| `ErrImagePull` / `pull access denied` / `401 Unauthorized` | No or wrong `imagePullSecrets`, Secret in another namespace, expired token | `kubectl describe pod`; recreate the docker-registry Secret |
| Changed a ConfigMap, app still uses old value | Env vars or `subPath` mount | `kubectl rollout restart deployment/<name>` |
| `illegal base64 data at input byte` on apply | Wrote plain text in `data` | Use `stringData` for plain text, or `echo -n value \| base64` (note `-n`) |

---

## Known issues in the manifests

The files are intentionally left as written in class. Review findings (`yamllint -d relaxed`, `kubeconform -strict`, manual review):

| File | Finding | Impact | Production fix |
|---|---|---|---|
| `manifests/primeiro-secret.yaml` | Real-looking credentials committed (base64 = plain text) | Anyone with repo access can read them | Never commit Secrets; use Sealed Secrets, SOPS, External Secrets Operator or Vault; rotate exposed values |
| `manifests/primeiro-secret.yaml` | `type: opaque` (lowercase) | Accepted as a *custom* type, not the built-in `Opaque` | `type: Opaque` |
| `manifests/secret-meu-servico-web-tls.yaml` | Empty file (0 bytes) | Nothing to apply; the Secret is created imperatively | Delete it, or keep a template without key material |
| `config/nginx.conf` | No `events {}` block (the ConfigMap version has it) | `kubectl create configmap --from-file` with this file → nginx fails to start | Add `events {}`; keep a single source of truth and generate the ConfigMap from it (Kustomize `configMapGenerator`) |
| `manifests/pod-secret.yaml`, `pod-configmap-secret.yaml` | Same Pod name `giropops-pod` | Can't run both | Unique names |
| `manifests/pod-secret.yaml` | Credentials exposed as env vars | Visible to anything that can read the process env, crash dumps, `kubectl describe` of child processes | Prefer mounted files for sensitive values |
| all Pods | Untagged `nginx` image, no resources, bare Pods (no controller) | Non-reproducible, BestEffort, no self-healing | Pin tags, requests/limits, Deployments |
| `manifests/configmap.yaml` | `namespace: default` hard-coded | Can't be reused in other namespaces with `-n` | Leave namespace out of reusable manifests |
| `manifests/pod-usando-imagem-privada.yaml` | `metadata.name` indented with 1 space; trailing space after the image | Valid YAML, cosmetic | `yamllint` in CI |

---

## Interview questions

<details>
<summary>1. Are Kubernetes Secrets secure?</summary>

By default they are only base64-encoded and stored in etcd unencrypted. They become reasonably secure with: encryption at rest (`EncryptionConfiguration`, ideally with a KMS provider), tight RBAC on `get/list/watch secrets` **and** on Pod creation in the namespace, audit logging, and not storing them in Git (or storing them encrypted with SOPS/Sealed Secrets). Many teams keep the source of truth in Vault / AWS Secrets Manager and sync it with External Secrets Operator or the Secrets Store CSI driver.
</details>

<details>
<summary>2. ConfigMap updated, but the app still sees the old value. Why?</summary>

If consumed as environment variables, values are fixed at container start. If mounted with `subPath`, the file is never updated. Plain volume mounts are updated after the kubelet sync period, but the application still has to re-read the file. Fix: restart the rollout, ideally automatically via a checksum annotation on the Pod template.
</details>

<details>
<summary>3. `data` vs `stringData` in a Secret?</summary>

`data` values must be base64-encoded; `stringData` accepts plain text and is merged into `data` (encoded) by the API server on write — it is write-only and never returned on read. `stringData` wins if a key appears in both.
</details>

<details>
<summary>4. How do Pods pull from a private registry?</summary>

Create a `kubernetes.io/dockerconfigjson` Secret (`kubectl create secret docker-registry`) in the Pod's namespace and reference it in `spec.imagePullSecrets`, or attach it to the ServiceAccount so every Pod using that SA gets it. On clouds, node IAM roles / workload identity (ECR, GAR, ACR) often replace static credentials.
</details>

<details>
<summary>5. Why mount a file with `subPath`, and what is the downside?</summary>

To place a single key as a single file inside an existing directory (e.g. `/etc/nginx/nginx.conf`) without hiding the rest of the image's files in that directory. The downside: `subPath` mounts are not updated when the ConfigMap/Secret changes.
</details>

<details>
<summary>6. How would you rotate a TLS certificate stored in a Secret with zero downtime?</summary>

Update the Secret (`kubectl create secret tls … --dry-run=client -o yaml | kubectl apply -f -`). If mounted as a volume without `subPath`, the files update in place and the app must reload them (nginx `-s reload`, or a sidecar/reloader watching the files); otherwise `kubectl rollout restart` a Deployment with a RollingUpdate strategy. In practice, cert-manager automates issuance and renewal (module 10).
</details>

<details>
<summary>7. What is an immutable ConfigMap/Secret and why use it?</summary>

`immutable: true` forbids changes to `data`. It protects against accidental edits that would break running apps and reduces API-server load because kubelets stop watching it. To change config you create a new object (e.g. with a hash suffix, as Kustomize generators do) and roll the Deployment to it.
</details>

---

## References

- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Encrypting confidential data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Pull an image from a private registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [External Secrets Operator](https://external-secrets.io/) · [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) · [SOPS](https://github.com/getsops/sops)
