#!/bin/bash

# YuNet Face Detection API Test Script
# Follows api-docker-contract.md standards

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8000}"
VERBOSE="${VERBOSE:-false}"
TEST_DIR="test"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for running tests
run_test() {
    local test_name="$1"
    local curl_cmd="$2"
    local expected_status="$3"
    local expected_contains="$4"
    
    echo -n "Testing $test_name... "
    
    # Execute curl command
    if [ "$VERBOSE" == "true" ]; then
        response=$(eval "$curl_cmd -w '\n%{http_code}'" 2>&1)
        status_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | head -n -1)
    else
        response=$(eval "$curl_cmd -w '\n%{http_code}' -s" 2>&1)
        status_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | head -n -1)
    fi
    
    # Check status code
    if [ "$status_code" != "$expected_status" ]; then
        echo -e "${RED}FAILED${NC} (Status: $status_code, Expected: $expected_status)"
        [ "$VERBOSE" == "true" ] && echo "Response: $body"
        ((TESTS_FAILED++))
        return 1
    fi
    
    # Check response contains expected string
    if [ -n "$expected_contains" ]; then
        if [[ ! "$body" == *"$expected_contains"* ]]; then
            echo -e "${RED}FAILED${NC} (Response missing: $expected_contains)"
            [ "$VERBOSE" == "true" ] && echo "Response: $body"
            ((TESTS_FAILED++))
            return 1
        fi
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    return 0
}

echo "==================================="
echo "YuNet Face Detection API Tests"
echo "Base URL: $BASE_URL"
echo "==================================="

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${YELLOW}Warning: $TEST_DIR directory not found!${NC}"
    echo "Creating test directory with sample files..."
    mkdir -p "$TEST_DIR"
fi

# Test 1: Health Check
run_test "Health Check" \
    "curl -X GET $BASE_URL/health" \
    "200" \
    '"status":"healthy"'

# Test 2: Alternative Health Check (Kubernetes-style)
run_test "Health Check (K8s)" \
    "curl -X GET $BASE_URL/healthz" \
    "200" \
    '"status":"healthy"'

# Test 3: Root Endpoint
run_test "Root Info" \
    "curl -X GET $BASE_URL/" \
    "200" \
    '"service":"YuNet Face Detection Raw API"'

# Test 4: File Upload - Valid Image
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Detection - File Upload" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' $BASE_URL/face-detect/file" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection - File Upload (test/test-face.jpg not found)"
fi

# Test 5: File Upload with Parameters
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Detection - File with Params" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'score_threshold=0.5' -F 'visualize=true' $BASE_URL/face-detect/file" \
        "200" \
        '"success":true'
fi

# Test 6: Base64 Request
if [ -f "$TEST_DIR/test-base64.txt" ]; then
    run_test "Face Detection - Base64" \
        "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"'$(cat $TEST_DIR/test-base64.txt)'\"}' $BASE_URL/face-detect/base64" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection - Base64 (test/test-base64.txt not found)"
fi

# Test 7: URL Request (using sample image)
run_test "Face Detection - URL (Lena)" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_url\":\"https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg\"}' $BASE_URL/face-detect/url" \
    "200" \
    '"success":true'

# Test 8: Invalid Base64 Request
run_test "Invalid Base64 Request" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"invalid_base64\"}' $BASE_URL/face-detect/base64" \
    "200" \
    '"success":false'

# Test 9: Empty JSON Request (Should fail with 422)
run_test "Empty JSON Request" \
    "curl -X POST -H 'Content-Type: application/json' -d '{}' $BASE_URL/face-detect/base64" \
    "422" \
    ""

# Test 10: Invalid URL
run_test "Invalid URL Request" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_url\":\"https://invalid-url-that-does-not-exist.com/image.jpg\"}' $BASE_URL/face-detect/url" \
    "200" \
    '"success":false'

# Test 11: Check for face count in response
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    echo -n "Testing Face Count Response... "
    response=$(curl -s -X POST -F "file=@$TEST_DIR/test-face.jpg" "$BASE_URL/face-detect/file")
    if echo "$response" | grep -q '"face_count":'; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAILED${NC} (face_count field missing)"
        ((TESTS_FAILED++))
    fi
fi

# Test 12: Processing time check
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    echo -n "Testing Processing Time in Response... "
    response=$(curl -s -X POST -F "file=@$TEST_DIR/test-face.jpg" "$BASE_URL/face-detect/file")
    if echo "$response" | grep -q '"processing_time_ms":'; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAILED${NC} (processing_time_ms field missing)"
        ((TESTS_FAILED++))
    fi
fi

echo "==================================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}"
echo "==================================="

# Exit with appropriate code
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1