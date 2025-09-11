#!/bin/bash
set -euo pipefail

# ============================================================
# ArgoCD Installation Script with Helm and nginx-ingress
# Version 2.0 - With advanced execution logs
# ============================================================

# --- Configuration and variables ---
FORCE_CLEAN=false
SKIP_RBAC=false
EXTRA_HELM_ARGS=""
CLUSTER_IP="178.254.23.139"
ARGOCD_DOMAIN="argocd.${CLUSTER_IP}.nip.io"
CURRENT_CONTEXT=$(kubectl config current-context)
LOG_FILE="argocd-install-$(date '+%Y%m%d-%H%M%S').log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')


# --- Logging functions ---
log() {
    local message="[$(date '+%H:%M:%S')] - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Function to capture pod logs and events
log_pod_events() {
    local namespace=$1
    local log_prefix=$2
    log "--- Starting pod logging in namespace '$namespace' ---"
    
    # Capture events
    log "Recent events for '$namespace':"
    kubectl get events -n "$namespace" --sort-by='.lastTimestamp' --field-selector='type!=Normal' | tee -a "$LOG_FILE"
    
    # Capture pod logs
    local pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    if [ -z "$pods" ]; then
        log "No pods found in '$namespace'."
    else
        for pod in $pods; do
            log "Logs for pod '$pod':"
            kubectl logs "$pod" -n "$namespace" --tail=20 | tee -a "$LOG_FILE"
        done
    fi
    log "--- Finished pod logging in namespace '$namespace' ---"
}


# --- Start of script ---
echo "=" >> "$LOG_FILE"
echo "🚀 NEW ARGOCD SESSION - $(date)" >> "$LOG_FILE"
echo "=" >> "$LOG_FILE"
log "🔧 Starting ArgoCD installation"
log "📋 Context: $CURRENT_CONTEXT"
log "🌐 Domain: $ARGOCD_DOMAIN"
log "📁 Log file: $LOG_FILE"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force-clean)
      FORCE_CLEAN=true
      shift
      ;;
    --skip-rbac)
      SKIP_RBAC=true
      shift
      ;;
    --domain)
      ARGOCD_DOMAIN="$2"
      shift 2
      ;;
    --set*)
      EXTRA_HELM_ARGS="$EXTRA_HELM_ARGS $1"
      shift
      ;;
    -*|--*)
      log "❌ Unknown option $1"
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

# Preliminary checks
log "🔍 Verifying cluster access..."
if ! kubectl cluster-info &> /dev/null; then
  log "❌ Kubernetes cluster not detected."
  exit 1
fi
log "✅ Cluster accessible"

if ! command -v helm &> /dev/null; then
  log "❌ Helm is not installed."
  exit 1
fi
log "✅ Helm is installed: $(helm version --short)"

log "🧹 Cleaning up existing ArgoCD installation..."
# Deleting existing resources for a clean installation
kubectl delete ns argocd --wait --timeout=120s 2>/dev/null || true
log "✅ Cleanup of namespace 'argocd' finished."

# CRD cleanup
if $FORCE_CLEAN; then
    log "🧽 Deleting ArgoCD CRDs (force mode)..."
    kubectl get crds -o name | grep 'argoproj.io' | xargs -r kubectl delete --timeout=30s 2>/dev/null || true
fi
log "✅ CRD cleanup finished."

log "📦 Creating namespace 'argocd'..."
kubectl create namespace argocd || true
kubectl label namespace argocd environment=staging app.kubernetes.io/part-of=argocd --overwrite
log "✅ Namespace 'argocd' created and labeled."

log "📥 Adding and updating ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update >/dev/null
log "✅ Helm repositories updated."

# --- Preparing Helm values with Ingress correction ---
log "🔧 Preparing Helm configuration..."
HELM_VALUES="--kube-context=${CURRENT_CONTEXT} \
--set server.ingress.enabled=true \
--set server.ingress.ingressClassName=nginx \
--set server.ingress.hosts[0]=${ARGOCD_DOMAIN} \
--set server.ingress.annotations.nginx\.ingress\.kubernetes\.io/force-ssl-redirect=true \
--set server.ingress.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol=HTTP \
--set server.ingress.annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size=100m \
--set server.ingress.tls[0].hosts[0]=${ARGOCD_DOMAIN} \
--set server.ingress.tls[0].secretName=argocd-tls \
--set server.extraArgs[0]=--insecure"

# Add extra Helm arguments
if [ -n "$EXTRA_HELM_ARGS" ]; then
    HELM_VALUES="$HELM_VALUES $EXTRA_HELM_ARGS"
fi

log "🚀 Starting ArgoCD installation with Helm..."
log "📋 Helm command:"
log "helm upgrade --install argocd argo/argo-cd --namespace argocd $HELM_VALUES --wait --timeout 10m0s"

# Execute Helm installation
if ! helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  $HELM_VALUES \
  --wait \
  --timeout 10m0s 2>&1 | tee -a "$LOG_FILE"; then
    log "❌ Helm installation failed."
    log "🔍 Logging deployment errors..."
    log_pod_events "argocd" "argocd-install"
    log "Logging the cause of the NGINX Ingress deployment error..."
    log_pod_events "ingress-nginx" "nginx-ingress"
    exit 1
fi

log "✅ Helm installation completed successfully."

# --- Post-deployment logging ---
log "🔍 Logging deployed resources..."
log "--- Deployment status ---"
kubectl get all,ingress -n argocd --show-labels | tee -a "$LOG_FILE"
log "--- Ingress description ---"
kubectl describe ingress argocd-server -n argocd | tee -a "$LOG_FILE"
log "--- ArgoCD pod logs ---"
log_pod_events "argocd" "argocd-post-install"
log "--- Nginx Ingress controller logs ---"
log_pod_events "ingress-nginx" "nginx-post-install"


# --- RBAC Configuration and password retrieval ---
if ! $SKIP_RBAC; then
    log "🔐 Applying RBAC configuration..."
    kubectl apply -f - <<EOF | tee -a "$LOG_FILE"
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
    log "✅ RBAC configuration applied."
fi

ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode || echo "unknown")
if [ "$ADMIN_PWD" == "unknown" ] || [ -z "$ADMIN_PWD" ]; then
    log "⚠️ Unable to retrieve admin password."
else
    log "✅ Admin password retrieved."
fi

# --- Final instructions ---
cat << EOF

🎉 ArgoCD deployment successful on https://${ARGOCD_DOMAIN}

📋 Login information:
   👤 Username: admin
   🔑 Password: ${ADMIN_PWD}

---
💡 **How it works?**
* The script installs ArgoCD and configures an Ingress for your domain.
* The Nginx Ingress manages incoming traffic and redirects it to the ArgoCD service.
* The script captures pod logs and events in the **$LOG_FILE** file for debugging.

---
🚀 Happy GitOps!
EOF
log "🎉 ArgoCD installation completed successfully."