#!/bin/bash

echo "=== BASELINE TEST ==="
echo "Blue active (should all show X-App-Pool: blue):"
for i in {1..3}; do
  echo "Request $i:"
  curl -s -I http://localhost:8080/version | grep -E "X-App-Pool|X-Release-Id"
done

echo ""
echo "=== CHAOS ERROR MODE TEST ==="
echo "Triggering chaos on Blue..."
curl -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
sleep 1
echo "Rapid requests during chaos (should all be 200 with X-App-Pool: green):"
for i in {1..5}; do
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/version)
  pool=$(curl -s -I http://localhost:8080/version | grep "X-App-Pool" | awk '{print $2}')
  echo "Request $i: Status=$status, X-App-Pool=$pool"
done
echo "Stopping chaos..."
curl -X POST http://localhost:8081/chaos/stop > /dev/null

echo ""
echo "=== RECOVERY TEST ==="
echo "Waiting for fail_timeout window (6 seconds)..."
sleep 6
echo "After chaos (should be back to X-App-Pool: blue):"
curl -s -I http://localhost:8080/version | grep -E "X-App-Pool|X-Release-Id"

echo ""
echo "=== DIRECT PORT ACCESS TEST ==="
echo "Blue direct (8081):"
curl -s -I http://localhost:8081/version | grep -E "X-App-Pool|X-Release-Id"
echo ""
echo "Green direct (8082):"
curl -s -I http://localhost:8082/version | grep -E "X-App-Pool|X-Release-Id"

echo ""
echo "✅ ALL TESTS COMPLETE"