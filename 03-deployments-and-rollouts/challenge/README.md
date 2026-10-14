# Challenge — Rollback drill

> No new manifests: the drill uses `../manifests/` as they are, plus imperative commands.

## Statement

1. Deploy `rollback-banana` (namespace `giropops`) and record the running nginx version.
2. Ship a **broken release**: change the image to a tag that does not exist (`nginx:1.17.999`).
3. Observe what the `Recreate` strategy does to availability while the new Pods cannot start.
4. Find the cause using only `kubectl`.
5. Roll back to the last good revision and prove the service is healthy again.
6. Explain how the outcome would differ with `RollingUpdate`.

## Solution

```bash
cd 03-deployments-and-rollouts
kubectl apply -f manifests/namespace.yaml -f manifests/deployment.yaml
kubectl -n giropops rollout status deploy/rollback-banana
kubectl -n giropops exec deploy/rollback-banana -- nginx -v           # nginx/1.17.0

# Broken release
kubectl -n giropops set image deploy/rollback-banana mginx=nginx:1.17.999
kubectl -n giropops annotate deploy/rollback-banana kubernetes.io/change-cause="bad tag 1.17.999" --overwrite
kubectl -n giropops get pods -l app=rollback          # ALL old Pods gone, new ones ErrImagePull / ImagePullBackOff
kubectl -n giropops get deploy rollback-banana        # READY 0/14  → full outage

# Diagnose
kubectl -n giropops describe pod -l app=rollback | grep -A3 -m1 'Failed'
kubectl -n giropops get events --sort-by=.lastTimestamp | tail

# Recover
kubectl -n giropops rollout history deploy/rollback-banana
kubectl -n giropops rollout undo deploy/rollback-banana
kubectl -n giropops rollout status deploy/rollback-banana
kubectl -n giropops exec deploy/rollback-banana -- nginx -v           # nginx/1.17.0 again
```

**Why it was an outage:** `Recreate` scales the old ReplicaSet to 0 *before* creating the new Pods, so when the new image cannot be pulled, nothing is serving.

**With `RollingUpdate`** (default 25%/25%), Kubernetes would create a few new Pods (`maxSurge`) and remove at most `maxUnavailable` old ones; because the new Pods never become Ready, the rollout stalls and ~75% of the old Pods keep serving traffic. The rollout eventually reports `ProgressDeadlineExceeded` — degraded, but not down.

## Acceptance checklist

- [ ] You saw `READY 0/14` during the broken release and can explain why.
- [ ] You identified `ImagePullBackOff` and the bad tag from events, not by guessing.
- [ ] `rollout history` shows the revisions with a change-cause.
- [ ] After `rollout undo`, 14/14 Pods are Ready on `nginx:1.17.0`.
- [ ] You can explain the RollingUpdate alternative in two sentences.
