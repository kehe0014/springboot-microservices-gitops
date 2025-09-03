#!/bin/bash

# Create namespace
kubectl create namespace gitops-demo

# Apply ArgoCD Applications
kubectl apply -f applications/api-gateway.yaml
kubectl apply -f applications/user-service.yaml
kubectl apply -f applications/product-service.yaml

echo "GitOps bootstrap completed!"