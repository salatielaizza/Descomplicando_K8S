# Day 7 — Command cheat sheet

## Services

```bash
kubectl get svc                                   # or: kubectl get services
kubectl get svc -o wide                           # shows the selector
kubectl describe svc nginx
kubectl get endpointslices -l kubernetes.io/service-name=nginx
kubectl get endpoints nginx                       # legacy API, still handy

# Imperative
kubectl expose deployment nginx --port=80 --target-port=80                      # ClusterIP
kubectl expose deployment nginx --name=nginx-np --type=NodePort --port=80
kubectl expose deployment nginx --name=nginx-lb --type=LoadBalancer --port=80
kubectl create service clusterip nginx --tcp=80:80 --dry-run=client -o yaml
kubectl create service nodeport nginx --tcp=80:80 --node-port=32000 --dry-run=client -o yaml
kubectl create service externalname db --external-name=db.example.com

kubectl port-forward svc/nginx 8080:80            # quick local access without NodePort/LB
```

## DNS / connectivity tests

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
#   wget -qO- http://nginx
#   nslookup nginx.default.svc.cluster.local
#   nslookup nginx-0.nginx
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

## StatefulSet

```bash
kubectl get statefulsets                          # or: kubectl get sts
kubectl describe sts nginx
kubectl get pods -l app=nginx -w
kubectl scale sts nginx --replicas=5
kubectl rollout status sts nginx
kubectl rollout history sts nginx
kubectl get pvc
kubectl delete sts nginx                          # PVCs are kept
kubectl delete sts nginx --cascade=orphan         # keep the Pods too
```
