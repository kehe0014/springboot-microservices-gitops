#!/bin/bash
set -euo pipefail

# ============================================================
# Elasticsearch installation script
# ============================================================

source ./functions.sh

# --- Configuration ---
NAMESPACE="efk"
LOG_FILE="${LOG_FILE:-/dev/null}"

wait_for_cluster_connectivity
ensure_namespace "$NAMESPACE"

# --- Deploy Elasticsearch ---
log "🚀 Installing Elasticsearch..."
helm install elasticsearch elastic/elasticsearch --namespace "$NAMESPACE" \
  --set replicas=1 \
  --set service.type=ClusterIP \
  --set imageTag="7.17.6" \
  --set esJavaOpts="-Xms512m -Xmx512m" \
  --wait --timeout 10m0s
log "✅ Elasticsearch installed successfully."
