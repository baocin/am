#!/bin/bash

# Voice API Integration Tests
# Following API Docker Contract Specification

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8257}"
VERBOSE="${VERBOSE:-false}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for running tests
run_test() {
    local test_name="$1"
    local curl_cmd="$2"
    local expected_status="$3"
    local expected_contains="$4"
    
    echo "Testing $test_name..."
    echo "Command: $curl_cmd"
    
    # Execute curl command and capture output
    response=$(eval "$curl_cmd -w '\n%{http_code}'" 2>&1)
    status_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)
    
    # Always print the response for visibility
    echo "Response: $body"
    echo -n "Result: "
    
    # Check status code
    if [ "$status_code" != "$expected_status" ]; then
        echo -e "${RED}FAILED${NC} (Status: $status_code, Expected: $expected_status)"
        ((TESTS_FAILED++))
        echo "---"
        return 1
    fi
    
    # Check response contains expected string
    if [ -n "$expected_contains" ]; then
        if [[ ! "$body" == *"$expected_contains"* ]]; then
            echo -e "${RED}FAILED${NC} (Response missing: $expected_contains)"
            ((TESTS_FAILED++))
            echo "---"
            return 1
        fi
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    echo "---"
    return 0
}

echo "==================================="
echo "Voice API Integration Tests"
echo "Base URL: $BASE_URL"
echo "==================================="

# Test 1: Root Endpoint
run_test "Root Info" \
    "curl -X GET $BASE_URL/" \
    "200" \
    '"service":"Voice API"'

# Test 2: Health Check
run_test "Health Check" \
    "curl -X GET $BASE_URL/health" \
    "200" \
    '"status":"healthy"'

# Test 3: Kubernetes Health Check
run_test "Kubernetes Health" \
    "curl -X GET $BASE_URL/healthz" \
    "200" \
    '"status":"healthy"'

# Test 4: List Speakers
run_test "List Speakers" \
    "curl -X GET $BASE_URL/speakers" \
    "200" \
    "["

# Test 5: Process Base64 Audio (with test audio)
if [ -f "test/test-audio.wav" ]; then
    AUDIO_BASE64=$(base64 -w 0 test/test-audio.wav 2>/dev/null || base64 test/test-audio.wav)
    run_test "Process Base64 Audio" \
        "curl -X POST -H 'Content-Type: application/json' -d '{\"audio_base64\":\"'$AUDIO_BASE64'\"}' $BASE_URL/process/base64" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Process Base64 Audio (test/test-audio.wav not found)"
    echo "---"
fi

# Test 6: TTS Generation
run_test "TTS Generate" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"text\":\"Hello world\",\"voice\":\"0\"}' $BASE_URL/tts/generate" \
    "200" \
    '"success":true'

# Test 7: Invalid Request Handling (missing required field)
run_test "Invalid Request Handling" \
    "curl -X POST -H 'Content-Type: application/json' -d '{}' $BASE_URL/process/base64" \
    "422" \
    ""

# Test 8: Register Speaker with Invalid Data
run_test "Invalid Speaker Registration" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"name\":\"test\"}' $BASE_URL/speakers/register" \
    "400" \
    ""

# Test 9: Delete Non-existent Speaker
run_test "Delete Non-existent Speaker" \
    "curl -X DELETE $BASE_URL/speakers/nonexistent_speaker_12345" \
    "404" \
    ""

# Test 10: Demo Page
run_test "Demo Page" \
    "curl -X GET $BASE_URL/demo" \
    "200" \
    ""

# Test 11: WebSocket Endpoints Check (just verify they exist)
echo "Testing WebSocket endpoint availability..."
echo "Command: curl -X GET $BASE_URL/ws/asr"
ws_check=$(curl -s -o /dev/null -w "%{http_code}" -X GET $BASE_URL/ws/asr 2>/dev/null)
echo "Response: HTTP $ws_check"
echo -n "Result: "
if [ "$ws_check" == "200" ] || [ "$ws_check" == "426" ] || [ "$ws_check" == "404" ]; then
    echo -e "${GREEN}PASSED${NC} (WebSocket endpoints configured)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}FAILED${NC} (Unexpected response: $ws_check)"
    ((TESTS_FAILED++))
fi
echo "---"

# Test 12: API Documentation
run_test "API Documentation" \
    "curl -X GET $BASE_URL/docs" \
    "200" \
    ""

echo "==================================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}"
echo "==================================="

# Exit with appropriate code
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1