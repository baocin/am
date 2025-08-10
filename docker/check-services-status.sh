#!/bin/bash

# Quick Docker Services Status Check
# Shows which services are running and their ports

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Docker Services Status Check${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# Check specific containers
declare -A SERVICES=(
    ["voice-api"]="8257"
    ["nomic-embed-api"]="8003"
    ["rapidocr-raw-api"]="8000"
    ["yunet-face-detection"]="8002"
)

echo "Checking known services..."
echo ""

for container in "${!SERVICES[@]}"; do
    port=${SERVICES[$container]}
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        # Container is running
        status=$(docker ps --filter "name=^${container}$" --format "{{.Status}}")
        echo -e "${GREEN}✓${NC} $container (port $port): ${GREEN}Running${NC} - $status"
        
        # Test health endpoint if available
        if curl -s -f -m 2 "http://localhost:$port/health" > /dev/null 2>&1; then
            echo -e "  └─ Health check: ${GREEN}✓ Healthy${NC}"
        else
            echo -e "  └─ Health check: ${YELLOW}⚠ Not responding${NC}"
        fi
    else
        echo -e "${RED}✗${NC} $container (port $port): ${RED}Not running${NC}"
    fi
done

echo ""
echo "All running containers:"
echo "------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20

echo ""
echo -e "${BLUE}To start a service:${NC}"
echo "  cd /home/aoi/code/loomv4/docker/<service-name>"
echo "  docker compose up -d --build"

echo ""
echo -e "${BLUE}To test all services:${NC}"
echo "  /home/aoi/code/loomv4/docker/test-all-services.sh"