#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting GitOps Bootstrap Process...${NC}"
echo "==========================================="

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Success: $1${NC}"
    else
        echo -e "${RED}❌ Failed: $1${NC}"
        exit 1
    fi
}

# 1. Create namespace
echo -e "${YELLOW}📦 Creating gitops-demo namespace...${NC}"
kubectl create namespace gitops-demo --dry-run=client -o yaml | kubectl apply -f -
check_success "Namespace creation"

# 2. Validate application files exist
echo -e "${YELLOW}🔍 Validating application files...${NC}"
if [ ! -d "applications/dev" ]; then
    echo -e "${RED}❌ Directory applications/dev/ not found!${NC}"
    exit 1
fi

APP_FILES=(applications/dev/*.yaml)
if [ ${#APP_FILES[@]} -eq 0 ]; then
    echo -e "${RED}❌ No YAML files found in applications/dev/${NC}"
    exit 1
fi

# 3. Apply applications
echo -e "${YELLOW}🔗 Applying ArgoCD Applications...${NC}"
for app_file in "${APP_FILES[@]}"; do
    echo -e "📄 Applying $(basename "$app_file")..."
    kubectl apply -f "$app_file"
    check_success "Application $(basename "$app_file")"
done

# 4. Wait and check status
echo -e "${YELLOW}⏳ Waiting for ArgoCD to process applications...${NC}"
sleep 8

echo -e "${YELLOW}📊 Current status:${NC}"
kubectl get applications -n argocd

echo -e "${YELLOW}🐳 Pod status:${NC}"
kubectl get pods -n gitops-demo

echo ""
echo -e "${GREEN}✅ GitOps bootstrap completed successfully!${NC}"
echo "==========================================="
echo -e "Next steps:"
echo -e "1. 🌐 Open ArgoCD UI: https://178.254.23.39:30915"
echo -e "2. 🔍 Monitor: kubectl get app -n argocd -w"
echo -e "3. 📖 Logs: argocd app logs <app-name>"
echo -e "4. 🔄 Sync: argocd app sync <app-name>"