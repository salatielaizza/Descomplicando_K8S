# Descomplicando Kubernetes — Learning Portfolio

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![kind](https://img.shields.io/badge/kind-local%20clusters-blue)
![Status](https://img.shields.io/badge/status-in%20progress-yellow)

Hands-on notes, manifests and labs from the **Descomplicando o Kubernetes — Expert Mode** course by Jeferson Fernando ([LinuxTips](https://www.linuxtips.io/)), restructured into a documented, module-by-module learning path aimed at real-world DevOps / Platform Engineering work and CKA/CKAD preparation.

Every module contains:

- a **README** with learning objectives, key concepts, a step-by-step lab, a troubleshooting table and interview questions;
- **cleaned-up manifests** (pinned images, recommended labels, resource requests/limits);
- a **challenge** with its solution where the course provides one.

## Learning Path

| # | Module | Topics | Status |
|---|--------|--------|--------|
| 01 | [Kubernetes Fundamentals](01-kubernetes-fundamentals/) | Containers, OCI/CRI, cluster architecture, kind, Pods, kubectl | ✅ Restructured |
| 02 | [`day-2`](day-2/) | Pods in depth: resources, limits, volumes (`emptyDir`) | 🚧 To restructure |
| 03 | [`day-3`](day-3/) | — | 🚧 To restructure |
| 04 | [`day-4`](day-4/) | — | 🚧 To restructure |
| 06 | [`day-6`](day-6/) | — | 🚧 To restructure |
| 07 | [`day-7`](day-7/) | — | 🚧 To restructure |
| 08 | [`day-8`](day-8/) | — | 🚧 To restructure |
| — | [Cases](cases/) | Real-world troubleshooting scenarios with post-mortems | 🚧 To restructure |

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Docker](https://docs.docker.com/engine/install/) | Runs the kind nodes |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Local multi-node clusters |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes CLI |

Quick start:

```bash
git clone https://github.com/salatielaizza/Descomplicando_K8S.git
cd Descomplicando_K8S/01-kubernetes-fundamentals
kind create cluster --config kind/kind-multinode.yaml
kubectl apply -f manifests/
```

## Repository Conventions

- Module folders are named `NN-topic-in-kebab-case`.
- Inside a module: `manifests/` (Kubernetes objects), `kind/` (cluster configs), `challenge/` (exercises), `commands.md` (cheat sheet).
- Manifests follow the [recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/), never use the `latest` tag, and declare resource requests/limits.

## Credits

Course content and original material: **LinuxTips — Descomplicando o Kubernetes** ([public book](https://github.com/badtuxx/DescomplicandoKubernetes)). Notes, restructuring and lab improvements: [@salatielaizza](https://github.com/salatielaizza).
