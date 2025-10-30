#!/bin/bash

echo "════════════════════════════════════════"
echo "  DushaneBOT Slack Diagnostics"
echo "════════════════════════════════════════"
echo ""

# Step 1: Check webhook in .env
echo "1. Checking webhook configuration..."
if grep -q "SLACK_WEBHOOK_URL=https://" .env; then
    echo "   ✓ Webhook URL is set in .env"
    WEBHOOK=$(grep SLACK_WEBHOOK_URL .env | cut -d'=' -f2)
    echo "   Webhook: ${WEBHOOK:0:50}..."
else
    echo "   ✗ NO WEBHOOK in .env!"
    echo ""
    echo "   FIX: Add your webhook to .env:"
    echo "   nano .env"
    echo "   Then add: SLACK_WEBHOOK_URL=https://hooks.slack.com/services/..."
    exit 1
fi
echo ""

# Step 2: Test webhook directly
echo "2. Testing webhook directly..."
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H 'Content-type: application/json' \
  --data '{"text":"🧪 Direct test from DushaneBOT - If you see this, webhook works!"}' \
  "$WEBHOOK")

if [ "$response" = "200" ]; then
    echo "   ✓ Webhook test successful (HTTP 200)"
    echo "   → CHECK SLACK NOW for test message!"
else
    echo "   ✗ Webhook returned HTTP $response"
    echo "   The webhook might be invalid or expired"
    exit 1
fi
echo ""

# Step 3: Check alert_watcher status
echo "3. Checking alert_watcher service..."
if docker compose ps alert_watcher 2>/dev/null | grep -q "Up" || docker-compose ps alert_watcher 2>/dev/null | grep -q "Up"; then
    echo "   ✓ alert_watcher is running"
else
    echo "   ✗ alert_watcher is NOT running"
    echo "   Starting it now..."
    docker compose up -d alert_watcher 2>/dev/null || docker-compose up -d alert_watcher 2>/dev/null
    sleep 5
fi
echo ""

# Step 4: Check if watcher has webhook
echo "4. Checking if alert_watcher sees the webhook..."
logs=$(docker compose logs alert_watcher 2>/dev/null || docker-compose logs alert_watcher 2>/dev/null)

if echo "$logs" | grep -q "Slack webhook configured: Yes"; then
    echo "   ✓ Watcher has webhook configured"
elif echo "$logs" | grep -q "Slack webhook configured: No"; then
    echo "   ✗ Watcher does NOT have webhook!"
    echo "   This means it started before .env was updated"
    echo ""
    echo "   FIXING: Restarting alert_watcher..."
    docker compose restart alert_watcher 2>/dev/null || docker-compose restart alert_watcher 2>/dev/null
    sleep 5
    echo "   ✓ Restarted"
    
    # Check again
    new_logs=$(docker compose logs alert_watcher --tail=20 2>/dev/null || docker-compose logs alert_watcher --tail=20 2>/dev/null)
    if echo "$new_logs" | grep -q "Slack webhook configured: Yes"; then
        echo "   ✓ NOW webhook is configured!"
    else
        echo "   ✗ Still no webhook - check your .env file"
        exit 1
    fi
else
    echo "   ? Cannot determine webhook status"
fi
echo ""

# Step 5: Trigger failover
echo "5. Triggering failover to generate alert..."
echo "   Starting chaos on Blue..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null

echo "   Sending 25 requests (this will take ~12 seconds)..."
for i in {1..25}; do
    curl -s http://localhost:8080/version > /dev/null
    if [ $((i % 5)) -eq 0 ]; then
        echo -n "."
    fi
    sleep 0.5
done
echo " done"

echo "   Waiting for DushaneBOT to detect and alert..."
sleep 5

# Step 6: Check logs
echo ""
echo "6. Checking alert_watcher activity..."
recent_logs=$(docker compose logs alert_watcher --tail=40 2>/dev/null || docker-compose logs alert_watcher --tail=40 2>/dev/null)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Recent Alert Watcher Logs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$recent_logs" | tail -20
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 7: Check for specific events
if echo "$recent_logs" | grep -q "FAILOVER.*Pool change detected"; then
    echo "   ✓ Failover was DETECTED"
else
    echo "   ✗ Failover was NOT detected"
fi

if echo "$recent_logs" | grep -q "\[SLACK\]"; then
    echo "   ✓ Slack alert activity logged"
    
    if echo "$recent_logs" | grep -q "alert sent successfully"; then
        echo "   ✓✓ ALERT SENT SUCCESSFULLY!"
        echo ""
        echo "   🎉 CHECK YOUR SLACK CHANNEL NOW!"
        echo "   You should see a message from DushaneBOT 🤖"
    elif echo "$recent_logs" | grep -q "COOLDOWN"; then
        echo "   ⚠️  Alert was in COOLDOWN period"
        echo "   You need to wait 5 minutes between alerts"
        echo "   The last alert was sent too recently"
    elif echo "$recent_logs" | grep -q "No Slack webhook"; then
        echo "   ✗ Watcher says no webhook configured"
        echo "   Run: docker compose restart alert_watcher"
    fi
else
    echo "   ✗ No Slack activity in logs"
    echo ""
    echo "   Possible reasons:"
    echo "   • Cooldown active (wait 5 minutes)"
    echo "   • Maintenance mode enabled"
    echo "   • Watcher hasn't processed logs yet"
fi

# Stop chaos
echo ""
echo "7. Stopping chaos..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null
echo "   ✓ Chaos stopped"

echo ""
echo "════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════"
echo ""
echo "What to check in Slack:"
echo "  1. Direct test message (should already be there)"
echo "  2. FAILOVER ALERT from DushaneBOT 🤖"
echo ""
echo "If you still don't see alerts:"
echo "  • Check which Slack channel the webhook posts to"
echo "  • Look in ALL channels (might not be in main)"
echo "  • Check DMs/Apps"
echo "  • Wait 5 minutes and run: ./test-slack-quick.sh"
echo ""
