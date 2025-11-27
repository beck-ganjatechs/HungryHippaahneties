# Architecture Guide

## Table of Contents

1. [System Overview](#system-overview)
2. [Component Architecture](#component-architecture)
3. [Network Architecture](#network-architecture)
4. [Data Flow](#data-flow)
5. [Technology Stack](#technology-stack)
6. [Kubernetes Resources](#kubernetes-resources)

---

## System Overview

HungryHippaahneties implements a defense-in-depth architecture with multiple security layers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES INGRESS                                   │
│                                                                              │
│  • TLS 1.2/1.3 Termination          • Rate Limiting (100 req/s)            │
│  • HSTS Enforcement                  • Request Size Limits (10MB)           │
│  • Security Headers Injection        • IP-based Access Control              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WAF LAYER                                       │
│                    ModSecurity + OWASP Core Rule Set                         │
│                                                                              │
│  • SQL Injection Prevention          • Remote File Inclusion Block          │
│  • Cross-Site Scripting (XSS)        • Command Injection Prevention         │
│  • CSRF Protection                   • PHI Leakage Detection                │
│  • Scanner/Bot Detection             • Anomaly Scoring (Threshold: 5)       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         REVERSE PROXY (NGINX)                                │
│                                                                              │
│  Security Headers:                   Rate Limiting:                          │
│  • Strict-Transport-Security         • General: 10 req/s                    │
│  • X-Frame-Options: DENY             • Auth: 5 req/min                      │
│  • X-Content-Type-Options            • API: 100 req/s                       │
│  • Content-Security-Policy                                                   │
│  • Referrer-Policy                   Logging:                               │
│  • Permissions-Policy                • HIPAA-compliant JSON format          │
│  • Cross-Origin-*-Policy             • Request ID tracking                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
          ▼                         ▼                         ▼
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│    FRONTEND     │       │   API SERVICE   │       │    BACKEND      │
│                 │       │                 │       │                 │
│ Technology:     │       │ Technology:     │       │ Technology:     │
│ • React/Vue/    │       │ • Node.js 20    │       │ • Python 3.12   │
│   Angular       │       │ • Express/      │       │ • FastAPI/      │
│ • NGINX (serve) │       │   Fastify       │       │   Flask         │
│                 │       │                 │       │ • Gunicorn      │
│ Port: 3000      │       │ Port: 8000      │       │ Port: 8080      │
│                 │       │                 │       │                 │
│ Security:       │       │ Security:       │       │ Security:       │
│ • Static assets │       │ • JWT Auth      │       │ • Input valid.  │
│ • CSP enforced  │       │ • Rate limiting │       │ • Parameterized │
│ • No secrets    │       │ • Input valid.  │       │   queries       │
└─────────────────┘       └─────────────────┘       └─────────────────┘
                                    │                         │
                                    └────────────┬────────────┘
                                                 │
                      ┌──────────────────────────┼──────────────────────────┐
                      │                          │                          │
                      ▼                          ▼                          ▼
            ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
            │   POSTGRESQL    │        │      REDIS      │        │   AUDIT LOGS    │
            │                 │        │                 │        │                 │
            │ Version: 16     │        │ Version: 7      │        │ • Fluentd       │
            │ Port: 5432      │        │ Port: 6380(TLS) │        │ • Elasticsearch │
            │                 │        │                 │        │ • Prometheus    │
            │ Security:       │        │ Security:       │        │ • Falco         │
            │ • TLS required  │        │ • TLS only      │        │                 │
            │ • scram-sha-256 │        │ • ACL-based     │        │ Retention:      │
            │ • Row-level sec │        │ • Commands      │        │ • 7 years       │
            │ • Audit logging │        │   restricted    │        │   (HIPAA)       │
            │                 │        │ • No EVAL       │        │                 │
            │ Storage:        │        │                 │        │                 │
            │ • Encrypted PVC │        │ Storage:        │        │                 │
            │ • 20Gi default  │        │ • Encrypted PVC │        │                 │
            └─────────────────┘        └─────────────────┘        └─────────────────┘
```

---

## Component Architecture

### 1. Ingress Layer

**Purpose**: External traffic entry point with TLS termination

| Setting | Value | Rationale |
|---------|-------|-----------|
| TLS Protocols | TLSv1.2, TLSv1.3 | OWASP TLS recommendations |
| Cipher Suites | ECDHE-*-AES256-GCM-SHA384 | Strong encryption only |
| HSTS | 1 year + preload | Prevent downgrade attacks |
| Rate Limit | 100 req/s | DoS prevention |

### 2. WAF Layer (ModSecurity)

**Purpose**: Application-layer attack prevention

```yaml
Configuration:
  SecRuleEngine: On
  ParanoiaLevel: 2        # Balanced security/usability
  AnomalyThreshold: 5     # Block after 5 points

Protected Against:
  - SQL Injection (CRS 942xxx)
  - XSS (CRS 941xxx)
  - LFI/RFI (CRS 930xxx/931xxx)
  - Command Injection (CRS 932xxx)
  - Scanner Detection (CRS 913xxx)

Custom Rules:
  - PHI Pattern Detection (SSN, Medical Record Numbers)
  - HIPAA-specific data leakage prevention
```

### 3. Reverse Proxy (NGINX)

**Purpose**: Request routing, security headers, rate limiting

```nginx
Security Headers Applied:
├── Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
├── X-Frame-Options: DENY
├── X-Content-Type-Options: nosniff
├── Content-Security-Policy: default-src 'self'; ...
├── Referrer-Policy: strict-origin-when-cross-origin
├── Permissions-Policy: geolocation=(), camera=(), microphone=()
├── Cross-Origin-Opener-Policy: same-origin
├── Cross-Origin-Embedder-Policy: require-corp
└── Cross-Origin-Resource-Policy: same-origin
```

### 4. Frontend Service

**Purpose**: Static asset serving, user interface

| Aspect | Implementation |
|--------|----------------|
| Serving | NGINX (Alpine-based) |
| Build | Multi-stage Docker build |
| Security | CSP headers, no inline scripts |
| User | Non-root (UID 10001) |

### 5. API Service

**Purpose**: RESTful API, business logic, authentication

| Aspect | Implementation |
|--------|----------------|
| Runtime | Node.js 20 (Alpine) |
| Framework | Express/Fastify |
| Auth | JWT with fingerprint binding |
| Sessions | Redis-backed, 15-min timeout |

**JWT Security Implementation**:
```javascript
// Token includes SHA-256 hash of browser fingerprint
// Fingerprint stored in HttpOnly cookie
// Token sidejacking prevention per OWASP JWT Cheat Sheet
{
  "sub": "user_id",
  "iat": 1234567890,
  "exp": 1234568790,  // 15 minutes
  "fgp": "sha256(fingerprint)"  // Browser context binding
}
```

### 6. Backend Service

**Purpose**: Data processing, database operations

| Aspect | Implementation |
|--------|----------------|
| Runtime | Python 3.12 (slim) |
| Framework | FastAPI/Flask |
| Server | Gunicorn (4 workers) |
| DB Access | SQLAlchemy with parameterized queries |

### 7. PostgreSQL Database

**Purpose**: Primary data store for PHI

| Security Control | Setting |
|-----------------|---------|
| Authentication | scram-sha-256 |
| Transport | TLS 1.2+ required |
| Audit | log_statement = 'all' |
| Connections | SSL/TLS only (pg_hba.conf) |
| Row Security | Enabled |

### 8. Redis Cache

**Purpose**: Session storage, caching, rate limiting

| Security Control | Setting |
|-----------------|---------|
| Port | 6380 (TLS only) |
| Authentication | ACL-based users |
| Dangerous Commands | Disabled (FLUSHALL, DEBUG, etc.) |
| Persistence | AOF + RDB with encryption |

---

## Network Architecture

### Network Segmentation (Three-Tier)

Based on OWASP Network Segmentation Cheat Sheet:

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND TIER                             │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│  │   WAF    │    │  NGINX   │    │ Frontend │                  │
│  │          │───▶│  Proxy   │───▶│ Service  │                  │
│  └──────────┘    └──────────┘    └──────────┘                  │
│                                                                  │
│  Allowed: Ingress from Internet                                  │
│  Denied: Direct access to middleware/backend                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (NetworkPolicy: frontend→middleware)
┌─────────────────────────────────────────────────────────────────┐
│                       MIDDLEWARE TIER                            │
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │   API Service    │         │  Backend Service │             │
│  │   (Port 8000)    │         │   (Port 8080)    │             │
│  └──────────────────┘         └──────────────────┘             │
│                                                                  │
│  Allowed: From frontend tier only                                │
│  Denied: Direct internet access, cross-app communication         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (NetworkPolicy: middleware→backend)
┌─────────────────────────────────────────────────────────────────┐
│                        BACKEND TIER                              │
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │   PostgreSQL     │         │      Redis       │             │
│  │   (Port 5432)    │         │   (Port 6380)    │             │
│  └──────────────────┘         └──────────────────┘             │
│                                                                  │
│  Allowed: From middleware tier only                              │
│  Denied: All other traffic, no egress                           │
└─────────────────────────────────────────────────────────────────┘
```

### Network Policy Summary

| Source | Destination | Ports | Status |
|--------|-------------|-------|--------|
| Internet | WAF | 443, 80 | ALLOW |
| WAF | NGINX Proxy | 443 | ALLOW |
| NGINX Proxy | Frontend | 3000 | ALLOW |
| NGINX Proxy | API | 8000 | ALLOW |
| NGINX Proxy | Backend | 8080 | ALLOW |
| Frontend | API | 8000 | ALLOW |
| API | Backend | 8080 | ALLOW |
| API | PostgreSQL | 5432 | ALLOW |
| API | Redis | 6380 | ALLOW |
| Backend | PostgreSQL | 5432 | ALLOW |
| Backend | Redis | 6380 | ALLOW |
| PostgreSQL | * | * | DENY (no egress) |
| Redis | * | * | DENY (no egress) |
| * | * | * | DEFAULT DENY |

---

## Data Flow

### Authentication Flow

```
┌──────┐     ┌─────┐     ┌─────┐     ┌─────┐     ┌───────┐
│Client│     │ WAF │     │NGINX│     │ API │     │ Redis │
└──┬───┘     └──┬──┘     └──┬──┘     └──┬──┘     └───┬───┘
   │            │           │           │            │
   │ POST /api/auth/login   │           │            │
   │───────────────────────▶│           │            │
   │            │           │           │            │
   │            │ Validate request      │            │
   │            │◀─────────▶│           │            │
   │            │           │           │            │
   │            │           │ Forward   │            │
   │            │           │──────────▶│            │
   │            │           │           │            │
   │            │           │           │ Validate credentials
   │            │           │           │──────────────────────▶
   │            │           │           │            │
   │            │           │           │ Create session
   │            │           │           │───────────▶│
   │            │           │           │            │
   │            │           │           │ Store session
   │            │           │           │◀───────────│
   │            │           │           │            │
   │ JWT + HttpOnly fingerprint cookie  │            │
   │◀───────────────────────────────────│            │
   │            │           │           │            │
```

### PHI Data Access Flow

```
┌──────┐     ┌─────┐     ┌─────┐     ┌───────┐     ┌────────────┐
│Client│     │ WAF │     │ API │     │Backend│     │ PostgreSQL │
└──┬───┘     └──┬──┘     └──┬──┘     └───┬───┘     └─────┬──────┘
   │            │           │            │               │
   │ GET /api/patient/123   │            │               │
   │ (JWT + Fingerprint)    │            │               │
   │───────────────────────▶│            │               │
   │            │           │            │               │
   │            │ SQL/XSS check          │               │
   │            │◀─────────▶│            │               │
   │            │           │            │               │
   │            │           │ Validate JWT               │
   │            │           │ + fingerprint              │
   │            │           │────────────│               │
   │            │           │            │               │
   │            │           │ Authorized request         │
   │            │           │───────────▶│               │
   │            │           │            │               │
   │            │           │            │ Parameterized query
   │            │           │            │ (TLS connection)
   │            │           │            │──────────────▶│
   │            │           │            │               │
   │            │           │            │ AUDIT LOG     │
   │            │           │            │ (who, what,   │
   │            │           │            │  when, where) │
   │            │           │            │◀──────────────│
   │            │           │            │               │
   │ Encrypted response     │            │               │
   │◀───────────────────────────────────│               │
   │            │           │            │               │
```

---

## Technology Stack

### Container Images

| Service | Base Image | Size | Security |
|---------|------------|------|----------|
| NGINX Proxy | nginx:1.25-alpine | ~40MB | Non-root, read-only |
| API | node:20-alpine | ~180MB | Non-root, dumb-init |
| Backend | python:3.12-slim | ~150MB | Non-root, no shell |
| Frontend | nginx:1.25-alpine | ~50MB | Non-root, read-only |
| WAF | owasp/modsecurity-crs:nginx-alpine | ~100MB | CRS rules included |
| PostgreSQL | postgres:16-alpine | ~230MB | SSL enforced |
| Redis | redis:7-alpine | ~30MB | TLS + ACL |

### Kubernetes Resources

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Namespace | 1 | Isolation with PSS |
| Deployment | 5 | Stateless services |
| StatefulSet | 2 | Database, Cache |
| Service | 8 | Internal networking |
| Ingress | 1 | External access |
| NetworkPolicy | 8 | Traffic control |
| ServiceAccount | 7 | Workload identity |
| Role/RoleBinding | 6 | RBAC permissions |
| Secret | 4 | Credentials |
| ConfigMap | 6 | Configuration |
| PVC | 2 | Persistent storage |
| ResourceQuota | 1 | Resource limits |
| LimitRange | 1 | Default limits |

---

## Scaling Considerations

### Horizontal Pod Autoscaler (HPA) Recommendations

```yaml
# Example HPA for API service
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### Database Scaling

| Approach | Use Case |
|----------|----------|
| Read Replicas | High read workloads |
| Connection Pooling | Many concurrent connections |
| Vertical Scaling | Complex queries |
| Sharding | Very large datasets |

### Cache Scaling

| Approach | Use Case |
|----------|----------|
| Redis Cluster | High availability |
| Sentinel | Automatic failover |
| Memory increase | Large session counts |

---

## Related Documentation

- [Security Controls](./SECURITY.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Operations Runbook](./OPERATIONS.md)
