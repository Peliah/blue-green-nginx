#!/usr/bin/env python3
"""
Nginx Log Watcher - Monitors Nginx logs for failover events and error rate spikes.
Sends alerts to Slack when operational issues are detected.
"""

import os
import sys
import time
import json
import re
from collections import deque
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
import requests


class AlertWatcher:
    """Monitors Nginx logs and sends alerts to Slack."""
    
    def __init__(self):
        # Configuration from environment variables
        self.slack_webhook = os.environ.get('SLACK_WEBHOOK_URL', '')
        self.active_pool = os.environ.get('ACTIVE_POOL', 'blue')
        self.error_threshold = float(os.environ.get('ERROR_RATE_THRESHOLD', '2'))
        self.window_size = int(os.environ.get('WINDOW_SIZE', '200'))
        self.cooldown_sec = int(os.environ.get('ALERT_COOLDOWN_SEC', '300'))
        self.maintenance_mode = os.environ.get('MAINTENANCE_MODE', 'false').lower() == 'true'
        
        # State tracking
        self.last_pool = self.active_pool
        self.request_window = deque(maxlen=self.window_size)
        self.last_failover_alert = None
        self.last_error_rate_alert = None
        self.last_recovery_alert = None
        
        # Statistics
        self.total_requests = 0
        self.total_errors = 0
        
        print(f"[INIT] Alert Watcher starting...")
        print(f"[INIT] Initial active pool: {self.active_pool}")
        print(f"[INIT] Error rate threshold: {self.error_threshold}%")
        print(f"[INIT] Window size: {self.window_size} requests")
        print(f"[INIT] Alert cooldown: {self.cooldown_sec}s")
        print(f"[INIT] Maintenance mode: {self.maintenance_mode}")
        print(f"[INIT] Slack webhook configured: {'Yes' if self.slack_webhook else 'No'}")
        
    def parse_log_line(self, line: str) -> Optional[Dict[str, Any]]:
        """Parse a monitoring log line into structured data."""
        try:
            # Parse key=value format
            data = {}
            # Use regex to handle quoted values and spaces
            pattern = r'(\w+)=([^\s]+(?:\s+[^\s=]+)*?)(?=\s+\w+=|\s*$)'
            matches = re.findall(pattern, line)
            
            for key, value in matches:
                data[key] = value.strip()
            
            # Skip healthcheck requests
            if data.get('uri', '').startswith('/healthz'):
                return None
                
            return data
            
        except Exception as e:
            print(f"[ERROR] Failed to parse log line: {e}")
            return None
    
    def is_error_response(self, status: str, upstream_status: str) -> bool:
        """Check if the response is a server error (5xx)."""
        try:
            # Check both final status and upstream status
            status_code = int(status) if status and status != '-' else 0
            upstream_code = int(upstream_status) if upstream_status and upstream_status != '-' else 0
            
            return status_code >= 500 or upstream_code >= 500
        except (ValueError, TypeError):
            return False
    
    def calculate_error_rate(self) -> float:
        """Calculate current error rate as percentage."""
        if len(self.request_window) == 0:
            return 0.0
        
        error_count = sum(1 for is_error in self.request_window if is_error)
        return (error_count / len(self.request_window)) * 100
    
    def should_send_alert(self, alert_type: str) -> bool:
        """Check if enough time has passed since last alert of this type."""
        if self.maintenance_mode:
            print(f"[MAINTENANCE] Suppressing {alert_type} alert (maintenance mode active)")
            return False
            
        if not self.slack_webhook:
            print(f"[WARN] No Slack webhook configured, skipping {alert_type} alert")
            return False
        
        now = datetime.now()
        last_alert_map = {
            'failover': self.last_failover_alert,
            'error_rate': self.last_error_rate_alert,
            'recovery': self.last_recovery_alert
        }
        
        last_alert = last_alert_map.get(alert_type)
        if last_alert is None:
            return True
            
        time_since_last = (now - last_alert).total_seconds()
        if time_since_last < self.cooldown_sec:
            print(f"[COOLDOWN] Skipping {alert_type} alert ({time_since_last:.0f}s < {self.cooldown_sec}s)")
            return False
            
        return True
    
    def send_slack_alert(self, alert_type: str, message: str, details: Dict[str, Any] = None):
        """Send an alert to Slack."""
        if not self.should_send_alert(alert_type):
            return
        
        # Color coding
        colors = {
            'failover': '#FF9800',  # Orange
            'error_rate': '#F44336',  # Red
            'recovery': '#4CAF50'  # Green
        }
        
        # Build Slack message
        slack_data = {
            "username": "DushaneBOT",
            "icon_emoji": ":robot_face:",
            "text": f":warning: *{alert_type.upper()} ALERT*",
            "attachments": [{
                "color": colors.get(alert_type, '#FF0000'),
                "title": f"{alert_type.replace('_', ' ').title()} Detected",
                "text": message,
                "fields": [],
                "footer": "DushaneBOT - Nginx Alert Watcher",
                "ts": int(time.time())
            }]
        }
        
        # Add details as fields
        if details:
            for key, value in details.items():
                slack_data["attachments"][0]["fields"].append({
                    "title": key,
                    "value": str(value),
                    "short": True
                })
        
        # Add runbook link
        slack_data["attachments"][0]["fields"].append({
            "title": "Action",
            "value": "See runbook.md for response procedures",
            "short": False
        })
        
        try:
            response = requests.post(
                self.slack_webhook,
                json=slack_data,
                headers={'Content-Type': 'application/json'},
                timeout=5
            )
            
            if response.status_code == 200:
                print(f"[SLACK] {alert_type} alert sent successfully")
                # Update last alert time
                now = datetime.now()
                if alert_type == 'failover':
                    self.last_failover_alert = now
                elif alert_type == 'error_rate':
                    self.last_error_rate_alert = now
                elif alert_type == 'recovery':
                    self.last_recovery_alert = now
            else:
                print(f"[ERROR] Slack API returned {response.status_code}: {response.text}")
                
        except Exception as e:
            print(f"[ERROR] Failed to send Slack alert: {e}")
    
    def check_failover(self, current_pool: str):
        """Detect and alert on pool failover."""
        if not current_pool or current_pool == '-':
            return
            
        if current_pool != self.last_pool:
            print(f"[FAILOVER] Pool change detected: {self.last_pool} -> {current_pool}")
            
            message = f"Traffic has failed over from *{self.last_pool}* pool to *{current_pool}* pool."
            details = {
                "Previous Pool": self.last_pool,
                "Current Pool": current_pool,
                "Total Requests": self.total_requests,
                "Timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
            }
            
            self.send_slack_alert('failover', message, details)
            self.last_pool = current_pool
    
    def check_error_rate(self):
        """Check if error rate exceeds threshold and alert."""
        if len(self.request_window) < self.window_size:
            # Don't alert until we have a full window
            return
        
        error_rate = self.calculate_error_rate()
        
        if error_rate > self.error_threshold:
            print(f"[ERROR_RATE] High error rate detected: {error_rate:.2f}% (threshold: {self.error_threshold}%)")
            
            message = f"Error rate has exceeded threshold: *{error_rate:.2f}%* (threshold: {self.error_threshold}%)"
            details = {
                "Error Rate": f"{error_rate:.2f}%",
                "Threshold": f"{self.error_threshold}%",
                "Window Size": f"{self.window_size} requests",
                "Current Pool": self.last_pool,
                "Timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
            }
            
            self.send_slack_alert('error_rate', message, details)
    
    def check_recovery(self, current_pool: str):
        """Check if primary pool has recovered."""
        if not current_pool or current_pool == '-':
            return
            
        # Check if we're back to the expected active pool after being on backup
        if current_pool == self.active_pool and self.last_pool != self.active_pool:
            print(f"[RECOVERY] Primary pool {self.active_pool} has recovered")
            
            message = f"Primary pool *{self.active_pool}* has recovered and is now serving traffic."
            details = {
                "Pool": self.active_pool,
                "Total Requests": self.total_requests,
                "Timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
            }
            
            self.send_slack_alert('recovery', message, details)
    
    def process_log_entry(self, log_data: Dict[str, Any]):
        """Process a single log entry and check for alerts."""
        pool = log_data.get('pool', '-')
        status = log_data.get('status', '-')
        upstream_status = log_data.get('upstream_status', '-')
        
        # Track request
        self.total_requests += 1
        is_error = self.is_error_response(status, upstream_status)
        
        if is_error:
            self.total_errors += 1
        
        # Add to sliding window
        self.request_window.append(is_error)
        
        # Check for alerts
        self.check_failover(pool)
        self.check_recovery(pool)
        self.check_error_rate()
        
        # Periodic stats
        if self.total_requests % 100 == 0:
            error_rate = self.calculate_error_rate()
            print(f"[STATS] Requests: {self.total_requests}, "
                  f"Errors: {self.total_errors}, "
                  f"Current Pool: {pool}, "
                  f"Error Rate (window): {error_rate:.2f}%")
    
    def tail_log_file(self, filepath: str):
        """Tail a log file and process new lines."""
        print(f"[TAIL] Waiting for {filepath}...")
        
        # Wait for file to exist
        while not os.path.exists(filepath):
            time.sleep(1)
        
        print(f"[TAIL] Found {filepath}, starting to monitor...")
        
        with open(filepath, 'r') as f:
            # Move to end of file
            f.seek(0, 2)
            
            while True:
                line = f.readline()
                if line:
                    log_data = self.parse_log_line(line.strip())
                    if log_data:
                        self.process_log_entry(log_data)
                else:
                    time.sleep(0.1)
    
    def run(self):
        """Main run loop."""
        log_file = '/var/log/nginx/monitoring.log'
        
        try:
            self.tail_log_file(log_file)
        except KeyboardInterrupt:
            print("\n[SHUTDOWN] Received interrupt signal")
        except Exception as e:
            print(f"[ERROR] Fatal error: {e}")
            sys.exit(1)


if __name__ == '__main__':
    watcher = AlertWatcher()
    watcher.run()
