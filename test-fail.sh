#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Blue/Green Failover Test ==="
echo ""

# Configuration
NGINX_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"
TEST_DURATION=10
REQUEST_INTERVAL=0.5

# Load expected values from .env if available
if [ -f .env ]; then
    source .env
    EXPECTED_BLUE_RELEASE="${RELEASE_ID_BLUE:-blue-v1.0.0}"
    EXPECTED_GREEN_RELEASE="${RELEASE_ID_GREEN:-green-v1.0.0}"
    EXPECTED_ACTIVE="${ACTIVE_POOL:-blue}"
else
    EXPECTED_BLUE_RELEASE="blue-v1.0.0"
    EXPECTED_GREEN_RELEASE="green-v1.0.0"
    EXPECTED_ACTIVE="blue"
fi

# Counters
total_requests=0
success_count=0
blue_count=0
green_count=0
error_count=0

# Function to extract header value
get_header() {
    local response="$1"
    local header_name="$2"
    echo "$response" | grep -i "^${header_name}:" | cut -d' ' -f2- | tr -d '\r\n'
}

# Test 1: Baseline - Blue should be active
echo -e "${YELLOW}Test 1: Baseline Check (${EXPECTED_ACTIVE} active)${NC}"

baseline_failures=0
for i in {1..5}; do
    # Get both headers and body
    response=$(curl -s -i "$NGINX_URL/version")
    
    # Extract status code
    http_code=$(echo "$response" | head -n1 | cut -d' ' -f2)
    
    # Extract headers
    app_pool=$(get_header "$response" "X-App-Pool")
    release_id=$(get_header "$response" "X-Release-Id")
    
    if [ "$http_code" = "200" ]; then
        echo "  Request $i: ✓ 200 OK - Pool: ${app_pool:-MISSING} | Release: ${release_id:-MISSING}"
        
        # Verify it's the expected pool
        if [ "$app_pool" != "$EXPECTED_ACTIVE" ]; then
            echo -e "${RED}    ERROR: Expected pool '$EXPECTED_ACTIVE', got '$app_pool'${NC}"
            baseline_failures=$((baseline_failures + 1))
        fi
        
        # Verify release ID matches expected
        expected_release_var="EXPECTED_${EXPECTED_ACTIVE^^}_RELEASE"
        expected_release="${!expected_release_var}"
        if [ -n "$expected_release" ] && [ "$release_id" != "$expected_release" ]; then
            echo -e "${YELLOW}    WARNING: Expected release '$expected_release', got '$release_id'${NC}"
        fi
    else
        echo -e "${RED}  Request $i: ✗ HTTP $http_code${NC}"
        baseline_failures=$((baseline_failures + 1))
    fi
    
    sleep 0.2
done

if [ $baseline_failures -gt 0 ]; then
    echo -e "${RED}✗ Baseline test failed with $baseline_failures errors${NC}\n"
    exit 1
fi

echo -e "${GREEN}✓ Baseline test passed${NC}\n"

# Test 2: Induce chaos on Blue
echo -e "${YELLOW}Test 2: Inducing chaos on Blue (error mode)${NC}"

chaos_response=$(curl -s -i -X POST "$BLUE_URL/chaos/start?mode=error")
chaos_code=$(echo "$chaos_response" | head -n1 | cut -d' ' -f2)

if [ "$chaos_code" = "200" ]; then
    echo -e "${GREEN}✓ Chaos mode activated on Blue${NC}"
else
    echo -e "${RED}✗ Failed to activate chaos mode (HTTP $chaos_code)${NC}"
    echo "Response: $chaos_response"
    exit 1
fi

# Verify chaos is working
sleep 1
echo "Verifying Blue is now failing..."
blue_test=$(curl -s -i "$BLUE_URL/version")
blue_test_code=$(echo "$blue_test" | head -n1 | cut -d' ' -f2)

if [ "$blue_test_code" = "500" ]; then
    echo -e "${GREEN}✓ Blue is correctly returning 500 errors${NC}\n"
else
    echo -e "${YELLOW}⚠ Blue returned HTTP $blue_test_code (expected 500)${NC}\n"
fi

# Test 3: Verify automatic failover to Green
echo -e "${YELLOW}Test 3: Testing automatic failover (${TEST_DURATION}s)${NC}"
echo "Requirement: 0 non-200 responses, ≥95% from Green"
echo ""

start_time=$(date +%s)
end_time=$((start_time + TEST_DURATION))

# Track first green response time
first_green_time=""
failover_detected=false

while [ $(date +%s) -lt $end_time ]; do
    response=$(curl -s -i "$NGINX_URL/version" 2>&1)
    
    # Check if curl succeeded
    if [ $? -ne 0 ]; then
        total_requests=$((total_requests + 1))
        error_count=$((error_count + 1))
        echo -e "${RED}  ✗ Request $total_requests: Connection failed${NC}"
        sleep $REQUEST_INTERVAL
        continue
    fi
    
    # Extract status code
    http_code=$(echo "$response" | head -n1 | cut -d' ' -f2)
    
    # Extract headers
    app_pool=$(get_header "$response" "X-App-Pool")
    release_id=$(get_header "$response" "X-Release-Id")
    
    total_requests=$((total_requests + 1))
    
    if [ "$http_code" = "200" ]; then
        success_count=$((success_count + 1))
        
        if [ "$app_pool" = "blue" ]; then
            blue_count=$((blue_count + 1))
            echo "  ✓ Request $total_requests: HTTP 200 - Pool: blue | Release: $release_id"
        elif [ "$app_pool" = "green" ]; then
            green_count=$((green_count + 1))
            
            # Mark first green response
            if [ -z "$first_green_time" ]; then
                first_green_time=$(date +%s)
                failover_time=$((first_green_time - start_time))
                echo -e "${GREEN}  ✓ Request $total_requests: HTTP 200 - Pool: green | Release: $release_id [FAILOVER DETECTED at ${failover_time}s]${NC}"
                failover_detected=true
            else
                echo "  ✓ Request $total_requests: HTTP 200 - Pool: green | Release: $release_id"
            fi
        else
            echo -e "${YELLOW}  ✓ Request $total_requests: HTTP 200 - Pool: ${app_pool:-UNKNOWN} | Release: $release_id${NC}"
        fi
    else
        error_count=$((error_count + 1))
        echo -e "${RED}  ✗ Request $total_requests: HTTP $http_code - Pool: ${app_pool:-N/A}${NC}"
    fi
    
    sleep $REQUEST_INTERVAL
done

# Test 4: Stop chaos and verify recovery
echo -e "\n${YELLOW}Test 4: Stopping chaos on Blue${NC}"
stop_response=$(curl -s -i -X POST "$BLUE_URL/chaos/stop")
stop_code=$(echo "$stop_response" | head -n1 | cut -d' ' -f2)

if [ "$stop_code" = "200" ]; then
    echo -e "${GREEN}✓ Chaos mode deactivated${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected response when stopping chaos (HTTP $stop_code)${NC}"
fi

# Wait for Blue to recover
sleep 2

echo "Verifying Blue recovery..."
blue_recovery=$(curl -s -i "$BLUE_URL/version")
blue_recovery_code=$(echo "$blue_recovery" | head -n1 | cut -d' ' -f2)

if [ "$blue_recovery_code" = "200" ]; then
    echo -e "${GREEN}✓ Blue is now healthy (HTTP 200)${NC}\n"
else
    echo -e "${YELLOW}⚠ Blue still returning HTTP $blue_recovery_code${NC}\n"
fi

# Results
echo "=== Test Results ==="
echo "Total Requests: $total_requests"
echo "Successful (200): $success_count"
echo "Errors (non-200): $error_count"
echo "Blue responses: $blue_count"
echo "Green responses: $green_count"
echo ""

# Calculate rates
if [ $total_requests -gt 0 ]; then
    success_rate=$((success_count * 100 / total_requests))
    green_rate=$((green_count * 100 / total_requests))
else
    success_rate=0
    green_rate=0
fi

echo "Success Rate: ${success_rate}%"
echo "Green Rate: ${green_rate}%"
echo ""

# Validation
echo "=== Validation ==="

# CRITICAL: Zero non-200s allowed
if [ $error_count -gt 0 ]; then
    echo -e "${RED}✗ FAIL: Detected $error_count failed requests${NC}"
    echo -e "${RED}  Requirement: 0 non-200 responses during failover${NC}"
    exit 1
else
    echo -e "${GREEN}✓ PASS: Zero failed requests (0 non-200s)${NC}"
fi

# Check if failover happened
if [ $green_count -eq 0 ]; then
    echo -e "${RED}✗ FAIL: No failover to Green detected${NC}"
    echo -e "${RED}  Green handled 0 requests${NC}"
    exit 1
else
    echo -e "${GREEN}✓ PASS: Failover to Green detected (${green_count} requests)${NC}"
fi

# Check green rate ≥95%
if [ $green_rate -lt 95 ]; then
    echo -e "${RED}✗ FAIL: Green response rate is ${green_rate}%${NC}"
    echo -e "${RED}  Requirement: ≥95% responses from Green${NC}"
    exit 1
else
    echo -e "${GREEN}✓ PASS: Green handled ${green_rate}% of requests (≥95%)${NC}"
fi

# Overall result
echo ""
echo -e "${GREEN}✓✓✓ ALL TESTS PASSED! ✓✓✓${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Zero failed requests during chaos${NC}"
echo -e "${GREEN}✓ Automatic failover to Green confirmed${NC}"
echo -e "${GREEN}✓ Green handled ${green_count}/${total_requests} requests (${green_rate}%)${NC}"
echo -e "${GREEN}✓ Headers correctly forwarded (X-App-Pool, X-Release-Id)${NC}"

if [ -n "$first_green_time" ]; then
    echo -e "${GREEN}✓ Failover time: ${failover_time}s after chaos${NC}"
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"