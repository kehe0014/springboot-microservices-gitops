#!/bin/bash
set -euo pipefail

# ============================================================
# Script d'Installation ArgoCD avec Helm et nginx-ingress
# Version 2.0 - Avec logs d'exécution avancés
# ============================================================

# --- Configuration et variables ---
FORCE_CLEAN=false
SKIP_RBAC=false
EXTRA_HELM_ARGS=""
CLUSTER_IP="178.254.23.139"
ARGOCD_DOMAIN="argocd.${CLUSTER_IP}.nip.io"
CURRENT_CONTEXT=$(kubectl config current-context)
LOG_FILE="argocd-install-$(date '+%Y%m%d-%H%M%S').log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')


# --- Fonctions de logging ---
log() {
    local message="[$(date '+%H:%M:%S')] - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Fonction pour capturer les logs de pods et les événements
log_pod_events() {
    local namespace=$1
    local log_prefix=$2
    log "--- Début de la journalisation des pods dans le namespace '$namespace' ---"
    
    # Capture des événements
    log "Événements récents pour '$namespace':"
    kubectl get events -n "$namespace" --sort-by='.lastTimestamp' --field-selector='type!=Normal' | tee -a "$LOG_FILE"
    
    # Capture des logs de pods
    local pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    if [ -z "$pods" ]; then
        log "Aucun pod trouvé dans '$namespace'."
    else
        for pod in $pods; do
            log "Logs du pod '$pod':"
            kubectl logs "$pod" -n "$namespace" --tail=20 | tee -a "$LOG_FILE"
        done
    fi
    log "--- Fin de la journalisation des pods dans le namespace '$namespace' ---"
}


# --- Début du script ---
echo "=" >> "$LOG_FILE"
echo "🚀 NOUVELLE SESSION ARGOCD - $(date)" >> "$LOG_FILE"
echo "=" >> "$LOG_FILE"
log "🔧 Démarrage de l'installation ArgoCD"
log "📋 Contexte: $CURRENT_CONTEXT"
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
      log "❌ Option inconnue $1"
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

# Vérifications préliminaires
log "🔍 Vérification de l'accès au cluster..."
if ! kubectl cluster-info &> /dev/null; then
  log "❌ Cluster Kubernetes non détecté."
  exit 1
fi
log "✅ Cluster accessible"

if ! command -v helm &> /dev/null; then
  log "❌ Helm n'est pas installé."
  exit 1
fi
log "✅ Helm est installé: $(helm version --short)"

log "🧹 Nettoyage de l'installation ArgoCD existante..."
# Suppression des ressources existantes pour une installation propre
kubectl delete ns argocd --wait --timeout=120s 2>/dev/null || true
log "✅ Nettoyage du namespace 'argocd' terminé."

# Nettoyage des CRDs
if $FORCE_CLEAN; then
    log "🧽 Suppression des CRDs ArgoCD (mode force)..."
    kubectl get crds -o name | grep 'argoproj.io' | xargs -r kubectl delete --timeout=30s 2>/dev/null || true
fi
log "✅ Nettoyage des CRDs terminé."

log "📦 Création du namespace 'argocd'..."
kubectl create namespace argocd || true
kubectl label namespace argocd environment=staging app.kubernetes.io/part-of=argocd --overwrite
log "✅ Namespace 'argocd' créé et labellisé."

log "📥 Ajout et mise à jour du dépôt Helm ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update >/dev/null
log "✅ Dépôts Helm mis à jour."

# --- Préparation des valeurs Helm avec la correction de l'Ingress ---
log "🔧 Préparation de la configuration Helm..."
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

# Ajout des arguments Helm supplémentaires
if [ -n "$EXTRA_HELM_ARGS" ]; then
    HELM_VALUES="$HELM_VALUES $EXTRA_HELM_ARGS"
fi

log "🚀 Démarrage de l'installation ArgoCD avec Helm..."
log "📋 Commande Helm:"
log "helm upgrade --install argocd argo/argo-cd --namespace argocd $HELM_VALUES --wait --timeout 10m0s"

# Exécution de l'installation Helm
if ! helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  $HELM_VALUES \
  --wait \
  --timeout 10m0s 2>&1 | tee -a "$LOG_FILE"; then
    log "❌ Échec de l'installation Helm."
    log "🔍 Journalisation des erreurs de déploiement..."
    log_pod_events "argocd" "argocd-install"
    log "Journalisation de la cause de l'erreur du déploiement NGINX Ingress..."
    log_pod_events "ingress-nginx" "nginx-ingress"
    exit 1
fi

log "✅ Installation Helm terminée avec succès."

# --- Journalisation post-déploiement ---
log "🔍 Journalisation des ressources déployées..."
log "--- Statut du déploiement ---"
kubectl get all,ingress -n argocd --show-labels | tee -a "$LOG_FILE"
log "--- Description de l'Ingress ---"
kubectl describe ingress argocd-server -n argocd | tee -a "$LOG_FILE"
log "--- Logs des pods ArgoCD ---"
log_pod_events "argocd" "argocd-post-install"
log "--- Logs du contrôleur Nginx Ingress ---"
log_pod_events "ingress-nginx" "nginx-post-install"


# --- Configuration RBAC et récupération du mot de passe ---
if ! $SKIP_RBAC; then
    log "🔐 Application de la configuration RBAC..."
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
    log "✅ Configuration RBAC appliquée."
fi

ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode || echo "unknown")
if [ "$ADMIN_PWD" == "unknown" ] || [ -z "$ADMIN_PWD" ]; then
    log "⚠️ Impossible de récupérer le mot de passe admin."
else
    log "✅ Mot de passe admin récupéré."
fi

# --- Instructions finales ---
cat << EOF

🎉 Déploiement d'ArgoCD réussi sur https://${ARGOCD_DOMAIN}

📋 Informations de connexion:
   👤 Username: admin
   🔑 Password: ${ADMIN_PWD}

---
💡 **Comment ça fonctionne ?**
* Le script installe ArgoCD et configure un Ingress pour votre domaine.
* L'Ingress Nginx gère le trafic entrant et le redirige vers le service ArgoCD.
* Le script capture les logs des pods et les événements dans le fichier **$LOG_FILE** pour le débogage.

---
🚀 Bon GitOps!
EOF