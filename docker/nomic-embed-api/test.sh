#!/bin/bash

# Nomic Embed Vision API Test Script
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
echo "Nomic Embed Vision API Tests"
echo "Base URL: $BASE_URL"
echo "==================================="

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${YELLOW}Warning: $TEST_DIR directory not found!${NC}"
    echo "Creating test directory with sample files..."
    mkdir -p "$TEST_DIR"
fi

# Test 1: Health Check
echo ""
echo "Running Health Check..."
curl -s "$BASE_URL/health" | jq '.' 2>/dev/null || curl -s "$BASE_URL/health"
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
echo ""
echo "Getting API Info..."
curl -s "$BASE_URL/" | jq '.' 2>/dev/null || curl -s "$BASE_URL/"
run_test "Root Info" \
    "curl -X GET $BASE_URL/" \
    "200" \
    '"service":"Nomic Embed Vision Raw API"'

# Test 4: Text Embedding - Single Text
echo ""
echo "Testing Text Embedding..."
TEXT_REQUEST='{"text":"This is a test sentence for embedding generation.","task":"search_document","normalize":true}'
echo "Request: $TEXT_REQUEST"
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$TEXT_REQUEST" \
    "$BASE_URL/embed/text" | jq '.' 2>/dev/null || \
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$TEXT_REQUEST" \
    "$BASE_URL/embed/text"

run_test "Text Embedding - Single" \
    "curl -X POST -H 'Content-Type: application/json' -d '$TEXT_REQUEST' $BASE_URL/embed/text" \
    "200" \
    '"success":true'

# Test 5: Text Embedding - Batch
echo ""
echo "Testing Batch Text Embedding..."
BATCH_TEXT_REQUEST='{"text":["First sentence","Second sentence","Third sentence"],"task":"search_query","normalize":true}'
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$BATCH_TEXT_REQUEST" \
    "$BASE_URL/embed/text" | jq '.success, .num_embeddings, .embedding_dim' 2>/dev/null

run_test "Text Embedding - Batch" \
    "curl -X POST -H 'Content-Type: application/json' -d '$BATCH_TEXT_REQUEST' $BASE_URL/embed/text" \
    "200" \
    '"num_embeddings":3'

# Test 6: Image Embedding from Base64
if [ -f "$TEST_DIR/test-image.jpg" ]; then
    echo ""
    echo "Testing Image Embedding from Base64..."
    if [ -f "$TEST_DIR/test-base64.txt" ]; then
        IMAGE_BASE64=$(cat "$TEST_DIR/test-base64.txt")
        IMAGE_REQUEST="{\"image_base64\":\"$IMAGE_BASE64\",\"normalize\":true}"
        
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$IMAGE_REQUEST" \
            "$BASE_URL/embed/image/base64" | jq '.success, .embedding_dim' 2>/dev/null
        
        run_test "Image Embedding - Base64" \
            "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"'$(cat $TEST_DIR/test-base64.txt)'\",\"normalize\":true}' $BASE_URL/embed/image/base64" \
            "200" \
            '"success":true'
    fi
else
    echo -e "${YELLOW}SKIPPED${NC} Image Embedding - Base64 (test/test-image.jpg not found)"
fi

# Test 7: Image Embedding from URL
echo ""
echo "Testing Image Embedding from URL..."
URL_REQUEST='{"image_url":"https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg","normalize":true}'
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$URL_REQUEST" \
    "$BASE_URL/embed/image/url" | jq '.success, .embedding_dim' 2>/dev/null

run_test "Image Embedding - URL" \
    "curl -X POST -H 'Content-Type: application/json' -d '$URL_REQUEST' $BASE_URL/embed/image/url" \
    "200" \
    '"success":true'

# Test 8: Multimodal Embedding
echo ""
echo "Testing Multimodal Embedding..."
if [ -f "$TEST_DIR/test-base64.txt" ]; then
    MULTIMODAL_REQUEST="{\"inputs\":[{\"type\":\"text\",\"content\":\"A beautiful landscape\"},{\"type\":\"image\",\"content\":\"$(cat $TEST_DIR/test-base64.txt)\"}],\"normalize\":true}"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$MULTIMODAL_REQUEST" \
        "$BASE_URL/embed/multimodal" | jq '.success, .num_embeddings' 2>/dev/null
    
    run_test "Multimodal Embedding" \
        "curl -X POST -H 'Content-Type: application/json' -d '{\"inputs\":[{\"type\":\"text\",\"content\":\"test\"}],\"normalize\":true}' $BASE_URL/embed/multimodal" \
        "200" \
        '"success":true'
else
    echo -e "${YELLOW}SKIPPED${NC} Multimodal Embedding (test files not found)"
fi

# Test 9: Invalid Request - Empty JSON
echo ""
echo "Testing Error Handling..."
run_test "Empty JSON Request" \
    "curl -X POST -H 'Content-Type: application/json' -d '{}' $BASE_URL/embed/text" \
    "422" \
    ""

# Test 10: Invalid Base64
run_test "Invalid Base64 Image" \
    "curl -X POST -H 'Content-Type: application/json' -d '{\"image_base64\":\"invalid_base64\",\"normalize\":true}' $BASE_URL/embed/image/base64" \
    "200" \
    '"success":false'

# Test 11: Check embedding dimension
if [ -f "$TEST_DIR/test-base64.txt" ]; then
    echo -n "Testing Embedding Dimension Response... "
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"text":"test","normalize":true}' \
        "$BASE_URL/embed/text")
    if echo "$response" | grep -q '"embedding_dim":'; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAILED${NC} (embedding_dim field missing)"
        ((TESTS_FAILED++))
    fi
fi

# Test 12: Processing time check
echo -n "Testing Processing Time in Response... "
response=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"text":"test","normalize":true}' \
    "$BASE_URL/embed/text")
if echo "$response" | grep -q '"processing_time_ms":'; then
    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}FAILED${NC} (processing_time_ms field missing)"
    ((TESTS_FAILED++))
fi

echo ""
echo "==================================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}"
echo "==================================="

# Exit with appropriate code
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1