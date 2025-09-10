#!/bin/bash
# debug-cluster.sh

echo "🔍 Vérification du cluster Kubernetes..."
echo "Contexte: $(kubectl config current-context)"

echo "📡 Test de connexion..."
timeout 30s kubectl cluster-info && echo "✅ Cluster accessible" || echo "❌ Timeout de connexion"

echo "🌐 Test de DNS..."
nslookup 178.254.23.139
ping -c 3 178.254.23.139

echo "🔒 Vérification des certificats..."
kubectl config view --minify --raw | grep certificate

echo "📊 État des nodes..."
kubectl get nodes --request-timeout=30s