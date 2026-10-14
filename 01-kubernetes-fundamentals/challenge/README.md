# Challenge — "Pessoa Diretora X"

## Statement

> Original (PT-BR): *Criar um cluster kind com 1 nó de control plane e 3 workers, escrever um arquivo de definição e subir um Pod com nginx.*

1. Create a kind cluster with **1 control-plane node and 3 worker nodes**.
2. Write a **Pod definition file** (YAML) instead of using only imperative commands.
3. Run an **nginx** Pod from that file.

## Solution

| File | Purpose |
|------|---------|
| [`kind-cluster-diretora-x.yaml`](kind-cluster-diretora-x.yaml) | kind cluster: 1 control plane + 3 workers |
| [`pod-diretora-x.yaml`](pod-diretora-x.yaml) | nginx Pod definition |

```bash
# 1. Create the cluster
kind create cluster --config challenge/kind-cluster-diretora-x.yaml

# 2. Confirm 4 nodes are Ready (1 control-plane, 3 workers)
kubectl get nodes

# 3. Apply the Pod definition and wait until it is Ready
kubectl apply -f challenge/pod-diretora-x.yaml
kubectl wait --for=condition=Ready pod/diretora-x --timeout=90s

# 4. Verify: which worker did the scheduler pick, and does nginx answer?
kubectl get pod diretora-x -o wide
kubectl port-forward pod/diretora-x 8081:80 &
curl -I http://localhost:8081
kill %1

# 5. Clean up
kind delete cluster --name diretora-x
```

## Acceptance checklist

- [ ] `kubectl get nodes` shows 4 nodes, all `Ready`
- [ ] `kubectl get pod diretora-x` shows `1/1 Running`
- [ ] The Pod was scheduled on a **worker**, not on the control plane (it carries a `NoSchedule` taint)
- [ ] `curl -I` returns `HTTP/1.1 200 OK` with a `Server: nginx` header
