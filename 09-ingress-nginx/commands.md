# Day 9 — Command cheat sheet

## kind

```bash
kind create cluster --name ingress --config <config.yaml>
kind get clusters
kind get nodes --name ingress
kind delete cluster --name ingress
docker ps --format '{{.Names}}\t{{.Ports}}'        # check the 80/443 port mappings
```

## ingress-nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx get pods -o wide
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller -f
kubectl get ingressclass
kubectl annotate ingressclass nginx ingressclass.kubernetes.io/is-default-class="true"
```

## Ingress objects

```bash
kubectl get ingress                                # or: kubectl get ing
kubectl describe ingress giropops-senhas
kubectl get ingress giropops-senhas -o yaml

# Imperative
kubectl create ingress giropops-senhas --class=nginx \
  --rule="giropops.example.com/*=giropops-senhas:5000" --dry-run=client -o yaml
kubectl create ingress multi --class=nginx \
  --rule="/app*=giropops-senhas:5000" --rule="/web*=nginx:80" \
  --annotation nginx.ingress.kubernetes.io/rewrite-target=/ --dry-run=client -o yaml
```

## Testing

```bash
curl -i http://localhost/
curl -H 'Host: giropops.nginx.io' http://localhost/
curl --resolve giropops.salatielaizza.com:80:127.0.0.1 http://giropops.salatielaizza.com/
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/static/...
echo "127.0.0.1 giropops.nginx.io" | sudo tee -a /etc/hosts
```

## Application

```bash
kubectl apply -f manifests/giropops-senhas/
kubectl port-forward svc/giropops-senhas 5000:5000
kubectl logs deploy/giropops-senhas
kubectl exec deploy/redis-deployment -- redis-cli KEYS '*'
```
