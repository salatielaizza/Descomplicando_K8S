1639  kubectl create namespace producao --dry-run -o yaml
 1640  kubectl create namespace producao --dry-run -o yaml>namespace.yaml
 1641  ls
 1642  ll
 1643  rm deployment.yaml pod.yaml 
 1644  ll
 1645  vim deployment-problematico.yaml
 1646  ls
 1647  kubectl apply -f deployment-problematico.yaml
 1648  kgp
 1649  kgp -n namespace.yaml 
 1650  kgp -n producao
 1651  cat namespace.yaml 
 1652  kgp -n producao -w
 1653  nvim deployment-quebrado.yaml
 1654  kubectl apply -f deployment-quebrado.yaml
 1655  kubectl get pods -n producao
 1656  kubectl get pods -n producao -w
 1657  k describe pod -n producao meu-servico-85c878b46b-h7p89 
 1658  k describe pod -n producao meu-servico-85c878b46b-h7p89 | grep OOM
 1659* 
 1660  kubectl get pods -n producao -w
 1661  k describe pod -n producao meu-servico-85c878b46b-zjp7g 
 1662  k describe pod -n producao meu-servico*
 1663  k describe pod -n producao meu-servico
 1664  POD_PROBLEMA=$(kubectl get pods -n producao -l version=v2-problematica -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
 1665  kubectl describe pod $POD_PROBLEMA -n producao
 1666  kubectl describe pod $POD_PROBLEMA -n producao | grep -A 20 'Events:'
 1667  kubectl logs $POD_PROBLEMA -n producao --previous 2>/dev/null || echo 'Sem logs anteriores disponíveis'
 1668  history
 1669  history 
 1670  kaf deployment-problematico.yaml 
 1671  kgp -n pro
 1672  kgp -n producao
 1673  kubectl logs $POD_PROBLEMA -n producao --previous 2>/dev/null || echo 'Sem logs anteriores disponíveis'
 1674  kubectl apply -f deployment-quebrado.yaml
 1675  kgp -n producao
 1676  kubectl logs $POD_PROBLEMA -n producao --previous 2>/dev/null || echo 'Sem logs anteriores disponíveis'
 1677  kubectl get replicaset -n producao
 1678  kubectl describe replicaset -n producao -l version=v2-problematica
 1679  kgp -n producao
 1680  kubectl describe replicaset -n producao 
 1681  kubectl describe replicaset -n producao -w
 1682  kubectl describe replicaset -n producao w
 1683  kubectl describe replicaset -n producao watch
 1684  kubectl describe replicaset -n producao -watch
 1685  watch kubectl describe replicaset -n producao 
 1686  kubectl describe deployment meu-servico -n producao | grep OOMKil
 1687  kubectl get deployment meu-servico -n producao -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' && echo ' <- Readiness' || echo 'Sem Readiness Probe'
 1688  kubectl get deployment meu-servico -n producao 
 1689  nvim deployment-corrigido.yaml
 1690  kaf deployment-corrigido.yaml 
 1691  kgp -n producao
 1692  k delete deployments.apps -n producao meu-servico 
 1693  kaf deployment-quebrado.yaml 
 1694  kgp
 1695  kgp -n producao
 1696  k describe -n producao deployments.apps  meu-servico 
 1697  k get pod -n producao meu-servico-85c878b46b-k8s7w 
 1698  k describe pod -n producao meu-servico-85c878b46b-k8s7w 
 1699  k logs -f pods/meu-servico-85c878b46b-k8s7w
 1700  k logs -f pods/meu-servico-85c878b46b-k8s7w -n producao 
 1701  ls
 1702  kaf deployment-corrigido.yaml 
 1703  kgp -n producao
 1704  k logs -f pods/meu-servico-d85747485-vk6jk -n producao 
 1705  k logs -f pods/meu-servico-d85747485-ccmxq -n producao 
 1706  kgp -n producao
 1707  k logs -f pods/meu-servico-d85747485-vk6jk -n producao 

