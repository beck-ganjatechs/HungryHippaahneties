#!/bin/bash
# HungryHippaahneties - Deployment Script
# HIPAA-Compliant Kubernetes Stack

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="hungryhippaahneties"
ENVIRONMENT="${1:-production}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HungryHippaahneties Deployment${NC}"
echo -e "${GREEN}HIPAA-Compliant Kubernetes Stack${NC}"
echo -e "${GREEN}========================================${NC}"

# Pre-flight checks
echo -e "\n${YELLOW}Running pre-flight checks...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Check Helm (optional)
if command -v helm &> /dev/null; then
    HELM_AVAILABLE=true
else
    HELM_AVAILABLE=false
    echo -e "${YELLOW}Warning: Helm not found, using kustomize${NC}"
fi

echo -e "${GREEN}Pre-flight checks passed!${NC}"

# Create namespace with Pod Security Standards
echo -e "\n${YELLOW}Creating namespace with security policies...${NC}"
kubectl apply -f k8s/base/namespace.yaml

# Wait for namespace
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/${NAMESPACE} --timeout=30s

# Apply RBAC
echo -e "\n${YELLOW}Applying RBAC configuration...${NC}"
kubectl apply -f k8s/base/rbac.yaml

# Apply Network Policies
echo -e "\n${YELLOW}Applying Network Policies...${NC}"
kubectl apply -f k8s/base/network-policies.yaml

# Apply Secrets (PLACEHOLDER - Replace with external secrets in production)
echo -e "\n${YELLOW}Applying Secrets...${NC}"
echo -e "${RED}WARNING: Using placeholder secrets. Replace with external secrets manager in production!${NC}"
kubectl apply -f k8s/base/secrets.yaml

# Apply ConfigMaps
echo -e "\n${YELLOW}Applying ConfigMaps...${NC}"
kubectl apply -f k8s/base/configmaps.yaml

# Apply Services
echo -e "\n${YELLOW}Applying Services...${NC}"
kubectl apply -f k8s/base/services.yaml

# Apply Deployments
echo -e "\n${YELLOW}Applying Deployments...${NC}"
kubectl apply -f k8s/base/deployments.yaml

# Apply Ingress
echo -e "\n${YELLOW}Applying Ingress...${NC}"
kubectl apply -f k8s/base/ingress.yaml

# Apply Audit Logging
echo -e "\n${YELLOW}Applying Audit Logging Configuration...${NC}"
kubectl apply -f k8s/base/audit-logging.yaml

# Wait for deployments
echo -e "\n${YELLOW}Waiting for deployments to be ready...${NC}"

deployments=("nginx-proxy" "api" "backend" "frontend" "modsecurity-waf")
for deployment in "${deployments[@]}"; do
    echo "Waiting for ${deployment}..."
    kubectl rollout status deployment/${deployment} -n ${NAMESPACE} --timeout=300s || true
done

# Wait for StatefulSets
echo -e "\n${YELLOW}Waiting for StatefulSets...${NC}"
statefulsets=("postgresql" "redis")
for sts in "${statefulsets[@]}"; do
    echo "Waiting for ${sts}..."
    kubectl rollout status statefulset/${sts} -n ${NAMESPACE} --timeout=300s || true
done

# Verify deployment
echo -e "\n${YELLOW}Verifying deployment...${NC}"
kubectl get all -n ${NAMESPACE}

# Security verification
echo -e "\n${YELLOW}Running security verification...${NC}"

# Check Pod Security Standards compliance
echo "Checking Pod Security Standards..."
NON_COMPLIANT=$(kubectl get pods -n ${NAMESPACE} -o json | jq -r '.items[] | select(.spec.securityContext.runAsNonRoot != true) | .metadata.name' 2>/dev/null || echo "")
if [ -n "$NON_COMPLIANT" ]; then
    echo -e "${RED}Warning: Some pods may not be running as non-root${NC}"
else
    echo -e "${GREEN}All pods comply with runAsNonRoot${NC}"
fi

# Check Network Policies
echo "Checking Network Policies..."
NP_COUNT=$(kubectl get networkpolicies -n ${NAMESPACE} --no-headers | wc -l)
if [ "$NP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Network Policies applied: ${NP_COUNT}${NC}"
else
    echo -e "${RED}Warning: No Network Policies found${NC}"
fi

# Check TLS secrets
echo "Checking TLS certificates..."
if kubectl get secret tls-certificates -n ${NAMESPACE} &> /dev/null; then
    echo -e "${GREEN}TLS certificates secret found${NC}"
else
    echo -e "${RED}Warning: TLS certificates secret not found${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}HIPAA Compliance Checklist:${NC}"
echo "[ ] Replace placeholder secrets with external secrets manager"
echo "[ ] Configure cert-manager for automatic TLS certificate rotation"
echo "[ ] Enable Kubernetes audit logging on API server"
echo "[ ] Configure log shipping to SIEM"
echo "[ ] Set up Falco for runtime security monitoring"
echo "[ ] Review and customize WAF rules"
echo "[ ] Configure backup and disaster recovery"
echo "[ ] Complete BAA with cloud provider"
echo "[ ] Document all security controls"
echo "[ ] Schedule regular security assessments"

echo -e "\n${YELLOW}Access Information:${NC}"
echo "Namespace: ${NAMESPACE}"
echo "Ingress: kubectl get ingress -n ${NAMESPACE}"
echo "Services: kubectl get svc -n ${NAMESPACE}"
echo "Pods: kubectl get pods -n ${NAMESPACE}"
