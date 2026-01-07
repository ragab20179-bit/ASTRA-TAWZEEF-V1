#!/bin/bash

################################################################################
# ASTRA / TAWZEEF Monitoring Script
# 
# Monitors services and displays real-time metrics
# Usage: ./monitor.sh [command]
# Commands: status, logs, metrics, restart, stop, start
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_NAME="astra-tawzeef"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

show_status() {
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" ps
    
    echo -e "\n${BLUE}=== Health Checks ===${NC}"
    
    # ASTRA Core
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        HEALTH=$(curl -s http://localhost:8000/health)
        log_success "ASTRA Core: $HEALTH"
    else
        log_error "ASTRA Core: UNHEALTHY"
    fi
    
    # Orchestrator
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        log_success "Orchestrator: HEALTHY"
    else
        log_error "Orchestrator: UNHEALTHY"
    fi
    
    # Watcher
    if curl -sf http://localhost:8002/health > /dev/null 2>&1; then
        log_success "Watcher: HEALTHY"
    else
        log_error "Watcher: UNHEALTHY"
    fi
}

show_logs() {
    SERVICE=${1:-""}
    LINES=${2:-50}
    
    if [ -z "$SERVICE" ]; then
        echo -e "\n${BLUE}=== All Services Logs (last $LINES lines) ===${NC}"
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" logs --tail=$LINES
    else
        echo -e "\n${BLUE}=== $SERVICE Logs (last $LINES lines) ===${NC}"
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" logs --tail=$LINES "$SERVICE"
    fi
}

show_metrics() {
    echo -e "\n${BLUE}=== Database Metrics ===${NC}"
    
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" exec -T postgres psql -U astra -d astra << 'SQL'
-- Decision outcomes
SELECT 'ASTRA Decisions' as metric, outcome, COUNT(*) as count, MAX(created_at) as latest
FROM astra_decision_artifacts
GROUP BY outcome
ORDER BY count DESC;

-- Execution status
SELECT 'Executions' as metric, outcome, COUNT(*) as count, MAX(created_at) as latest
FROM tawzeef_execution_artifacts
GROUP BY outcome
ORDER BY count DESC;

-- Database size
SELECT 'Database Size' as metric, 
       pg_size_pretty(pg_database_size('astra')) as size;

-- Table sizes
SELECT 'Table Sizes' as metric,
       schemaname,
       tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
SQL
}

show_resource_usage() {
    echo -e "\n${BLUE}=== Container Resource Usage ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
        $(docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" ps -q)
}

restart_services() {
    SERVICE=${1:-""}
    
    if [ -z "$SERVICE" ]; then
        log_info "Restarting all services..."
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" restart
    else
        log_info "Restarting $SERVICE..."
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" restart "$SERVICE"
    fi
    
    sleep 5
    show_status
}

stop_services() {
    log_info "Stopping all services..."
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" down
    log_success "Services stopped"
}

start_services() {
    log_info "Starting all services..."
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" up -d
    sleep 5
    show_status
}

watch_logs() {
    SERVICE=${1:-""}
    
    if [ -z "$SERVICE" ]; then
        echo -e "\n${BLUE}=== Watching All Services (Ctrl+C to stop) ===${NC}"
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" logs -f
    else
        echo -e "\n${BLUE}=== Watching $SERVICE (Ctrl+C to stop) ===${NC}"
        docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" logs -f "$SERVICE"
    fi
}

show_help() {
    cat << EOF
${BLUE}ASTRA / TAWZEEF Monitoring Script${NC}

Usage: ./monitor.sh [command] [options]

Commands:
  status              Show service status and health checks
  logs [service]      Show logs (optional: specific service)
  watch [service]     Watch logs in real-time (optional: specific service)
  metrics             Show database metrics
  resources           Show container resource usage
  restart [service]   Restart services (optional: specific service)
  stop                Stop all services
  start               Start all services
  help                Show this help message

Examples:
  ./monitor.sh status
  ./monitor.sh logs astra-core
  ./monitor.sh watch
  ./monitor.sh metrics
  ./monitor.sh restart orchestrator

Services:
  - postgres
  - astra-core
  - orchestrator
  - watcher
EOF
}

main() {
    COMMAND=${1:-status}
    OPTION=${2:-""}
    
    case "$COMMAND" in
        status)
            show_status
            ;;
        logs)
            show_logs "$OPTION" 50
            ;;
        watch)
            watch_logs "$OPTION"
            ;;
        metrics)
            show_metrics
            ;;
        resources)
            show_resource_usage
            ;;
        restart)
            restart_services "$OPTION"
            ;;
        stop)
            stop_services
            ;;
        start)
            start_services
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
