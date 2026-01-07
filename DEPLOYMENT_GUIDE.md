# 🚀 ASTRA / TAWZEEF Production Deployment Guide

**Version:** 1.0.0  
**Last Updated:** December 31, 2025  
**Status:** ✅ READY FOR DEPLOYMENT

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Configuration](#configuration)
4. [Deployment](#deployment)
5. [Verification](#verification)
6. [Testing](#testing)
7. [Monitoring](#monitoring)
8. [Maintenance](#maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Rollback](#rollback)

---

## Quick Start

For experienced DevOps engineers, here's the quick deployment path:

```bash
# 1. Extract project
tar -xzf astra_taw_prod_v1.tar.gz
cd astra_taw_prod_v1

# 2. Configure environment
cp .env.example .env
nano .env  # Update PG_PASSWORD and other settings

# 3. Deploy
./deploy.sh production

# 4. Verify
./test.sh

# 5. Monitor
./monitor.sh status
```

**Estimated Time:** 10-15 minutes

---

## Prerequisites

### System Requirements

- **OS:** Ubuntu 20.04 LTS or later (or compatible Linux)
- **CPU:** 2+ cores
- **RAM:** 4GB minimum (8GB recommended)
- **Disk:** 20GB free space (for database growth)
- **Network:** Outbound internet access for Docker image pulls

### Software Requirements

- **Docker:** 20.10+ ([Install Docker](https://docs.docker.com/engine/install/))
- **Docker Compose:** 2.0+ ([Install Docker Compose](https://docs.docker.com/compose/install/))
- **curl:** For health checks and testing
- **bash:** For deployment scripts

### Verification

```bash
# Check Docker
docker --version
# Expected: Docker version 20.10.x or higher

# Check Docker Compose
docker compose version
# Expected: Docker Compose version 2.x.x or higher

# Check curl
curl --version
# Expected: curl version 7.x.x or higher
```

---

## Configuration

### Step 1: Extract Project

```bash
# Extract the deployment package
tar -xzf astra_taw_prod_v1.tar.gz
cd astra_taw_prod_v1

# Verify structure
ls -la
# Should show: deploy.sh, test.sh, backup.sh, monitor.sh, docker-compose.prod.yml, etc.
```

### Step 2: Create Environment File

```bash
# Copy example environment file
cp .env.example .env

# Edit with your settings
nano .env
```

### Step 3: Configure Critical Settings

Edit `.env` and update the following:

#### Database Configuration

```bash
# CRITICAL: Change this to a strong password!
PG_PASSWORD=your_secure_password_here_min_16_chars

# Optional: Change database name/user if needed
PG_DB=astra
PG_USER=astra
PG_HOST=postgres
PG_PORT=5432
```

#### Service Ports

```bash
# Default ports (change if conflicts exist)
ASTRA_PORT=8000
ORCHESTRATOR_PORT=8001
WATCHER_PORT=8002
```

#### ASTRA Configuration

```bash
# Policy pack path (usually no change needed)
ASTRA_POLICY_PACK_PATH=/app/services/astra_core/policy_pack.json

# Timeout for ASTRA calls to orchestrator/watcher
ASTRA_TIMEOUT_S=0.3
```

#### Metrics (Optional)

```bash
# Leave empty to disable metrics
# Or set to your StatsD server
STATSD_HOST=
STATSD_PORT=8125
```

#### Environment

```bash
# Deployment environment
ENVIRONMENT=production
LOG_LEVEL=info
```

### Step 4: Verify Configuration

```bash
# Check .env file
cat .env

# Verify critical values are set
grep "PG_PASSWORD" .env  # Should NOT be "CHANGE_ME_SECURE_PASSWORD"
```

---

## Deployment

### Automated Deployment (Recommended)

```bash
# Run deployment script
./deploy.sh production

# The script will:
# 1. Check prerequisites
# 2. Validate environment
# 3. Build Docker images
# 4. Start services
# 5. Verify health
# 6. Run smoke tests (if not production)
```

### Manual Deployment

If you prefer to deploy manually:

```bash
# 1. Build Docker images
docker compose -f docker-compose.prod.yml --env-file .env build

# 2. Start services
docker compose -f docker-compose.prod.yml --env-file .env up -d

# 3. Wait for services to be ready
sleep 15

# 4. Check status
docker compose -f docker-compose.prod.yml --env-file .env ps
```

### Deployment Output

Successful deployment should show:

```
CONTAINER ID   IMAGE                    STATUS              PORTS
xxxxx          astra-postgres:16        Up 2 seconds        0.0.0.0:5432->5432/tcp
xxxxx          astra-core:latest        Up 1 second         0.0.0.0:8000->8000/tcp
xxxxx          astra-orchestrator:latest Up 1 second        0.0.0.0:8001->8001/tcp
xxxxx          astra-watcher:latest     Up 1 second         0.0.0.0:8002->8002/tcp
```

---

## Verification

### Health Checks

```bash
# ASTRA Core (should show policy pack version)
curl http://localhost:8000/health
# Expected: {"ok": true, "policy_pack_version": "1.0.0"}

# Orchestrator
curl http://localhost:8001/health
# Expected: {"ok": true}

# Watcher (should show disabled by default)
curl http://localhost:8002/health
# Expected: {"ok": true, "enabled": false}
```

### Service Logs

```bash
# View recent logs
docker compose -f docker-compose.prod.yml --env-file .env logs --tail=50

# Watch logs in real-time
docker compose -f docker-compose.prod.yml --env-file .env logs -f

# View specific service logs
docker compose -f docker-compose.prod.yml --env-file .env logs astra-core
```

### Database Connectivity

```bash
# Connect to PostgreSQL
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra

# Check tables
\dt

# Count artifacts
SELECT COUNT(*) FROM astra_decision_artifacts;

# Exit
\q
```

---

## Testing

### Automated Test Suite

```bash
# Run comprehensive smoke tests
./test.sh

# Expected output:
# ✓ ASTRA Core health: {"ok": true, "policy_pack_version": "1.0.0"}
# ✓ Orchestrator health: {"ok": true}
# ✓ Watcher health: {"ok": true, "enabled": false}
# ✓ ALLOW case passed
# ✓ DENY (missing consent) case passed
# ✓ DENY (unauthorized role) case passed
# ✓ DENY (unknown action) case passed
# ✓ Watcher correctly disabled
# ✓ Performance OK: XXXms (< 500ms)
```

### Manual Testing

#### Test 1: ALLOW Case (Recruiter with consent)

```bash
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"11111111-1111-1111-1111-111111111111",
    "actor":{"id":"recruiter-1","role":"recruiter"},
    "context":{"domain":"interview","action":"start","consent":true}
  }'
```

**Expected Response:**
```json
{
  "execution_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "astra_decision_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "outcome": "EXECUTED"
}
```

#### Test 2: DENY Case (Missing consent)

```bash
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"22222222-2222-2222-2222-222222222222",
    "actor":{"id":"recruiter-1","role":"recruiter"},
    "context":{"domain":"interview","action":"start"}
  }'
```

**Expected Response:**
```json
{
  "outcome": "DENY",
  "astra_decision_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

#### Test 3: DENY Case (Unauthorized role)

```bash
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"33333333-3333-3333-3333-333333333333",
    "actor":{"id":"candidate-1","role":"candidate"},
    "context":{"domain":"interview","action":"start","consent":true}
  }'
```

**Expected Response:**
```json
{
  "outcome": "DENY",
  "astra_decision_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

---

## Monitoring

### Real-time Monitoring

```bash
# Show service status
./monitor.sh status

# Watch logs in real-time
./monitor.sh watch

# Watch specific service logs
./monitor.sh watch astra-core

# Show database metrics
./monitor.sh metrics

# Show resource usage
./monitor.sh resources
```

### Key Metrics to Track

| Metric | Target | Alert If |
|--------|--------|----------|
| ASTRA latency (p99) | <100ms | >200ms |
| Orchestrator latency (p99) | <150ms | >300ms |
| Error rate | <0.1% | >1% |
| ASTRA availability | 99.9% | <99% |
| Database connections | <50 | >80 |

### Database Queries

```bash
# Decision distribution
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra -c \
  "SELECT outcome, COUNT(*) FROM astra_decision_artifacts GROUP BY outcome;"

# Recent decisions
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra -c \
  "SELECT created_at, outcome, reason_code FROM astra_decision_artifacts ORDER BY created_at DESC LIMIT 10;"

# Database size
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra -c \
  "SELECT pg_size_pretty(pg_database_size('astra'));"
```

---

## Maintenance

### Regular Backups

```bash
# Create backup
./backup.sh ./backups

# Backups are created with timestamp:
# - astra_backup_YYYYMMDD_HHMMSS.sql
# - config_backup_YYYYMMDD_HHMMSS.tar.gz

# Schedule daily backups (crontab)
crontab -e
# Add: 0 2 * * * /path/to/astra_taw_prod_v1/backup.sh /path/to/backups
```

### Service Management

```bash
# Restart all services
./monitor.sh restart

# Restart specific service
./monitor.sh restart astra-core

# Stop all services
./monitor.sh stop

# Start all services
./monitor.sh start
```

### Policy Updates

```bash
# Edit policy pack
nano services/astra_core/policy_pack.json

# Restart ASTRA Core to reload policy
./monitor.sh restart astra-core

# Verify new policy
curl http://localhost:8000/health
```

### Database Maintenance

```bash
# Connect to database
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra

# Analyze tables (optimize queries)
ANALYZE;

# Vacuum tables (cleanup)
VACUUM;

# Check index usage
SELECT * FROM pg_stat_user_indexes;

# Exit
\q
```

### Log Rotation

Docker automatically rotates logs based on `docker-compose.prod.yml` settings:
- Max size: 10MB per file
- Max files: 3 files per service

---

## Troubleshooting

### Services Won't Start

**Symptom:** `docker compose up -d` fails or services exit immediately

**Solutions:**

```bash
# 1. Check logs
docker compose -f docker-compose.prod.yml --env-file .env logs

# 2. Verify .env file
cat .env | grep -E "PG_PASSWORD|ASTRA"

# 3. Check port conflicts
netstat -tuln | grep -E "8000|8001|8002|5432"

# 4. Rebuild images
docker compose -f docker-compose.prod.yml --env-file .env build --no-cache

# 5. Remove old containers
docker compose -f docker-compose.prod.yml --env-file .env down -v
docker compose -f docker-compose.prod.yml --env-file .env up -d
```

### Database Connection Timeout

**Symptom:** `ASTRA_UNAVAILABLE` or `connection timeout`

**Solutions:**

```bash
# 1. Check PostgreSQL is running
docker compose -f docker-compose.prod.yml --env-file .env ps postgres

# 2. Verify database credentials
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra -d astra -c "SELECT 1;"

# 3. Increase connection timeout
# Edit .env: PG_CONNECT_TIMEOUT=5
docker compose -f docker-compose.prod.yml --env-file .env restart

# 4. Check network connectivity
docker compose -f docker-compose.prod.yml --env-file .env exec astra-core ping postgres
```

### ASTRA Timeout

**Symptom:** Orchestrator returns `ASTRA_UNAVAILABLE`

**Solutions:**

```bash
# 1. Check ASTRA Core is running
curl http://localhost:8000/health

# 2. Measure ASTRA latency
time curl http://localhost:8000/health

# 3. Increase timeout if needed
# Edit .env: ASTRA_TIMEOUT_S=0.5
docker compose -f docker-compose.prod.yml --env-file .env restart orchestrator watcher

# 4. Check ASTRA Core logs
docker compose -f docker-compose.prod.yml --env-file .env logs astra-core
```

### Policy Pack Not Loading

**Symptom:** ASTRA Core fails to start

**Solutions:**

```bash
# 1. Verify policy pack file exists
docker compose -f docker-compose.prod.yml --env-file .env exec astra-core ls -la /app/services/astra_core/policy_pack.json

# 2. Validate JSON syntax
docker compose -f docker-compose.prod.yml --env-file .env exec astra-core python3 -c "import json; json.load(open('/app/services/astra_core/policy_pack.json'))"

# 3. Check ASTRA_POLICY_PACK_PATH
docker compose -f docker-compose.prod.yml --env-file .env exec astra-core env | grep ASTRA_POLICY_PACK_PATH

# 4. View ASTRA Core logs
docker compose -f docker-compose.prod.yml --env-file .env logs astra-core
```

### All Requests Denied

**Symptom:** All authorization requests return DENY

**Solutions:**

```bash
# 1. Check policy pack version
curl http://localhost:8000/health

# 2. Verify policy pack content
docker compose -f docker-compose.prod.yml --env-file .env exec astra-core cat /app/services/astra_core/policy_pack.json

# 3. Test with valid payload
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"test-uuid",
    "actor":{"id":"recruiter-1","role":"recruiter"},
    "context":{"domain":"interview","action":"start","consent":true}
  }'

# 4. Check decision reason
# Review ASTRA Core logs for reason_code
docker compose -f docker-compose.prod.yml --env-file .env logs astra-core | grep reason_code
```

---

## Rollback

### Quick Rollback

```bash
# Stop current deployment
./monitor.sh stop

# Restore from backup
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra astra < backups/astra_backup_YYYYMMDD_HHMMSS.sql

# Restore configuration
tar -xzf backups/config_backup_YYYYMMDD_HHMMSS.tar.gz

# Start services
./monitor.sh start

# Verify
./test.sh
```

### Full Rollback (If Needed)

```bash
# 1. Stop services
docker compose -f docker-compose.prod.yml --env-file .env down

# 2. Remove volumes (WARNING: Deletes data!)
docker volume rm astra-tawzeef_pgdata

# 3. Restore from backup
# Copy backup files to project directory
cp /backup/location/astra_backup_*.sql .
cp /backup/location/config_backup_*.tar.gz .

# 4. Restart with backup
docker compose -f docker-compose.prod.yml --env-file .env up -d
sleep 15
docker compose -f docker-compose.prod.yml --env-file .env exec postgres psql -U astra astra < astra_backup_*.sql

# 5. Verify
./test.sh
```

---

## Support & Resources

### Documentation

- [README.md](./README.md) — Project overview
- [DEPLOYMENT_READY.md](./DEPLOYMENT_READY.md) — Deployment checklist
- [docker-compose.prod.yml](./docker-compose.prod.yml) — Docker Compose configuration

### Scripts

- `deploy.sh` — Automated deployment
- `test.sh` — Smoke tests
- `monitor.sh` — Monitoring and management
- `backup.sh` — Database backups

### Logs

```bash
# View all logs
docker compose -f docker-compose.prod.yml --env-file .env logs

# Follow logs
docker compose -f docker-compose.prod.yml --env-file .env logs -f

# Specific service
docker compose -f docker-compose.prod.yml --env-file .env logs astra-core
```

### Emergency Contacts

- **DevOps Lead:** [Your contact]
- **On-Call:** [Your contact]
- **Escalation:** [Your contact]

---

## Checklist

### Pre-Deployment

- [ ] Docker and Docker Compose installed
- [ ] `.env` file created and configured
- [ ] Database password changed from default
- [ ] Sufficient disk space available (20GB+)
- [ ] Network connectivity verified
- [ ] Firewall rules configured (ports 8000, 8001, 8002, 5432)

### Post-Deployment

- [ ] All services running (`docker compose ps`)
- [ ] Health endpoints responding
- [ ] Smoke tests passing (`./test.sh`)
- [ ] Database artifacts created
- [ ] Logs clean (no errors)
- [ ] Backups configured
- [ ] Monitoring enabled
- [ ] Documentation updated

---

## Conclusion

Your ASTRA / TAWZEEF system is now ready for production deployment. Follow this guide step-by-step for a smooth deployment experience.

**Questions?** Refer to the [Troubleshooting](#troubleshooting) section or contact your DevOps team.

