#!/bin/bash

# Unified Docker Services Test Runner
# Tests all Docker services in the docker/* directories
# Ensures containers are running and executes their test.sh scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/home/aoi/code/loomv4/docker"

# Track overall statistics
TOTAL_SERVICES=0
SERVICES_RUNNING=0
SERVICES_FAILED=0
SERVICES_SKIPPED=0
ALL_TESTS_PASSED=0
ALL_TESTS_FAILED=0

# Results storage
declare -A SERVICE_STATUS
declare -A SERVICE_TESTS_PASSED
declare -A SERVICE_TESTS_FAILED
declare -A SERVICE_PORTS
declare -A SERVICE_ERRORS

# Service configurations
declare -A SERVICE_CONFIGS=(
    ["stt-whisper"]="8257"
    ["nomic-embed-api"]="8003"
    ["rapidocr-raw-api"]="8004"
    ["yunet-face-detection-raw-api"]="8002"
    ["voiceapi-raw-api"]="8257"
)

# Function to print section headers
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

# Function to print sub-headers
print_subheader() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to check if port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to get container name from docker-compose.yml
get_container_name() {
    local service_dir=$1
    local compose_file="$service_dir/docker-compose.yml"
    
    if [ -f "$compose_file" ]; then
        # Try to extract container_name from docker-compose.yml
        container_name=$(grep -A5 "container_name:" "$compose_file" | grep "container_name:" | sed 's/.*container_name: *//' | tr -d '"' | tr -d "'" | head -1)
        if [ -z "$container_name" ]; then
            # If no container_name, use service name
            container_name=$(basename "$service_dir")
        fi
        echo "$container_name"
    else
        echo $(basename "$service_dir")
    fi
}

# Function to check if container is running
is_container_running() {
    local container_name=$1
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# Function to start a service
start_service() {
    local service_dir=$1
    local service_name=$(basename "$service_dir")
    
    echo -e "${YELLOW}Starting $service_name...${NC}"
    
    cd "$service_dir"
    
    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}No docker-compose.yml found in $service_dir${NC}"
        return 1
    fi
    
    # Try to start the service
    if docker compose up -d --build 2>&1 | grep -E "(error|Error|ERROR)" > /dev/null; then
        echo -e "${RED}Failed to start $service_name${NC}"
        return 1
    fi
    
    # Wait for service to be ready
    echo -e "${YELLOW}Waiting for $service_name to be ready...${NC}"
    sleep 10
    
    return 0
}

# Function to run tests for a service
run_service_tests() {
    local service_dir=$1
    local service_name=$(basename "$service_dir")
    local port=${SERVICE_CONFIGS[$service_name]:-8000}
    
    SERVICE_PORTS[$service_name]=$port
    
    print_subheader "Testing $service_name (Port: $port)"
    
    cd "$service_dir"
    
    # Check if test.sh exists
    if [ ! -f "test.sh" ]; then
        echo -e "${YELLOW}No test.sh found for $service_name${NC}"
        SERVICE_STATUS[$service_name]="NO_TESTS"
        ((SERVICES_SKIPPED++))
        return 1
    fi
    
    # Make test.sh executable
    chmod +x test.sh
    
    # Check if container is running
    local container_name=$(get_container_name "$service_dir")
    
    if ! is_container_running "$container_name"; then
        echo -e "${YELLOW}Container $container_name is not running. Attempting to start...${NC}"
        
        if ! start_service "$service_dir"; then
            echo -e "${RED}Failed to start $service_name${NC}"
            SERVICE_STATUS[$service_name]="START_FAILED"
            SERVICE_ERRORS[$service_name]="Failed to start container"
            ((SERVICES_FAILED++))
            return 1
        fi
    else
        echo -e "${GREEN}Container $container_name is running${NC}"
    fi
    
    # Check if port is accessible
    if ! check_port $port; then
        echo -e "${RED}Port $port is not accessible for $service_name${NC}"
        SERVICE_STATUS[$service_name]="PORT_NOT_ACCESSIBLE"
        SERVICE_ERRORS[$service_name]="Port $port not accessible"
        ((SERVICES_FAILED++))
        return 1
    fi
    
    # Run the tests
    echo -e "${CYAN}Executing test.sh for $service_name...${NC}"
    echo ""
    
    # Capture test output and results
    test_output=$(BASE_URL="http://localhost:$port" ./test.sh 2>&1)
    test_exit_code=$?
    
    # Parse test results
    tests_passed=$(echo "$test_output" | grep -oP '\d+(?= passed)' | tail -1)
    tests_failed=$(echo "$test_output" | grep -oP '\d+(?= failed)' | tail -1)
    
    # Default to 0 if not found
    tests_passed=${tests_passed:-0}
    tests_failed=${tests_failed:-0}
    
    SERVICE_TESTS_PASSED[$service_name]=$tests_passed
    SERVICE_TESTS_FAILED[$service_name]=$tests_failed
    
    # Update totals
    ALL_TESTS_PASSED=$((ALL_TESTS_PASSED + tests_passed))
    ALL_TESTS_FAILED=$((ALL_TESTS_FAILED + tests_failed))
    
    # Show test summary
    if [ $test_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ $service_name: All tests passed ($tests_passed tests)${NC}"
        SERVICE_STATUS[$service_name]="PASSED"
        ((SERVICES_RUNNING++))
    else
        echo -e "${RED}✗ $service_name: Tests failed (Passed: $tests_passed, Failed: $tests_failed)${NC}"
        SERVICE_STATUS[$service_name]="FAILED"
        ((SERVICES_FAILED++))
        
        # Show last few lines of output for debugging
        echo -e "${YELLOW}Last test output:${NC}"
        echo "$test_output" | tail -20
    fi
    
    return $test_exit_code
}

# Function to generate summary report
generate_summary() {
    print_header "TEST SUMMARY REPORT"
    
    # Overall statistics
    echo ""
    echo -e "${BOLD}Overall Statistics:${NC}"
    echo -e "  Total Services Tested:  ${BOLD}$TOTAL_SERVICES${NC}"
    echo -e "  Services Running:       ${GREEN}$SERVICES_RUNNING${NC}"
    echo -e "  Services Failed:        ${RED}$SERVICES_FAILED${NC}"
    echo -e "  Services Skipped:       ${YELLOW}$SERVICES_SKIPPED${NC}"
    echo -e "  Total Tests Passed:     ${GREEN}$ALL_TESTS_PASSED${NC}"
    echo -e "  Total Tests Failed:     ${RED}$ALL_TESTS_FAILED${NC}"
    
    # Service details table
    echo ""
    echo -e "${BOLD}Service Status Details:${NC}"
    echo -e "${CYAN}┌────────────────────────────┬──────────┬────────────┬─────────────┬─────────────────────┐${NC}"
    echo -e "${CYAN}│ Service                    │ Port     │ Status     │ Tests       │ Notes               │${NC}"
    echo -e "${CYAN}├────────────────────────────┼──────────┼────────────┼─────────────┼─────────────────────┤${NC}"
    
    for service_dir in "$BASE_DIR"/*; do
        if [ -d "$service_dir" ]; then
            service_name=$(basename "$service_dir")
            
            # Skip non-service directories
            if [[ "$service_name" == "test-all-services.sh" ]] || [[ ! -f "$service_dir/docker-compose.yml" ]]; then
                continue
            fi
            
            port=${SERVICE_PORTS[$service_name]:-"N/A"}
            status=${SERVICE_STATUS[$service_name]:-"NOT_RUN"}
            passed=${SERVICE_TESTS_PASSED[$service_name]:-0}
            failed=${SERVICE_TESTS_FAILED[$service_name]:-0}
            error=${SERVICE_ERRORS[$service_name]:-""}
            
            # Format service name (truncate if needed)
            formatted_name=$(printf "%-26s" "$service_name" | cut -c1-26)
            
            # Format status with color
            case $status in
                "PASSED")
                    status_display="${GREEN}✓ PASSED${NC}"
                    tests_display="${GREEN}P:$passed F:$failed${NC}"
                    notes_display="All tests passed"
                    ;;
                "FAILED")
                    status_display="${RED}✗ FAILED${NC}"
                    tests_display="${RED}P:$passed F:$failed${NC}"
                    notes_display="Tests failed"
                    ;;
                "NO_TESTS")
                    status_display="${YELLOW}⚠ NO_TESTS${NC}"
                    tests_display="${YELLOW}N/A${NC}"
                    notes_display="No test.sh found"
                    ;;
                "START_FAILED")
                    status_display="${RED}✗ START_ERR${NC}"
                    tests_display="${RED}N/A${NC}"
                    notes_display="$error"
                    ;;
                "PORT_NOT_ACCESSIBLE")
                    status_display="${RED}✗ PORT_ERR${NC}"
                    tests_display="${RED}N/A${NC}"
                    notes_display="$error"
                    ;;
                *)
                    status_display="${YELLOW}⚠ UNKNOWN${NC}"
                    tests_display="${YELLOW}N/A${NC}"
                    notes_display="Not tested"
                    ;;
            esac
            
            echo -e "${CYAN}│${NC} $formatted_name ${CYAN}│${NC} $(printf "%-8s" "$port") ${CYAN}│${NC} $status_display  ${CYAN}│${NC} $(printf "%-11s" "$tests_display") ${CYAN}│${NC} $(printf "%-19s" "$notes_display" | cut -c1-19) ${CYAN}│${NC}"
        fi
    done
    
    echo -e "${CYAN}└────────────────────────────┴──────────┴────────────┴─────────────┴─────────────────────┘${NC}"
    
    # Final summary
    echo ""
    if [ $SERVICES_FAILED -eq 0 ] && [ $ALL_TESTS_FAILED -eq 0 ] && [ $SERVICES_SKIPPED -eq 0 ]; then
        echo -e "${BOLD}${GREEN}✓ All services are running and all tests passed!${NC}"
        return 0
    elif [ $SERVICES_FAILED -gt 0 ] || [ $ALL_TESTS_FAILED -gt 0 ]; then
        echo -e "${BOLD}${RED}✗ Some services or tests failed. Please review the details above.${NC}"
        return 1
    else
        echo -e "${BOLD}${YELLOW}⚠ Testing completed with warnings. Some services were skipped.${NC}"
        return 2
    fi
}

# Main execution
main() {
    print_header "DOCKER SERVICES UNIFIED TEST RUNNER"
    echo -e "${BOLD}Testing all services in: $BASE_DIR${NC}"
    echo -e "${BOLD}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    # Count total services
    for service_dir in "$BASE_DIR"/*; do
        if [ -d "$service_dir" ] && [ -f "$service_dir/docker-compose.yml" ]; then
            ((TOTAL_SERVICES++))
        fi
    done
    
    echo -e "${BOLD}Found $TOTAL_SERVICES services to test${NC}"
    
    # Test each service
    for service_dir in "$BASE_DIR"/*; do
        if [ -d "$service_dir" ] && [ -f "$service_dir/docker-compose.yml" ]; then
            run_service_tests "$service_dir"
        fi
    done
    
    # Generate and display summary
    generate_summary
    exit_code=$?
    
    # Save report to file
    report_file="$BASE_DIR/test-report-$(date '+%Y%m%d-%H%M%S').txt"
    echo ""
    echo -e "${CYAN}Saving report to: $report_file${NC}"
    
    # Generate text report
    {
        echo "DOCKER SERVICES TEST REPORT"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================="
        echo ""
        echo "SUMMARY:"
        echo "  Total Services: $TOTAL_SERVICES"
        echo "  Running: $SERVICES_RUNNING"
        echo "  Failed: $SERVICES_FAILED"
        echo "  Skipped: $SERVICES_SKIPPED"
        echo "  Tests Passed: $ALL_TESTS_PASSED"
        echo "  Tests Failed: $ALL_TESTS_FAILED"
        echo ""
        echo "SERVICE DETAILS:"
        for service_dir in "$BASE_DIR"/*; do
            if [ -d "$service_dir" ] && [ -f "$service_dir/docker-compose.yml" ]; then
                service_name=$(basename "$service_dir")
                echo "  - $service_name:"
                echo "      Status: ${SERVICE_STATUS[$service_name]:-NOT_RUN}"
                echo "      Port: ${SERVICE_PORTS[$service_name]:-N/A}"
                echo "      Tests Passed: ${SERVICE_TESTS_PASSED[$service_name]:-0}"
                echo "      Tests Failed: ${SERVICE_TESTS_FAILED[$service_name]:-0}"
                if [ -n "${SERVICE_ERRORS[$service_name]}" ]; then
                    echo "      Error: ${SERVICE_ERRORS[$service_name]}"
                fi
            fi
        done
    } > "$report_file"
    
    echo -e "${GREEN}Report saved successfully${NC}"
    echo ""
    
    exit $exit_code
}

# Run main function
main "$@"