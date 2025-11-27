# Troubleshooting Guide

## Table of Contents

1. [Diagnostic Commands](#diagnostic-commands)
2. [Common Issues](#common-issues)
3. [Pod Issues](#pod-issues)
4. [Network Issues](#network-issues)
5. [Database Issues](#database-issues)
6. [Authentication Issues](#authentication-issues)
7. [Performance Issues](#performance-issues)
8. [Security Issues](#security-issues)
9. [FAQ](#faq)

---

## Diagnostic Commands

### Quick Health Check

```bash
#!/bin/bash
# Quick diagnostic script

NAMESPACE="hungryhippaahneties"

echo "=== Cluster Health ==="
kubectl cluster-info
echo ""

echo "=== Namespace Status ==="
kubectl get namespace $NAMESPACE
echo ""

echo "=== Pod Status ==="
kubectl get pods -n $NAMESPACE -o wide
echo ""

echo "=== Pod Resource Usage ==="
kubectl top pods -n $NAMESPACE
echo ""

echo "=== Recent Events ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20
echo ""

echo "=== Services ==="
kubectl get svc -n $NAMESPACE
echo ""

echo "=== Ingress ==="
kubectl get ingress -n $NAMESPACE
echo ""

echo "=== PVC Status ==="
kubectl get pvc -n $NAMESPACE
echo ""

echo "=== Network Policies ==="
kubectl get networkpolicies -n $NAMESPACE
```

### Detailed Pod Diagnostics

```bash
# Get pod details
kubectl describe pod <pod-name> -n hungryhippaahneties

# Get pod logs
kubectl logs <pod-name> -n hungryhippaahneties

# Get previous container logs (if crashed)
kubectl logs <pod-name> -n hungryhippaahneties --previous

# Follow logs in real-time
kubectl logs -f <pod-name> -n hungryhippaahneties

# Get logs from all containers in pod
kubectl logs <pod-name> -n hungryhippaahneties --all-containers

# Get logs from all pods with label
kubectl logs -l app=api -n hungryhippaahneties
```

### Network Diagnostics

```bash
# Test DNS resolution
kubectl run dns-test --rm -it --image=busybox -n hungryhippaahneties -- nslookup api-service

# Test service connectivity
kubectl run net-test --rm -it --image=busybox -n hungryhippaahneties -- wget -qO- http://api-service:8000/health

# Test external connectivity
kubectl run net-test --rm -it --image=busybox -n hungryhippaahneties -- wget -qO- https://google.com

# Check endpoint IPs
kubectl get endpoints -n hungryhippaahneties
```

---

## Common Issues

### Issue: Pods Stuck in Pending State

**Symptoms:**
```
NAME                   READY   STATUS    RESTARTS   AGE
api-xxxxx-xxxxx        0/1     Pending   0          5m
```

**Causes & Solutions:**

1. **Insufficient Resources**
   ```bash
   # Check node resources
   kubectl describe nodes | grep -A 5 "Allocated resources"

   # Check pod resource requests
   kubectl describe pod <pod-name> -n hungryhippaahneties | grep -A 10 "Requests"

   # Solution: Scale cluster or reduce requests
   ```

2. **PVC Not Bound**
   ```bash
   # Check PVC status
   kubectl get pvc -n hungryhippaahneties

   # Check storage class
   kubectl get storageclass

   # Solution: Ensure storage class exists and has available capacity
   ```

3. **Node Selector/Affinity Not Matched**
   ```bash
   # Check pod's node requirements
   kubectl describe pod <pod-name> -n hungryhippaahneties | grep -A 10 "Node-Selectors"

   # Solution: Update node labels or pod requirements
   ```

### Issue: Pods in CrashLoopBackOff

**Symptoms:**
```
NAME                   READY   STATUS             RESTARTS   AGE
api-xxxxx-xxxxx        0/1     CrashLoopBackOff   5          10m
```

**Causes & Solutions:**

1. **Application Error**
   ```bash
   # Check logs
   kubectl logs <pod-name> -n hungryhippaahneties --previous

   # Common causes:
   # - Missing environment variables
   # - Database connection failure
   # - Invalid configuration
   ```

2. **Liveness Probe Failure**
   ```bash
   # Check probe configuration
   kubectl describe pod <pod-name> -n hungryhippaahneties | grep -A 10 "Liveness"

   # Solution: Adjust probe timing or fix health endpoint
   ```

3. **Resource Limits Too Low**
   ```bash
   # Check if OOMKilled
   kubectl describe pod <pod-name> -n hungryhippaahneties | grep -i "oom"

   # Solution: Increase memory limits
   ```

### Issue: Pods in ImagePullBackOff

**Symptoms:**
```
NAME                   READY   STATUS             RESTARTS   AGE
api-xxxxx-xxxxx        0/1     ImagePullBackOff   0          5m
```

**Causes & Solutions:**

```bash
# Check events
kubectl describe pod <pod-name> -n hungryhippaahneties | grep -A 10 "Events"

# Common causes:
# 1. Image doesn't exist - verify image name and tag
# 2. Private registry - check imagePullSecrets
# 3. Network issue - check registry connectivity

# Solution for private registry:
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<user> \
  --docker-password=<password> \
  -n hungryhippaahneties
```

### Issue: Service Not Accessible

**Symptoms:**
- `Connection refused` when accessing service
- `No route to host`

**Causes & Solutions:**

```bash
# 1. Check service exists
kubectl get svc -n hungryhippaahneties

# 2. Check endpoints
kubectl get endpoints <service-name> -n hungryhippaahneties
# If empty, pods aren't matching the selector

# 3. Check pod labels match service selector
kubectl get pods -n hungryhippaahneties --show-labels

# 4. Check network policies
kubectl get networkpolicies -n hungryhippaahneties

# 5. Test from within cluster
kubectl run test --rm -it --image=busybox -n hungryhippaahneties -- wget -qO- http://<service>:<port>/health
```

---

## Pod Issues

### Pod Security Policy Violations

**Symptom:**
```
Error: container has runAsNonRoot and image has non-numeric user (appuser), cannot verify user is non-root
```

**Solution:**
```yaml
# Ensure user is numeric in Dockerfile
USER 10001

# Or in pod spec
securityContext:
  runAsUser: 10001
  runAsGroup: 10001
```

### Pod Cannot Mount Volume

**Symptom:**
```
Warning  FailedMount  Unable to attach or mount volumes
```

**Solutions:**
```bash
# 1. Check PVC exists and is bound
kubectl get pvc -n hungryhippaahneties

# 2. Check storage class
kubectl get storageclass

# 3. Check node has available volumes
kubectl describe node <node-name> | grep -A 5 "Attachable"

# 4. For StatefulSet, check volumeClaimTemplates
```

### Pod OOMKilled

**Symptom:**
```
Last State:     Terminated
Reason:         OOMKilled
```

**Solutions:**
```bash
# 1. Check current memory usage
kubectl top pods -n hungryhippaahneties

# 2. Increase memory limits
kubectl patch deployment api -n hungryhippaahneties --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "1Gi"}]'

# 3. Investigate memory leak in application
kubectl logs <pod-name> -n hungryhippaahneties | grep -i "memory\|heap"
```

---

## Network Issues

### Network Policy Blocking Traffic

**Symptom:**
- Services can't communicate
- `Connection timed out`

**Diagnosis:**
```bash
# 1. Check network policies
kubectl get networkpolicies -n hungryhippaahneties -o yaml

# 2. Verify pod labels match policy selectors
kubectl get pods -n hungryhippaahneties --show-labels

# 3. Test connectivity from different namespace
kubectl run test --rm -it --image=busybox -n default -- wget -qO- --timeout=5 http://api-service.hungryhippaahneties:8000/health

# Expected: blocked by network policy
```

**Solutions:**
```bash
# Temporarily disable network policy for testing
kubectl delete networkpolicy default-deny-all -n hungryhippaahneties

# Or add specific allow rule
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-debug
  namespace: hungryhippaahneties
spec:
  podSelector:
    matchLabels:
      app: api
  ingress:
    - from:
        - podSelector: {}
EOF
```

### DNS Resolution Failing

**Symptom:**
```
wget: bad address 'api-service'
```

**Solutions:**
```bash
# 1. Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Check DNS service
kubectl get svc -n kube-system kube-dns

# 3. Test DNS from pod
kubectl run dns-test --rm -it --image=busybox -n hungryhippaahneties -- nslookup kubernetes.default

# 4. Check /etc/resolv.conf in pod
kubectl exec -it <pod-name> -n hungryhippaahneties -- cat /etc/resolv.conf
```

### TLS/SSL Errors

**Symptom:**
```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

**Solutions:**
```bash
# 1. Check certificate is valid
kubectl get certificate -n hungryhippaahneties
kubectl describe certificate hungryhippaahneties-tls -n hungryhippaahneties

# 2. Check secret contains certificate
kubectl get secret tls-certificates -n hungryhippaahneties -o yaml

# 3. Verify certificate chain
kubectl get secret tls-certificates -n hungryhippaahneties -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

# 4. Check certificate expiry
kubectl get secret tls-certificates -n hungryhippaahneties -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout
```

---

## Database Issues

### Cannot Connect to PostgreSQL

**Symptom:**
```
psycopg2.OperationalError: could not connect to server: Connection refused
```

**Solutions:**
```bash
# 1. Check PostgreSQL pod is running
kubectl get pods -l app=postgresql -n hungryhippaahneties

# 2. Check service exists
kubectl get svc postgresql-service -n hungryhippaahneties

# 3. Check endpoints
kubectl get endpoints postgresql-service -n hungryhippaahneties

# 4. Test connection from within cluster
kubectl run pg-test --rm -it --image=postgres:16-alpine -n hungryhippaahneties -- \
  psql -h postgresql-service -U hipaa_app_user -d hungryhippaahneties_db -c "SELECT 1;"

# 5. Check PostgreSQL logs
kubectl logs -l app=postgresql -n hungryhippaahneties

# 6. Verify credentials
kubectl get secret db-credentials -n hungryhippaahneties -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

### Database Connection Exhausted

**Symptom:**
```
FATAL: too many connections for role "hipaa_app_user"
```

**Solutions:**
```bash
# 1. Check current connections
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# 2. View active connections
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT pid, usename, application_name, state FROM pg_stat_activity;"

# 3. Kill idle connections
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND usename = 'hipaa_app_user';"

# 4. Increase max_connections in postgresql.conf
# Or implement connection pooling (PgBouncer)
```

### Redis Connection Issues

**Symptom:**
```
Error: Connection refused - connect(2) for redis-service:6380
```

**Solutions:**
```bash
# 1. Check Redis pod
kubectl get pods -l app=redis -n hungryhippaahneties

# 2. Check Redis logs
kubectl logs -l app=redis -n hungryhippaahneties

# 3. Test connection (TLS)
kubectl run redis-test --rm -it --image=redis:7-alpine -n hungryhippaahneties -- \
  redis-cli --tls --cert /etc/redis/ssl/redis.crt --key /etc/redis/ssl/redis.key \
  --cacert /etc/redis/ssl/ca.crt -h redis-service -p 6380 PING

# 4. Verify TLS certificates are mounted
kubectl exec -n hungryhippaahneties redis-0 -- ls -la /etc/redis/ssl/
```

---

## Authentication Issues

### JWT Validation Failures

**Symptom:**
```
401 Unauthorized: Invalid token
```

**Solutions:**
```bash
# 1. Check JWT secret is set
kubectl get secret api-secrets -n hungryhippaahneties -o jsonpath='{.data.JWT_SECRET}' | base64 -d | head -c 20

# 2. Verify token format
# Decode JWT at jwt.io (remove sensitive data first)

# 3. Check token expiration
# JWT 'exp' claim should be in the future

# 4. Check fingerprint cookie is being sent
# Browser DevTools → Application → Cookies → __Secure-Fgp

# 5. Check API logs for specific error
kubectl logs -l app=api -n hungryhippaahneties | grep -i "jwt\|token\|auth"
```

### Session Issues

**Symptom:**
```
Session expired or invalid
```

**Solutions:**
```bash
# 1. Check Redis is accessible
kubectl exec -n hungryhippaahneties deploy/api -- curl -s http://redis-service:6379/ping

# 2. Check session timeout configuration
kubectl get configmap app-config -n hungryhippaahneties -o jsonpath='{.data.SESSION_TIMEOUT}'

# 3. Check Redis has session data
kubectl exec -n hungryhippaahneties redis-0 -- \
  redis-cli --tls ... KEYS "session:*" | head -5

# 4. Check for clock skew
kubectl exec -n hungryhippaahneties deploy/api -- date
kubectl exec -n hungryhippaahneties redis-0 -- date
```

---

## Performance Issues

### High Response Times

**Diagnosis:**
```bash
# 1. Check pod resource usage
kubectl top pods -n hungryhippaahneties

# 2. Check if pods are being throttled
kubectl describe pod <pod-name> -n hungryhippaahneties | grep -i throttl

# 3. Check database query performance
kubectl exec -n hungryhippaahneties postgresql-0 -- \
  psql -U postgres -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# 4. Check for network latency
kubectl run latency-test --rm -it --image=busybox -n hungryhippaahneties -- \
  time wget -qO- http://api-service:8000/health
```

**Solutions:**
```bash
# 1. Scale horizontally
kubectl scale deployment api --replicas=5 -n hungryhippaahneties

# 2. Increase resources
kubectl patch deployment api -n hungryhippaahneties --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "2000m"}]'

# 3. Add caching layer
# Ensure Redis is being used effectively

# 4. Optimize database queries
# Add indexes, review slow query log
```

### Memory Pressure

**Diagnosis:**
```bash
# Check node memory
kubectl describe nodes | grep -A 5 "memory"

# Check pod memory
kubectl top pods -n hungryhippaahneties --sort-by=memory
```

**Solutions:**
```bash
# 1. Increase memory limits
# 2. Scale horizontally to distribute load
# 3. Investigate memory leaks in application
# 4. Enable memory monitoring and alerts
```

---

## Security Issues

### WAF Blocking Legitimate Traffic

**Symptom:**
```
403 Forbidden
ModSecurity: Access denied
```

**Solutions:**
```bash
# 1. Check WAF logs
kubectl logs -l app=modsecurity-waf -n hungryhippaahneties | grep -i "blocked\|denied"

# 2. Identify rule that triggered
# Look for rule ID in logs (e.g., 942100)

# 3. Add exception for false positive
# Update modsecurity.conf with rule exclusion:
# SecRuleRemoveById 942100

# 4. Lower paranoia level temporarily
kubectl set env deployment/modsecurity-waf PARANOIA=1 -n hungryhippaahneties
```

### Certificate Expired

**Symptom:**
```
curl: (60) SSL certificate has expired
```

**Solutions:**
```bash
# 1. Check cert-manager status
kubectl get certificates -n hungryhippaahneties

# 2. Check certificate details
kubectl describe certificate hungryhippaahneties-tls -n hungryhippaahneties

# 3. Force renewal
kubectl delete certificate hungryhippaahneties-tls -n hungryhippaahneties
kubectl apply -f certificate.yaml

# 4. Check cert-manager logs
kubectl logs -l app=cert-manager -n cert-manager
```

---

## FAQ

### Q: How do I access the database directly?

```bash
# Port forward to local machine
kubectl port-forward svc/postgresql-service 5432:5432 -n hungryhippaahneties

# Connect with psql (in another terminal)
psql -h localhost -U hipaa_app_user -d hungryhippaahneties_db
```

### Q: How do I view application logs?

```bash
# All API logs
kubectl logs -l app=api -n hungryhippaahneties

# Follow logs
kubectl logs -f -l app=api -n hungryhippaahneties

# Logs from last hour
kubectl logs -l app=api -n hungryhippaahneties --since=1h
```

### Q: How do I restart a deployment?

```bash
# Rolling restart
kubectl rollout restart deployment/api -n hungryhippaahneties

# Watch rollout
kubectl rollout status deployment/api -n hungryhippaahneties
```

### Q: How do I check if my changes are applied?

```bash
# Check deployment revision
kubectl rollout history deployment/api -n hungryhippaahneties

# Check current image
kubectl get deployment api -n hungryhippaahneties -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Q: How do I debug a pod that won't start?

```bash
# 1. Check events
kubectl describe pod <pod-name> -n hungryhippaahneties

# 2. Check logs
kubectl logs <pod-name> -n hungryhippaahneties

# 3. Start debug container
kubectl debug <pod-name> -n hungryhippaahneties --image=busybox -it
```

### Q: How do I update a secret?

```bash
# Delete and recreate
kubectl delete secret api-secrets -n hungryhippaahneties
kubectl create secret generic api-secrets \
  --from-literal=JWT_SECRET=$(openssl rand -base64 64) \
  -n hungryhippaahneties

# Restart pods to pick up new secret
kubectl rollout restart deployment/api -n hungryhippaahneties
```

---

## Related Documentation

- [Architecture Guide](./ARCHITECTURE.md)
- [Operations Runbook](./OPERATIONS.md)
- [Deployment Guide](./DEPLOYMENT.md)
