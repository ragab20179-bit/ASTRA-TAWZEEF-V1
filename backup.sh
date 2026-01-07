#!/bin/bash

################################################################################
# ASTRA / TAWZEEF Backup Script
# 
# Creates backups of PostgreSQL database and configuration
# Usage: ./backup.sh [backup_dir]
# Example: ./backup.sh ./backups
################################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
BACKUP_DIR=${1:-./.backups}
PROJECT_NAME="astra-tawzeef"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/astra_backup_$TIMESTAMP.sql"
CONFIG_BACKUP="$BACKUP_DIR/config_backup_$TIMESTAMP.tar.gz"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     ASTRA / TAWZEEF Backup Script                             ║"
    echo "║     Backup Directory: $BACKUP_DIR"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    log_info "Backup directory: $BACKUP_DIR"
    
    # Source .env
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
    
    # Backup PostgreSQL database
    log_info "Backing up PostgreSQL database..."
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" exec -T postgres \
        pg_dump -U "${PG_USER:-astra}" "${PG_DB:-astra}" > "$BACKUP_FILE"
    
    if [ -f "$BACKUP_FILE" ]; then
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_success "Database backup created: $BACKUP_FILE ($SIZE)"
    else
        log_error "Failed to create database backup"
        exit 1
    fi
    
    # Backup configuration files
    log_info "Backing up configuration files..."
    tar -czf "$CONFIG_BACKUP" \
        .env \
        services/astra_core/policy_pack.json \
        migrations/ \
        2>/dev/null || true
    
    if [ -f "$CONFIG_BACKUP" ]; then
        SIZE=$(du -h "$CONFIG_BACKUP" | cut -f1)
        log_success "Configuration backup created: $CONFIG_BACKUP ($SIZE)"
    else
        log_error "Failed to create configuration backup"
        exit 1
    fi
    
    # Create restore instructions
    log_info "Creating restore instructions..."
    cat > "$BACKUP_DIR/RESTORE_$TIMESTAMP.md" << 'EOF'
# ASTRA / TAWZEEF Restore Instructions

## Restore Database

```bash
# Connect to PostgreSQL container
docker compose exec postgres psql -U astra astra < astra_backup_YYYYMMDD_HHMMSS.sql
```

## Restore Configuration

```bash
# Extract configuration backup
tar -xzf config_backup_YYYYMMDD_HHMMSS.tar.gz

# Restart services to apply changes
docker compose restart
```

## Verify Restore

```bash
# Check database
docker compose exec postgres psql -U astra -d astra -c "SELECT COUNT(*) FROM astra_decision_artifacts;"

# Check health
curl http://localhost:8000/health
```
EOF
    
    log_success "Restore instructions created: $BACKUP_DIR/RESTORE_$TIMESTAMP.md"
    
    # Cleanup old backups (keep last 30 days)
    log_info "Cleaning up old backups (keeping last 30 days)..."
    find "$BACKUP_DIR" -name "astra_backup_*.sql" -mtime +30 -delete
    find "$BACKUP_DIR" -name "config_backup_*.tar.gz" -mtime +30 -delete
    
    log_success "Old backups cleaned up"
    
    echo -e "\n${GREEN}✓ Backup completed successfully!${NC}"
    echo -e "${BLUE}Backup files:${NC}"
    echo "  - Database: $BACKUP_FILE"
    echo "  - Configuration: $CONFIG_BACKUP"
    echo "  - Instructions: $BACKUP_DIR/RESTORE_$TIMESTAMP.md"
}

main "$@"
