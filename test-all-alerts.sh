#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  DushaneBOT - Complete Alert Test Suite 🤖                ${NC}"
echo -e "${CYAN}  Testing ALL 3 Alert Types                                ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check webhook
WEBHOOK=$(grep SLACK_WEBHOOK_URL .env | cut -d'=' -f2)
if [ -z "$WEBHOOK" ]; then
    echo -e "${RED}ERROR: SLACK_WEBHOOK_URL not set in .env${NC}"
    exit 1
fi

echo -e "${YELLOW}This test will take about 15 minutes due to alert cooldowns${NC}"
echo -e "${YELLOW}You will see 3 different alerts from DushaneBOT in Slack${NC}"
echo ""
read -p "Press ENTER to start..."
echo ""

# ═══════════════════════════════════════════════════════════
# TEST 1: FAILOVER ALERT (Blue → Green)
# ═══════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TEST 1: Failover Alert 🟠                                ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "1. Checking current state..."
pool=$(curl -sI http://localhost:8080/version | grep X-App-Pool | awk '{print $2}' | tr -d '\r')
echo "   Current pool: $pool"
echo ""

echo "2. Triggering chaos on Blue to force failover..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
echo "   ✓ Chaos started"
echo ""

echo "3. Sending traffic to trigger failover..."
for i in {1..20}; do
    curl -s http://localhost:8080/version > /dev/null
    echo -n "."
    sleep 0.5
done
echo " done"
echo ""

echo "4. Waiting for DushaneBOT to detect and send alert (10 seconds)..."
sleep 10

echo ""
echo "5. Checking logs..."
if docker compose logs alert_watcher --tail=30 2>/dev/null | grep -q "failover alert sent successfully" || \
   docker-compose logs alert_watcher --tail=30 2>/dev/null | grep -q "failover alert sent successfully"; then
    echo -e "${GREEN}   ✓✓ FAILOVER ALERT SENT!${NC}"
    echo ""
    echo -e "${GREEN}   📱 CHECK SLACK: You should see a FAILOVER ALERT from DushaneBOT 🤖${NC}"
    echo -e "${GREEN}      Message: 'Traffic has failed over from blue pool to green pool'${NC}"
else
    echo -e "${YELLOW}   ⚠️  Alert might be in cooldown or still processing${NC}"
fi

echo ""
echo "6. Stopping Blue chaos..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null
echo "   ✓ Chaos stopped"
echo ""

read -p "Press ENTER when you've confirmed the FAILOVER alert in Slack..."
echo ""

# ═══════════════════════════════════════════════════════════
# COOLDOWN WAIT 1
# ═══════════════════════════════════════════════════════════

echo -e "${YELLOW}⏳ Waiting 5 minutes for alert cooldown...${NC}"
echo "   (This prevents duplicate alerts)"
for i in {300..1}; do
    mins=$((i/60))
    secs=$((i%60))
    printf "\r   Time remaining: %02d:%02d" $mins $secs
    sleep 1
done
echo ""
echo ""

# ═══════════════════════════════════════════════════════════
# TEST 2: ERROR RATE ALERT
# ═══════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TEST 2: High Error Rate Alert 🔴                         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "1. Starting chaos on BOTH pools to force errors..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
curl -s -X POST http://localhost:8082/chaos/start?mode=error > /dev/null
echo "   ✓ Chaos started on Blue and Green"
echo ""

echo "2. Generating 250 requests to trigger error rate alert..."
echo "   (This will take about 25 seconds)"
for i in {1..250}; do
    curl -s http://localhost:8080/version > /dev/null
    if [ $((i % 25)) -eq 0 ]; then
        echo -n "."
    fi
    sleep 0.1
done
echo " done"
echo ""

echo "3. Waiting for DushaneBOT to detect high error rate (10 seconds)..."
sleep 10

echo ""
echo "4. Checking logs..."
if docker compose logs alert_watcher --tail=30 2>/dev/null | grep -q "error_rate alert sent successfully" || \
   docker-compose logs alert_watcher --tail=30 2>/dev/null | grep -q "error_rate alert sent successfully"; then
    echo -e "${GREEN}   ✓✓ ERROR RATE ALERT SENT!${NC}"
    echo ""
    echo -e "${GREEN}   📱 CHECK SLACK: You should see an ERROR_RATE ALERT from DushaneBOT 🤖${NC}"
    echo -e "${GREEN}      Message: 'Error rate has exceeded threshold'${NC}"
else
    echo -e "${YELLOW}   ⚠️  Alert might be in cooldown or threshold not reached${NC}"
    echo "   Checking error rate..."
    docker compose logs alert_watcher --tail=10 2>/dev/null | grep "ERROR_RATE" || \
    docker-compose logs alert_watcher --tail=10 2>/dev/null | grep "ERROR_RATE"
fi

echo ""
echo "5. Stopping chaos on both pools..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null
curl -s -X POST http://localhost:8082/chaos/stop > /dev/null
echo "   ✓ Chaos stopped"
echo ""

read -p "Press ENTER when you've confirmed the ERROR RATE alert in Slack..."
echo ""

# ═══════════════════════════════════════════════════════════
# COOLDOWN WAIT 2
# ═══════════════════════════════════════════════════════════

echo -e "${YELLOW}⏳ Waiting 5 minutes for alert cooldown...${NC}"
for i in {300..1}; do
    mins=$((i/60))
    secs=$((i%60))
    printf "\r   Time remaining: %02d:%02d" $mins $secs
    sleep 1
done
echo ""
echo ""

# ═══════════════════════════════════════════════════════════
# TEST 3: RECOVERY ALERT (Green → Blue)
# ═══════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TEST 3: Recovery Alert 🟢                                ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "1. Checking current pool..."
pool=$(curl -sI http://localhost:8080/version | grep X-App-Pool | awk '{print $2}' | tr -d '\r')
echo "   Current pool: $pool"

if [ "$pool" != "blue" ]; then
    echo ""
    echo "2. Triggering failover to Green first..."
    curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
    echo "   ✓ Chaos started on Blue"
    
    echo ""
    echo "3. Sending traffic to switch to Green..."
    for i in {1..15}; do
        curl -s http://localhost:8080/version > /dev/null
        sleep 0.5
    done
    echo "   ✓ Traffic sent"
    
    echo ""
    echo "4. Waiting for cooldown (5 minutes)..."
    for i in {300..1}; do
        mins=$((i/60))
        secs=$((i%60))
        printf "\r   Time remaining: %02d:%02d" $mins $secs
        sleep 1
    done
    echo ""
fi

echo ""
echo "5. Stopping Blue chaos to allow recovery..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null
echo "   ✓ Blue chaos stopped"
echo ""

echo "6. Waiting for Blue to recover (10 seconds)..."
sleep 10

echo ""
echo "7. Sending traffic to trigger recovery detection..."
for i in {1..15}; do
    curl -s http://localhost:8080/version > /dev/null
    echo -n "."
    sleep 0.5
done
echo " done"
echo ""

echo "8. Waiting for DushaneBOT to detect recovery (10 seconds)..."
sleep 10

echo ""
echo "9. Checking logs..."
if docker compose logs alert_watcher --tail=30 2>/dev/null | grep -q "recovery alert sent successfully" || \
   docker-compose logs alert_watcher --tail=30 2>/dev/null | grep -q "recovery alert sent successfully"; then
    echo -e "${GREEN}   ✓✓ RECOVERY ALERT SENT!${NC}"
    echo ""
    echo -e "${GREEN}   📱 CHECK SLACK: You should see a RECOVERY ALERT from DushaneBOT 🤖${NC}"
    echo -e "${GREEN}      Message: 'Primary pool blue has recovered'${NC}"
else
    echo -e "${YELLOW}   ⚠️  Recovery alert might not have triggered${NC}"
    echo "   Current pool:"
    curl -sI http://localhost:8080/version | grep X-App-Pool
fi

echo ""
echo ""

# ═══════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Test Complete! 🎉                                         ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}You should now have 3 alerts from DushaneBOT in Slack:${NC}"
echo ""
echo "  🟠 FAILOVER ALERT"
echo "     'Traffic has failed over from blue pool to green pool'"
echo ""
echo "  🔴 ERROR_RATE ALERT"
echo "     'Error rate has exceeded threshold: X%'"
echo ""
echo "  🟢 RECOVERY ALERT"
echo "     'Primary pool blue has recovered and is now serving traffic'"
echo ""
echo -e "${YELLOW}📸 Take screenshots of all 3 alerts for your submission!${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Show final logs
echo "Recent alert activity:"
docker compose logs alert_watcher --tail=50 2>/dev/null | grep -E "FAILOVER|ERROR_RATE|RECOVERY|SLACK" || \
docker-compose logs alert_watcher --tail=50 2>/dev/null | grep -E "FAILOVER|ERROR_RATE|RECOVERY|SLACK"
