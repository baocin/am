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

# Test 4: Face Detection from File
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Detection from File" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'visualize=false' $BASE_URL/detect/file" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection from File (test/test-face.jpg not found)"
    echo "---"
fi

# Test 5: Face Detection with Visualization
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Detection with Visualization" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'visualize=true' $BASE_URL/detect/file" \
        "200" \
        '"visualization_base64":'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection with Visualization (test/test-face.jpg not found)"
    echo "---"
fi

# Test 6: Face Detection from Base64
if [ -f "$TEST_DIR/test-base64.txt" ]; then
    BASE64_DATA=$(cat "$TEST_DIR/test-base64.txt")
    run_test "Face Detection from Base64" \
        "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"'$BASE64_DATA'\",\"visualize\":false}' $BASE_URL/detect/base64" \
        "200" \
        '"success":true'
else
    # Generate base64 from an image if available
    if [ -f "$TEST_DIR/test-face.jpg" ]; then
        BASE64_DATA=$(base64 -w 0 "$TEST_DIR/test-face.jpg" 2>/dev/null || base64 "$TEST_DIR/test-face.jpg")
        run_test "Face Detection from Base64" \
            "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"'$BASE64_DATA'\",\"visualize\":false}' $BASE_URL/detect/base64" \
            "200" \
            '"success":true'
    else
        echo -e "${YELLOW}SKIPPED${NC} Face Detection from Base64 (no test images found)"
        echo "---"
    fi
fi

# Test 7: Face Detection from URL
run_test "Face Detection from URL" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_url\":\"https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg\",\"visualize\":false}' $BASE_URL/detect/url" \
    "200" \
    '"success":true'

# Test 8: Face Detection Batch Processing
if [ -f "$TEST_DIR/test-face.jpg" ] && [ -f "$TEST_DIR/test-data.json" ]; then
    # Create a second test image if not exists
    if [ ! -f "$TEST_DIR/test-face2.jpg" ]; then
        cp "$TEST_DIR/test-face.jpg" "$TEST_DIR/test-face2.jpg" 2>/dev/null || true
    fi
    
    if [ -f "$TEST_DIR/test-face2.jpg" ]; then
        run_test "Face Detection Batch Processing" \
            "curl -X POST -F 'files=@$TEST_DIR/test-face.jpg' -F 'files=@$TEST_DIR/test-face2.jpg' -F 'visualize=false' $BASE_URL/detect/batch" \
            "200" \
            '"results":'
    else
        echo -e "${YELLOW}SKIPPED${NC} Face Detection Batch Processing (unable to create second test image)"
        echo "---"
    fi
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection Batch Processing (test images not found)"
    echo "---"
fi

# Test 9: Face Detection with Confidence Threshold
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Detection with Confidence Threshold" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'confidence_threshold=0.8' -F 'visualize=false' $BASE_URL/detect/file" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Detection with Confidence Threshold (test/test-face.jpg not found)"
    echo "---"
fi

# Test 10: Invalid Request - Empty JSON
run_test "Invalid Request Handling" \
    "curl -X POST -H 'Content-Type: application/json' -d '{}' $BASE_URL/detect/base64" \
    "422" \
    ""

# Test 11: Invalid Base64
run_test "Invalid Base64 Image" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"invalid_base64_data\",\"visualize\":false}' $BASE_URL/detect/base64" \
    "200" \
    '"success":false'

# Test 12: Invalid URL
run_test "Invalid URL" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_url\":\"http://invalid.url/image.jpg\",\"visualize\":false}' $BASE_URL/detect/url" \
    "200" \
    '"success":false'

# Test 13: Processing Time Check
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Processing Time in Response" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'visualize=false' $BASE_URL/detect/file" \
        "200" \
        '"processing_time_ms":'
else
    echo -e "${YELLOW}SKIPPED${NC} Processing Time Check (test images not found)"
    echo "---"
fi

# Test 14: Face Count in Response
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Face Count in Response" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'visualize=false' $BASE_URL/detect/file" \
        "200" \
        '"num_faces":'
else
    echo -e "${YELLOW}SKIPPED${NC} Face Count Check (test images not found)"
    echo "---"
fi

# Test 15: Bounding Box Check
if [ -f "$TEST_DIR/test-face.jpg" ]; then
    run_test "Bounding Box in Response" \
        "curl -X POST -F 'file=@$TEST_DIR/test-face.jpg' -F 'visualize=false' $BASE_URL/detect/file" \
        "200" \
        '"bbox":'
else
    echo -e "${YELLOW}SKIPPED${NC} Bounding Box Check (test images not found)"
    echo "---"
fi

echo "==================================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}"
echo "==================================="

# Exit with appropriate code
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1