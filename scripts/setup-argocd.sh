#!/bin/bash
set -e

# Safely delete the ArgoCD namespace if it exists.
# The '--ignore-not-found' flag prevents the script from failing
# with an error if the namespace has already been deleted.
echo "🧹 Cleaning up any existing ArgoCD installation..."
kubectl delete namespace argocd --ignore-not-found=true

echo "🚀 Deploying ArgoCD on the Kubernetes cluster..."
echo "📦 Creating the argocd namespace..."
kubectl create namespace argocd

echo "📥 Installing ArgoCD manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

#echo "⏳ Waiting for ArgoCD services to be created..."
#sleep 30


#echo "🔧 Changing argocd-server service to NodePort for external access..."
#kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

#echo "⏳ Waiting for NodePort assignment..."
#sleep 5

echo "🔎 Checking ArgoCD new services status after patching NodePort..."
kubectl get svc -n argocd

#echo "🌐 Starting port-forward to ArgoCD..."
#if lsof -i :8080 >/dev/null 2>&1; then
  #echo "⚠️ Port 8080 is already in use, skipping port-forward."
#else
  #kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
  #sleep 2
#fi

echo "🔐 Configuring RBAC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-deployer
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-deployer-role
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-deployer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-deployer-role
subjects:
  - kind: ServiceAccount
    name: argocd-deployer
    namespace: argocd
EOF

echo "🔑 Retrieving the administrator password (waiting up to 30s)..."
for i in {1..6}; do
  ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

  if [ -n "$ADMIN_PWD" ]; then
    echo "✅ ArgoCD admin password: $ADMIN_PWD"
    break
  else
    echo "⏳ Secret not ready yet, retrying in 5s..."
    sleep 5
  fi
done

if [ -z "$ADMIN_PWD" ]; then
  echo "⚠️ Admin password not available yet. Run this manually later:"
  echo 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'
fi

echo "🔎 Checking ArgoCD pods (they may still be starting)..."
kubectl get pods -n argocd

echo "🔎 Checking ArgoCD services ..."
kubectl get svc -n argocd

echo "🔧 Patching ArgoCD Changing argocd-server service to NodePort for external access..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

echo "⏳ Waiting for NodePort assignment..."
sleep 5

echo "🔎 Checking ArgoCD new services status after patching NodePort..."
kubectl get svc -n argocd



echo "🎉 ArgoCD deployment triggered!"
echo "🌐 Access URL: https://178.254.23.139:8080"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PWD"
echo "💡 Note: It may take a few minutes for all ArgoCD components to   
be fully operational."
echo "🔗 To stop port-forwarding, run: kill \$(lsof -t -i :8080)"
echo "🔗 To access the ArgoCD CLI, run: brew install argocd"
echo "🔗 Then login with: argocd login 127.0.0.
1:8080 --username admin --password $ADMIN_PWD --insecure"
echo "🔗 To change the admin password, run: argocd account update-password" 
echo "🔗 For more info, visit: https://argo-cd.readthedocs.io/en/stable/getting_started/"
echo "🚀 Happy deploying with ArgoCD!"
# End of script