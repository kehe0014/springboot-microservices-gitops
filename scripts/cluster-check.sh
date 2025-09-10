#!/bin/bash
echo "🔍 Testing cluster connection..."
kubectl cluster-info && echo "✅ Cluster accessible" || echo "❌ Cluster inaccessible"
kubectl get nodes && echo "✅ Nodes accessible" || echo "❌ Nodes inaccessible"
kubectl config current-context && echo "✅ Context set" || echo "❌ Context issue"
