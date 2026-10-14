# Day 3 — Command cheat sheet

Commands used in class (from the course PDF), cleaned up and grouped. The manifests in this module use namespace `giropops`; add `-n giropops` where needed.

## Create / generate

```bash
kubectl create deployment nginx-deployment --image=nginx --replicas=3 \
  --dry-run=client -o yaml > deployment.yaml       # generate a manifest
kubectl create namespace giropops --dry-run=client -o yaml > namespace.yaml
kubectl apply -f deployment.yaml
```

## Inspect

```bash
kubectl get deployments -l app=nginx-deployment
kubectl get replicasets -l app=nginx-deployment
kubectl get pods -l app=nginx-deployment -o wide
kubectl get pods -l app=nginx-deployment -o yaml
kubectl describe deployment nginx-deployment
kubectl exec -it <pod-name> -- nginx -v              # which version is running?
```

## Update

```bash
kubectl set image deployment/nginx-deployment <container>=nginx:1.19.2
kubectl annotate deployment/nginx-deployment kubernetes.io/change-cause="<why>" --overwrite
kubectl scale deployment nginx-deployment --replicas=5
kubectl edit deployment nginx-deployment
```

## Rollout

```bash
kubectl rollout status   deployment nginx-deployment
kubectl rollout history  deployment nginx-deployment
kubectl rollout history  deployment nginx-deployment --revision=1
kubectl rollout undo     deployment nginx-deployment
kubectl rollout undo     deployment nginx-deployment --to-revision=1
kubectl rollout pause    deployment nginx-deployment
kubectl rollout resume   deployment nginx-deployment
kubectl rollout restart  deployment nginx-deployment
```

## Clean up

```bash
kubectl delete deployment nginx-deployment
kubectl delete -f deployment.yaml
kubectl delete namespace giropops
```
