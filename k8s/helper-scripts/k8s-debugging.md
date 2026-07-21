
**Delete all failed pods across namespaces:**

```bash
kubectl delete pods --field-selector=status.phase=Failed -A


for status in Failed Pending; do
  kubectl get pods --field-selector=status.phase=$status -A
done

```

**Remove a taint from a node:**

```bash
kubectl taint nodes worker-1 node.kubernetes.io/memory-pressure:NoSchedule-
```

**Check out of memory/ evicted pods**

```bash
kubectl get events -A --field-selector reason=OOMKilling
kubectl get events -A --field-selector reason=Evicted
```

**Label a worker node with the worker role:**

```bash
kubectl label node worker-1 node-role.kubernetes.io/worker=worker
```


```bash
kubeadm kubeconfig user \
  --org system:nodes \
  --client-name system:node:eclapls00111ld \
  > /etc/kubernetes/kubelet.conf
```


**yaml validation**
```bash
python3 -c "import yaml, sys; yaml.safe_load(sys.stdin)" < /etc/kubernetes/manifests/kube-apiserver.yaml
```

```bash
# strip yamls from non essential data
yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration", .status)' file.yaml
```