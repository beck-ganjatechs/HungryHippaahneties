# Security Controls Documentation

## Table of Contents

1. [Security Overview](#security-overview)
2. [OWASP Controls Implementation](#owasp-controls-implementation)
3. [Authentication & Session Management](#authentication--session-management)
4. [Authorization](#authorization)
5. [Input Validation & WAF](#input-validation--waf)
6. [Cryptography](#cryptography)
7. [Container Security](#container-security)
8. [Kubernetes Security](#kubernetes-security)
9. [Network Security](#network-security)
10. [Logging & Monitoring](#logging--monitoring)
11. [Security Checklist](#security-checklist)

---

## Security Overview

HungryHippaahneties implements defense-in-depth security based on the OWASP Cheat Sheet Series. Every component has been hardened following industry best practices.

### Security Principles Applied

| Principle | Implementation |
|-----------|----------------|
| **Defense in Depth** | Multiple security layers (WAF, proxy, app, DB) |
| **Least Privilege** | Minimal permissions for all components |
| **Fail Secure** | Default deny, explicit allow |
| **Separation of Duties** | Distinct service accounts per workload |
| **Security by Design** | Security built into architecture |

---

## OWASP Controls Implementation

### OWASP Top 10 (2021) Coverage

| Risk | Control | Location |
|------|---------|----------|
| **A01: Broken Access Control** | RBAC, Network Policies, JWT validation | K8s RBAC, API |
| **A02: Cryptographic Failures** | TLS 1.2+, AES-256, scram-sha-256 | All components |
| **A03: Injection** | Parameterized queries, WAF rules, input validation | Backend, WAF |
| **A04: Insecure Design** | Threat modeling, security architecture | Architecture |
| **A05: Security Misconfiguration** | Hardened configs, Pod Security Standards | All configs |
| **A06: Vulnerable Components** | Image scanning, dependency audit | CI/CD |
| **A07: Auth Failures** | Strong auth, MFA support, session management | API |
| **A08: Software/Data Integrity** | Image signing, SBOM, secrets management | CI/CD |
| **A09: Logging Failures** | HIPAA audit logging, centralized logs | Fluentd |
| **A10: SSRF** | WAF rules, egress restrictions | WAF, NetworkPolicy |

---

## Authentication & Session Management

### Password Requirements

Based on OWASP Authentication Cheat Sheet:

```yaml
Password Policy:
  minimum_length: 15          # Without MFA
  minimum_length_with_mfa: 8  # With MFA enabled
  maximum_length: 128         # Allow passphrases

  # No complexity requirements (per NIST 800-63B)
  require_uppercase: false
  require_lowercase: false
  require_numbers: false
  require_special: false

  # Breach detection
  check_breached_passwords: true  # HaveIBeenPwned API

  # No periodic rotation (per NIST 800-63B)
  rotation_required: false
  rotate_on_compromise: true
```

### Password Storage

```python
# Using Argon2id (OWASP recommended)
from argon2 import PasswordHasher

ph = PasswordHasher(
    time_cost=2,        # 2 iterations
    memory_cost=19456,  # 19 MiB
    parallelism=1,      # 1 degree of parallelism
    hash_len=32,        # 32-byte hash
    salt_len=16         # 16-byte salt
)

# Hash password
hash = ph.hash(password)

# Verify password
try:
    ph.verify(hash, password)
except VerifyMismatchError:
    # Invalid password
    pass
```

### Session Management

```yaml
Session Configuration:
  storage: Redis (TLS)
  id_length: 128 bits (32 hex chars)
  generator: CSPRNG (crypto.randomBytes)

  Timeouts:
    idle_timeout: 900       # 15 minutes
    absolute_timeout: 28800 # 8 hours
    renewal_interval: 900   # Regenerate every 15 min

  Cookie Attributes:
    name: __Host-SessionId
    secure: true
    httpOnly: true
    sameSite: Strict
    path: /
    # No domain (origin-server only)
    # No expires (session cookie)
```

### JWT Implementation

Based on OWASP JWT Cheat Sheet:

```javascript
// JWT with browser fingerprint binding (anti-sidejacking)

// 1. Generate fingerprint on login
const fingerprint = crypto.randomBytes(32).toString('hex');
const fingerprintHash = crypto.createHash('sha256')
  .update(fingerprint)
  .digest('hex');

// 2. Create JWT with fingerprint hash
const token = jwt.sign({
  sub: userId,
  iat: Math.floor(Date.now() / 1000),
  exp: Math.floor(Date.now() / 1000) + 900, // 15 minutes
  fgp: fingerprintHash  // Fingerprint hash in token
}, privateKey, { algorithm: 'RS256' });

// 3. Send fingerprint as hardened cookie
res.cookie('__Secure-Fgp', fingerprint, {
  httpOnly: true,
  secure: true,
  sameSite: 'Strict',
  maxAge: 900000  // 15 minutes
});

// 4. Validation: compare token fgp with cookie hash
function validateToken(token, fingerprintCookie) {
  const decoded = jwt.verify(token, publicKey);
  const cookieHash = crypto.createHash('sha256')
    .update(fingerprintCookie)
    .digest('hex');

  if (decoded.fgp !== cookieHash) {
    throw new Error('Token sidejacking detected');
  }
  return decoded;
}
```

### Multi-Factor Authentication

```yaml
MFA Configuration:
  required_for:
    - Administrative access
    - PHI data access
    - Account changes
    - Password reset

  Supported Methods:
    - TOTP (Google Authenticator, Authy)
    - WebAuthn/FIDO2 (Hardware keys)
    - SMS (backup only, not recommended)

  Recovery:
    - 10 one-time backup codes
    - Codes: 8 characters, alphanumeric
    - Stored: Argon2id hashed
```

---

## Authorization

### RBAC Model

Based on OWASP Authorization Cheat Sheet:

```yaml
Roles:
  # System roles
  system:admin:
    description: Full system access
    permissions: ["*"]

  system:operator:
    description: Operational access
    permissions:
      - pods:read
      - pods:list
      - logs:read
      - deployments:read

  # Application roles
  app:admin:
    description: Application administrator
    permissions:
      - users:*
      - config:*
      - audit:read

  app:user:
    description: Standard user
    permissions:
      - profile:read
      - profile:update
      - data:read

  app:readonly:
    description: Read-only access
    permissions:
      - data:read

Authorization Principles:
  - Deny by default
  - Validate on every request
  - Server-side only (never client-side)
  - Use ABAC for fine-grained control
```

### Kubernetes RBAC

```yaml
# Service Account with minimal permissions
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-sa
automountServiceAccountToken: false  # Don't auto-mount

---
# Role with specific permissions only
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: api-role
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["app-config"]  # Specific resources only
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["api-secrets"]
    verbs: ["get"]
```

---

## Input Validation & WAF

### Input Validation Strategy

Based on OWASP Input Validation Cheat Sheet:

```yaml
Validation Approach:
  method: Allowlist (whitelist)
  location: Server-side (mandatory)

  For Each Input:
    1. Type validation (string, number, date)
    2. Length validation (min/max)
    3. Format validation (regex for structured data)
    4. Range validation (business logic bounds)
    5. Encoding validation (UTF-8)

Examples:
  email:
    type: string
    max_length: 254
    pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

  phone:
    type: string
    max_length: 20
    pattern: "^\\+?[1-9]\\d{1,14}$"

  date:
    type: string
    format: ISO8601
    pattern: "^\\d{4}-\\d{2}-\\d{2}$"
```

### WAF Rules (ModSecurity)

```apache
# SQL Injection Prevention
SecRule ARGS|ARGS_NAMES|REQUEST_COOKIES "@detectSQLi" \
    "id:942100,\
    phase:2,\
    block,\
    msg:'SQL Injection Attack Detected',\
    severity:'CRITICAL',\
    tag:'OWASP_CRS',\
    tag:'attack-sqli'"

# XSS Prevention
SecRule ARGS|REQUEST_HEADERS "@detectXSS" \
    "id:941100,\
    phase:2,\
    block,\
    msg:'XSS Attack Detected',\
    severity:'CRITICAL',\
    tag:'attack-xss'"

# PHI Leakage Prevention (HIPAA-specific)
SecRule RESPONSE_BODY "@rx \\d{3}-\\d{2}-\\d{4}" \
    "id:950001,\
    phase:4,\
    block,\
    msg:'Potential SSN Leakage',\
    tag:'HIPAA',\
    severity:'CRITICAL'"
```

### SQL Injection Prevention

```python
# CORRECT: Parameterized queries
from sqlalchemy import text

def get_patient(patient_id: str):
    query = text("SELECT * FROM patients WHERE id = :id")
    result = db.execute(query, {"id": patient_id})
    return result

# WRONG: String concatenation (NEVER DO THIS)
# query = f"SELECT * FROM patients WHERE id = '{patient_id}'"
```

---

## Cryptography

### TLS Configuration

Based on OWASP Transport Layer Security Cheat Sheet:

```nginx
# NGINX TLS Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
ssl_ecdh_curve X25519:secp384r1;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
```

### Encryption at Rest

```yaml
Data Encryption:
  Algorithm: AES-256-GCM
  Key Management: External (Vault/KMS)

  Encrypted:
    - PostgreSQL data (PVC encryption)
    - Redis persistence (AOF/RDB)
    - Kubernetes secrets (etcd encryption)
    - Backup files

  Key Rotation:
    schedule: 90 days
    method: Envelope encryption (KEK + DEK)
```

### Secrets Management

Based on OWASP Secrets Management Cheat Sheet:

```yaml
Secrets Storage:
  Production:
    - HashiCorp Vault (recommended)
    - AWS Secrets Manager
    - Azure Key Vault
    - GCP Secret Manager

  Development:
    - Kubernetes Secrets (encrypted at rest)
    - Sealed Secrets (GitOps)

Secret Lifecycle:
  Creation:
    - CSPRNG generation
    - Minimum 256-bit entropy
    - Never transmitted in plaintext

  Rotation:
    - Automated rotation
    - Database: Dynamic credentials (per-connection)
    - API keys: 90 days
    - Certificates: 30 days before expiry

  Revocation:
    - Immediate on compromise
    - Audit trail maintained
```

---

## Container Security

### Dockerfile Security

Based on OWASP Docker Security Cheat Sheet:

```dockerfile
# Security-hardened Dockerfile example
FROM node:20-alpine AS builder
WORKDIR /app

# Use non-root user for build
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

# Copy and install dependencies
COPY --chown=appuser:appgroup package*.json ./
RUN npm ci --only=production && \
    npm audit --audit-level=high

COPY --chown=appuser:appgroup . .
RUN npm run build

# Production stage
FROM node:20-alpine AS production

# Remove unnecessary tools
RUN apk --no-cache upgrade && \
    rm -rf /var/cache/apk/* /tmp/*

# Non-root user
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup -H -s /sbin/nologin

WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules

# Read-only filesystem
RUN chmod -R 550 /app

USER appuser
EXPOSE 8000

# Use dumb-init for signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

### Container Security Checklist

| Control | Status | Implementation |
|---------|--------|----------------|
| Non-root user | ✅ | UID 10001 |
| Read-only filesystem | ✅ | readOnlyRootFilesystem: true |
| No privilege escalation | ✅ | allowPrivilegeEscalation: false |
| Drop all capabilities | ✅ | capabilities.drop: ALL |
| Seccomp profile | ✅ | RuntimeDefault |
| No privileged mode | ✅ | privileged: false |
| Resource limits | ✅ | CPU/Memory defined |
| Image scanning | ✅ | Trivy in CI/CD |
| No secrets in image | ✅ | External secrets |

---

## Kubernetes Security

### Pod Security Standards

Based on OWASP Kubernetes Security Cheat Sheet:

```yaml
# Namespace with PSS Restricted level
apiVersion: v1
kind: Namespace
metadata:
  name: hungryhippaahneties
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Security Context (Required for All Pods)

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault

  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 10001
        capabilities:
          drop:
            - ALL
```

### etcd Encryption

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

---

## Network Security

### Network Policies

```yaml
# Default deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 5432
```

### Security Headers

```nginx
# All security headers applied by NGINX
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options "DENY" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'; object-src 'none';" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=(), payment=()" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header Cross-Origin-Embedder-Policy "require-corp" always;
add_header Cross-Origin-Resource-Policy "same-origin" always;
```

---

## Logging & Monitoring

### Audit Logging Requirements

Based on OWASP Logging Cheat Sheet:

```yaml
Log Events (Mandatory):
  Authentication:
    - Login success/failure
    - Logout
    - Password changes
    - MFA events
    - Session creation/destruction

  Authorization:
    - Access granted/denied
    - Privilege changes
    - Role assignments

  Data Access:
    - PHI read/write/delete
    - Export operations
    - Bulk queries

  System:
    - Startup/shutdown
    - Configuration changes
    - Error conditions

Log Attributes:
  When:
    - timestamp (ISO 8601)
    - timezone (UTC)
  Where:
    - application_id
    - hostname
    - source_ip
    - request_uri
  Who:
    - user_id
    - session_id
    - client_info
  What:
    - event_type
    - action
    - result
    - severity

Data Exclusions (Never Log):
  - Passwords
  - Session tokens
  - API keys
  - Credit card numbers
  - SSN (mask as ***-**-1234)
  - PHI (unless required for audit)
```

### Log Format

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "level": "INFO",
  "event": "authn_login_success",
  "request_id": "abc123",
  "user_id": "user_456",
  "source_ip": "10.0.0.50",
  "user_agent": "Mozilla/5.0...",
  "action": "authenticate",
  "result": "success",
  "duration_ms": 150,
  "compliance": "HIPAA"
}
```

---

## Security Checklist

### Pre-Production Checklist

#### Infrastructure
- [ ] TLS 1.2+ enforced on all connections
- [ ] Certificate chain valid and trusted
- [ ] HSTS enabled with preload
- [ ] All security headers configured
- [ ] Network policies in place (default deny)
- [ ] Ingress rate limiting configured

#### Kubernetes
- [ ] Pod Security Standards: Restricted
- [ ] RBAC with least privilege
- [ ] Service accounts without auto-mount
- [ ] etcd encryption enabled
- [ ] Audit logging enabled
- [ ] Resource quotas defined

#### Containers
- [ ] Non-root users (UID 10001+)
- [ ] Read-only filesystems
- [ ] No privilege escalation
- [ ] Capabilities dropped
- [ ] Images scanned for vulnerabilities
- [ ] No secrets in images

#### Application
- [ ] Input validation on all endpoints
- [ ] Parameterized database queries
- [ ] JWT with fingerprint binding
- [ ] Session timeout (15 min)
- [ ] Error messages generic
- [ ] Audit logging complete

#### Secrets
- [ ] External secrets manager configured
- [ ] No secrets in code/config
- [ ] Rotation procedures tested
- [ ] Backup procedures tested

#### Monitoring
- [ ] Log aggregation working
- [ ] Alerting configured
- [ ] Falco rules deployed
- [ ] Prometheus metrics collected

---

## Related Documentation

- [Architecture Guide](./ARCHITECTURE.md)
- [HIPAA Compliance](./HIPAA-COMPLIANCE.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Operations Runbook](./OPERATIONS.md)
