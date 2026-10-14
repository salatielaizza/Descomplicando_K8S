# Day 10 — Command cheat sheet

## Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager get pods
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=180s
```

## Issuers

```bash
kubectl get issuer -A
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Annotate an Ingress

```bash
kubectl annotate ingress giropops-senhas cert-manager.io/cluster-issuer=letsencrypt-prod --overwrite   # ClusterIssuer
kubectl annotate ingress giropops-senhas cert-manager.io/issuer=letsencrypt-staging --overwrite        # Issuer (same namespace)
kubectl annotate ingress giropops-senhas cert-manager.io/issuer-                                       # remove
```

## Follow the issuance chain

```bash
kubectl get certificate,certificaterequest,order,challenge
kubectl describe certificate <name>
kubectl describe order <name>
kubectl describe challenge <name>
kubectl -n cert-manager logs deploy/cert-manager -f
kubectl get secret <secretName> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates
```

## cmctl (optional CLI)

```bash
cmctl check api                                    # is cert-manager ready?
cmctl status certificate <name>                    # whole chain in one view
cmctl renew <name>                                 # force renewal
```

## Test HTTPS

```bash
curl -v  --resolve giropops.salatielaizza.com:443:127.0.0.1 https://giropops.salatielaizza.com/
curl -k  https://localhost/ -H 'Host: giropops.salatielaizza.com'
openssl s_client -connect 127.0.0.1:443 -servername giropops.salatielaizza.com </dev/null | openssl x509 -noout -subject -issuer -dates
dig +short giropops.salatielaizza.com              # must resolve to the ingress public IP for HTTP-01
```
