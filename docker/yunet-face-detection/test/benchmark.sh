#!/bin/bash

# Performance benchmark script for YuNet Face Detection API
BASE_URL="${BASE_URL:-http://localhost:8002}"

echo "Running performance benchmark..."
echo "================================="

# Test 1: Single request timing
echo "Single request performance:"
time curl -s -X POST \
  -F "file=@test-face.jpg" \
  "$BASE_URL/face-detect/file" \
  -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n"

echo ""

# Test 2: Concurrent requests test
echo "Testing 10 concurrent requests..."
for i in {1..10}; do
  curl -s -X POST \
    -F "file=@test-face.jpg" \
    "$BASE_URL/face-detect/file" \
    -o /dev/null -w "Request $i - Status: %{http_code}, Time: %{time_total}s\n" &
done
wait

echo ""

# Test 3: Load test with timing
echo "Load test with 50 sequential requests..."
time for i in {1..50}; do
  curl -s -X POST \
    -F "file=@test-face.jpg" \
    "$BASE_URL/face-detect/file" \
    -o /dev/null
done

echo ""

# Test 4: Memory usage check (if container is running)
echo "Container resource usage:"
docker stats --no-stream yunet-face-detection 2>/dev/null || echo "Container stats unavailable"

echo ""
echo "Benchmark complete!"