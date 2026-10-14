# Descomplicando Kubernetes — Learning Portfolio

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![kind](https://img.shields.io/badge/kind-local%20clusters-blue)
![Modules](https://img.shields.io/badge/modules-10%2F10%20restructured-brightgreen)

Hands-on notes, manifests and labs from the **Descomplicando o Kubernetes — Expert Mode** course by Jeferson Fernando ([LinuxTips](https://www.linuxtips.io/)), restructured into a documented, module-by-module learning path aimed at real-world DevOps / Platform Engineering work and CKA/CKAD preparation.

Every module contains:

- a **README** with learning objectives, key concepts, a step-by-step lab, a troubleshooting table, *known issues in the manifests* and interview questions;
- a **`commands.md`** cheat sheet with the commands used in the lesson;
- the **manifests written during the course**, organised by purpose (`manifests/`, `kind/`, `config/`, `scripts/`…);
- a **challenge** with its solution where there is a real exercise.

## Learning Path

| # | Module | Topics | Lab environment |
|---|--------|--------|-----------------|
| 01 | [Kubernetes Fundamentals](01-kubernetes-fundamentals/) | Containers, OCI/CRI, cluster architecture, kind, first Pods, kubectl | kind |
| 02 | [Pods in Depth: Resources & Volumes](02-pods-resources-and-volumes/) | Multi-container Pods, requests/limits, QoS classes, OOMKilled, `emptyDir` | kind |
| 03 | [Deployments, Rollouts & Rollbacks](03-deployments-and-rollouts/) | Deployment → ReplicaSet → Pod, RollingUpdate vs Recreate, `rollout history/undo`, Namespaces | kind |
| 04 | [ReplicaSets, DaemonSets & Probes](04-replicasets-daemonsets-and-probes/) | ReplicaSet, DaemonSet, `maxSurge`/`maxUnavailable`, startup/liveness/readiness probes | kind (multi-node) |
| 05 | [Building a Cluster with kubeadm](05-cluster-installation-with-kubeadm/) | Node preparation, containerd, `kubeadm init/join`, kubeconfig, CNI (Flannel, Calico, Cilium) | 3 Linux VMs |
| 06 | [Persistent Storage](06-persistent-volumes-and-storage/) | StorageClass, PV, PVC, static vs dynamic provisioning, access modes, reclaim policy, NFS | kind (+ optional NFS server) |
| 07 | [Services & StatefulSets](07-services-and-statefulsets/) | ClusterIP, NodePort, LoadBalancer, headless Services, DNS, StatefulSets, `volumeClaimTemplates` | kind (multi-node) |
| 08 | [Secrets & ConfigMaps](08-secrets-and-configmaps/) | Opaque/TLS/registry Secrets, ConfigMaps, env vs volume mounts, `subPath`, `imagePullSecrets`, HTTPS nginx | kind |
| 09 | [Ingress with ingress-nginx](09-ingress-nginx/) | Ingress controllers, IngressClass, path & host routing, `rewrite-target`, Gateway API outlook | kind (ports 80/443) |
| 10 | [HTTPS with cert-manager](10-ingress-tls-with-cert-manager/) | cert-manager, Issuer/ClusterIssuer, ACME HTTP-01, Let's Encrypt staging/prod, private CA | kind from module 09 |
| — | [Cases](cases/) | Real-world troubleshooting scenarios with post-mortems (e.g. the Friday deploy: missing resources and probes) | kind |

Suggested order: 01 → 04 build on each other; 05 can be done any time (it needs VMs, not kind); 06 → 08 are independent; 09 → 10 are one continuous lab.

## Prerequisites

| Tool | Used in | Purpose |
|------|---------|---------|
| [Docker](https://docs.docker.com/engine/install/) | all kind labs | Runs the kind nodes |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | 01-04, 06-10 | Local multi-node clusters |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | all | Kubernetes CLI |
| 3 Linux VMs (Ubuntu/Debian, 2 vCPU / 2 GB) | 05 | kubeadm cluster |
| `openssl` | 08, 10 | Certificates |
| `curl` | 07-10 | Testing Services and Ingress |

Quick start:

```bash
git clone https://github.com/salatielaizza/Descomplicando_K8S.git
cd Descomplicando_K8S/01-kubernetes-fundamentals
kind create cluster --config kind/kind-multinode.yaml
kubectl apply -f manifests/
```

Then follow the **Hands-on lab** section of each module's README.

## Repository Layout

```
Descomplicando_K8S/
├── 01-kubernetes-fundamentals/
│   ├── README.md          # objectives, concepts, lab, troubleshooting, known issues, interview questions
│   ├── commands.md        # cheat sheet
│   ├── kind/              # kind cluster configs
│   ├── manifests/         # Kubernetes objects
│   └── challenge/         # exercise + solution
├── 02-…/ … 10-…/          # same structure (+ config/, scripts/, reference/ where needed)
└── cases/                 # troubleshooting cases and post-mortems
```

## Conventions

- Module folders are named `NN-topic-in-kebab-case`.
- **Module 01** manifests were cleaned up: pinned image tags, [recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/), resource requests/limits, named ports.
- **Modules 02-10** keep the manifests **exactly as written during the course**. Their problems (untagged images, label typos, name clashes, wrong annotations…) are not silently fixed: each README lists them in a *Known issues in the manifests* table with the production fix, which turns every module into a "spot the problem" review exercise. Where a file is broken, the lab shows how to fix the live object with `kubectl` instead.
- Docs are in English; original Portuguese course notes are kept unchanged where they exist (`05-…/course-notes-pt-br.md`).

## Notes

- **ingress-nginx** (module 09) was [retired by the Kubernetes project](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/). It is still used here to learn the `Ingress` API; new clusters should look at the [Gateway API](https://gateway-api.sigs.k8s.io/).
- The legacy `apt.kubernetes.io` repository and Weave Net used in the original day-5 notes no longer exist; module 05 uses `pkgs.k8s.io` and Flannel.

## Credits

Course content and original material: **LinuxTips — Descomplicando o Kubernetes** ([public book](https://github.com/badtuxx/DescomplicandoKubernetes)). Notes, restructuring and lab improvements: [@salatielaizza](https://github.com/salatielaizza).
