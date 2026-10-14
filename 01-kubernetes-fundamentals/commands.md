# Day 1 — Command Cheat Sheet

Commands used in this module, cleaned up and grouped by purpose.
`k` is used as an alias for `kubectl` (see [Shell setup](#shell-setup)).

## Cluster lifecycle (kind)

```bash
kind create cluster --config kind/kind-multinode.yaml   # create from a config file
kind get clusters                                       # list kind clusters
kubectl cluster-info --context kind-dk8s                # API server / CoreDNS endpoints
kind delete cluster --name dk8s                         # tear down
```

## Inspecting the cluster

```bash
kubectl get nodes -o wide                    # nodes, roles, internal IPs, runtime
kubectl get namespaces                       # default, kube-system, kube-public, ...
kubectl get pods -A                          # Pods in all namespaces
kubectl get pods -n kube-system -o wide      # control-plane components + which node runs them
kubectl get deployments,replicasets -n kube-system
kubectl get services -n kube-system          # e.g. kube-dns
kubectl api-resources                        # every resource type and its short name
kubectl explain pod.spec.containers          # built-in schema docs for any field
```

## Creating Pods

```bash
# Imperative (quick tests)
kubectl run giropops --image nginx:1.30 --port 80

# Generate YAML without creating anything, then apply it (declarative)
kubectl run giropops --image nginx:1.30 --port 80 --dry-run=client -o yaml > pod.yaml
kubectl apply -f pod.yaml
```

> **Common mistakes from the original notes:** the Pod name is a positional argument
> (`kubectl run <name> --image ...`), not `--name`/`-name`; and `-n` selects the
> **namespace**, not the Pod name.

## Working with a Pod

```bash
kubectl get pod giropops -o wide             # status, IP, node
kubectl describe pod giropops                # events: scheduling, image pull, probes
kubectl logs giropops                        # container stdout/stderr
kubectl exec -ti giropops -- bash            # shell inside the container
kubectl port-forward pod/giropops 8081:80    # reach the Pod from localhost
kubectl delete pod giropops
```

## Shell setup

```bash
# Bash completion
sudo apt install -y bash-completion
kubectl completion bash > ~/.kube/completion.bash.inc
echo "source ~/.kube/completion.bash.inc" >> ~/.bashrc

# `k` alias with completion
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

source ~/.bashrc
```
