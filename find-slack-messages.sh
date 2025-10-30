#!/bin/bash

echo "════════════════════════════════════════"
echo "  Finding Your Slack Messages 🔍"
echo "════════════════════════════════════════"
echo ""

# Get webhook
WEBHOOK=$(grep SLACK_WEBHOOK_URL .env | cut -d'=' -f2)

if [ -z "$WEBHOOK" ]; then
    echo "ERROR: No webhook in .env"
    exit 1
fi

echo "Your webhook: ${WEBHOOK:0:50}..."
echo ""

# Extract workspace and channel info
WORKSPACE=$(echo $WEBHOOK | cut -d'/' -f5)
CHANNEL=$(echo $WEBHOOK | cut -d'/' -f6)

echo "Webhook details:"
echo "  Workspace ID: $WORKSPACE"
echo "  Channel ID: $CHANNEL"
echo ""

echo "════════════════════════════════════════"
echo "  Sending Test Messages"
echo "════════════════════════════════════════"
echo ""

# Send multiple test messages
echo "Sending test message 1 (simple text)..."
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🧪 TEST 1: Simple message from DushaneBOT"}' \
  "$WEBHOOK"
echo ""
sleep 2

echo "Sending test message 2 (with username and emoji)..."
curl -X POST -H 'Content-type: application/json' \
  --data '{"username":"DushaneBOT","icon_emoji":":robot_face:","text":"🧪 TEST 2: Message with bot name"}' \
  "$WEBHOOK"
echo ""
sleep 2

echo "Sending test message 3 (rich message)..."
curl -X POST -H 'Content-type: application/json' \
  --data '{
    "username": "DushaneBOT",
    "icon_emoji": ":robot_face:",
    "text": "🧪 TEST 3: Rich formatted message",
    "attachments": [{
        "color": "#FF9800",
        "title": "Test Alert",
        "text": "If you see this, you found where messages go!",
        "fields": [
            {"title": "Status", "value": "Working", "short": true},
            {"title": "Test", "value": "Success", "short": true}
        ],
        "footer": "DushaneBOT - Alert System"
    }]
  }' \
  "$WEBHOOK"
echo ""
sleep 2

echo ""
echo "════════════════════════════════════════"
echo "  3 Test Messages Sent! ✅"
echo "════════════════════════════════════════"
echo ""
echo "Now check EVERY location in your Slack:"
echo ""
echo "1. 🔍 Use Slack Search:"
echo "   • Click the search bar at the top"
echo "   • Type: DushaneBOT"
echo "   • Press Enter"
echo "   • You should see all messages"
echo ""
echo "2. 📱 Check these locations:"
echo "   • All channels (check each one)"
echo "   • Direct Messages (DMs)"
echo "   • Apps section (bottom of sidebar)"
echo "   • Saved items"
echo "   • Threads"
echo ""
echo "3. 🔔 Check notifications:"
echo "   • Look for the red dot on Slack icon"
echo "   • Check notification center"
echo ""
echo "4. 🌐 Which workspace?"
echo "   • Make sure you're in the RIGHT workspace"
echo "   • Workspace ID: $WORKSPACE"
echo "   • You might have multiple Slack workspaces"
echo ""
echo "════════════════════════════════════════"
echo ""
echo "IMPORTANT: The messages ARE being sent!"
echo "The webhook returns HTTP 200 (success)"
echo "They're somewhere in your Slack workspace"
echo ""
echo "════════════════════════════════════════"
echo ""
echo "Webhook configuration info:"
echo ""
echo "When you created this webhook, you selected:"
echo "  • A specific workspace"
echo "  • A specific channel or DM"
echo ""
echo "To find out where it posts:"
echo "1. Go to: https://api.slack.com/apps"
echo "2. Find your app (the one with this webhook)"
echo "3. Click 'Incoming Webhooks'"
echo "4. Look at the webhook URL's channel"
echo ""
echo "════════════════════════════════════════"
echo ""

# Check alert watcher logs
echo "Recent alerts sent by DushaneBOT:"
echo ""
docker compose logs alert_watcher 2>/dev/null | grep "alert sent successfully" | tail -10 || \
docker-compose logs alert_watcher 2>/dev/null | grep "alert sent successfully" | tail -10

echo ""
echo "════════════════════════════════════════"
echo ""
read -p "Did you find the 3 test messages? (yes/no): " answer

if [ "$answer" = "yes" ]; then
    echo ""
    echo "✅ Great! That's where ALL your alerts go!"
    echo "   Now run: ./test-all-alerts.sh"
    echo "   And check that same location"
else
    echo ""
    echo "Let's check the webhook configuration..."
    echo ""
    echo "Run this command to re-test the webhook:"
    echo "  curl -X POST -H 'Content-type: application/json' --data '{\"text\":\"TEST\"}' \"$WEBHOOK\""
    echo ""
    echo "If it returns 'ok', the webhook works"
    echo "If it returns 'channel_not_found', the webhook is wrong"
    echo ""
    echo "To create a NEW webhook:"
    echo "1. Go to your Slack workspace in browser"
    echo "2. Click your workspace name → Settings & Administration → Manage Apps"
    echo "3. Search for 'Incoming Webhooks'"
    echo "4. Click 'Add to Slack'"
    echo "5. Choose the channel where you WANT messages"
    echo "6. Copy the new webhook URL"
    echo "7. Update .env file"
fi

echo ""
