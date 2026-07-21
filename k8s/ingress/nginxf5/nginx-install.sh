## nginx install

# clone repo
git clone https://github.com/nginx/kubernetes-ingress.git --branch v5.4.3
cd kubernetes-ingress

# Namespace and Service Account
kubectl apply -f deployments/common/ns-and-sa.yaml
# RBAC
kubectl apply -f deployments/rbac/rbac.yaml
# configmap
kubectl apply -f deployments/common/nginx-config.yaml
## ingressclass.kubernetes.io/is-default-class annotation.
kubectl apply -f deployments/common/ingress-class.yaml
# CRDs
kubectl apply -f https://raw.githubusercontent.com/nginx/kubernetes-ingress/v5.4.3/deploy/crds.yaml
# daemonset
kubectl apply -f deployments/daemon-set/nginx-ingress.yaml
# service - port 80 and 443 change to nlb ports
kubectl create -f deployments/service/nodeport.yaml

# uninstall
kubectl delete namespace nginx-ingress
kubectl delete clusterrole nginx-ingress
kubectl delete clusterrolebinding nginx-ingress
kubectl delete -f https://raw.githubusercontent.com/nginx/kubernetes-ingress/v5.4.3/deploy/crds.yaml