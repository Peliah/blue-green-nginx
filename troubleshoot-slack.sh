#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Slack Alert Troubleshooting Script      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Get webhook from .env file
SLACK_WEBHOOK=$(grep SLACK_WEBHOOK_URL .env | cut -d '=' -f2)

if [ -z "$SLACK_WEBHOOK" ]; then
    echo -e "${RED}✗ SLACK_WEBHOOK_URL not set in .env${NC}"
    echo "Please set it and try again"
    exit 1
fi

# Step 1: Test webhook directly
echo -e "${YELLOW}Step 1: Testing Slack webhook directly...${NC}"
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
  --data '{"text":"🧪 Direct test from troubleshooting script"}' \
  "$SLACK_WEBHOOK")

if [ "$response" = "200" ]; then
    echo -e "${GREEN}✓ Webhook responds with 200 OK${NC}"
    echo -e "${GREEN}  Check your Slack channel - you should see a test message!${NC}"
else
    echo -e "${RED}✗ Webhook returned HTTP $response${NC}"
    echo -e "${RED}  The webhook might be invalid or expired${NC}"
    exit 1
fi
echo ""

# Step 2: Check if services are running
echo -e "${YELLOW}Step 2: Checking Docker services...${NC}"
if ! docker compose ps &> /dev/null && ! docker-compose ps &> /dev/null; then
    echo -e "${RED}✗ Services are not running${NC}"
    echo -e "${YELLOW}  Starting services now...${NC}"
    docker compose up -d || docker-compose up -d
    echo -e "${YELLOW}  Waiting 10 seconds for services to start...${NC}"
    sleep 10
fi

# Check services again
if docker compose ps 2>/dev/null | grep -q "Up" || docker-compose ps 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✓ Services are running${NC}"
    docker compose ps 2>/dev/null || docker-compose ps 2>/dev/null
else
    echo -e "${RED}✗ Services failed to start${NC}"
    exit 1
fi
echo ""

# Step 3: Check alert_watcher logs
echo -e "${YELLOW}Step 3: Checking alert_watcher service...${NC}"
if docker compose ps 2>/dev/null | grep -q "alert_watcher" || docker-compose ps 2>/dev/null | grep -q "alert_watcher"; then
    echo -e "${GREEN}✓ alert_watcher service exists${NC}"
    
    # Check if it's running
    if docker compose ps alert_watcher 2>/dev/null | grep -q "Up" || docker-compose ps alert_watcher 2>/dev/null | grep -q "Up"; then
        echo -e "${GREEN}✓ alert_watcher is running${NC}"
    else
        echo -e "${RED}✗ alert_watcher is not running${NC}"
        echo -e "${YELLOW}  Restarting alert_watcher...${NC}"
        docker compose up -d alert_watcher 2>/dev/null || docker-compose up -d alert_watcher 2>/dev/null
        sleep 5
    fi
else
    echo -e "${RED}✗ alert_watcher service not found${NC}"
    echo -e "${RED}  Make sure you're using the updated docker-compose.yml${NC}"
    exit 1
fi
echo ""

# Step 4: Check watcher initialization
echo -e "${YELLOW}Step 4: Checking alert_watcher initialization...${NC}"
watcher_logs=$(docker compose logs alert_watcher 2>/dev/null || docker-compose logs alert_watcher 2>/dev/null)

if echo "$watcher_logs" | grep -q "Alert Watcher starting"; then
    echo -e "${GREEN}✓ Watcher initialized${NC}"
else
    echo -e "${RED}✗ Watcher not initialized${NC}"
    echo -e "${YELLOW}  Showing last 20 lines of watcher logs:${NC}"
    docker compose logs alert_watcher --tail=20 2>/dev/null || docker-compose logs alert_watcher --tail=20 2>/dev/null
    exit 1
fi

if echo "$watcher_logs" | grep -q "Slack webhook configured: Yes"; then
    echo -e "${GREEN}✓ Slack webhook is configured${NC}"
else
    echo -e "${RED}✗ Slack webhook not configured in watcher${NC}"
    echo -e "${YELLOW}  The watcher may have started before .env was updated${NC}"
    echo -e "${YELLOW}  Restarting alert_watcher...${NC}"
    docker compose restart alert_watcher 2>/dev/null || docker-compose restart alert_watcher 2>/dev/null
    sleep 5
fi

if echo "$watcher_logs" | grep -q "Found /var/log/nginx/monitoring.log"; then
    echo -e "${GREEN}✓ Monitoring log file detected${NC}"
else
    echo -e "${YELLOW}⚠ Monitoring log not found yet${NC}"
    echo -e "${YELLOW}  Sending a test request to create the log...${NC}"
    curl -s http://localhost:8080/version > /dev/null
    sleep 2
fi
echo ""

# Step 5: Check monitoring log exists
echo -e "${YELLOW}Step 5: Checking Nginx monitoring logs...${NC}"
if docker compose exec nginx test -f /var/log/nginx/monitoring.log 2>/dev/null || docker-compose exec nginx test -f /var/log/nginx/monitoring.log 2>/dev/null; then
    echo -e "${GREEN}✓ monitoring.log exists${NC}"
    
    # Send test request
    curl -s http://localhost:8080/version > /dev/null
    sleep 1
    
    # Check log format
    log_entry=$(docker compose exec nginx tail -1 /var/log/nginx/monitoring.log 2>/dev/null || docker-compose exec nginx tail -1 /var/log/nginx/monitoring.log 2>/dev/null)
    
    if echo "$log_entry" | grep -q "pool="; then
        echo -e "${GREEN}✓ Log format is correct${NC}"
        echo -e "${BLUE}  Sample: $(echo "$log_entry" | head -c 100)...${NC}"
    else
        echo -e "${RED}✗ Log format is incorrect${NC}"
        echo -e "${RED}  Log: $log_entry${NC}"
    fi
else
    echo -e "${RED}✗ monitoring.log does not exist${NC}"
    echo -e "${RED}  Nginx may not have the updated configuration${NC}"
    exit 1
fi
echo ""

# Step 6: Trigger a failover and wait for alert
echo -e "${YELLOW}Step 6: Triggering failover to generate alert...${NC}"
echo -e "${BLUE}  This will take about 15 seconds...${NC}"
echo ""

# Start chaos
echo "  → Inducing chaos on Blue pool..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
sleep 2

# Generate traffic
echo "  → Sending 25 requests to trigger failover..."
for i in {1..25}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.3
done

# Wait for detection
echo "  → Waiting for alert watcher to detect and send alert..."
sleep 5

# Check logs for alert
echo ""
echo -e "${YELLOW}Checking for alert activity...${NC}"
recent_logs=$(docker compose logs alert_watcher --tail=50 2>/dev/null || docker-compose logs alert_watcher --tail=50 2>/dev/null)

if echo "$recent_logs" | grep -q "FAILOVER"; then
    echo -e "${GREEN}✓ Failover detected by watcher${NC}"
else
    echo -e "${RED}✗ Failover not detected${NC}"
fi

if echo "$recent_logs" | grep -q "SLACK"; then
    echo -e "${GREEN}✓ Alert sent to Slack${NC}"
    
    if echo "$recent_logs" | grep -q "alert sent successfully"; then
        echo -e "${GREEN}✓✓ Slack confirmed receipt!${NC}"
        echo -e "${GREEN}   CHECK YOUR SLACK CHANNEL NOW!${NC}"
    elif echo "$recent_logs" | grep -q "ERROR.*Slack"; then
        echo -e "${RED}✗ Error sending to Slack${NC}"
        echo "$recent_logs" | grep "ERROR.*Slack"
    fi
else
    echo -e "${YELLOW}⚠ No Slack activity logged${NC}"
    echo -e "${YELLOW}  Possible reasons:${NC}"
    echo -e "${YELLOW}  1. Alert cooldown is active (wait 5 minutes)${NC}"
    echo -e "${YELLOW}  2. Maintenance mode is enabled${NC}"
    echo -e "${YELLOW}  3. Watcher hasn't processed logs yet${NC}"
fi

# Stop chaos
echo ""
echo "  → Stopping chaos..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Diagnostics Complete                     ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Recent watcher logs (last 30 lines):${NC}"
docker compose logs alert_watcher --tail=30 2>/dev/null || docker-compose logs alert_watcher --tail=30 2>/dev/null
echo ""
echo -e "${YELLOW}If you still don't see alerts in Slack:${NC}"
echo "  1. Check the Slack channel/app where the webhook posts"
echo "  2. Verify the webhook isn't expired"
echo "  3. Check for maintenance mode: grep MAINTENANCE_MODE .env"
echo "  4. Wait 5 minutes (cooldown) and try again"
echo "  5. Check watcher logs for errors: docker compose logs alert_watcher"
