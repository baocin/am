#!/usr/bin/env python3
"""
Test script for Nomic Embed Vision API
"""

import requests
import base64
import json
import sys
import numpy as np
from pathlib import Path
from typing import List

# API base URL
BASE_URL = "http://localhost:8002"

def calculate_cosine_similarity(vec1: List[float], vec2: List[float]) -> float:
    """Calculate cosine similarity between two vectors"""
    vec1 = np.array(vec1)
    vec2 = np.array(vec2)
    return np.dot(vec1, vec2) / (np.linalg.norm(vec1) * np.linalg.norm(vec2))

def test_health():
    """Test health endpoint"""
    print("Testing health endpoint...")
    response = requests.get(f"{BASE_URL}/health")
    if response.status_code == 200:
        print("✓ Health check passed")
        print(json.dumps(response.json(), indent=2))
    else:
        print(f"✗ Health check failed: {response.status_code}")
    print()

def test_text_embedding():
    """Test text embedding endpoint"""
    print("Testing text embedding...")
    
    # Test single text
    payload = {
        "text": "This is a test sentence for embedding.",
        "task": "search_document",
        "normalize": True
    }
    
    response = requests.post(f"{BASE_URL}/embed/text", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print("✓ Single text embedding successful")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
        else:
            print(f"✗ Text embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    
    # Test batch text
    print("\nTesting batch text embedding...")
    payload = {
        "text": [
            "The quick brown fox jumps over the lazy dog.",
            "Machine learning is transforming the world.",
            "Python is a versatile programming language."
        ],
        "task": "search_document",
        "normalize": True
    }
    
    response = requests.post(f"{BASE_URL}/embed/text", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print("✓ Batch text embedding successful")
            print(f"  Number of embeddings: {result['num_embeddings']}")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
            
            # Test similarity
            if len(result['embeddings']) >= 2:
                sim = calculate_cosine_similarity(
                    result['embeddings'][0], 
                    result['embeddings'][1]
                )
                print(f"  Similarity between first two texts: {sim:.3f}")
        else:
            print(f"✗ Batch text embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
    print()

def test_image_embedding_file(image_path):
    """Test image embedding with file upload"""
    print(f"Testing image embedding with file: {image_path}")
    
    if not Path(image_path).exists():
        print(f"✗ File not found: {image_path}")
        return
    
    with open(image_path, 'rb') as f:
        files = {'files': f}
        params = {'normalize': 'true'}
        response = requests.post(f"{BASE_URL}/embed/image/file", files=files, params=params)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Image embedding successful")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
        else:
            print(f"✗ Image embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_image_embedding_base64(image_path):
    """Test image embedding with base64 encoding"""
    print(f"Testing image embedding with base64: {image_path}")
    
    if not Path(image_path).exists():
        print(f"✗ File not found: {image_path}")
        return
    
    with open(image_path, 'rb') as f:
        image_base64 = base64.b64encode(f.read()).decode('utf-8')
    
    payload = {
        'image_base64': image_base64,
        'normalize': True
    }
    
    response = requests.post(f"{BASE_URL}/embed/image/base64", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Image base64 embedding successful")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
        else:
            print(f"✗ Image embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_image_embedding_url():
    """Test image embedding with URL"""
    print("Testing image embedding with URL...")
    
    # Use a sample image URL
    image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png"
    
    payload = {
        'image_url': image_url,
        'normalize': True
    }
    
    response = requests.post(f"{BASE_URL}/embed/image/url", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Image URL embedding successful")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
        else:
            print(f"✗ Image embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_multimodal_embedding(image_path=None):
    """Test multimodal embedding with mixed text and images"""
    print("Testing multimodal embedding...")
    
    inputs = [
        {"type": "text", "content": "A beautiful sunset over the ocean"},
        {"type": "text", "content": "Machine learning and artificial intelligence"}
    ]
    
    # Add image if provided
    if image_path and Path(image_path).exists():
        with open(image_path, 'rb') as f:
            image_base64 = base64.b64encode(f.read()).decode('utf-8')
        inputs.append({"type": "image", "content": image_base64})
    
    payload = {
        'inputs': inputs,
        'normalize': True
    }
    
    response = requests.post(f"{BASE_URL}/embed/multimodal", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Multimodal embedding successful")
            print(f"  Number of embeddings: {result['num_embeddings']}")
            print(f"  Embedding dimension: {result['embedding_dim']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
            
            # Calculate similarities
            if len(result['embeddings']) >= 2:
                print("\n  Cross-modal similarities:")
                for i in range(len(result['embeddings'])):
                    for j in range(i+1, len(result['embeddings'])):
                        sim = calculate_cosine_similarity(
                            result['embeddings'][i], 
                            result['embeddings'][j]
                        )
                        input_type_i = inputs[i]['type']
                        input_type_j = inputs[j]['type']
                        print(f"    {input_type_i}[{i}] vs {input_type_j}[{j}]: {sim:.3f}")
        else:
            print(f"✗ Multimodal embedding failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_semantic_similarity():
    """Test semantic similarity between related texts"""
    print("Testing semantic similarity...")
    
    test_pairs = [
        ("cat", "kitten"),
        ("dog", "puppy"),
        ("car", "automobile"),
        ("happy", "joyful"),
        ("computer", "banana"),  # Unrelated
    ]
    
    for word1, word2 in test_pairs:
        payload = {
            "text": [word1, word2],
            "task": "search_document",
            "normalize": True
        }
        
        response = requests.post(f"{BASE_URL}/embed/text", json=payload)
        
        if response.status_code == 200 and response.json()['success']:
            result = response.json()
            sim = calculate_cosine_similarity(
                result['embeddings'][0], 
                result['embeddings'][1]
            )
            print(f"  '{word1}' vs '{word2}': {sim:.3f}")
    print()

def main():
    print("=" * 60)
    print("Nomic Embed Vision API Test Suite")
    print("=" * 60)
    print()
    
    # Test health endpoint
    test_health()
    
    # Test text embedding
    test_text_embedding()
    
    # Test semantic similarity
    test_semantic_similarity()
    
    # Test with a local image file (if provided)
    test_image = None
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
    else:
        # Look for a test image in the current directory
        test_images = list(Path('.').glob('*.jpg')) + list(Path('.').glob('*.png'))
        if test_images:
            test_image = str(test_images[0])
            print(f"Using test image: {test_image}")
    
    if test_image:
        # Test image embeddings
        test_image_embedding_file(test_image)
        test_image_embedding_base64(test_image)
        
        # Test multimodal with image
        test_multimodal_embedding(test_image)
    else:
        print("No test image provided or found")
        print("Usage: python test_api.py [image_path]")
        
        # Test multimodal without image
        test_multimodal_embedding()
    
    # Test image URL embedding
    test_image_embedding_url()
    
    print("=" * 60)
    print("Test suite completed")
    print("=" * 60)

if __name__ == "__main__":
    main()