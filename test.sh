#!/bin/bash

################################################################################
# ASTRA / TAWZEEF Test Script
# 
# Runs comprehensive smoke tests against deployed services
# Usage: ./test.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BASE_URL=${BASE_URL:-"http://localhost"}
ASTRA_PORT=${ASTRA_PORT:-8000}
ORCHESTRATOR_PORT=${ORCHESTRATOR_PORT:-8001}
WATCHER_PORT=${WATCHER_PORT:-8002}

TESTS_PASSED=0
TESTS_FAILED=0

################################################################################
# Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
}

test_health_endpoints() {
    echo -e "\n${BLUE}=== Testing Health Endpoints ===${NC}"
    
    # ASTRA Core health
    log_info "Testing ASTRA Core health endpoint..."
    RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL:$ASTRA_PORT/health")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "ASTRA Core health: $BODY"
    else
        log_error "ASTRA Core health failed (HTTP $HTTP_CODE)"
    fi
    
    # Orchestrator health
    log_info "Testing Orchestrator health endpoint..."
    RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL:$ORCHESTRATOR_PORT/health")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Orchestrator health: $BODY"
    else
        log_error "Orchestrator health failed (HTTP $HTTP_CODE)"
    fi
    
    # Watcher health
    log_info "Testing Watcher health endpoint..."
    RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL:$WATCHER_PORT/health")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Watcher health: $BODY"
    else
        log_error "Watcher health failed (HTTP $HTTP_CODE)"
    fi
}

test_allow_case() {
    echo -e "\n${BLUE}=== Testing ALLOW Case ===${NC}"
    
    log_info "Test: Recruiter starting interview with consent..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL:$ORCHESTRATOR_PORT/v2/orchestrator/execute" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"11111111-1111-1111-1111-111111111111",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"start","consent":true}
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | grep -q "EXECUTED"; then
        log_success "ALLOW case passed: $BODY"
    else
        log_error "ALLOW case failed (HTTP $HTTP_CODE): $BODY"
    fi
}

test_deny_missing_consent() {
    echo -e "\n${BLUE}=== Testing DENY Case (Missing Consent) ===${NC}"
    
    log_info "Test: Recruiter starting interview without consent..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL:$ORCHESTRATOR_PORT/v2/orchestrator/execute" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"22222222-2222-2222-2222-222222222222",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"start"}
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | grep -q "DENY"; then
        log_success "DENY (missing consent) case passed: $BODY"
    else
        log_error "DENY (missing consent) case failed (HTTP $HTTP_CODE): $BODY"
    fi
}

test_deny_unauthorized_role() {
    echo -e "\n${BLUE}=== Testing DENY Case (Unauthorized Role) ===${NC}"
    
    log_info "Test: Candidate attempting to start interview..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL:$ORCHESTRATOR_PORT/v2/orchestrator/execute" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"33333333-3333-3333-3333-333333333333",
            "actor":{"id":"candidate-1","role":"candidate"},
            "context":{"domain":"interview","action":"start","consent":true}
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | grep -q "DENY"; then
        log_success "DENY (unauthorized role) case passed: $BODY"
    else
        log_error "DENY (unauthorized role) case failed (HTTP $HTTP_CODE): $BODY"
    fi
}

test_deny_unknown_action() {
    echo -e "\n${BLUE}=== Testing DENY Case (Unknown Action) ===${NC}"
    
    log_info "Test: Recruiter attempting unknown action..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL:$ORCHESTRATOR_PORT/v2/orchestrator/execute" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"44444444-4444-4444-4444-444444444444",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"unknown_action","consent":true}
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | grep -q "DENY"; then
        log_success "DENY (unknown action) case passed: $BODY"
    else
        log_error "DENY (unknown action) case failed (HTTP $HTTP_CODE): $BODY"
    fi
}

test_watcher_disabled() {
    echo -e "\n${BLUE}=== Testing Watcher (Disabled by Default) ===${NC}"
    
    log_info "Test: Watcher submit endpoint (should be disabled)..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL:$WATCHER_PORT/v2/watcher/submit" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"55555555-5555-5555-5555-555555555555",
            "watcher":{"id":"watcher-1"},
            "actor":{"id":"watcher-1","role":"watcher"},
            "context":{"domain":"watcher","action":"submit"}
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "403" ] && echo "$BODY" | grep -q "WATCHER_DISABLED"; then
        log_success "Watcher correctly disabled: $BODY"
    else
        log_error "Watcher test failed (HTTP $HTTP_CODE): $BODY"
    fi
}

test_performance() {
    echo -e "\n${BLUE}=== Testing Performance ===${NC}"
    
    log_info "Measuring ASTRA decision latency..."
    
    START=$(date +%s%N)
    curl -s -X POST "$BASE_URL:$ORCHESTRATOR_PORT/v2/orchestrator/execute" \
        -H "Content-Type: application/json" \
        -d '{
            "request_id":"66666666-6666-6666-6666-666666666666",
            "actor":{"id":"recruiter-1","role":"recruiter"},
            "context":{"domain":"interview","action":"start","consent":true}
        }' > /dev/null
    END=$(date +%s%N)
    
    LATENCY=$(( (END - START) / 1000000 ))
    
    if [ $LATENCY -lt 500 ]; then
        log_success "Performance OK: ${LATENCY}ms (< 500ms)"
    else
        log_error "Performance SLOW: ${LATENCY}ms (> 500ms)"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     ASTRA / TAWZEEF Test Suite                                ║"
    echo "║     Base URL: $BASE_URL"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check if services are running
    log_info "Checking if services are running..."
    if ! curl -sf "$BASE_URL:$ASTRA_PORT/health" > /dev/null 2>&1; then
        log_error "ASTRA Core is not responding at $BASE_URL:$ASTRA_PORT"
        exit 1
    fi
    
    # Run all tests
    test_health_endpoints
    test_allow_case
    test_deny_missing_consent
    test_deny_unauthorized_role
    test_deny_unknown_action
    test_watcher_disabled
    test_performance
    
    # Summary
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
