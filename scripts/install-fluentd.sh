#!/bin/bash
set -euo pipefail

# ============================================================
# Fluentd installation script
# ============================================================

source ./functions.sh

# --- Configuration ---
NAMESPACE="efk"
LOG_FILE="${LOG_FILE:-/dev/null}"

wait_for_cluster_connectivity
ensure_namespace "$NAMESPACE"

# --- Deploy Fluentd ---
log "🚀 Installing Fluentd..."
helm install fluentd fluent/fluentd --namespace "$NAMESPACE" \
  --set fullnameOverride="fluentd" \
  --set rbac.create=true \
  --set tolerations[0].effect=NoSchedule \
  --set tolerations[0].key=node-role.kubernetes.io/master \
  --set tolerations[0].operator=Exists \
  --set fluentd.args="--no-dir-perms --disable-version-check --log-level info" \
  --set fluentd.image.tag="v1.14.6" \
  --set config.serviceAccount.name="fluentd" \
  --set config.clusterRole.name="fluentd" \
  --set config.clusterRoleBinding.name="fluentd" \
  --set extraFiles[0].name=fluentd.conf \
  --set extraFiles[0].data='''<match kubernetes.**>
  @type stdout
</match>''' \
  --wait --timeout 10m0s
log "✅ Fluentd installed successfully."
