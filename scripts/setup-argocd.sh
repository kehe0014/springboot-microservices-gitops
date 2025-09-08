#!/bin/bash
set -euo pipefail

# ============================================================
# Expert-grade ArgoCD Installation Script using Helm
# Target cluster: development (127.0.0.1)
# Usage:
#   ./setup-argocd.sh            # normal cleanup + install
#   ./setup-argocd.sh --force-clean  # aggressive cleanup + install
# ============================================================

FORCE_CLEAN=false
if [[ "${1:-}" == "--force-clean" ]]; then
  FORCE_CLEAN=true
fi

# --- Pre-check: ensure cluster is reachable ---
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "❌ No Kubernetes cluster detected. Please start your cluster and set the correct context."
  exit 1
fi

echo "🧹 Cleaning up any existing ArgoCD installation..."

# Delete namespace if it exists
if kubectl get ns argocd >/dev/null 2>&1; then
  kubectl delete ns argocd --wait
fi

# --- Cleanup orphaned CRDs ---
echo "🧽 Cleaning up ArgoCD CRDs..."
if $FORCE_CLEAN; then
  # Aggressive mode: delete any CRD containing "argoproj.io"
  ARGOCD_CRDS=$(kubectl get crds --no-headers 2>/dev/null | awk '/argoproj.io/ {print $1}' || true)
else
  # Normal mode: only CRDs known to ArgoCD
  ARGOCD_CRDS=$(kubectl get crds --no-headers 2>/dev/null | awk '/argoproj.io/ && (/applications/ || /applicationsets/ || /appprojects/)/ {print $1}' || true)
fi

if [ -n "$ARGOCD_CRDS" ]; then
  kubectl delete crd $ARGOCD_CRDS
  echo "✅ Removed ArgoCD CRDs:"
  echo "$ARGOCD_CRDS"
else
  echo "ℹ️ No ArgoCD CRDs found."
fi

# --- Cleanup orphaned cluster-scoped resources ---
echo "🧽 Cleaning up ArgoCD cluster-scoped resources..."
if $FORCE_CLEAN; then
  # Aggressive mode: delete anything with "argocd" in the name
  ARGOCD_CLUSTER_RESOURCES=$(kubectl get clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration \
    -o name 2>/dev/null | grep argocd || true)
else
  # Normal mode: still delete but more targeted
  ARGOCD_CLUSTER_RESOURCES=$(kubectl get clusterrole,clusterrolebinding,mutatingwebhookconfiguration,validatingwebhookconfiguration \
    -o name 2>/dev/null | grep argocd || true)
fi

if [ -n "$ARGOCD_CLUSTER_RESOURCES" ]; then
  kubectl delete $ARGOCD_CLUSTER_RESOURCES
  echo "✅ Removed cluster-scoped ArgoCD resources:"
  echo "$ARGOCD_CLUSTER_RESOURCES"
else
  echo "ℹ️ No cluster-scoped ArgoCD resources found."
fi

echo "📦 Creating namespace 'argocd'..."
kubectl create namespace argocd

echo "📥 Adding and updating ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

echo "🚀 Installing ArgoCD with Helm..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --set server.service.nodePortHttps=30443 \
  --wait \
  --timeout 10m0s

# --- Wait for ArgoCD pods ---
#echo "⏳ Waiting for ArgoCD pods to be ready..."
#kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# --- Configure RBAC ---
echo "🔐 Configuring RBAC for CI/CD service account..."
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

# --- Retrieve admin password ---
echo "🔑 Retrieving the administrator password..."
for i in {1..6}; do
  ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
  if [ -n "${ADMIN_PWD}" ]; then
    echo "✅ ArgoCD admin password retrieved."
    break
  fi
  echo "⏳ Secret not ready yet, retrying in 5s..."
  sleep 5
done

if [ -z "${ADMIN_PWD:-}" ]; then
  echo "⚠️ Admin password not available yet. Retrieve it manually later:"
  echo 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'
fi

# --- Display ArgoCD status ---
echo "🔎 Checking ArgoCD pods..."
kubectl get pods -n argocd

echo "🔎 Checking ArgoCD services..."
kubectl get svc -n argocd

# --- Final instructions ---
echo "🎉 ArgoCD has been successfully deployed on cluster 'development'"
echo "🌐 Access ArgoCD UI at:"
echo "   👉 http://127.0.0.1:30080 (HTTP)"
echo "   👉 https://127.0.0.1:30443 (HTTPS)"
echo "👤 Username: admin"
echo "🔑 Password: ${ADMIN_PWD:-<pending>}"
echo ""
echo "💡 CLI access:"
echo "   argocd login 127.0.0.1:30443 --username admin --password ${ADMIN_PWD:-<pending>} --insecure"
echo ""
echo "🔧 To change the admin password:"
echo "   argocd account update-password"
echo ""
echo "📚 Documentation: https://argo-cd.readthedocs.io/en/stable/getting_started/"
echo "🚀 Happy GitOps with ArgoCD!"
echo ""
echo "⚠️ Note: For production use, ensure to secure ArgoCD properly and avoid using default credentials."