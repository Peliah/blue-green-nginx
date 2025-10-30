# Slack Alert Troubleshooting Guide

## Your Webhook
```
Set in your local .env file - do not commit to git!
```

## Quick Fix Steps

### Step 1: Test Webhook Directly
Run this to verify the webhook works:

```bash
# Replace YOUR_WEBHOOK_URL with your actual webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🧪 Testing webhook"}' \
  YOUR_WEBHOOK_URL
```

**✅ Expected:** You should see a message in your Slack channel  
**❌ If not:** The webhook might be invalid or you're checking the wrong channel

### Step 2: Restart Services with New Webhook

The `.env` file has been updated with your webhook. Now restart the alert_watcher:

```bash
# Restart the watcher to pick up the new webhook URL
docker compose restart alert_watcher

# Or if using docker-compose (older version)
docker-compose restart alert_watcher

# Wait for it to initialize
sleep 5

# Check if it picked up the webhook
docker compose logs alert_watcher | grep webhook
```

**✅ Expected:** You should see `Slack webhook configured: Yes`

### Step 3: Use the Quick Test Script

```bash
./test-slack-quick.sh
```

This will:
1. Test the webhook directly
2. Restart the watcher
3. Trigger a failover
4. Generate an alert

**✅ Expected:** You should see 2 messages in Slack:
- Test message
- Failover alert

### Step 4: Use the Full Troubleshooting Script

```bash
./troubleshoot-slack.sh
```

This runs comprehensive diagnostics and tells you exactly what's wrong.

## Common Issues and Fixes

### Issue 1: Services Not Running

**Check:**
```bash
docker compose ps
# or
docker-compose ps
```

**Fix:**
```bash
docker compose up -d
# or
docker-compose up -d
```

### Issue 2: Alert Watcher Started Before .env Update

**Symptom:** Logs show `Slack webhook configured: No`

**Fix:**
```bash
# Restart the watcher
docker compose restart alert_watcher

# Verify it picked up the webhook
docker compose logs alert_watcher | grep "webhook configured"
```

### Issue 3: Monitoring Log Doesn't Exist

**Symptom:** Watcher logs show "Waiting for /var/log/nginx/monitoring.log"

**Fix:**
```bash
# Send a request to create the log
curl http://localhost:8080/version

# Wait a moment
sleep 2

# Check if log was created
docker compose exec nginx ls -la /var/log/nginx/monitoring.log
```

### Issue 4: Alert Cooldown Active

**Symptom:** No alert sent even though failover detected

**Explanation:** Alerts have a cooldown period (default: 300 seconds / 5 minutes) to prevent spam.

**Fix:**
- Wait 5 minutes between tests
- Or check logs: `docker compose logs alert_watcher | grep COOLDOWN`

### Issue 5: Maintenance Mode Enabled

**Check:**
```bash
grep MAINTENANCE_MODE .env
```

**Fix:**
```bash
# Should be false
sed -i 's/MAINTENANCE_MODE=true/MAINTENANCE_MODE=false/' .env
docker compose restart alert_watcher
```

### Issue 6: Wrong Slack Channel

**Issue:** Alerts are being sent, but you're checking the wrong Slack channel

**Fix:**
- Check which channel the webhook posts to
- Look at all channels in your Slack workspace
- The webhook typically posts to a specific channel that was selected during webhook creation

## Manual Failover Test (Step by Step)

If the scripts don't work, try manually:

```bash
# 1. Make sure services are running
docker compose up -d

# 2. Restart watcher with new webhook
docker compose restart alert_watcher
sleep 5

# 3. Verify watcher is initialized
docker compose logs alert_watcher --tail=20

# You should see:
#   [INIT] Alert Watcher starting...
#   [INIT] Slack webhook configured: Yes
#   [TAIL] Found /var/log/nginx/monitoring.log

# 4. Check current serving pool
curl -I http://localhost:8080/version | grep X-App-Pool
# Should show: X-App-Pool: blue

# 5. Start chaos on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error
echo "Chaos started"

# 6. Send requests (one at a time to see progress)
for i in {1..20}; do
  echo "Request $i..."
  pool=$(curl -sI http://localhost:8080/version | grep X-App-Pool | tr -d '\r')
  echo "  $pool"
  sleep 0.5
done

# 7. Wait for alert
echo "Waiting for alert to be sent..."
sleep 5

# 8. Check watcher logs
docker compose logs alert_watcher --tail=30

# Look for:
#   [FAILOVER] Pool change detected: blue -> green
#   [SLACK] failover alert sent successfully

# 9. Stop chaos
curl -X POST http://localhost:8081/chaos/stop
echo "Chaos stopped"

# 10. Check Slack channel
echo ""
echo "CHECK YOUR SLACK CHANNEL NOW!"
echo ""
```

## Viewing Live Logs

Watch the alert_watcher in real-time:

```bash
docker compose logs -f alert_watcher
```

Then in another terminal, trigger a failover:

```bash
curl -X POST http://localhost:8081/chaos/start?mode=error
for i in {1..20}; do curl http://localhost:8080/version; sleep 0.5; done
curl -X POST http://localhost:8081/chaos/stop
```

## Debugging Checklist

Run through this checklist:

- [ ] Webhook test returns "ok": `curl -X POST ... (returns "ok")`
- [ ] Services are running: `docker compose ps` shows all "Up"
- [ ] Alert watcher is running: `docker compose ps alert_watcher` shows "Up"
- [ ] Webhook configured in watcher: logs show "Slack webhook configured: Yes"
- [ ] Monitoring log exists: `docker compose exec nginx ls /var/log/nginx/monitoring.log`
- [ ] Monitoring log has correct format: logs show `pool=` field
- [ ] No cooldown active: wait 5 minutes between tests
- [ ] Maintenance mode disabled: `MAINTENANCE_MODE=false` in .env
- [ ] Failover detected: logs show `[FAILOVER]`
- [ ] Alert sent: logs show `[SLACK] failover alert sent successfully`

## What You Should See in Slack

When it works, you'll see a message like this:

```
⚠️ FAILOVER ALERT
Failover Detected

Traffic has failed over from blue pool to green pool.

Previous Pool: blue
Current Pool: green
Total Requests: 23
Timestamp: 2025-10-30 15:45:12 UTC

Action: See runbook.md for response procedures
```

## Still Not Working?

### Check Exact Error

```bash
# Get full watcher logs
docker compose logs alert_watcher > watcher_logs.txt

# Search for errors
grep -i error watcher_logs.txt

# Search for Slack activity
grep -i slack watcher_logs.txt

# Search for failover detection
grep -i failover watcher_logs.txt
```

### Verify Watcher Code

```bash
# Check if watcher.py exists
ls -la watcher.py

# Verify it's being mounted
docker compose exec alert_watcher ls -la /app/watcher.py
```

### Restart Everything

```bash
# Nuclear option - restart everything
docker compose down
docker compose up -d

# Wait for services to be healthy
sleep 15

# Try again
./test-slack-quick.sh
```

## Get Help

If still not working, share:

1. Output of: `docker compose logs alert_watcher`
2. Output of: `docker compose ps`
3. Output of: `curl -I http://localhost:8080/version`
4. Whether the direct webhook test worked
5. Which Slack channel you're checking

## Alternative: Test Without Failover

If failover is complex, test error rate alert instead:

```bash
# Start chaos on BOTH pools
curl -X POST http://localhost:8081/chaos/start?mode=error
curl -X POST http://localhost:8082/chaos/start?mode=error

# Generate 250 requests to trigger error rate alert
for i in {1..250}; do
  curl -s http://localhost:8080/version > /dev/null
done

# Wait for alert
sleep 5

# Check logs
docker compose logs alert_watcher | grep ERROR_RATE

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop
```

This should trigger an error rate alert if everything is working.
