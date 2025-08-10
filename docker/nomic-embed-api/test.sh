#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# API endpoint
API_URL="http://localhost:8002"

echo "=================================================="
echo "Nomic Embed Vision API Test Suite"
echo "=================================================="
echo ""

# Create test_images directory if it doesn't exist
mkdir -p test_images

# Copy test images from RapidOCR if available
echo -e "${YELLOW}Setting up test images...${NC}"
if [ -d "../rapidocr-raw-api/test_images" ]; then
    cp ../rapidocr-raw-api/test_images/*.png test_images/ 2>/dev/null
    cp ../rapidocr-raw-api/test_images/*.jpg test_images/ 2>/dev/null
    echo -e "${GREEN}✓ Copied test images from RapidOCR${NC}"
else
    echo -e "${YELLOW}⚠ RapidOCR test images not found, using downloaded samples${NC}"
fi

# Download sample images if needed
if [ ! -f "test_images/sample1.jpg" ]; then
    echo "Downloading sample images..."
    curl -s -o test_images/sample1.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Group_photo_of_participants_at_2023_Wikimedia_Summit_01.jpg/640px-Group_photo_of_participants_at_2023_Wikimedia_Summit_01.jpg"
    curl -s -o test_images/sample2.png "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png"
fi

echo ""
echo "=================================================="
echo "1. Testing Health Check"
echo "=================================================="
echo ""

curl -X GET "$API_URL/health" 2>/dev/null | python3 -m json.tool
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
fi

echo ""
echo "=================================================="
echo "2. Testing Text Embedding - Single Text"
echo "=================================================="
echo ""

echo "Request: Embedding for 'Hello, this is a test sentence'"
RESPONSE=$(curl -s -X POST "$API_URL/embed/text" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello, this is a test sentence for embedding",
    "task": "search_document",
    "normalize": true
  }')

SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])")
if [ "$SUCCESS" = "True" ]; then
    echo -e "${GREEN}✓ Single text embedding successful${NC}"
    echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
else
    echo -e "${RED}✗ Single text embedding failed${NC}"
    echo $RESPONSE | python3 -m json.tool
fi

echo ""
echo "=================================================="
echo "3. Testing Text Embedding - Batch"
echo "=================================================="
echo ""

echo "Request: Batch embedding for multiple texts"
RESPONSE=$(curl -s -X POST "$API_URL/embed/text" \
  -H "Content-Type: application/json" \
  -d '{
    "text": [
      "The quick brown fox jumps over the lazy dog",
      "Machine learning is transforming the world",
      "Python is a versatile programming language"
    ],
    "task": "search_document",
    "normalize": true
  }')

SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])")
if [ "$SUCCESS" = "True" ]; then
    echo -e "${GREEN}✓ Batch text embedding successful${NC}"
    echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Number of embeddings: {data[\"num_embeddings\"]}'); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
else
    echo -e "${RED}✗ Batch text embedding failed${NC}"
fi

echo ""
echo "=================================================="
echo "4. Testing Image Embedding - File Upload"
echo "=================================================="
echo ""

# Find first available test image
TEST_IMAGE=$(ls test_images/*.{jpg,png} 2>/dev/null | head -n 1)

if [ -n "$TEST_IMAGE" ]; then
    echo "Using test image: $TEST_IMAGE"
    RESPONSE=$(curl -s -X POST "$API_URL/embed/image/file" \
      -F "files=@$TEST_IMAGE" \
      -F "normalize=true")
    
    SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
    if [ "$SUCCESS" = "True" ]; then
        echo -e "${GREEN}✓ Image file embedding successful${NC}"
        echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
    else
        echo -e "${RED}✗ Image file embedding failed${NC}"
        echo $RESPONSE | python3 -m json.tool
    fi
else
    echo -e "${YELLOW}⚠ No test images found${NC}"
fi

echo ""
echo "=================================================="
echo "5. Testing Image Embedding - Base64"
echo "=================================================="
echo ""

if [ -n "$TEST_IMAGE" ]; then
    echo "Converting image to base64..."
    BASE64_IMAGE=$(base64 < "$TEST_IMAGE" | tr -d '\n')
    
    RESPONSE=$(curl -s -X POST "$API_URL/embed/image/base64" \
      -H "Content-Type: application/json" \
      -d "{
        \"image_base64\": \"$BASE64_IMAGE\",
        \"normalize\": true
      }")
    
    SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
    if [ "$SUCCESS" = "True" ]; then
        echo -e "${GREEN}✓ Image base64 embedding successful${NC}"
        echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
    else
        echo -e "${RED}✗ Image base64 embedding failed${NC}"
    fi
fi

echo ""
echo "=================================================="
echo "6. Testing Image Embedding - URL"
echo "=================================================="
echo ""

echo "Using sample image URL from Wikipedia"
RESPONSE=$(curl -s -X POST "$API_URL/embed/image/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png",
    "normalize": true
  }')

SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
if [ "$SUCCESS" = "True" ]; then
    echo -e "${GREEN}✓ Image URL embedding successful${NC}"
    echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
else
    echo -e "${RED}✗ Image URL embedding failed${NC}"
fi

echo ""
echo "=================================================="
echo "7. Testing Multimodal Embedding"
echo "=================================================="
echo ""

if [ -n "$TEST_IMAGE" ] && [ -n "$BASE64_IMAGE" ]; then
    echo "Testing mixed text and image inputs..."
    
    RESPONSE=$(curl -s -X POST "$API_URL/embed/multimodal" \
      -H "Content-Type: application/json" \
      -d "{
        \"inputs\": [
          {\"type\": \"text\", \"content\": \"A beautiful sunset over the ocean\"},
          {\"type\": \"text\", \"content\": \"Machine learning and artificial intelligence\"},
          {\"type\": \"image\", \"content\": \"$BASE64_IMAGE\"}
        ],
        \"normalize\": true
      }")
    
    SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
    if [ "$SUCCESS" = "True" ]; then
        echo -e "${GREEN}✓ Multimodal embedding successful${NC}"
        echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Number of embeddings: {data[\"num_embeddings\"]}'); print(f'  Embedding dimension: {data[\"embedding_dim\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
    else
        echo -e "${RED}✗ Multimodal embedding failed${NC}"
    fi
else
    echo "Testing multimodal with text only..."
    RESPONSE=$(curl -s -X POST "$API_URL/embed/multimodal" \
      -H "Content-Type: application/json" \
      -d '{
        "inputs": [
          {"type": "text", "content": "First text input"},
          {"type": "text", "content": "Second text input"}
        ],
        "normalize": true
      }')
    
    SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
    if [ "$SUCCESS" = "True" ]; then
        echo -e "${GREEN}✓ Multimodal (text only) embedding successful${NC}"
    else
        echo -e "${RED}✗ Multimodal embedding failed${NC}"
    fi
fi

echo ""
echo "=================================================="
echo "8. Testing Semantic Similarity"
echo "=================================================="
echo ""

echo "Computing cosine similarity between related words..."

# Create a Python script to test similarity
cat > /tmp/test_similarity.py << 'EOF'
import requests
import numpy as np
import json

def cosine_similarity(v1, v2):
    v1 = np.array(v1)
    v2 = np.array(v2)
    return np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

api_url = "http://localhost:8002"
test_pairs = [
    ("cat", "kitten"),
    ("dog", "puppy"),
    ("happy", "joyful"),
    ("car", "automobile"),
    ("computer", "banana")  # Unrelated
]

for word1, word2 in test_pairs:
    response = requests.post(f"{api_url}/embed/text", json={
        "text": [word1, word2],
        "task": "search_document",
        "normalize": True
    })
    
    if response.status_code == 200 and response.json()['success']:
        result = response.json()
        sim = cosine_similarity(result['embeddings'][0], result['embeddings'][1])
        print(f"  '{word1}' vs '{word2}': {sim:.3f}")
    else:
        print(f"  Failed to compute similarity for '{word1}' vs '{word2}'")
EOF

python3 /tmp/test_similarity.py
rm /tmp/test_similarity.py

echo ""
echo "=================================================="
echo "9. Testing Batch Image Processing"
echo "=================================================="
echo ""

# Find multiple test images
TEST_IMAGES=(test_images/*.{jpg,png})
if [ ${#TEST_IMAGES[@]} -ge 2 ]; then
    echo "Testing batch image processing with multiple files..."
    
    # Build curl command with multiple files
    CURL_CMD="curl -s -X POST \"$API_URL/embed/image/file\""
    for img in "${TEST_IMAGES[@]:0:2}"; do
        if [ -f "$img" ]; then
            CURL_CMD="$CURL_CMD -F \"files=@$img\""
        fi
    done
    CURL_CMD="$CURL_CMD -F \"normalize=true\""
    
    RESPONSE=$(eval $CURL_CMD)
    SUCCESS=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['success'])" 2>/dev/null)
    
    if [ "$SUCCESS" = "True" ]; then
        echo -e "${GREEN}✓ Batch image embedding successful${NC}"
        echo $RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'  Number of embeddings: {data[\"num_embeddings\"]}'); print(f'  Processing time: {data.get(\"processing_time_ms\", \"N/A\")} ms')"
    else
        echo -e "${RED}✗ Batch image embedding failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Not enough test images for batch processing${NC}"
fi

echo ""
echo "=================================================="
echo "Test Suite Completed"
echo "=================================================="
echo ""
echo "Test images are stored in: ./test_images/"
echo "To run Python test suite: python3 test_api.py"
echo ""