# Day 2 — kubectl cheat sheet

## Create

```bash
kubectl run giropops --image=nginx:1.30 --port=80                 # imperative
kubectl run giropops --image=nginx:1.30 --dry-run=client -o yaml  # generate YAML only
kubectl apply  -f pod.yaml        # create or update
kubectl create -f pod.yaml        # create only — fails if it already exists
```

## Inspect

```bash
kubectl get pods                       # current namespace (default)
kubectl get pods -A                    # all namespaces (= --all-namespaces)
kubectl get pods -n kube-system        # one namespace
kubectl get pods -o wide               # + Pod IP and node
kubectl get pod giropops -o yaml       # full object, incl. status
kubectl get pod giropops -o json
kubectl get pods --show-labels
kubectl get pods -l run=giropops       # filter by label
kubectl describe pod giropops          # events, containers, volumes, QoS
kubectl get pod giropops -o jsonpath='{.status.qosClass}{"\n"}'
kubectl top pod giropops               # requires metrics-server
```

## Logs and interaction

```bash
kubectl logs giropops                  # single-container Pod
kubectl logs giropops -c girus         # multi-container: pick the container
kubectl logs -f giropops               # follow
kubectl logs giropops --previous       # logs of the crashed instance

kubectl exec giropops -c strigus -- ls            # run one command
kubectl exec -it giropops -c girus -- sh          # interactive shell (exit: Ctrl+D)
kubectl attach giropops -c strigus                # attach to PID 1 (exit: Ctrl+C)
```

## Stress testing (resources)

```bash
# Inside a container with the polinux/stress image
stress --vm 1 --vm-bytes 250M --vm-hang 1   # allocate 250 MB and hold it
stress --cpu 2 --timeout 60                 # 2 busy CPU workers for 60 s
stress --help
```

## Namespaces and cleanup

```bash
kubectl create namespace treinamento-ch2
kubectl delete pod giropops
kubectl delete -f pod.yaml
kubectl delete pods --all -n treinamento-ch2
```
