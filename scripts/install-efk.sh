#!/bin/bash
set -euo pipefail

# ============================================================
# Orchestrator script for deploying the EFK stack
# ============================================================

source ./functions.sh

# --- Configuration ---
NAMESPACE="efk"
KIBANA_DOMAIN="kibana.178.254.23.139.nip.io"
LOG_FILE="efk-install-$(date '+%Y%m%d-%H%M%S').log"

# --- Header ---
echo "=" | tee -a "$LOG_FILE"
echo "🚀 NEW EFK INSTALL SESSION - $(date)" | tee -a "$LOG_FILE"
echo "=" | tee -a "$LOG_FILE"
log "🔧 Starting orchestrated EFK stack deployment..."

# --- Cluster connectivity ---
wait_for_cluster_connectivity

# --- Namespace cleanup ---
log "🧹 Cleaning up old EFK namespace..."
kubectl delete ns "$NAMESPACE" --ignore-not-found --wait --timeout=120s
log "✅ Namespace '$NAMESPACE' removed."

log "📦 Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE"
log "✅ Namespace '$NAMESPACE' created."

# --- Helm repos ---
log "📥 Adding and updating Helm repositories..."
helm repo add elastic https://helm.elastic.co >/dev/null
helm repo add fluent https://fluent.github.io/helm-charts >/dev/null
helm repo update >/dev/null
log "✅ Helm repositories added and updated."

# --- Component deployments ---
log "--- Deploying EFK components ---"

# Elasticsearch
if is_installed "elasticsearch"; then
    log "ℹ️ Elasticsearch already installed. Skipping..."
else
    log "🚀 Installing Elasticsearch..."
    ./install-elasticsearch.sh
fi

# Fluentd
if is_installed "fluentd"; then
    log "ℹ️ Fluentd already installed. Skipping..."
else
    log "🚀 Installing Fluentd..."
    ./install-fluentd.sh
fi

# Kibana
if is_installed "kibana"; then
    log "ℹ️ Kibana already installed. Skipping..."
else
    log "🚀 Installing Kibana..."
    ./install-kibana.sh
fi

log "✅ EFK stack deployment completed."

cat << EOF
🎉 EFK stack successfully deployed!
🌐 Access Kibana at: https://${KIBANA_DOMAIN}
EOF
