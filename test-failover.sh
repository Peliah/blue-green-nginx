#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Blue/Green Failover Test ==="
echo ""

# Configuration
NGINX_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"
TEST_DURATION=10
REQUEST_INTERVAL=0.5

# Counters
total_requests=0
success_count=0
blue_count=0
green_count=0
error_count=0

# Test 1: Baseline - Blue should be active
echo -e "${YELLOW}Test 1: Baseline Check (Blue active)${NC}"
for i in {1..5}; do
    response=$(curl -s -w "\n%{http_code}" "$NGINX_URL/version")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" -eq 200 ]; then
        pool=$(echo "$body" | grep -o '"pool":"[^"]*"' | cut -d'"' -f4)
        release=$(echo "$body" | grep -o '"release":"[^"]*"' | cut -d'"' -f4)
        echo "  Request $i: ✓ 200 OK - Pool: $pool, Release: $release"
        
        if [ "$pool" != "blue" ]; then
            echo -e "${RED}  ERROR: Expected pool 'blue', got '$pool'${NC}"
            exit 1
        fi
    else
        echo -e "${RED}  Request $i: ✗ HTTP $http_code${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ Baseline test passed${NC}\n"

# Test 2: Induce chaos on Blue
echo -e "${YELLOW}Test 2: Inducing chaos on Blue (error mode)${NC}"
chaos_response=$(curl -s -X POST "$BLUE_URL/chaos/start?mode=error" -w "\n%{http_code}")
chaos_code=$(echo "$chaos_response" | tail -n1)

if [ "$chaos_code" -eq 200 ]; then
    echo -e "${GREEN}✓ Chaos mode activated on Blue${NC}\n"
else
    echo -e "${RED}✗ Failed to activate chaos mode (HTTP $chaos_code)${NC}"
    exit 1
fi

# Wait a moment for chaos to take effect
sleep 1

# Test 3: Verify automatic failover to Green
echo -e "${YELLOW}Test 3: Testing automatic failover (${TEST_DURATION}s)${NC}"
start_time=$(date +%s)
end_time=$((start_time + TEST_DURATION))

while [ $(date +%s) -lt $end_time ]; do
    response=$(curl -s -w "\n%{http_code}" "$NGINX_URL/version" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    total_requests=$((total_requests + 1))
    
    if [ "$http_code" -eq 200 ]; then
        success_count=$((success_count + 1))
        pool=$(echo "$body" | grep -o '"pool":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$pool" = "blue" ]; then
            blue_count=$((blue_count + 1))
        elif [ "$pool" = "green" ]; then
            green_count=$((green_count + 1))
        fi
        
        echo "  ✓ Request $total_requests: HTTP $http_code - Pool: $pool"
    else
        error_count=$((error_count + 1))
        echo -e "${RED}  ✗ Request $total_requests: HTTP $http_code${NC}"
    fi
    
    sleep $REQUEST_INTERVAL
done

# Test 4: Stop chaos
echo -e "\n${YELLOW}Test 4: Stopping chaos on Blue${NC}"
curl -s -X POST "$BLUE_URL/chaos/stop" > /dev/null
echo -e "${GREEN}✓ Chaos mode deactivated${NC}\n"

# Results
echo "=== Test Results ==="
echo "Total Requests: $total_requests"
echo "Successful (200): $success_count"
echo "Errors (non-200): $error_count"
echo "Blue responses: $blue_count"
echo "Green responses: $green_count"
echo ""

# Calculate success rate
success_rate=$((success_count * 100 / total_requests))
green_rate=$((green_count * 100 / total_requests))

echo "Success Rate: ${success_rate}%"
echo "Green Rate: ${green_rate}%"
echo ""

# Validate results
if [ $error_count -gt 0 ]; then
    echo -e "${RED}✗ FAIL: Detected $error_count failed requests (expected 0)${NC}"
    exit 1
fi

if [ $green_rate -lt 95 ]; then
    echo -e "${RED}✗ FAIL: Green response rate is ${green_rate}% (expected ≥95%)${NC}"
    exit 1
fi

if [ $green_count -eq 0 ]; then
    echo -e "${RED}✗ FAIL: No failover to Green detected${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All tests passed!${NC}"
echo -e "${GREEN}  - Zero failed requests during failover${NC}"
echo -e "${GREEN}  - Automatic switch to Green detected${NC}"
echo -e "${GREEN}  - Green handled ${green_rate}% of requests${NC}"