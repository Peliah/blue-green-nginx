#!/bin/sh

set -e

# Determine which pool is active and assign backup roles
if [ "$ACTIVE_POOL" = "blue" ]; then
    export BLUE_ROLE=""
    export GREEN_ROLE="backup"
elif [ "$ACTIVE_POOL" = "green" ]; then
    export BLUE_ROLE="backup"
    export GREEN_ROLE=""
else
    echo "ERROR: ACTIVE_POOL must be 'blue' or 'green', got: $ACTIVE_POOL"
    exit 1
fi

echo "=== Nginx Configuration ==="
echo "Active Pool: $ACTIVE_POOL"
echo "Blue Upstream: $BLUE_UPSTREAM (role: ${BLUE_ROLE:-primary})"
echo "Green Upstream: $GREEN_UPSTREAM (role: ${GREEN_ROLE:-primary})"
echo "==========================="

# Use envsubst to replace variables in the template
envsubst '${BLUE_UPSTREAM} ${GREEN_UPSTREAM} ${BLUE_ROLE} ${GREEN_ROLE}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/conf.d/default.conf

# Validate configuration
nginx -t

# Start nginx in foreground
exec nginx -g 'daemon off;'