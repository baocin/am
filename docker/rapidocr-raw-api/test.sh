#!/bin/bash

# RapidOCR API Test Script
# Collection of curl commands to test all API endpoints

BASE_URL="http://localhost:8000"
TEST_DIR="test_images"

echo "========================================="
echo "RapidOCR API Test Suite"
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
    echo "Run ./test_images_setup.sh to create test images, or create the directory manually."
    echo ""
fi

# 1. Health & Info Endpoints
print_test "API Root Info"
curl -X GET "$BASE_URL/"
echo -e "\n"

print_test "Health Check"
curl -X GET "$BASE_URL/health"
echo -e "\n"

# 2. OCR from File Upload
if [ -f "$TEST_DIR/1.png" ]; then
    print_test "OCR from File - 1.png (without visualization)"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/1.png" \
      -F "visualize=false"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/1.png not found${NC}\n"
fi

if [ -f "$TEST_DIR/2.png" ]; then
    print_test "OCR from File - 2.png (with visualization)"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/2.png" \
      -F "visualize=true"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/2.png not found${NC}\n"
fi

if [ -f "$TEST_DIR/3.png" ]; then
    print_test "OCR from File - 3.png"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/3.png" \
      -F "visualize=false"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/3.png not found${NC}\n"
fi

if [ -f "$TEST_DIR/test.jpg" ]; then
    print_test "OCR from File - test.jpg (JPEG format)"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/test.jpg" \
      -F "visualize=false"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/test.jpg not found${NC}\n"
fi

if [ -f "$TEST_DIR/handwriting.png" ]; then
    print_test "OCR from File - handwriting.png"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/handwriting.png" \
      -F "visualize=false"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/handwriting.png not found${NC}\n"
fi

# 3. OCR from Base64
print_test "OCR from Base64 (small test image)"
curl -X POST "$BASE_URL/ocr/base64" \
  -H "Content-Type: application/json" \
  -d '{
    "image_base64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    "visualize": false
  }'
echo -e "\n"

# If you have a base64 encoded image file
if [ -f "$TEST_DIR/1_base64.txt" ]; then
    print_test "OCR from Base64 - 1.png encoded"
    BASE64_CONTENT=$(cat $TEST_DIR/1_base64.txt)
    curl -X POST "$BASE_URL/ocr/base64" \
      -H "Content-Type: application/json" \
      -d "{
        \"image_base64\": \"$BASE64_CONTENT\",
        \"visualize\": false
      }"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping: $TEST_DIR/1_base64.txt not found${NC}\n"
fi

# 4. OCR from URL
print_test "OCR from URL - RapidOCR test image"
curl -X POST "$BASE_URL/ocr/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://github.com/RapidAI/RapidOCR/blob/main/python/tests/test_files/ch_en_num.jpg?raw=true",
    "visualize": false
  }'
echo -e "\n"

print_test "OCR from URL - Placeholder image with text"
curl -X POST "$BASE_URL/ocr/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://via.placeholder.com/400x200/000000/FFFFFF?text=Test+OCR+Text",
    "visualize": false
  }'
echo -e "\n"

# 5. Error Handling Tests
print_test "Error Test - Invalid Base64"
curl -X POST "$BASE_URL/ocr/base64" \
  -H "Content-Type: application/json" \
  -d '{
    "image_base64": "invalid_base64_string",
    "visualize": false
  }'
echo -e "\n"

print_test "Error Test - Missing Required Field"
curl -X POST "$BASE_URL/ocr/base64" \
  -H "Content-Type: application/json" \
  -d '{
    "visualize": false
  }'
echo -e "\n"

print_test "Error Test - Invalid URL"
curl -X POST "$BASE_URL/ocr/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://invalid-url-that-does-not-exist.com/image.jpg",
    "visualize": false
  }'
echo -e "\n"

# 6. Performance Test with timing
if [ -f "$TEST_DIR/1.png" ]; then
    print_test "Performance Test - Measure response time"
    time curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/1.png" \
      -F "visualize=false" \
      -o /dev/null -s -w "\nStatus: %{http_code}\nTime: %{time_total}s\n"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping performance test: $TEST_DIR/1.png not found${NC}\n"
fi

# 7. Concurrent requests test
if [ -f "$TEST_DIR/1.png" ]; then
    print_test "Concurrent Requests Test (3 parallel requests)"
    for i in {1..3}; do
      curl -X POST "$BASE_URL/ocr/file" \
        -F "file=@$TEST_DIR/1.png" \
        -F "visualize=false" \
        -o /dev/null -s -w "Request $i - Status: %{http_code}, Time: %{time_total}s\n" &
    done
    wait
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping concurrent test: $TEST_DIR/1.png not found${NC}\n"
fi

# 8. Pretty printed JSON response
if [ -f "$TEST_DIR/1.png" ]; then
    print_test "OCR with Pretty JSON Output"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/1.png" \
      -F "visualize=false" \
      -s | python3 -m json.tool 2>/dev/null || echo "Install python3 for pretty JSON output"
    echo -e "\n"
else
    echo -e "${YELLOW}Skipping pretty JSON test: $TEST_DIR/1.png not found${NC}\n"
fi

# 9. Test non-image file error handling
if [ -f "$TEST_DIR/document.pdf" ]; then
    print_test "Error Test - Non-image file (PDF)"
    curl -X POST "$BASE_URL/ocr/file" \
      -F "file=@$TEST_DIR/document.pdf" \
      -F "visualize=false"
    echo -e "\n"
fi

# Summary
echo "========================================="
echo -e "${GREEN}Test Suite Complete${NC}"
echo "========================================="
echo ""
echo "Usage Notes:"
echo "1. Make sure the RapidOCR service is running: docker-compose up"
echo "2. Create test images: ./test_images_setup.sh"
echo "3. All test images should be in the $TEST_DIR/ directory"
echo "4. For base64 tests: base64 $TEST_DIR/1.png > $TEST_DIR/1_base64.txt"
echo "5. Check docker logs for server-side errors: docker logs rapidocr-raw-api"
echo ""
echo "Quick Tests:"
echo "  ./test.sh                    # Run all tests"
echo "  curl $BASE_URL/health        # Quick health check"
echo "  curl $BASE_URL/docs          # Open API documentation"
echo ""
echo "Test Images Expected:"
echo "  $TEST_DIR/1.png             # Test image 1"
echo "  $TEST_DIR/2.png             # Test image 2"
echo "  $TEST_DIR/3.png             # Test image 3"
echo "  $TEST_DIR/test.jpg          # JPEG format test"
echo "  $TEST_DIR/handwriting.png   # Handwriting test"
echo "  $TEST_DIR/1_base64.txt      # Base64 encoded 1.png"