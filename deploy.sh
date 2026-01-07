#!/bin/bash

################################################################################
# ASTRA / TAWZEEF Production Deployment Script
# 
# Usage: ./deploy.sh [environment]
# Examples:
#   ./deploy.sh development
#   ./deploy.sh staging
#   ./deploy.sh production
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-production}
PROJECT_NAME="astra-tawzeef"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

################################################################################
# Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    log_success "Docker found: $(docker --version)"
    
    # Check Docker Compose
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    log_success "Docker Compose found: $(docker compose version)"
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_warning ".env file not found. Creating from .env.example..."
        if [ -f ".env.example" ]; then
            cp .env.example "$ENV_FILE"
            log_warning "Please edit .env and set secure passwords before deploying!"
            exit 1
        else
            log_error ".env.example not found"
            exit 1
        fi
    fi
    
    log_success "All prerequisites met"
}

validate_environment() {
    log_info "Validating environment configuration..."
    
    # Source .env file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Check critical variables
    if [ -z "$PG_PASSWORD" ] || [ "$PG_PASSWORD" = "CHANGE_ME_SECURE_PASSWORD" ]; then
        log_error "PG_PASSWORD is not set or using default value. Please update .env file."
        exit 1
    fi
    
    if [ -z "$ENVIRONMENT" ]; then
        log_error "ENVIRONMENT is not set in .env file"
        exit 1
    fi
    
    log_success "Environment configuration valid"
}

build_images() {
    log_info "Building Docker images..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" build
    
    log_success "Docker images built successfully"
}

start_services() {
    log_info "Starting services..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" up -d
    
    log_success "Services started"
    
    # Wait for services to be ready
    log_info "Waiting for services to be healthy..."
    sleep 15
}

verify_health() {
    log_info "Verifying service health..."
    
    # Check ASTRA Core
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        ASTRA_HEALTH=$(curl -s http://localhost:8000/health)
        log_success "ASTRA Core is healthy: $ASTRA_HEALTH"
    else
        log_error "ASTRA Core health check failed"
        return 1
    fi
    
    # Check Orchestrator
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        log_success "Orchestrator is healthy"
    else
        log_error "Orchestrator health check failed"
        return 1
    fi
    
    # Check Watcher
    if curl -sf http://localhost:8002/health > /dev/null 2>&1; then
        log_success "Watcher is healthy"
    else
        log_error "Watcher health check failed"
        return 1
    fi
    
    log_success "All services are healthy"
}

run_smoke_tests() {
    log_info "Running smoke tests..."
    
    # Test 1: ALLOW case (recruiter with consent)
    log_info "Test 1: ALLOW case (recruiter with consent)..."
    RESPONSE=$(curl -s -X POST http://localhost:8001/v2/orchestrator/execute \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"11111111-1111-1111-1111-111111111111",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"start","consent":true}
        }')
    
    if echo "$RESPONSE" | grep -q "EXECUTED"; then
        log_success "Test 1 passed: $RESPONSE"
    else
        log_error "Test 1 failed: $RESPONSE"
        return 1
    fi
    
    # Test 2: DENY case (missing consent)
    log_info "Test 2: DENY case (missing consent)..."
    RESPONSE=$(curl -s -X POST http://localhost:8001/v2/orchestrator/execute \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"22222222-2222-2222-2222-222222222222",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"start"}
        }')
    
    if echo "$RESPONSE" | grep -q "DENY"; then
        log_success "Test 2 passed: $RESPONSE"
    else
        log_error "Test 2 failed: $RESPONSE"
        return 1
    fi
    
    # Test 3: DENY case (unauthorized role)
    log_info "Test 3: DENY case (unauthorized role)..."
    RESPONSE=$(curl -s -X POST http://localhost:8001/v2/orchestrator/execute \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"33333333-3333-3333-3333-333333333333",
            "actor":{"id":"candidate-1","role":"candidate"},
            "context":{"domain":"interview","action":"start","consent":true}
        }')
    
    if echo "$RESPONSE" | grep -q "DENY"; then
        log_success "Test 3 passed: $RESPONSE"
    else
        log_error "Test 3 failed: $RESPONSE"
        return 1
    fi
    
    log_success "All smoke tests passed"
}

show_status() {
    log_info "Showing service status..."
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" ps
}

show_logs() {
    log_info "Recent logs:"
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" -p "$PROJECT_NAME" logs --tail=20
}

################################################################################
# Main Execution
################################################################################

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     ASTRA / TAWZEEF Production Deployment Script              ║"
    echo "║     Environment: $ENVIRONMENT"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    validate_environment
    build_images
    start_services
    verify_health
    
    # Run smoke tests only in non-production or with confirmation
    if [ "$ENVIRONMENT" != "production" ]; then
        run_smoke_tests
    else
        log_warning "Skipping smoke tests in production environment"
        log_info "Run tests manually with: ./test.sh"
    fi
    
    show_status
    
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     ✅ Deployment Completed Successfully!                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Verify services: docker compose ps"
    echo "2. View logs: docker compose logs -f"
    echo "3. Run tests: ./test.sh"
    echo "4. Configure monitoring: Update STATSD_HOST in .env"
    echo "5. Set up backups: ./backup.sh"
}

# Run main function
main "$@"
