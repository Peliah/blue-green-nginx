# Monitoring & Alerting Setup Guide

This guide walks you through setting up and testing the operational visibility and alerting system.

## Prerequisites

- Docker and Docker Compose installed
- Access to a Slack workspace (for alerts)
- Application images configured in `.env`

## Quick Setup

### 1. Configure Slack Webhook

To receive alerts in Slack:

1. **Create a Slack App:**
   - Go to https://api.slack.com/apps
   - Click "Create New App" → "From scratch"
   - Give it a name like "Nginx Monitor" and select your workspace

2. **Enable Incoming Webhooks:**
   - In your app settings, go to "Incoming Webhooks"
   - Toggle "Activate Incoming Webhooks" to **On**
   - Click "Add New Webhook to Workspace"
   - Select the channel where you want alerts (e.g., `#alerts`)
   - Click "Allow"

3. **Copy Webhook URL:**
   - You'll see a webhook URL like: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`
   - Copy this URL

4. **Update .env:**
   ```bash
   # Edit .env file
   nano .env
   
   # Set the webhook URL
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

### 2. Start Services

```bash
# Start all services including the alert watcher
docker-compose up -d

# Check that all services are running
docker-compose ps
```

Expected output:
```
NAME            SERVICE         STATUS          PORTS
alert_watcher   alert_watcher   running         
app_blue        app_blue        running (healthy)   0.0.0.0:8081->3000/tcp
app_green       app_green       running (healthy)   0.0.0.0:8082->3000/tcp
nginx_proxy     nginx           running         0.0.0.0:8080->80/tcp
```

### 3. Verify Monitoring

```bash
# Watch alert watcher logs
docker-compose logs -f alert_watcher
```

You should see:
```
[INIT] Alert Watcher starting...
[INIT] Initial active pool: blue
[INIT] Error rate threshold: 2%
[INIT] Window size: 200 requests
[INIT] Alert cooldown: 300s
[INIT] Slack webhook configured: Yes
[TAIL] Waiting for /var/log/nginx/monitoring.log...
[TAIL] Found /var/log/nginx/monitoring.log, starting to monitor...
```

### 4. Test Basic Functionality

```bash
# Send some test requests
for i in {1..5}; do
  curl http://localhost:8080/version
  sleep 1
done

# Check monitoring logs
docker-compose exec nginx tail -10 /var/log/nginx/monitoring.log
```

You should see log entries like:
```
time=2025-10-30T14:23:45+00:00 method=GET uri=/version status=200 pool=blue release=v1.0.0-blue upstream=172.18.0.3:3000 upstream_status=200 request_time=0.012 upstream_response_time=0.010
```

## Testing Alerts

### Test 1: Failover Alert

This test triggers a failover from Blue to Green and verifies you receive a Slack alert.

```bash
# 1. Induce chaos on Blue pool
curl -X POST http://localhost:8081/chaos/start?mode=error

# 2. Generate traffic (this will trigger failover)
for i in {1..20}; do
  curl http://localhost:8080/version
  sleep 0.5
done

# 3. Check Slack channel for failover alert
# You should receive an alert like:
# "⚠️ FAILOVER ALERT
#  Traffic has failed over from blue pool to green pool."

# 4. Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

**Expected Slack Alert:**

```
⚠️ FAILOVER ALERT
Failover Detected

Traffic has failed over from blue pool to green pool.

Previous Pool: blue
Current Pool: green
Total Requests: 23
Timestamp: 2025-10-30 14:23:45 UTC

Action: See runbook.md for response procedures
```

### Test 2: High Error Rate Alert

This test triggers a high error rate alert.

```bash
# 1. Start chaos on Blue (primary)
curl -X POST http://localhost:8081/chaos/start?mode=error

# 2. Also start chaos on Green (backup) to force errors
curl -X POST http://localhost:8082/chaos/start?mode=error

# 3. Generate enough requests to trigger error rate alert
# (needs 200+ requests to fill the window)
for i in {1..250}; do
  curl http://localhost:8080/version
done

# 4. Check Slack for error rate alert
# You should receive an alert about high error rate

# 5. Stop chaos on both
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop
```

**Expected Slack Alert:**

```
⚠️ ERROR_RATE ALERT
Error Rate High

Error rate has exceeded threshold: 100.00% (threshold: 2%)

Error Rate: 100.00%
Threshold: 2%
Window Size: 200 requests
Current Pool: green
Timestamp: 2025-10-30 14:25:12 UTC

Action: See runbook.md for response procedures
```

### Test 3: Recovery Alert

This test verifies recovery detection.

```bash
# 1. After stopping chaos in Test 1, wait for Blue to recover
sleep 6

# 2. Send requests
for i in {1..10}; do
  curl http://localhost:8080/version
  sleep 0.5
done

# 3. Check Slack for recovery alert
# You should receive an alert that primary pool has recovered
```

**Expected Slack Alert:**

```
⚠️ RECOVERY ALERT
Recovery Detected

Primary pool blue has recovered and is now serving traffic.

Pool: blue
Total Requests: 156
Timestamp: 2025-10-30 14:28:30 UTC

Action: See runbook.md for response procedures
```

## Automated Test Script

Run the comprehensive monitoring test:

```bash
./test-monitoring.sh
```

This script will:
- ✓ Verify all services are running
- ✓ Check monitoring log format
- ✓ Verify alert watcher is tracking requests
- ✓ Trigger failover and verify detection
- ✓ Check Slack configuration
- ✓ Test error rate tracking
- ✓ Test recovery detection

## Monitoring in Production

### View Live Logs

**Alert Watcher:**
```bash
docker-compose logs -f alert_watcher
```

**Nginx Monitoring:**
```bash
docker-compose exec nginx tail -f /var/log/nginx/monitoring.log
```

**All Services:**
```bash
docker-compose logs -f
```

### Check Statistics

The alert watcher logs statistics every 100 requests:

```bash
docker-compose logs alert_watcher | grep STATS
```

Output:
```
[STATS] Requests: 100, Errors: 0, Current Pool: blue, Error Rate (window): 0.00%
[STATS] Requests: 200, Errors: 2, Current Pool: blue, Error Rate (window): 1.00%
```

### Verify Alert History

Check alert watcher logs for sent alerts:

```bash
docker-compose logs alert_watcher | grep SLACK
```

Output:
```
[SLACK] failover alert sent successfully
[SLACK] error_rate alert sent successfully
[SLACK] recovery alert sent successfully
```

## Configuration Tuning

### Adjust Error Rate Threshold

For less sensitive alerting:

```bash
# In .env
ERROR_RATE_THRESHOLD=5  # Alert at 5% instead of 2%
WINDOW_SIZE=500         # Larger window for smoother average

# Restart watcher
docker-compose up -d alert_watcher
```

### Adjust Alert Cooldown

To prevent alert spam:

```bash
# In .env
ALERT_COOLDOWN_SEC=600  # 10 minutes between same alert type

# Restart watcher
docker-compose up -d alert_watcher
```

### Enable Maintenance Mode

Suppress alerts during planned operations:

```bash
# In .env
MAINTENANCE_MODE=true

# Restart watcher
docker-compose up -d alert_watcher

# ... perform maintenance ...

# Disable maintenance mode
MAINTENANCE_MODE=false
docker-compose up -d alert_watcher
```

## Troubleshooting

### No Slack Alerts Received

1. **Test webhook manually:**
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test alert from monitoring system"}' \
     https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

2. **Check alert watcher logs:**
   ```bash
   docker-compose logs alert_watcher | grep -E "SLACK|ERROR"
   ```

3. **Verify environment variable:**
   ```bash
   docker-compose exec alert_watcher env | grep SLACK_WEBHOOK_URL
   ```

### Alerts Not Triggering

1. **Check if watcher is running:**
   ```bash
   docker-compose ps alert_watcher
   ```

2. **Check for errors:**
   ```bash
   docker-compose logs alert_watcher | grep ERROR
   ```

3. **Verify monitoring log exists:**
   ```bash
   docker-compose exec nginx ls -l /var/log/nginx/monitoring.log
   ```

4. **Check cooldown:**
   - Alerts have a cooldown period (default 300s)
   - Wait for cooldown to expire before expecting duplicate alerts

### Monitoring Log Empty

1. **Send test requests:**
   ```bash
   for i in {1..5}; do curl http://localhost:8080/version; done
   ```

2. **Check Nginx is writing logs:**
   ```bash
   docker-compose exec nginx cat /var/log/nginx/monitoring.log
   ```

3. **Restart Nginx if needed:**
   ```bash
   docker-compose restart nginx
   ```

## Integration with CI/CD

For automated testing in CI/CD:

```bash
#!/bin/bash

# Start services
docker-compose up -d

# Wait for healthy
sleep 10

# Run monitoring test
./test-monitoring.sh

# Run failover test
./test-fail.sh

# Trigger failover and check for alert
curl -X POST http://localhost:8081/chaos/start?mode=error
for i in {1..20}; do curl http://localhost:8080/version; sleep 0.5; done

# Verify alert was sent
docker-compose logs alert_watcher | grep "FAILOVER" || exit 1
docker-compose logs alert_watcher | grep "alert sent successfully" || exit 1

# Cleanup
curl -X POST http://localhost:8081/chaos/stop
docker-compose down
```

## Summary Checklist

Before considering the setup complete, verify:

- [ ] All services running (`docker-compose ps`)
- [ ] Slack webhook configured in `.env`
- [ ] Monitoring logs being written (`monitoring.log` exists)
- [ ] Alert watcher initialized successfully
- [ ] Failover alert received in Slack
- [ ] Error rate alert received in Slack (optional)
- [ ] Recovery alert received in Slack
- [ ] Runbook documented and accessible
- [ ] Team trained on alert response procedures

## Next Steps

1. **Document in Runbook:** Add team-specific contact info and escalation procedures
2. **Set Up Alert Rotation:** Configure who receives alerts and when
3. **Integrate with Monitoring:** Connect to existing monitoring dashboards
4. **Set Up Log Aggregation:** Forward logs to centralized logging system
5. **Create Alert Dashboards:** Visualize alert trends over time

## Support

For issues or questions:
- See [runbook.md](runbook.md) for operational procedures
- See [README.md](README.md) for general documentation
- Check alert_watcher logs for debugging information
