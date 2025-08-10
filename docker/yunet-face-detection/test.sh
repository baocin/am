#!/bin/bash

# YuNet Face Detection API Test Script
# Tests all API endpoints with face images

BASE_URL="http://localhost:8001"
TEST_DIR="test_images"

echo "========================================="
echo "YuNet Face Detection API Test Suite"
echo "========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print test headers
print_test() {
    echo -e "${BLUE}Testing: $1${NC}"
    echo "----------------------------------------"
}

# Check if test_images directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${YELLOW}Warning: $TEST_DIR directory not found!${NC}"
    echo "Creating test_images directory..."
    mkdir -p "$TEST_DIR"
    echo "Please add face1.png and face2.png to the $TEST_DIR directory."
    echo ""
fi

# 1. Health & Info Endpoints
print_test "API Root Info"
curl -X GET "$BASE_URL/"
echo -e "\n"

print_test "Health Check (/health)"
curl -X GET "$BASE_URL/health"
echo -e "\n"

print_test "Health Check (/healthz)"
curl -X GET "$BASE_URL/healthz"
echo -e "\n"

# 2. Face Detection from File Upload
if [ -f "$TEST_DIR/face1.png" ]; then
    print_test "Face Detection from File - face1.png"
    curl -X POST "$BASE_URL/face-detect/" \
      -F "file=@$TEST_DIR/face1.png"
    echo -e "\n"
    
    print_test "Face Detection with custom thresholds - face1.png"
    curl -X POST "$BASE_URL/face-detect/file" \
      -F "file=@$TEST_DIR/face1.png" \
      -F "score_threshold=0.5" \
      -F "nms_threshold=0.4" \
      -F "top_k=100"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/face1.png not found${NC}\n"
fi

if [ -f "$TEST_DIR/face2.png" ]; then
    print_test "Face Detection from File - face2.png"
    curl -X POST "$BASE_URL/face-detect/" \
      -F "file=@$TEST_DIR/face2.png"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/face2.png not found${NC}\n"
fi

# Test with JPEG if available
if [ -f "$TEST_DIR/face1.jpg" ]; then
    print_test "Face Detection from File - face1.jpg (JPEG format)"
    curl -X POST "$BASE_URL/face-detect/" \
      -F "file=@$TEST_DIR/face1.jpg"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/face1.jpg not found${NC}\n"
fi

# 3. Face Detection from Base64
if [ -f "$TEST_DIR/face1.png" ]; then
    print_test "Face Detection from Base64 - face1.png"
    # Create base64 encoded version
    BASE64_CONTENT=$(base64 -i "$TEST_DIR/face1.png" | tr -d '\n')
    curl -X POST "$BASE_URL/face-detect/base64" \
      -H "Content-Type: application/json" \
      -d "{
        \"image_base64\": \"$BASE64_CONTENT\",
        \"score_threshold\": 0.7,
        \"nms_threshold\": 0.3,
        \"top_k\": 5000
      }"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping base64 test: $TEST_DIR/face1.png not found${NC}\n"
fi

# 4. Face Detection from URL
print_test "Face Detection from URL - Sample face image"
curl -X POST "$BASE_URL/face-detect/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg",
    "score_threshold": 0.7,
    "nms_threshold": 0.3,
    "top_k": 5000
  }'
echo -e "\n"

print_test "Face Detection from URL - Group photo"
curl -X POST "$BASE_URL/face-detect/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Beatles_and_Lill-Babs_1963.jpg/640px-Beatles_and_Lill-Babs_1963.jpg",
    "score_threshold": 0.5,
    "nms_threshold": 0.3,
    "top_k": 100
  }'
echo -e "\n"

# 5. Error Handling Tests
print_test "Error Test - Invalid Base64"
curl -X POST "$BASE_URL/face-detect/base64" \
  -H "Content-Type: application/json" \
  -d '{
    "image_base64": "invalid_base64_string",
    "score_threshold": 0.7
  }'
echo -e "\n"

print_test "Error Test - Missing Required Field"
curl -X POST "$BASE_URL/face-detect/base64" \
  -H "Content-Type: application/json" \
  -d '{
    "score_threshold": 0.7
  }'
echo -e "\n"

print_test "Error Test - Invalid URL"
curl -X POST "$BASE_URL/face-detect/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://invalid-url-that-does-not-exist.com/image.jpg"
  }'
echo -e "\n"

# 6. Performance Test
if [ -f "$TEST_DIR/face1.png" ]; then
    print_test "Performance Test - Measure response time"
    time curl -X POST "$BASE_URL/face-detect/" \
      -F "file=@$TEST_DIR/face1.png" \
      -o /dev/null -s -w "\nStatus: %{http_code}\nTime: %{time_total}s\n"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping performance test: $TEST_DIR/face1.png not found${NC}\n"
fi

# 7. Concurrent requests test
if [ -f "$TEST_DIR/face1.png" ]; then
    print_test "Concurrent Requests Test (3 parallel requests)"
    for i in {1..3}; do
      curl -X POST "$BASE_URL/face-detect/" \
        -F "file=@$TEST_DIR/face1.png" \
        -o /dev/null -s -w "Request $i - Status: %{http_code}, Time: %{time_total}s\n" &
    done
    wait
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping concurrent test: $TEST_DIR/face1.png not found${NC}\n"
fi

# 8. Pretty printed JSON response
if [ -f "$TEST_DIR/face1.png" ]; then
    print_test "Face Detection with Pretty JSON Output"
    curl -X POST "$BASE_URL/face-detect/" \
      -F "file=@$TEST_DIR/face1.png" \
      -s | python3 -m json.tool 2>/dev/null || echo "Install python3 for pretty JSON output"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping pretty JSON test: $TEST_DIR/face1.png not found${NC}\n"
fi

# Summary
echo "========================================="
echo -e "${GREEN}Test Suite Complete${NC}"
echo "========================================="
echo ""
echo "Usage Notes:"
echo "1. Make sure the YuNet service is running: docker-compose up"
echo "2. Place test images in $TEST_DIR/ directory:"
echo "   - face1.png: Single face image"
echo "   - face2.png: Multiple faces or different angle"
echo "3. Download YuNet model: ./download_model.sh"
echo "4. Check docker logs for errors: docker logs yunet-face-detection"
echo ""
echo "Quick Tests:"
echo "  ./test.sh                    # Run all tests"
echo "  curl $BASE_URL/health        # Quick health check"
echo "  curl $BASE_URL/docs          # Open API documentation"
echo ""
echo "Required Test Images:"
echo "  $TEST_DIR/face1.png         # Single face test image"
echo "  $TEST_DIR/face2.png         # Multiple faces test image"
echo ""
echo "Model Configuration:"
echo "  - Model: face_detection_yunet_2023mar_int8.onnx"
echo "  - Score Threshold: 0.7"
echo "  - NMS Threshold: 0.3"
echo "  - Top K: 5000"