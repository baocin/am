#!/bin/bash

# Monitor WebSocket connections in ingestion API
echo "Monitoring WebSocket connections..."
echo "================================="

# Get container ID
CONTAINER_ID=$(docker ps --filter "name=loomv2-ingestion-api" --format "{{.ID}}")

if [ -z "$CONTAINER_ID" ]; then
    echo "Error: loomv2-ingestion-api container not found"
    exit 1
fi

# Monitor logs with timestamp
docker logs -f --tail 50 "$CONTAINER_ID" 2>&1 | \
    grep -E "(WebSocket|connected|disconnected|closed|Health check|pong)" | \
    while IFS= read -r line; do
        echo "[$(date '+%H:%M:%S')] $line"
    done