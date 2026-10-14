# Challenge — "Why is my Pod never Ready?"

`nginx-deployment.yaml` (kept exactly as written in class) defines all three probes. Deploy it and figure out why it never becomes healthy — **without reading the manifest first**. Use only what the cluster tells you.

## Statement

1. Apply `nginx-deployment.yaml` and watch the Pod for two minutes.
2. Describe the behaviour: `READY`, `STATUS`, `RESTARTS` over time.
3. Find which probe is failing and why, using `kubectl describe` / events.
4. Explain why the liveness and readiness probes never report anything.
5. Prove the fix **without editing the file** (patch the live object), then state the one-line change the manifest needs.

## Solution

```bash
cd 04-replicasets-daemonsets-and-probes/challenge
kubectl apply -f nginx-deployment.yaml
kubectl get pods -l app=nginx-deployment -w
# READY 0/1 → Running, RESTARTS 1, 2, 3… → CrashLoopBackOff
```

```bash
POD=$(kubectl get pods -l app=nginx-deployment -o name | head -1)
kubectl describe $POD | sed -n '/Events/,$p'
#  Warning  Unhealthy  ...  Startup probe failed: dial tcp 10.244.x.y:81: connect: connection refused
#  Normal   Killing    ...  Container nginx failed startup probe, will be restarted
```

**Diagnosis:** the `startupProbe` uses `tcpSocket` on **port 81**, but nginx listens on **80**. With `initialDelaySeconds: 10`, default `periodSeconds: 10` and `failureThreshold: 3`, the kubelet kills the container after roughly 40 s, again and again. Liveness and readiness are **disabled until the startup probe succeeds**, so they never run — the Pod can't become Ready even though nginx itself is perfectly fine.

Verify nginx is healthy despite the probe:

```bash
kubectl exec $POD -- curl -sI http://localhost:80 | head -1     # HTTP/1.1 200 OK
```

Fix the live object (the file stays untouched):

```bash
kubectl patch deployment nginx-deployment --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/startupProbe/tcpSocket/port","value":80}]'
kubectl rollout status deploy/nginx-deployment
kubectl get pods -l app=nginx-deployment          # 1/1 Running, 0 restarts
```

**Manifest fix:** `startupProbe.tcpSocket.port: 80` — the corrected version of this same Deployment is used in module 06 ([`06-persistent-volumes-and-storage/manifests/nginx-deployment.yaml`](../../06-persistent-volumes-and-storage/manifests/nginx-deployment.yaml)).

Cleanup:

```bash
kubectl delete -f nginx-deployment.yaml
```

> `kubectl apply -f nginx-deployment.yaml` after the patch would bring port 81 back — the cluster always converges to what the file declares. In a real team the fix is a commit, not a patch.

## Acceptance checklist

- [ ] You found `Startup probe failed … :81` in the events before opening the YAML.
- [ ] You can explain why the Pod is `CrashLoopBackOff` although nginx works.
- [ ] You can explain why liveness/readiness events never appear.
- [ ] After the patch, the Pod is `1/1 Running` with no new restarts.
- [ ] You know why a later `kubectl apply` would undo your patch.
