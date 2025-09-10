#!/bin/bash
set -euo pipefail

# ============================================================
# Kibana installation script
# ============================================================

source ./functions.sh

# --- Configuration ---
NAMESPACE="efk"
RELEASE_NAME="kibana"
CHART_REPO="elastic/kibana"
CHART_VERSION="7.17.6"
KIBANA_DOMAIN="kibana.178.254.23.139.nip.io"
LOG_FILE="${LOG_FILE:-/dev/null}"

wait_for_cluster_connectivity
ensure_namespace "$NAMESPACE"

# --- Deploy Kibana ---
log "🚀 Installing Kibana..."
helm install "$RELEASE_NAME" "$CHART_REPO" --namespace "$NAMESPACE" \
  --set imageTag="$CHART_VERSION" \
  --set service.type=ClusterIP \
  --set elasticsearch.hosts[0]="http://elasticsearch-master:9200" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="$KIBANA_DOMAIN" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --set ingress.tls[0].hosts[0]="$KIBANA_DOMAIN" \
  --set ingress.tls[0].secretName=kibana-tls \
  --wait --timeout 10m0s
log "✅ Kibana installed successfully."
