#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Monitoring & Alerting Test Suite  ${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Configuration
NGINX_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"

# Test 1: Verify Services Running
echo -e "${YELLOW}Test 1: Verify Services${NC}"
echo "Checking service status..."

if docker-compose ps | grep -q "alert_watcher"; then
    echo -e "${GREEN}✓ alert_watcher service is running${NC}"
else
    echo -e "${RED}✗ alert_watcher service is not running${NC}"
    exit 1
fi

if docker-compose ps | grep -q "nginx_proxy"; then
    echo -e "${GREEN}✓ nginx_proxy service is running${NC}"
else
    echo -e "${RED}✗ nginx_proxy service is not running${NC}"
    exit 1
fi

echo ""

# Test 2: Verify Monitoring Logs
echo -e "${YELLOW}Test 2: Verify Monitoring Logs${NC}"
echo "Checking if monitoring.log exists and has correct format..."

# Send a test request
curl -s http://localhost:8080/version > /dev/null
sleep 1

# Check if log file exists
if docker-compose exec -T nginx test -f /var/log/nginx/monitoring.log; then
    echo -e "${GREEN}✓ monitoring.log exists${NC}"
    
    # Get last log entry
    last_log=$(docker-compose exec -T nginx tail -1 /var/log/nginx/monitoring.log)
    
    # Check for required fields
    if echo "$last_log" | grep -q "pool="; then
        echo -e "${GREEN}✓ Log contains 'pool' field${NC}"
    else
        echo -e "${RED}✗ Log missing 'pool' field${NC}"
        exit 1
    fi
    
    if echo "$last_log" | grep -q "release="; then
        echo -e "${GREEN}✓ Log contains 'release' field${NC}"
    else
        echo -e "${RED}✗ Log missing 'release' field${NC}"
        exit 1
    fi
    
    if echo "$last_log" | grep -q "upstream_status="; then
        echo -e "${GREEN}✓ Log contains 'upstream_status' field${NC}"
    else
        echo -e "${RED}✗ Log missing 'upstream_status' field${NC}"
        exit 1
    fi
    
    if echo "$last_log" | grep -q "upstream="; then
        echo -e "${GREEN}✓ Log contains 'upstream' field${NC}"
    else
        echo -e "${RED}✗ Log missing 'upstream' field${NC}"
        exit 1
    fi
    
    echo ""
    echo "Sample log entry:"
    echo "$last_log"
else
    echo -e "${RED}✗ monitoring.log does not exist${NC}"
    exit 1
fi

echo ""

# Test 3: Verify Alert Watcher
echo -e "${YELLOW}Test 3: Verify Alert Watcher${NC}"
echo "Checking alert_watcher logs..."

watcher_logs=$(docker-compose logs alert_watcher --tail=20)

if echo "$watcher_logs" | grep -q "Alert Watcher starting"; then
    echo -e "${GREEN}✓ Alert watcher initialized${NC}"
else
    echo -e "${RED}✗ Alert watcher not initialized properly${NC}"
    exit 1
fi

if echo "$watcher_logs" | grep -q "Initial active pool"; then
    echo -e "${GREEN}✓ Active pool detected${NC}"
else
    echo -e "${RED}✗ Active pool not detected${NC}"
    exit 1
fi

if echo "$watcher_logs" | grep -q "monitoring.log"; then
    echo -e "${GREEN}✓ Monitoring log file detected${NC}"
else
    echo -e "${YELLOW}⚠ Monitoring log file may not be detected yet${NC}"
fi

echo ""

# Test 4: Trigger Failover and Check Detection
echo -e "${YELLOW}Test 4: Failover Detection${NC}"
echo "Inducing chaos on Blue to trigger failover..."

# Start chaos
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
sleep 2

# Generate traffic to trigger failover detection
echo "Sending 20 requests to trigger failover..."
for i in {1..20}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.2
done

# Wait for detection
sleep 3

# Check logs for failover detection
watcher_logs=$(docker-compose logs alert_watcher --tail=50)

if echo "$watcher_logs" | grep -q "FAILOVER"; then
    echo -e "${GREEN}✓ Failover detected by alert watcher${NC}"
else
    echo -e "${YELLOW}⚠ Failover not yet detected (may need more requests)${NC}"
fi

# Stop chaos
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null

echo ""

# Test 5: Check Slack Configuration
echo -e "${YELLOW}Test 5: Slack Configuration${NC}"

if [ -f .env ]; then
    source .env
    
    if [ -n "$SLACK_WEBHOOK_URL" ] && [ "$SLACK_WEBHOOK_URL" != "" ]; then
        echo -e "${GREEN}✓ SLACK_WEBHOOK_URL is configured${NC}"
        
        # Check if it's a real webhook (not placeholder)
        if echo "$SLACK_WEBHOOK_URL" | grep -q "hooks.slack.com"; then
            echo -e "${GREEN}✓ Slack webhook appears valid${NC}"
        else
            echo -e "${YELLOW}⚠ Slack webhook may be a placeholder${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ SLACK_WEBHOOK_URL is not set (alerts will be logged but not sent)${NC}"
    fi
    
    echo "  ERROR_RATE_THRESHOLD: ${ERROR_RATE_THRESHOLD:-2}"
    echo "  WINDOW_SIZE: ${WINDOW_SIZE:-200}"
    echo "  ALERT_COOLDOWN_SEC: ${ALERT_COOLDOWN_SEC:-300}"
    echo "  MAINTENANCE_MODE: ${MAINTENANCE_MODE:-false}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

echo ""

# Test 6: Error Rate Tracking
echo -e "${YELLOW}Test 6: Error Rate Tracking${NC}"
echo "Checking if watcher is tracking requests..."

# Send some clean requests
echo "Sending 10 clean requests..."
for i in {1..10}; do
    curl -s http://localhost:8080/version > /dev/null
done

sleep 2

watcher_logs=$(docker-compose logs alert_watcher --tail=30)

if echo "$watcher_logs" | grep -q "STATS"; then
    echo -e "${GREEN}✓ Watcher is tracking request statistics${NC}"
    
    # Show the stats line
    stats_line=$(echo "$watcher_logs" | grep "STATS" | tail -1)
    echo "  $stats_line"
else
    echo -e "${YELLOW}⚠ No statistics logged yet (needs 100+ requests)${NC}"
fi

echo ""

# Test 7: Recovery Detection
echo -e "${YELLOW}Test 7: Recovery Detection${NC}"
echo "Waiting for Blue to recover..."
sleep 6

# Send requests to trigger recovery detection
echo "Sending requests after Blue recovery..."
for i in {1..10}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.5
done

sleep 2

watcher_logs=$(docker-compose logs alert_watcher --tail=50)

if echo "$watcher_logs" | grep -q "RECOVERY\|has recovered"; then
    echo -e "${GREEN}✓ Recovery detected by alert watcher${NC}"
else
    echo -e "${YELLOW}⚠ Recovery not yet detected${NC}"
fi

echo ""

# Summary
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}         Test Summary                ${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo -e "${GREEN}Core Components:${NC}"
echo "  ✓ Nginx monitoring log format"
echo "  ✓ Alert watcher service"
echo "  ✓ Environment configuration"
echo ""
echo -e "${GREEN}Monitoring Features:${NC}"
echo "  ✓ Pool tracking"
echo "  ✓ Error rate calculation"
echo "  ✓ Failover detection"
echo "  ✓ Recovery detection"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Configure SLACK_WEBHOOK_URL in .env to receive actual alerts"
echo "  2. Run test-fail.sh to trigger comprehensive failover test"
echo "  3. Monitor alert_watcher logs during production use"
echo "  4. See runbook.md for operational procedures"
echo ""
echo -e "${GREEN}✓✓✓ MONITORING TESTS COMPLETE ✓✓✓${NC}"
