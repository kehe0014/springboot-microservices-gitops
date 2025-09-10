#!/bin/bash
# ============================================================
# Common functions for EFK stack installation scripts
# ============================================================

# Logging function with timestamp
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Wait until the cluster is reachable
wait_for_cluster_connectivity() {
    log "🔍 Checking Kubernetes cluster connectivity..."
    local attempts=0 max_attempts=10 delay=15
    until kubectl cluster-info &> /dev/null; do
        if (( attempts >= max_attempts )); then
            log "❌ Failed to connect to the cluster after $max_attempts attempts."
            exit 1
        fi
        log "⚠️ Cluster not reachable. Retrying in $delay sec... ($((attempts+1))/$max_attempts)"
        sleep "$delay"
        ((attempts++))
    done
    log "✅ Cluster is accessible."
}

# Check if a Helm release is already installed
is_installed() {
    local component_name="$1"
    helm status "$component_name" --namespace "$NAMESPACE" &> /dev/null
}

# Ensure a Kubernetes namespace exists
ensure_namespace() {
    local ns="$1"
    if ! kubectl get namespace "$ns" &> /dev/null; then
        log "ℹ️ Creating namespace '$ns'..."
        kubectl create namespace "$ns"
    else
        log "ℹ️ Namespace '$ns' already exists."
    fi
}
