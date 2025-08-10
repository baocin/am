#!/bin/bash

# Quick test script for Nomic Embed API
API_URL="http://localhost:8002"

echo "Quick Nomic Embed API Test"
echo "=========================="
echo ""

# 1. Health check
echo "1. Health Check:"
curl -s "$API_URL/health" | python3 -m json.tool | head -10
echo ""

# 2. Text embedding
echo "2. Text Embedding (single):"
curl -s -X POST "$API_URL/embed/text" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello world, this is a test",
    "normalize": true
  }' | python3 -c "import sys, json; data=json.load(sys.stdin); print(f\"Success: {data['success']}\"); print(f\"Embedding dim: {data.get('embedding_dim', 'N/A')}\"); print(f\"First 5 values: {data['embeddings'][0][:5] if data.get('embeddings') else 'N/A'}\")"
echo ""

# 3. Text batch embedding with similarity
echo "3. Text Similarity Test:"
curl -s -X POST "$API_URL/embed/text" \
  -H "Content-Type: application/json" \
  -d '{
    "text": ["cat", "kitten", "dog", "computer"],
    "normalize": true
  }' | python3 -c "
import sys, json
import numpy as np

data = json.load(sys.stdin)
if data['success']:
    embeddings = np.array(data['embeddings'])
    
    # Calculate similarities
    words = ['cat', 'kitten', 'dog', 'computer']
    print('Cosine similarities:')
    for i in range(len(words)):
        for j in range(i+1, len(words)):
            sim = np.dot(embeddings[i], embeddings[j])
            print(f'  {words[i]} vs {words[j]}: {sim:.3f}')
"
echo ""

# 4. Download and test with image
echo "4. Image Embedding Test:"
if [ ! -f "/tmp/test_image.jpg" ]; then
    echo "Downloading test image..."
    curl -s -o /tmp/test_image.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png"
fi

curl -s -X POST "$API_URL/embed/image/file" \
  -F "files=@/tmp/test_image.jpg" \
  -F "normalize=true" | python3 -c "import sys, json; data=json.load(sys.stdin); print(f\"Success: {data['success']}\"); print(f\"Embedding dim: {data.get('embedding_dim', 'N/A')}\")"
echo ""

# 5. Cross-modal similarity
echo "5. Cross-Modal Test (text + image):"
BASE64_IMG=$(base64 < /tmp/test_image.jpg | tr -d '\n')
curl -s -X POST "$API_URL/embed/multimodal" \
  -H "Content-Type: application/json" \
  -d "{
    \"inputs\": [
      {\"type\": \"text\", \"content\": \"A colorful geometric shape\"},
      {\"type\": \"text\", \"content\": \"A car driving on the road\"},
      {\"type\": \"image\", \"content\": \"$BASE64_IMG\"}
    ],
    \"normalize\": true
  }" | python3 -c "
import sys, json
import numpy as np

data = json.load(sys.stdin)
if data['success']:
    embeddings = np.array(data['embeddings'])
    print(f\"Generated {len(embeddings)} embeddings\")
    
    # Calculate cross-modal similarities
    labels = ['text: geometric', 'text: car', 'image: test']
    print('Cross-modal similarities:')
    for i in range(len(labels)):
        for j in range(i+1, len(labels)):
            sim = np.dot(embeddings[i], embeddings[j])
            print(f'  {labels[i]} vs {labels[j]}: {sim:.3f}')
"

echo ""
echo "Test complete!"