# Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Installation](#detailed-installation)
4. [Configuration](#configuration)
5. [Environment-Specific Deployments](#environment-specific-deployments)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Upgrades and Rollbacks](#upgrades-and-rollbacks)

---

## Prerequisites

### Required Components

| Component | Version | Purpose |
|-----------|---------|---------|
| Kubernetes | 1.25+ | Container orchestration |
| kubectl | 1.25+ | Cluster management |
| Helm | 3.x | Package management (optional) |
| cert-manager | 1.12+ | TLS certificate management |
| NGINX Ingress | 1.8+ | Ingress controller |

### Cluster Requirements

```yaml
Minimum Resources:
  Nodes: 3 (for HA)
  CPU per node: 4 cores
  Memory per node: 8 GB
  Storage: 100 GB SSD (encrypted)

Network Requirements:
  - CNI with NetworkPolicy support (Calico, Cilium)
  - LoadBalancer service type available
  - Egress to container registry
```

### Pre-flight Checklist

```bash
# 1. Verify kubectl connection
kubectl cluster-info

# 2. Check Kubernetes version
kubectl version --short
# Required: v1.25.0+

# 3. Verify NGINX Ingress Controller
kubectl get pods -n ingress-nginx

# 4. Verify cert-manager
kubectl get pods -n cert-manager

# 5. Check storage class
kubectl get storageclass
# Should have encrypted storage class

# 6. Check NetworkPolicy support
kubectl api-resources | grep networkpolicies
```

---

## Quick Start

```bash
# Clone repository
git clone https://github.com/example/hungryhippaahneties.git
cd hungryhippaahneties

# Option 1: Deploy using script (recommended)
chmod +x scripts/deploy.sh
./scripts/deploy.sh production

# Option 2: Deploy using kustomize
kubectl apply -k k8s/base/

# Option 3: Deploy using Helm
helm install hungryhippaahneties ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties \
  --create-namespace

# Verify deployment
kubectl get pods -n hungryhippaahneties
```

---

## Detailed Installation

### Step 1: Create Namespace

```bash
# Apply namespace with Pod Security Standards
kubectl apply -f k8s/base/namespace.yaml

# Verify PSS labels
kubectl get namespace hungryhippaahneties --show-labels
```

Expected output:
```
NAME                  STATUS   AGE   LABELS
hungryhippaahneties   Active   10s   pod-security.kubernetes.io/enforce=restricted,...
```

### Step 2: Configure Secrets

**Option A: Using External Secrets Operator (Recommended)**

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace

# Create SecretStore (Vault example)
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "hungryhippaahneties"
EOF

# Create ExternalSecret
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: hungryhippaahneties
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials
  data:
    - secretKey: POSTGRES_USER
      remoteRef:
        key: hungryhippaahneties/database
        property: username
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: hungryhippaahneties/database
        property: password
EOF
```

**Option B: Using Kubernetes Secrets (Development Only)**

```bash
# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Create secrets
kubectl create secret generic db-credentials \
  --namespace hungryhippaahneties \
  --from-literal=POSTGRES_USER=hipaa_app_user \
  --from-literal=POSTGRES_PASSWORD=$DB_PASSWORD \
  --from-literal=POSTGRES_DB=hungryhippaahneties_db \
  --from-literal=DATABASE_URL="postgresql://hipaa_app_user:$DB_PASSWORD@postgresql-service:5432/hungryhippaahneties_db?sslmode=require"

kubectl create secret generic redis-credentials \
  --namespace hungryhippaahneties \
  --from-literal=REDIS_PASSWORD=$REDIS_PASSWORD \
  --from-literal=REDIS_URL="rediss://:$REDIS_PASSWORD@redis-service:6380/0"

kubectl create secret generic api-secrets \
  --namespace hungryhippaahneties \
  --from-literal=JWT_SECRET=$JWT_SECRET \
  --from-literal=ENCRYPTION_KEY=$ENCRYPTION_KEY

# Verify secrets
kubectl get secrets -n hungryhippaahneties
```

### Step 3: Configure TLS Certificates

**Option A: Using cert-manager with Let's Encrypt**

```bash
# Create ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

# Create Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hungryhippaahneties-tls
  namespace: hungryhippaahneties
spec:
  secretName: tls-certificates
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - hungryhippaahneties.example.com
    - www.hungryhippaahneties.example.com
    - api.hungryhippaahneties.example.com
EOF

# Wait for certificate
kubectl wait --for=condition=Ready certificate/hungryhippaahneties-tls \
  -n hungryhippaahneties --timeout=300s
```

**Option B: Using Self-Signed Certificates (Development)**

```bash
# Generate CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
  -subj "/CN=HungryHippaahneties CA"

# Generate server certificate
openssl genrsa -out tls.key 2048
openssl req -new -key tls.key -out tls.csr \
  -subj "/CN=hungryhippaahneties.example.com"
openssl x509 -req -days 365 -in tls.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out tls.crt

# Create secret
kubectl create secret generic tls-certificates \
  --namespace hungryhippaahneties \
  --from-file=tls.crt=tls.crt \
  --from-file=tls.key=tls.key \
  --from-file=ca.crt=ca.crt
```

### Step 4: Apply RBAC Configuration

```bash
kubectl apply -f k8s/base/rbac.yaml

# Verify service accounts
kubectl get serviceaccounts -n hungryhippaahneties

# Verify roles
kubectl get roles -n hungryhippaahneties

# Verify role bindings
kubectl get rolebindings -n hungryhippaahneties
```

### Step 5: Apply Network Policies

```bash
kubectl apply -f k8s/base/network-policies.yaml

# Verify network policies
kubectl get networkpolicies -n hungryhippaahneties
```

### Step 6: Deploy ConfigMaps

```bash
kubectl apply -f k8s/base/configmaps.yaml

# Or create from config files
kubectl create configmap nginx-config \
  --namespace hungryhippaahneties \
  --from-file=nginx.conf=configs/nginx/nginx.conf

kubectl create configmap postgresql-config \
  --namespace hungryhippaahneties \
  --from-file=postgresql.conf=configs/postgres/postgresql.conf

kubectl create configmap redis-config \
  --namespace hungryhippaahneties \
  --from-file=redis.conf=configs/redis/redis.conf

kubectl create configmap modsecurity-config \
  --namespace hungryhippaahneties \
  --from-file=modsecurity.conf=configs/modsecurity/modsecurity.conf
```

### Step 7: Deploy Services

```bash
kubectl apply -f k8s/base/services.yaml

# Verify services
kubectl get services -n hungryhippaahneties
```

### Step 8: Deploy Applications

```bash
kubectl apply -f k8s/base/deployments.yaml

# Wait for deployments
kubectl rollout status deployment/nginx-proxy -n hungryhippaahneties
kubectl rollout status deployment/api -n hungryhippaahneties
kubectl rollout status deployment/backend -n hungryhippaahneties
kubectl rollout status deployment/frontend -n hungryhippaahneties
kubectl rollout status deployment/modsecurity-waf -n hungryhippaahneties

# Wait for statefulsets
kubectl rollout status statefulset/postgresql -n hungryhippaahneties
kubectl rollout status statefulset/redis -n hungryhippaahneties
```

### Step 9: Configure Ingress

```bash
kubectl apply -f k8s/base/ingress.yaml

# Get ingress IP/hostname
kubectl get ingress -n hungryhippaahneties
```

### Step 10: Deploy Monitoring

```bash
kubectl apply -f k8s/base/audit-logging.yaml

# Verify Fluentd DaemonSet
kubectl get daemonset fluentd -n hungryhippaahneties
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_LEVEL` | Application log level | `info` |
| `LOG_FORMAT` | Log output format | `json` |
| `SESSION_TIMEOUT` | Session timeout (seconds) | `900` |
| `MAX_LOGIN_ATTEMPTS` | Max failed logins | `5` |
| `LOCKOUT_DURATION` | Account lockout (seconds) | `300` |
| `MFA_REQUIRED` | Require MFA | `true` |

### Helm Values

```bash
# View default values
helm show values ./helm/hungryhippaahneties

# Install with custom values
helm install hungryhippaahneties ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties \
  --create-namespace \
  --set global.environment=production \
  --set api.replicaCount=3 \
  --set postgresql.primary.persistence.size=50Gi \
  -f custom-values.yaml
```

### Custom Values Example

```yaml
# custom-values.yaml
global:
  environment: production
  storageClass: encrypted-ssd

api:
  replicaCount: 3
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "2000m"
      memory: "1Gi"

postgresql:
  primary:
    persistence:
      size: 50Gi

ingress:
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.example.com

hipaa:
  dataRetentionDays: 2555
  authentication:
    mfaRequired: true
```

---

## Environment-Specific Deployments

### Development

```bash
# Use development overlay
kubectl apply -k k8s/overlays/dev/

# Or with Helm
helm install hungryhippaahneties-dev ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties-dev \
  --create-namespace \
  --set global.environment=development \
  --set api.replicaCount=1 \
  --set backend.replicaCount=1 \
  --set postgresql.primary.persistence.size=5Gi
```

### Staging

```bash
# Use staging overlay
kubectl apply -k k8s/overlays/staging/

# Or with Helm
helm install hungryhippaahneties-staging ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties-staging \
  --create-namespace \
  --set global.environment=staging \
  --set api.replicaCount=2
```

### Production

```bash
# Use production overlay
kubectl apply -k k8s/overlays/prod/

# Or with Helm
helm install hungryhippaahneties ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties \
  --create-namespace \
  --set global.environment=production \
  --set api.replicaCount=3 \
  --set backend.replicaCount=3 \
  -f production-values.yaml
```

---

## Post-Deployment Verification

### 1. Verify All Pods Running

```bash
kubectl get pods -n hungryhippaahneties

# Expected: All pods in Running state
NAME                              READY   STATUS    RESTARTS   AGE
api-xxxxx-xxxxx                   1/1     Running   0          5m
backend-xxxxx-xxxxx               1/1     Running   0          5m
frontend-xxxxx-xxxxx              1/1     Running   0          5m
modsecurity-waf-xxxxx-xxxxx       1/1     Running   0          5m
nginx-proxy-xxxxx-xxxxx           1/1     Running   0          5m
postgresql-0                      1/1     Running   0          5m
redis-0                           1/1     Running   0          5m
```

### 2. Verify Services

```bash
kubectl get svc -n hungryhippaahneties

# Test internal connectivity
kubectl run test-pod --rm -it --image=busybox -n hungryhippaahneties -- sh
# Inside pod:
wget -qO- http://api-service:8000/health
wget -qO- http://backend-service:8080/health
```

### 3. Verify Network Policies

```bash
kubectl get networkpolicies -n hungryhippaahneties

# Test that default deny works
kubectl run test-pod --rm -it --image=busybox -n default -- sh
# This should fail (network policy blocks cross-namespace):
wget -qO- http://api-service.hungryhippaahneties:8000/health
```

### 4. Verify Security Context

```bash
# Check pod security context
kubectl get pods -n hungryhippaahneties -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.runAsNonRoot}{"\n"}{end}'

# All should show "true"
```

### 5. Verify TLS

```bash
# Get ingress hostname
INGRESS_IP=$(kubectl get ingress -n hungryhippaahneties -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Test TLS
openssl s_client -connect $INGRESS_IP:443 -servername hungryhippaahneties.example.com </dev/null 2>/dev/null | openssl x509 -text -noout

# Test HTTPS endpoint
curl -v https://hungryhippaahneties.example.com/health
```

### 6. Verify Security Headers

```bash
curl -I https://hungryhippaahneties.example.com

# Expected headers:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Content-Security-Policy: ...
```

### 7. Run Security Scan

```bash
# Using kubesec
kubectl get deployment api -n hungryhippaahneties -o yaml | kubesec scan -

# Using kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench
```

---

## Upgrades and Rollbacks

### Upgrade Application

```bash
# Update image tag
kubectl set image deployment/api api=hungryhippaahneties/api:1.1.0 -n hungryhippaahneties

# Or with Helm
helm upgrade hungryhippaahneties ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties \
  --set api.image.tag=1.1.0

# Watch rollout
kubectl rollout status deployment/api -n hungryhippaahneties
```

### Rollback

```bash
# Rollback to previous revision
kubectl rollout undo deployment/api -n hungryhippaahneties

# Or rollback to specific revision
kubectl rollout history deployment/api -n hungryhippaahneties
kubectl rollout undo deployment/api --to-revision=2 -n hungryhippaahneties

# Helm rollback
helm rollback hungryhippaahneties 1 -n hungryhippaahneties
```

### Database Migrations

```bash
# Run migrations as a job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate-$(date +%s)
  namespace: hungryhippaahneties
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: hungryhippaahneties/backend:1.1.0
          command: ["python", "manage.py", "migrate"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: DATABASE_URL
      restartPolicy: Never
  backoffLimit: 3
EOF

# Watch migration job
kubectl logs -f job/db-migrate-xxxxx -n hungryhippaahneties
```

---

## Related Documentation

- [Architecture Guide](./ARCHITECTURE.md)
- [Security Controls](./SECURITY.md)
- [Operations Runbook](./OPERATIONS.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
