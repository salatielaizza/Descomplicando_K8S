# Challenge — The Hungry Pod (`pod-faminto`)

> There was no written statement for this challenge in the original `day-2` folder; it is reconstructed from the two manifests committed during the course.

## Statement

1. In the namespace `treinamento-ch2`, run a Pod that allocates **250 MB** of memory with the `polinux/stress` image while its memory **limit is only 200Mi** (`pod-desafio-day2.yaml`).
2. Observe what happens and explain **why**.
3. Fix it with a Pod that runs the same workload and stays `Running` (`pod-comportado.yaml`).

## Files

| File | Pod | memory request / limit | Workload | Expected result |
|---|---|---|---|---|
| `pod-desafio-day2.yaml` | `pod-faminto` | 100Mi / **200Mi** | 250 MB | `OOMKilled` → `CrashLoopBackOff` |
| `pod-comportado.yaml` | `pod-comportado` | 100Mi / **400Mi** | 250 MB | `Running` |

> ⚠️ Both files contain the key `args` twice in the same container (see the module's *Known issues*). If your `kubectl` rejects them with a *duplicate field* error, remove the empty `args:` line in a local copy before applying.

## Solution

```bash
kubectl create namespace treinamento-ch2

# 1. The hungry Pod
kubectl apply -f pod-desafio-day2.yaml
kubectl get pod pod-faminto -n treinamento-ch2 -w      # OOMKilled → CrashLoopBackOff (Ctrl+C)
kubectl describe pod pod-faminto -n treinamento-ch2 | grep -A5 'Last State'
#   Reason:    OOMKilled
#   Exit Code: 137

# 2. The well-behaved Pod
kubectl apply -f pod-comportado.yaml
kubectl get pod pod-comportado -n treinamento-ch2      # Running, RESTARTS 0
kubectl top pod pod-comportado -n treinamento-ch2      # ~250Mi used, below the 400Mi limit

# Cleanup
kubectl delete namespace treinamento-ch2
```

### Why

- `requests.memory: 100Mi` only affects **scheduling**, so the Pod is placed on a node without problems.
- At runtime, `stress --vm-bytes 250M` tries to hold ~238Mi, above the **200Mi limit** enforced by the container's cgroup. Memory cannot be throttled, so the kernel OOM killer kills the process: `OOMKilled`, exit code `137` (128 + SIGKILL 9).
- With `restartPolicy: Always`, the kubelet restarts it with an exponential back-off → `CrashLoopBackOff`.
- Raising the limit to `400Mi` leaves headroom above the real usage, so the container stays up. In real life you size the limit from observed usage (e.g. p99 + margin), not by guessing.

## Acceptance checklist

- [ ] `pod-faminto` shows `OOMKilled` / exit code `137` in `kubectl describe`.
- [ ] You can explain why the **request** did not prevent the kill but the **limit** caused it.
- [ ] `pod-comportado` is `Running` with `0` restarts after a few minutes.
- [ ] Both Pods report QoS class `Burstable` — and you can say what change would make them `Guaranteed`.
- [ ] Namespace deleted at the end.
