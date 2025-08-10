#!/bin/bash

# Test script for SELF-HOSTED Moondream API - No API key required!

API_URL="http://localhost:8001"
TEST_IMAGE_PATH="./test_images/test.jpg"

echo "Testing SELF-HOSTED Moondream API..."
echo "===================================="
echo "NO API KEY REQUIRED - 100% LOCAL"
echo "===================================="

# Detect OS for base64 command compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    BASE64_CMD="base64 -i"
else
    # Linux
    BASE64_CMD="base64"
fi

# Check if API is running
echo -n "1. Health check... "
HEALTH_RESPONSE=$(curl -s "${API_URL}/health")
if [[ $HEALTH_RESPONSE == *"healthy"* ]]; then
    echo "✓ API is healthy"
    echo "   Model loaded: $(echo $HEALTH_RESPONSE | grep -o '"model_loaded":[^,}]*' | cut -d':' -f2)"
    echo "   Mode: $(echo $HEALTH_RESPONSE | grep -o '"mode":[^,}]*' | cut -d':' -f2)"
else
    echo "✗ API is not responding"
    exit 1
fi

# Test caption endpoint - NO API KEY NEEDED!
if [ -f "$TEST_IMAGE_PATH" ]; then
    echo -n "2. Testing caption endpoint (base64)... "
    $BASE64_CMD "$TEST_IMAGE_PATH" | tr -d '\n' > /tmp/image_base64.txt
    BASE64_IMAGE=$(cat /tmp/image_base64.txt)
    
    echo "{\"image\": \"data:image/jpeg;base64,${BASE64_IMAGE}\"}" > /tmp/request.json
    
    CAPTION_RESPONSE=$(curl -s -X POST "${API_URL}/caption" \
        -H "Content-Type: application/json" \
        --data-binary @/tmp/request.json)
    
    if [[ $CAPTION_RESPONSE == *"caption"* ]] && [[ $CAPTION_RESPONSE != *"error"* ]]; then
        echo "✓ Caption generated"
        echo "   Response: ${CAPTION_RESPONSE:0:100}..."
    else
        echo "✗ Caption generation failed"
        echo "   Response: $CAPTION_RESPONSE"
    fi
    
    rm -f /tmp/image_base64.txt /tmp/request.json
else
    echo "2. Test image not found at $TEST_IMAGE_PATH"
    echo "   Run: ./copy_test_images.sh"
fi

# Test upload caption endpoint - NO API KEY NEEDED!
if [ -f "$TEST_IMAGE_PATH" ]; then
    echo -n "3. Testing caption endpoint (file upload)... "
    UPLOAD_RESPONSE=$(curl -s -X POST "${API_URL}/upload/caption" \
        -F "file=@${TEST_IMAGE_PATH}")
    
    if [[ $UPLOAD_RESPONSE == *"caption"* ]] && [[ $UPLOAD_RESPONSE != *"error"* ]]; then
        echo "✓ Caption generated from upload"
        echo "   Response: ${UPLOAD_RESPONSE:0:100}..."
    else
        echo "✗ Upload caption generation failed"
        echo "   Response: $UPLOAD_RESPONSE"
    fi
else
    echo "3. Test image not found"
fi

# Test query endpoint - NO API KEY NEEDED!
if [ -f "$TEST_IMAGE_PATH" ]; then
    echo -n "4. Testing query endpoint... "
    $BASE64_CMD "$TEST_IMAGE_PATH" | tr -d '\n' > /tmp/image_base64.txt
    BASE64_IMAGE=$(cat /tmp/image_base64.txt)
    
    echo "{\"image\": \"data:image/jpeg;base64,${BASE64_IMAGE}\", \"question\": \"What is in this image?\"}" > /tmp/request.json
    
    QUERY_RESPONSE=$(curl -s -X POST "${API_URL}/query" \
        -H "Content-Type: application/json" \
        --data-binary @/tmp/request.json)
    
    if [[ $QUERY_RESPONSE == *"answer"* ]] && [[ $QUERY_RESPONSE != *"error"* ]]; then
        echo "✓ Query answered"
        echo "   Response: ${QUERY_RESPONSE:0:100}..."
    else
        echo "✗ Query failed"
        echo "   Response: $QUERY_RESPONSE"
    fi
    
    rm -f /tmp/image_base64.txt /tmp/request.json
else
    echo "4. Test image not found"
fi

echo "===================================="
echo "Testing complete!"
echo "Running in SELF-HOSTED mode"
echo "No external API calls made"
echo "===================================="