# Day 8 — Command cheat sheet

## Secrets

```bash
# Generic (Opaque)
kubectl create secret generic giropops-secret --from-literal=username=<user> --from-literal=password=<pass>
kubectl create secret generic app-config --from-file=./config.properties
kubectl create secret generic app-env --from-env-file=.env

# TLS
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout chave-privada.key -out certificado.crt -subj "/CN=giropops.local"
kubectl create secret tls meu-servico-web-tls-secret --cert=certificado.crt --key=chave-privada.key

# Registry credentials
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ --docker-username=<user> --docker-password=<token>

# Read / decode
kubectl get secrets
kubectl describe secret giropops-secret                     # sizes only, no values
kubectl get secret giropops-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret giropops-secret -o go-template='{{range $k,$v := .data}}{{$k}}={{$v|base64decode}}{{"\n"}}{{end}}'

# Encode / decode by hand (note -n: no trailing newline)
echo -n 'value' | base64
echo 'dmFsdWU=' | base64 -d

# Update in place
kubectl create secret generic giropops-secret --from-literal=password=<new> --dry-run=client -o yaml | kubectl apply -f -
```

## ConfigMaps

```bash
kubectl create configmap nginx-config --from-file=nginx.conf
kubectl create configmap app --from-literal=LOG_LEVEL=debug --from-literal=COLOR=blue
kubectl get configmaps                                      # or: kubectl get cm
kubectl describe cm nginx-config
kubectl get cm nginx-config -o yaml
kubectl edit cm nginx-config
```

## Use in Pods

```bash
kubectl exec giropops-pod -- env | grep -E 'USERNAME|PASSWORD'
kubectl exec giropops-pod -- cat /etc/nginx/nginx.conf
kubectl exec giropops-pod -- ls -l /etc/nginx/tls
kubectl exec giropops-pod -- nginx -t                       # validate config
kubectl port-forward pod/giropops-pod 8443:443
curl -k https://localhost:8443
kubectl rollout restart deployment/<name>                   # pick up env/subPath changes
```

## Docker Hub (outside Kubernetes)

```bash
docker login
docker tag <image> <user>/teste-privado:1.0
docker push <user>/teste-privado:1.0
```
