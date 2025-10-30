#!/bin/bash

echo "════════════════════════════════════════"
echo "  Quick Slack Alert Test"
echo "════════════════════════════════════════"
echo ""

# Test webhook
echo "1. Getting webhook from .env..."
SLACK_WEBHOOK=$(grep SLACK_WEBHOOK_URL .env | cut -d '=' -f2)

if [ -z "$SLACK_WEBHOOK" ]; then
    echo "ERROR: SLACK_WEBHOOK_URL not set in .env"
    echo "Please add your webhook URL to .env and try again"
    exit 1
fi

echo "2. Testing webhook directly..."
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"✅ Test 1: Direct webhook test"}' \
  "$SLACK_WEBHOOK"

echo ""
echo "   → Check Slack now for 'Test 1' message"
echo ""

# Restart watcher with new webhook
echo "3. Restarting alert_watcher with webhook..."
docker compose restart alert_watcher 2>/dev/null || docker-compose restart alert_watcher 2>/dev/null
sleep 5

echo "4. Checking watcher configuration..."
docker compose logs alert_watcher --tail=10 2>/dev/null || docker-compose logs alert_watcher --tail=10 2>/dev/null | grep -E "INIT|webhook"

echo ""
echo "5. Triggering failover..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
echo "   Chaos started on Blue"

echo ""
echo "6. Sending traffic (20 requests over 10 seconds)..."
for i in {1..20}; do
    curl -s http://localhost:8080/version > /dev/null
    echo -n "."
    sleep 0.5
done
echo " done"

echo ""
echo "7. Waiting for alert (5 seconds)..."
sleep 5

echo ""
echo "7. Checking for alert activity..."
docker compose logs alert_watcher --tail=20 2>/dev/null || docker-compose logs alert_watcher --tail=20 2>/dev/null

echo ""
echo "9. Stopping chaos..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null

echo ""
echo "════════════════════════════════════════"
echo "  CHECK YOUR SLACK CHANNEL NOW!"
echo "════════════════════════════════════════"
echo ""
echo "You should see:"
echo "  ✅ Test 1: Direct webhook test"
echo "  ⚠️  FAILOVER ALERT (if watcher is working)"
echo ""
echo "If you only see Test 1, check:"
echo "  → docker compose logs alert_watcher"
echo ""
