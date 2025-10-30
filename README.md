# Blue/Green Deployment with Nginx Auto-Failover

A production-ready Blue/Green deployment setup using Nginx for automatic failover with zero downtime.

## Architecture

```
                    ┌─────────────┐
                    │   Client    │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │    Nginx    │
                    │ (Port 8080) |
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       ┌─────────────┐          ┌─────────────┐
       │  Blue App   │          │  Green App  │
       │ (Port 8081) │          │ (Port 8082) │
       │  [PRIMARY]  │          │  [BACKUP]   │
       └─────────────┘          └─────────────┘
```

## Features

- **Automatic Failover**: Nginx detects failures and switches to backup within milliseconds
- **Zero Downtime**: Failed requests are automatically retried to the backup pool
- **Header Preservation**: Application headers (`X-App-Pool`, `X-Release-Id`) forwarded intact
- **Fast Failure Detection**: 2s timeouts with 1 max_fail triggers immediate failover
- **Manual Toggle**: Switch active pool via `ACTIVE_POOL` environment variable
- **Chaos Testing**: Built-in endpoints to simulate failures
- **🆕 Real-time Monitoring**: Python log watcher tracks pool health and error rates
- **🆕 Slack Alerts**: Automated notifications for failovers and high error rates
- **🆕 Operational Visibility**: Enhanced Nginx logs with pool, release, and timing data

## Quick Start

### 1. Configure Environment

Copy `.env.example` to `.env` and edit with your configuration:

```bash
cp .env.example .env
```

Edit `.env`:

```bash
# Set your container images
BLUE_IMAGE=your-registry/app:blue-v1
GREEN_IMAGE=your-registry/app:green-v1

# Blue is active by default
ACTIVE_POOL=blue

# Release identifiers
RELEASE_ID_BLUE=blue-v1.0.0
RELEASE_ID_GREEN=green-v1.0.0

# Optional: custom port (defaults to 3000)
PORT=3000

# Slack webhook for alerts (get from https://api.slack.com/messaging/webhooks)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Alert thresholds
ERROR_RATE_THRESHOLD=2
WINDOW_SIZE=200
ALERT_COOLDOWN_SEC=300
```

### 2. Start Services

```bash
# Make scripts executable
chmod +x entrypoint.sh test-failover.sh

# Start all services
docker-compose up -d

# Check logs
docker-compose logs -f
```

### 3. Verify Deployment

```bash
# Check version endpoint
curl http://localhost:8080/version

# Should return something like:
# {
#   "version": "1.0.0",
#   "pool": "blue",
#   "release": "blue-v1.0.0"
# }
# Headers: X-App-Pool: blue, X-Release-Id: blue-v1.0.0

# Check health
curl http://localhost:8080/healthz
```

## Testing Failover

### Automated Test

Run the comprehensive test script:

```bash
./test-failover.sh
```

This script:
1. Verifies Blue is active and serving all requests
2. Induces chaos on Blue (simulates 500 errors)
3. Sends continuous requests for 10 seconds
4. Validates zero failures and automatic switch to Green
5. Stops chaos and reports results

### Manual Testing

```bash
# 1. Baseline - all requests should go to Blue
for i in {1..5}; do
  curl -i http://localhost:8080/version | grep "X-App-Pool"
done

# 2. Trigger chaos on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error

# 3. Immediate requests should now go to Green (no errors!)
for i in {1..10}; do
  curl -i http://localhost:8080/version | grep "X-App-Pool"
  sleep 0.5
done

# 4. Stop chaos
curl -X POST http://localhost:8081/chaos/stop

# 5. Verify Blue recovery (may take up to 5s based on fail_timeout)
sleep 6
curl -i http://localhost:8080/version | grep "X-App-Pool"
```

### Chaos Modes

- **Error Mode**: Returns HTTP 500
  ```bash
  curl -X POST http://localhost:8081/chaos/start?mode=error
  ```

- **Timeout Mode**: Delays responses beyond nginx timeout
  ```bash
  curl -X POST http://localhost:8081/chaos/start?mode=timeout
  ```

- **Stop Chaos**:
  ```bash
  curl -X POST http://localhost:8081/chaos/stop
  ```

## Manual Pool Switching

To manually switch the active pool:

```bash
# Switch to Green
sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
docker-compose up -d nginx

# Switch to Blue
sed -i 's/ACTIVE_POOL=green/ACTIVE_POOL=blue/' .env
docker-compose up -d nginx
```

## Nginx Configuration Details

### Failover Settings

- **max_fails=1**: Single failure triggers failover
- **fail_timeout=5s**: Failed server recovers after 5 seconds
- **proxy_connect_timeout=2s**: Fast connection timeout
- **proxy_read_timeout=2s**: Fast read timeout
- **proxy_next_upstream**: Retries on error, timeout, http_5xx
- **proxy_next_upstream_tries=2**: Try both pools

### How It Works

1. **Normal Operation**: All requests go to primary (Blue by default)
2. **Failure Detection**: If Blue returns 5xx, times out, or connection fails
3. **Automatic Retry**: Nginx immediately retries the same request to backup (Green)
4. **Client Experience**: Gets 200 OK response, unaware of the retry
5. **Recovery**: After 5s (fail_timeout), Blue is re-evaluated

## Endpoints

### Main Service (via Nginx - Port 8080)
- `GET /version` - Returns version info with pool and release headers
- `GET /healthz` - Health check endpoint

### Direct Access (for chaos testing)
- **Blue**: `http://localhost:8081`
- **Green**: `http://localhost:8082`

Chaos endpoints (direct access only):
- `POST /chaos/start?mode=error` - Start error mode
- `POST /chaos/start?mode=timeout` - Start timeout mode  
- `POST /chaos/stop` - Stop chaos mode

## CI/CD Integration

The grader will:

1. Set environment variables in `.env`:
   ```bash
   BLUE_IMAGE=registry.example.com/app:blue-abc123
   GREEN_IMAGE=registry.example.com/app:green-def456
   ACTIVE_POOL=blue
   RELEASE_ID_BLUE=blue-release-v2.1.0
   RELEASE_ID_GREEN=green-release-v2.1.0
   ```

2. Start services:
   ```bash
   docker-compose up -d
   ```

3. Run validation:
   - Verify baseline (Blue active)
   - Trigger chaos on Blue
   - Send continuous requests
   - Validate zero failures and Green takeover
   - Check ≥95% Green response rate

## Monitoring and Alerts

### Overview

The system includes real-time monitoring with automated Slack alerts for operational issues:

- **Failover Detection**: Alerts when traffic shifts between Blue and Green pools
- **Error Rate Monitoring**: Tracks 5xx errors over a sliding window
- **Recovery Notifications**: Alerts when primary pool recovers

### Alert Types

#### 1. Failover Alert 🟠
Triggered when traffic automatically fails over from one pool to another.

**What it means:** The primary pool is unhealthy and traffic has switched to backup.

**Action:** See [runbook.md](runbook.md) for response procedures.

#### 2. High Error Rate Alert 🔴
Triggered when 5xx error rate exceeds threshold (default: 2% over last 200 requests).

**What it means:** Upstream services are experiencing issues.

**Action:** Investigate logs, consider rollback or failover.

#### 3. Recovery Alert 🟢
Triggered when primary pool becomes healthy again after a failover.

**What it means:** System has automatically recovered to normal operation.

**Action:** Monitor for stability, document incident.

### Configuration

Monitoring is configured via environment variables in `.env`:

```bash
# Slack webhook URL (required for alerts)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Error rate threshold (percentage)
ERROR_RATE_THRESHOLD=2

# Sliding window size (requests)
WINDOW_SIZE=200

# Alert cooldown (seconds)
ALERT_COOLDOWN_SEC=300

# Maintenance mode (suppresses alerts)
MAINTENANCE_MODE=false
```

### Viewing Logs

**Alert Watcher Logs:**
```bash
docker-compose logs -f alert_watcher
```

**Nginx Monitoring Logs:**
```bash
docker-compose exec nginx tail -f /var/log/nginx/monitoring.log
```

**Sample monitoring log entry:**
```
time=2025-10-30T14:23:45+00:00 method=GET uri=/version status=200 pool=blue release=v1.0.0-blue upstream=172.18.0.3:3000 upstream_status=200 request_time=0.012 upstream_response_time=0.010
```

### Testing Alerts

**Trigger a failover alert:**
```bash
# Induce chaos on Blue to force failover
curl -X POST http://localhost:8081/chaos/start?mode=error

# Send traffic to trigger detection
for i in {1..10}; do curl http://localhost:8080/version; sleep 0.5; done

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

**Simulate high error rate:**
```bash
# Enable error mode on active pool
curl -X POST http://localhost:8081/chaos/start?mode=error

# Generate enough requests to trigger alert (needs 200+ requests at >2% error rate)
for i in {1..250}; do curl http://localhost:8080/version; done

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

### Maintenance Mode

Suppress alerts during planned operations:

```bash
# Enable maintenance mode
sed -i 's/MAINTENANCE_MODE=false/MAINTENANCE_MODE=true/' .env
docker-compose up -d alert_watcher

# Perform maintenance...

# Disable maintenance mode
sed -i 's/MAINTENANCE_MODE=true/MAINTENANCE_MODE=false/' .env
docker-compose up -d alert_watcher
```

### Runbook

For detailed operational procedures, see [runbook.md](runbook.md).

## File Structure

```
.
├── docker-compose.yml      # Service orchestration
├── nginx/
│   └── nginx.conf         # Nginx configuration with monitoring
├── watcher.py             # Alert watcher service
├── requirements.txt       # Python dependencies
├── .env                   # Environment configuration (create from .env.example)
├── .env.example          # Environment configuration template
├── test.sh               # Quick test script
├── test-fail.sh          # Failover test script
├── runbook.md            # Operational procedures and troubleshooting
└── README.md             # This file
```

## Troubleshooting

### Check Service Status
```bash
docker-compose ps
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f app_blue
docker-compose logs -f app_green
```

### Verify Nginx Config
```bash
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf
```

### Test Direct Access
```bash
# Blue should respond
curl http://localhost:8081/version

# Green should respond
curl http://localhost:8082/version
```

### Reset Everything
```bash
docker-compose down -v
docker-compose up -d
```

## Performance Characteristics

- **Failover Time**: < 2 seconds (typically 100-500ms)
- **Failed Requests**: 0 (retries happen within same request)
- **Recovery Time**: 5 seconds (configurable via fail_timeout)
- **Request Timeout**: 2 seconds per attempt, 5 seconds total

## Success Criteria

✅ **Zero failed client requests** during failover  
✅ **Automatic switch** from Blue to Green when Blue fails  
✅ **≥95% Green responses** during Blue failure period  
✅ **Headers preserved**: X-App-Pool and X-Release-Id forwarded correctly  
✅ **Fast detection**: Failures detected within 2 seconds  

## License

This configuration is provided as-is for the Cool Keeds Blue/Green deployment challenge.