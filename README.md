# HungryHippaahneties

A HIPAA-compliant Kubernetes boilerplate stack built on OWASP security best practices.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INTERNET                                      │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    KUBERNETES INGRESS                                 │
│                    (TLS Termination)                                  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         WAF LAYER                                     │
│              ModSecurity + OWASP Core Rule Set                        │
│           (SQL Injection, XSS, CSRF Protection)                       │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    REVERSE PROXY (NGINX)                              │
│    • TLS 1.2/1.3 Only    • Security Headers    • Rate Limiting       │
│    • HSTS Enabled        • CSP Headers         • Request Filtering   │
└─────────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   FRONTEND    │     │   API SERVICE │     │   BACKEND     │
│   (React/Vue) │     │   (Node.js)   │     │   (Python)    │
│   Port: 3000  │     │   Port: 8000  │     │   Port: 8080  │
└───────────────┘     └───────────────┘     └───────────────┘
                              │                       │
                              └───────────┬───────────┘
                                          │
                      ┌───────────────────┼───────────────────┐
                      │                   │                   │
                      ▼                   ▼                   ▼
              ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
              │   POSTGRESQL  │   │     REDIS     │   │  AUDIT LOGS   │
              │   (Database)  │   │    (Cache)    │   │  (Fluentd)    │
              │   Port: 5432  │   │   Port: 6380  │   │               │
              │   TLS + Auth  │   │   TLS + ACL   │   │               │
              └───────────────┘   └───────────────┘   └───────────────┘
```

## HIPAA Compliance Features

### Technical Safeguards

| Requirement | Implementation |
|-------------|----------------|
| **Access Control** | RBAC, Service Accounts, Least Privilege |
| **Audit Controls** | Kubernetes Audit Logging, Fluentd, Prometheus |
| **Integrity Controls** | Read-only filesystems, Immutable containers |
| **Transmission Security** | TLS 1.2+, mTLS between services |
| **Encryption** | AES-256 at rest, TLS in transit |

### Administrative Safeguards

| Requirement | Implementation |
|-------------|----------------|
| **Unique User ID** | Service accounts per workload |
| **Emergency Access** | Break-glass procedures documented |
| **Automatic Logoff** | Session timeout (15 minutes) |
| **Encryption/Decryption** | External secrets management |

### Physical Safeguards

| Requirement | Implementation |
|-------------|----------------|
| **Workstation Security** | Pod Security Standards (Restricted) |
| **Device Controls** | Network Policies, Container isolation |

## Security Controls (OWASP-Based)

### 1. Authentication & Session Management
- Strong password requirements (15+ characters)
- MFA support
- JWT with fingerprint binding
- Session timeout after 15 minutes
- Secure cookie attributes (HttpOnly, Secure, SameSite)

### 2. Authorization
- RBAC with least privilege principle
- Service accounts without auto-mounted tokens
- Network policies for service isolation
- Resource quotas and limits

### 3. Input Validation
- ModSecurity WAF with OWASP CRS
- SQL injection prevention
- XSS protection
- Command injection blocking

### 4. Cryptography
- TLS 1.2/1.3 only (no legacy protocols)
- Strong cipher suites (AES-GCM, ChaCha20)
- Certificate pinning support
- Key rotation procedures

### 5. Error Handling & Logging
- Generic error messages to users
- Detailed logging server-side
- HIPAA-compliant audit trails
- PHI masking in logs

### 6. Data Protection
- Encryption at rest (etcd, PVCs)
- Encryption in transit (TLS everywhere)
- No sensitive data in logs
- Secure secrets management

## Quick Start

### Prerequisites

- Kubernetes cluster (1.25+)
- kubectl configured
- Helm 3.x (optional)
- cert-manager (for TLS)
- NGINX Ingress Controller

### Deployment

```bash
# Clone the repository
git clone https://github.com/example/hungryhippaahneties.git
cd hungryhippaahneties

# Deploy using the script
chmod +x scripts/deploy.sh
./scripts/deploy.sh production

# Or using kustomize
kubectl apply -k k8s/base/

# Or using Helm
helm install hungryhippaahneties ./helm/hungryhippaahneties \
  --namespace hungryhippaahneties \
  --create-namespace \
  -f helm/hungryhippaahneties/values.yaml
```

### Configuration

1. **Replace Placeholder Secrets**
   ```bash
   # Use external secrets manager (recommended)
   # Or create secrets manually
   kubectl create secret generic db-credentials \
     --from-literal=POSTGRES_PASSWORD=$(openssl rand -base64 32) \
     -n hungryhippaahneties
   ```

2. **Configure TLS Certificates**
   ```bash
   # Using cert-manager
   kubectl apply -f - <<EOF
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
   EOF
   ```

3. **Update DNS**
   - Point your domain to the ingress IP/hostname

## Directory Structure

```
hungryhippaahneties/
├── configs/
│   ├── nginx/
│   │   └── nginx.conf          # Hardened NGINX configuration
│   ├── postgres/
│   │   ├── postgresql.conf     # PostgreSQL security settings
│   │   └── pg_hba.conf         # Host-based authentication
│   ├── redis/
│   │   ├── redis.conf          # Redis TLS and security
│   │   └── users.acl           # Redis ACL configuration
│   └── modsecurity/
│       └── modsecurity.conf    # WAF rules
├── docker/
│   ├── Dockerfile.nginx        # Hardened NGINX image
│   ├── Dockerfile.api          # Node.js API image
│   ├── Dockerfile.backend      # Python backend image
│   ├── Dockerfile.frontend     # Frontend image
│   └── Dockerfile.waf          # ModSecurity WAF image
├── k8s/
│   └── base/
│       ├── namespace.yaml      # Namespace with PSS
│       ├── rbac.yaml           # RBAC configuration
│       ├── secrets.yaml        # Secret templates
│       ├── configmaps.yaml     # ConfigMaps
│       ├── network-policies.yaml # Network segmentation
│       ├── services.yaml       # Service definitions
│       ├── deployments.yaml    # Deployment specs
│       ├── ingress.yaml        # Ingress configuration
│       ├── audit-logging.yaml  # Logging setup
│       └── kustomization.yaml  # Kustomize config
├── helm/
│   └── hungryhippaahneties/
│       ├── Chart.yaml
│       └── values.yaml
├── scripts/
│   └── deploy.sh               # Deployment script
└── README.md
```

## Security Hardening Checklist

### Container Security
- [x] Non-root containers (UID 10001+)
- [x] Read-only root filesystems
- [x] No privilege escalation
- [x] Dropped all capabilities
- [x] Seccomp profiles (RuntimeDefault)
- [x] Resource limits defined

### Network Security
- [x] Default deny network policies
- [x] Service-to-service isolation
- [x] TLS for all internal communication
- [x] No NodePort services
- [x] Ingress-only external access

### Secrets Management
- [x] No secrets in code/images
- [x] Kubernetes secrets (encrypted at rest)
- [x] External secrets operator support
- [x] Sealed secrets support

### Monitoring & Alerting
- [x] Prometheus metrics
- [x] Kubernetes audit logging
- [x] Fluentd log collection
- [x] Falco runtime security
- [x] HIPAA-specific alerts

## HIPAA Compliance Checklist

Before going to production:

- [ ] Complete BAA (Business Associate Agreement) with cloud provider
- [ ] Replace all placeholder secrets
- [ ] Enable etcd encryption
- [ ] Configure external secrets manager (Vault, AWS Secrets Manager)
- [ ] Set up cert-manager for automatic certificate rotation
- [ ] Enable Kubernetes API audit logging
- [ ] Configure SIEM integration
- [ ] Set up Falco for runtime threat detection
- [ ] Implement backup and disaster recovery
- [ ] Document incident response procedures
- [ ] Conduct security assessment
- [ ] Train staff on security procedures
- [ ] Establish access review schedule

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
