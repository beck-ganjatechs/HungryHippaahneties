# Operations Runbook

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring & Alerting](#monitoring--alerting)
3. [Log Management](#log-management)
4. [Backup & Recovery](#backup--recovery)
5. [Scaling Procedures](#scaling-procedures)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Incident Response](#incident-response)
8. [Emergency Procedures](#emergency-procedures)

---

## Daily Operations

### Health Check Routine

```bash
#!/bin/bash
# Daily health check script

NAMESPACE="hungryhippaahneties"

echo "=== HungryHippaahneties Daily Health Check ==="
echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# 1. Pod Status
echo "=== Pod Status ==="
kubectl get pods -n $NAMESPACE -o wide
echo ""

# 2. Resource Usage
echo "=== Resource Usage ==="
kubectl top pods -n $NAMESPACE
echo ""

# 3. Recent Events
echo "=== Recent Events (last 1 hour) ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20
echo ""

# 4. Certificate Expiry
echo "=== Certificate Status ==="
kubectl get certificates -n $NAMESPACE
echo ""

# 5. PVC Status
echo "=== Persistent Volume Claims ==="
kubectl get pvc -n $NAMESPACE
echo ""

# 6. Service Endpoints
echo "=== Service Endpoints ==="
kubectl get endpoints -n $NAMESPACE
echo ""

# 7. Health Endpoints
echo "=== Application Health ==="
for svc in api-service backend-service frontend-service; do
  echo -n "$svc: "
  kubectl exec -n $NAMESPACE deploy/api -- curl -s http://$svc/health || echo "FAILED"
done
```

### Key Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU Usage | > 80% | Scale or investigate |
| Memory Usage | > 85% | Scale or investigate |
| Pod Restarts | > 3/hour | Investigate immediately |
| Response Time (p99) | > 500ms | Investigate |
| Error Rate | > 1% | Investigate |
| Failed Auth | > 10/min | Security alert |
| Disk Usage | > 80% | Expand or cleanup |

---

## Monitoring & Alerting

### Prometheus Queries

```yaml
# Key Prometheus queries for monitoring

# CPU Usage by Pod
sum(rate(container_cpu_usage_seconds_total{namespace="hungryhippaahneties"}[5m])) by (pod)

# Memory Usage by Pod
sum(container_memory_working_set_bytes{namespace="hungryhippaahneties"}) by (pod)

# HTTP Request Rate
sum(rate(http_requests_total{namespace="hungryhippaahneties"}[5m])) by (service)

# HTTP Error Rate
sum(rate(http_requests_total{namespace="hungryhippaahneties",status=~"5.."}[5m])) /
sum(rate(http_requests_total{namespace="hungryhippaahneties"}[5m]))

# Response Time (p99)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{namespace="hungryhippaahneties"}[5m])) by (le, service))

# Database Connections
pg_stat_activity_count{datname="hungryhippaahneties_db"}

# Redis Memory Usage
redis_memory_used_bytes{namespace="hungryhippaahneties"}

# Authentication Failures
sum(rate(authentication_failures_total{namespace="hungryhippaahneties"}[5m]))
```

### Alert Rules

```yaml
# Critical alerts
groups:
  - name: hungryhippaahneties-critical
    rules:
      - alert: PodCrashLooping
        expr: |
          rate(kube_pod_container_status_restarts_total{namespace="hungryhippaahneties"}[15m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} is crash looping"

      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{namespace="hungryhippaahneties",status=~"5.."}[5m])) /
          sum(rate(http_requests_total{namespace="hungryhippaahneties"}[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate above 5%"

      - alert: DatabaseDown
        expr: |
          pg_up{namespace="hungryhippaahneties"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL database is down"

      - alert: HighAuthFailures
        expr: |
          sum(rate(authentication_failures_total{namespace="hungryhippaahneties"}[5m])) > 10
        for: 2m
        labels:
          severity: critical
          compliance: hipaa
        annotations:
          summary: "High authentication failure rate - possible attack"

      - alert: CertificateExpiringSoon
        expr: |
          (certmanager_certificate_expiration_timestamp_seconds - time()) < 604800
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "TLS certificate expiring in less than 7 days"
```

### Grafana Dashboards

```json
{
  "dashboard": {
    "title": "HungryHippaahneties Overview",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{namespace=\"hungryhippaahneties\"}[5m])) by (service)"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "singlestat",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{namespace=\"hungryhippaahneties\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{namespace=\"hungryhippaahneties\"}[5m])) * 100"
          }
        ]
      },
      {
        "title": "Response Time (p99)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{namespace=\"hungryhippaahneties\"}[5m])) by (le, service))"
          }
        ]
      }
    ]
  }
}
```

---

## Log Management

### Log Locations

| Component | Log Location | Format |
|-----------|--------------|--------|
| NGINX | stdout/stderr | JSON |
| API | stdout/stderr | JSON |
| Backend | stdout/stderr | JSON |
| PostgreSQL | /var/log/postgresql/ | PostgreSQL format |
| Redis | /var/log/redis/ | Redis format |
| ModSecurity | /var/log/modsecurity/ | JSON |
| Kubernetes Audit | /var/log/kubernetes/audit/ | JSON |

### Log Queries (Elasticsearch)

```json
// Authentication failures in last hour
{
  "query": {
    "bool": {
      "must": [
        { "match": { "event": "authn_login_fail" } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  }
}

// PHI access events
{
  "query": {
    "bool": {
      "must": [
        { "match": { "event": "sensitive_read" } },
        { "match": { "compliance": "HIPAA" } }
      ]
    }
  }
}

// WAF blocked requests
{
  "query": {
    "bool": {
      "must": [
        { "exists": { "field": "modsecurity.messages" } },
        { "range": { "@timestamp": { "gte": "now-24h" } } }
      ]
    }
  }
}

// Errors by service
{
  "query": {
    "bool": {
      "must": [
        { "match": { "level": "ERROR" } }
      ]
    }
  },
  "aggs": {
    "by_service": {
      "terms": { "field": "kubernetes.labels.app" }
    }
  }
}
```

### Log Retention

```yaml
HIPAA Retention Requirements:
  Audit logs: 7 years (2555 days)
  Application logs: 1 year
  Security events: 7 years
  Access logs: 7 years

Elasticsearch ILM Policy:
  hot: 7 days (SSD storage)
  warm: 30 days (HDD storage)
  cold: 365 days (Archive storage)
  delete: After retention period

Backup:
  Frequency: Daily
  Retention: 7 years
  Location: Encrypted S3/GCS bucket
```

---

## Backup & Recovery

### Database Backup

```bash
#!/bin/bash
# PostgreSQL backup script

NAMESPACE="hungryhippaahneties"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BUCKET="s3://hungryhippaahneties-backups"

# Create backup
kubectl exec -n $NAMESPACE postgresql-0 -- \
  pg_dump -U hipaa_app_user -d hungryhippaahneties_db -F c \
  > backup_$TIMESTAMP.dump

# Encrypt backup
gpg --symmetric --cipher-algo AES256 backup_$TIMESTAMP.dump

# Upload to S3
aws s3 cp backup_$TIMESTAMP.dump.gpg $BACKUP_BUCKET/postgresql/

# Cleanup local files
rm backup_$TIMESTAMP.dump backup_$TIMESTAMP.dump.gpg

echo "Backup completed: backup_$TIMESTAMP.dump.gpg"
```

### Database Restore

```bash
#!/bin/bash
# PostgreSQL restore script

NAMESPACE="hungryhippaahneties"
BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup_file>"
  exit 1
fi

# Download from S3
aws s3 cp s3://hungryhippaahneties-backups/postgresql/$BACKUP_FILE .

# Decrypt
gpg --decrypt $BACKUP_FILE > restore.dump

# Stop application pods (prevent connections)
kubectl scale deployment/api deployment/backend --replicas=0 -n $NAMESPACE

# Restore database
kubectl exec -i -n $NAMESPACE postgresql-0 -- \
  pg_restore -U hipaa_app_user -d hungryhippaahneties_db -c < restore.dump

# Restart application pods
kubectl scale deployment/api --replicas=2 -n $NAMESPACE
kubectl scale deployment/backend --replicas=2 -n $NAMESPACE

# Cleanup
rm restore.dump $BACKUP_FILE

echo "Restore completed"
```

### Redis Backup

```bash
#!/bin/bash
# Redis backup script

NAMESPACE="hungryhippaahneties"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Trigger BGSAVE
kubectl exec -n $NAMESPACE redis-0 -- \
  redis-cli --tls --cert /etc/redis/ssl/redis.crt \
  --key /etc/redis/ssl/redis.key --cacert /etc/redis/ssl/ca.crt \
  -p 6380 HIPAA_BGSAVE_i9j0k1l2

# Wait for save to complete
sleep 10

# Copy dump file
kubectl cp $NAMESPACE/redis-0:/data/dump.rdb redis_backup_$TIMESTAMP.rdb

# Encrypt and upload
gpg --symmetric --cipher-algo AES256 redis_backup_$TIMESTAMP.rdb
aws s3 cp redis_backup_$TIMESTAMP.rdb.gpg s3://hungryhippaahneties-backups/redis/

echo "Redis backup completed"
```

### Backup Schedule

| Component | Frequency | Retention | Type |
|-----------|-----------|-----------|------|
| PostgreSQL | Every 6 hours | 7 years | Full |
| PostgreSQL WAL | Continuous | 7 days | Incremental |
| Redis | Every 6 hours | 30 days | RDB snapshot |
| Kubernetes configs | Daily | 1 year | YAML export |
| Secrets (Vault) | Real-time | 7 years | Vault replication |

---

## Scaling Procedures

### Horizontal Scaling

```bash
# Scale API service
kubectl scale deployment/api --replicas=5 -n hungryhippaahneties

# Scale backend service
kubectl scale deployment/backend --replicas=5 -n hungryhippaahneties

# Enable HPA
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: hungryhippaahneties
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
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
EOF
```

### Vertical Scaling

```bash
# Update resource limits
kubectl patch deployment api -n hungryhippaahneties --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "2000m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "1Gi"}
]'
```

### Database Scaling

```bash
# Increase PVC size (if supported)
kubectl patch pvc data-postgresql-0 -n hungryhippaahneties -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Add read replica (manual)
# This requires proper PostgreSQL replication setup
```

---

## Maintenance Procedures

### Certificate Rotation

```bash
# cert-manager handles automatic rotation
# Manual rotation if needed:

# 1. Generate new certificate
kubectl delete certificate hungryhippaahneties-tls -n hungryhippaahneties
kubectl apply -f certificate.yaml

# 2. Wait for new certificate
kubectl wait --for=condition=Ready certificate/hungryhippaahneties-tls \
  -n hungryhippaahneties --timeout=300s

# 3. Restart ingress to pick up new cert
kubectl rollout restart deployment/nginx-proxy -n hungryhippaahneties
```

### Secret Rotation

```bash
#!/bin/bash
# Secret rotation script

NAMESPACE="hungryhippaahneties"

# Generate new passwords
NEW_DB_PASSWORD=$(openssl rand -base64 32)
NEW_REDIS_PASSWORD=$(openssl rand -base64 32)

# Update PostgreSQL password
kubectl exec -n $NAMESPACE postgresql-0 -- psql -U postgres -c \
  "ALTER USER hipaa_app_user PASSWORD '$NEW_DB_PASSWORD';"

# Update Kubernetes secret
kubectl create secret generic db-credentials \
  --namespace $NAMESPACE \
  --from-literal=POSTGRES_PASSWORD=$NEW_DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart applications to pick up new secret
kubectl rollout restart deployment/api deployment/backend -n $NAMESPACE

echo "Secret rotation completed. Verify application health."
```

### Node Maintenance

```bash
# Cordon node (prevent new pods)
kubectl cordon node-1

# Drain node (move existing pods)
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# Perform maintenance...

# Uncordon node
kubectl uncordon node-1
```

### Kubernetes Upgrade

```bash
# 1. Review release notes and changelog
# 2. Test in staging environment
# 3. Backup all resources

# Export all resources
kubectl get all -n hungryhippaahneties -o yaml > backup-before-upgrade.yaml

# 4. Upgrade cluster (cloud provider specific)
# 5. Verify all pods running
kubectl get pods -n hungryhippaahneties

# 6. Run integration tests
# 7. Monitor for issues
```

---

## Incident Response

### Incident Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| P1 | Critical | 15 minutes | Data breach, complete outage |
| P2 | High | 1 hour | Partial outage, performance degradation |
| P3 | Medium | 4 hours | Non-critical feature broken |
| P4 | Low | 24 hours | Minor issues, cosmetic bugs |

### Incident Response Checklist

```markdown
## Incident Response Checklist

### 1. Detection & Triage (First 15 minutes)
- [ ] Acknowledge alert
- [ ] Assess severity level
- [ ] Notify on-call team
- [ ] Create incident channel

### 2. Investigation (Next 30 minutes)
- [ ] Check monitoring dashboards
- [ ] Review recent changes (deployments, config)
- [ ] Check logs for errors
- [ ] Identify affected components

### 3. Mitigation
- [ ] Implement immediate fix or workaround
- [ ] Scale resources if needed
- [ ] Rollback if caused by recent change
- [ ] Update status page

### 4. Resolution
- [ ] Verify fix is working
- [ ] Monitor for recurrence
- [ ] Document root cause
- [ ] Close incident

### 5. Post-Incident
- [ ] Conduct post-mortem (within 48 hours)
- [ ] Document lessons learned
- [ ] Create action items
- [ ] Update runbooks
```

### Common Incident Playbooks

#### Database Connection Issues

```bash
# 1. Check database pod status
kubectl get pods -l app=postgresql -n hungryhippaahneties

# 2. Check database logs
kubectl logs -l app=postgresql -n hungryhippaahneties --tail=100

# 3. Check connection count
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# 4. Check for locks
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT * FROM pg_locks WHERE granted = false;"

# 5. Restart if needed
kubectl rollout restart statefulset/postgresql -n hungryhippaahneties
```

#### High Memory Usage

```bash
# 1. Identify high-memory pods
kubectl top pods -n hungryhippaahneties --sort-by=memory

# 2. Check for memory leaks
kubectl logs <pod-name> -n hungryhippaahneties | grep -i "memory\|oom"

# 3. Scale horizontally to distribute load
kubectl scale deployment/api --replicas=5 -n hungryhippaahneties

# 4. Restart affected pods
kubectl delete pod <pod-name> -n hungryhippaahneties
```

---

## Emergency Procedures

### Emergency Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| On-Call Engineer | PagerDuty | Auto-escalate after 15 min |
| Security Team | security@example.com | Immediately for breaches |
| Database Admin | dba@example.com | Database emergencies |
| Management | manager@example.com | P1 incidents |

### Emergency: Suspected Data Breach

```bash
#!/bin/bash
# EMERGENCY: Data breach response

echo "!!! DATA BREACH RESPONSE INITIATED !!!"
echo "Time: $(date -u)"

NAMESPACE="hungryhippaahneties"

# 1. Preserve evidence (do NOT delete anything)
echo "Preserving logs..."
kubectl logs -l app=api -n $NAMESPACE --all-containers > evidence_api_$(date +%s).log
kubectl logs -l app=nginx-proxy -n $NAMESPACE > evidence_nginx_$(date +%s).log

# 2. Isolate affected components
echo "Isolating network..."
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-isolate
  namespace: $NAMESPACE
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF

# 3. Scale down to prevent further access (optional - depends on situation)
# kubectl scale deployment --all --replicas=0 -n $NAMESPACE

# 4. Notify security team
echo "NOTIFY SECURITY TEAM IMMEDIATELY"
echo "- Do not delete any logs or data"
echo "- Document all actions taken"
echo "- Prepare for forensic investigation"

# 5. HIPAA: Breach notification may be required within 60 days
echo "HIPAA: Document breach for potential notification requirements"
```

### Emergency: Scale to Zero (Stop All Traffic)

```bash
#!/bin/bash
# Emergency: Stop all application traffic

NAMESPACE="hungryhippaahneties"

echo "EMERGENCY: Scaling all deployments to zero"
echo "Time: $(date -u)"

# Scale all deployments to 0
kubectl scale deployment --all --replicas=0 -n $NAMESPACE

# Verify
kubectl get pods -n $NAMESPACE

echo "All application pods stopped"
echo "Database and cache still running for data preservation"
```

### Emergency: Restore Service

```bash
#!/bin/bash
# Restore service after emergency

NAMESPACE="hungryhippaahneties"

echo "Restoring service..."

# Scale deployments back up
kubectl scale deployment/nginx-proxy --replicas=2 -n $NAMESPACE
kubectl scale deployment/modsecurity-waf --replicas=2 -n $NAMESPACE
kubectl scale deployment/frontend --replicas=2 -n $NAMESPACE
kubectl scale deployment/api --replicas=2 -n $NAMESPACE
kubectl scale deployment/backend --replicas=2 -n $NAMESPACE

# Remove emergency network policy if applied
kubectl delete networkpolicy emergency-isolate -n $NAMESPACE 2>/dev/null

# Wait for pods
kubectl rollout status deployment --all -n $NAMESPACE

# Verify health
kubectl get pods -n $NAMESPACE

echo "Service restored. Verify application health."
```

---

## Related Documentation

- [Architecture Guide](./ARCHITECTURE.md)
- [Security Controls](./SECURITY.md)
- [HIPAA Compliance](./HIPAA-COMPLIANCE.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
