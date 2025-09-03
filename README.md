# GitOps Repository

This repository contains the GitOps configuration for deploying microservices to Kubernetes clusters.

## Structure

- `applications/`: ArgoCD Application definitions
- `charts/`: Helm charts for each microservice
- `environments/`: Environment-specific values
- `scripts/`: Utility scripts for setup

## Getting Started

1. Install ArgoCD:
```bash
./scripts/setup-argocd.sh