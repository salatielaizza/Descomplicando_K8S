# Day 6 — Command cheat sheet

## StorageClass

```bash
kubectl get storageclass                  # or: kubectl get sc
kubectl describe sc giropops
kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
kubectl patch sc <name> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## PersistentVolume

```bash
kubectl get pv
kubectl get pv --show-labels
kubectl describe pv meu-pv
kubectl label pv meu-pv storage=nfs --overwrite
kubectl patch pv meu-pv --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'   # Released → Available
kubectl patch pv meu-pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

## PersistentVolumeClaim

```bash
kubectl get pvc
kubectl describe pvc meu-pvc
kubectl get pvc meu-pvc -o jsonpath='{.spec.volumeName}{"\n"}'      # which PV it bound to
kubectl get pods -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="meu-pvc") | .metadata.name'   # who uses it
```

## Inside the Pod / node

```bash
kubectl exec <pod> -- df -h /usr/share/nginx/html
kubectl exec <pod> -- mount | grep -E 'nfs|/mnt'
docker exec <kind-node> ls -l /mnt/data      # kind: look at the hostPath on the node
showmount -e 192.168.1.133                   # NFS: list exports from a node
```

## Explain

```bash
kubectl explain pv.spec
kubectl explain pvc.spec.selector
kubectl explain storageclass.volumeBindingMode
```
