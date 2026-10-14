# Day 4 — Command cheat sheet

## ReplicaSet

```bash
kubectl apply -f nginx-replicaset.yaml
kubectl get replicasets            # or: kubectl get rs
kubectl describe rs nginx-replicaset
kubectl scale rs nginx-replicaset --replicas=5
kubectl get pods -l app=nginx-app -o wide
kubectl delete rs nginx-replicaset
```

## DaemonSet

```bash
kubectl apply -f nginx-daemonset.yaml
kubectl get daemonsets             # or: kubectl get ds
kubectl describe ds node-exporter
kubectl get pods -l app=node-exporter -o wide
kubectl rollout status ds/node-exporter
kubectl delete ds node-exporter

# Generate a DaemonSet skeleton (kubectl has no "create daemonset"):
kubectl create deployment node-exporter --image=prom/node-exporter --dry-run=client -o yaml \
  | sed -e 's/kind: Deployment/kind: DaemonSet/' -e '/replicas:/d' -e '/strategy:/d' > ds.yaml
```

## Strategies

```bash
kubectl get deploy limits-deploy -o jsonpath='{.spec.strategy}{"\n"}'
kubectl set image deploy/limits-deploy nginx=nginx:1.18
kubectl rollout status deploy/limits-deploy
kubectl rollout undo   deploy/limits-deploy
```

## Probes

```bash
kubectl describe pod <pod> | grep -E 'Liveness|Readiness|Startup'
kubectl get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
kubectl logs <pod> --previous                      # logs of the killed container
kubectl explain pod.spec.containers.livenessProbe  # field reference
```

## Taints (DaemonSet eligibility)

```bash
kubectl describe node <node> | grep Taints
kubectl taint node <node> key=value:NoSchedule     # add
kubectl taint node <node> key=value:NoSchedule-    # remove
```
