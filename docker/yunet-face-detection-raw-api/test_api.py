#!/usr/bin/env python3
"""
Test script for YuNet Face Detection API
"""

import requests
import base64
import json
import sys
from pathlib import Path

# API base URL
BASE_URL = "http://localhost:8001"

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

def test_face_detection_file(image_path):
    """Test face detection with file upload"""
    print(f"Testing face detection with file: {image_path}")
    
    if not Path(image_path).exists():
        print(f"✗ File not found: {image_path}")
        return
    
    with open(image_path, 'rb') as f:
        files = {'file': f}
        params = {'visualize': 'true'}
        response = requests.post(f"{BASE_URL}/face-detect/file", files=files, params=params)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Face detection successful")
            print(f"  Faces detected: {result['face_count']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
            if result.get('visualization_path'):
                print(f"  Visualization: {BASE_URL}/visualization/{result['visualization_path']}")
            
            # Print face details
            for i, face in enumerate(result.get('faces', [])):
                print(f"\n  Face {i+1}:")
                print(f"    Confidence: {face['confidence']:.3f}")
                print(f"    Bounding box: {face['bbox']}")
                print(f"    Landmarks: {len(face.get('landmarks', []))} points")
        else:
            print(f"✗ Face detection failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_face_detection_base64(image_path):
    """Test face detection with base64 encoded image"""
    print(f"Testing face detection with base64 encoding: {image_path}")
    
    if not Path(image_path).exists():
        print(f"✗ File not found: {image_path}")
        return
    
    with open(image_path, 'rb') as f:
        image_base64 = base64.b64encode(f.read()).decode('utf-8')
    
    payload = {
        'image_base64': image_base64,
        'visualize': True,
        'score_threshold': 0.5  # Lower threshold for testing
    }
    
    response = requests.post(f"{BASE_URL}/face-detect/base64", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Face detection successful")
            print(f"  Faces detected: {result['face_count']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
            if result.get('visualization_path'):
                print(f"  Visualization: {BASE_URL}/visualization/{result['visualization_path']}")
        else:
            print(f"✗ Face detection failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def test_face_detection_url(image_url):
    """Test face detection with image URL"""
    print(f"Testing face detection with URL: {image_url}")
    
    payload = {
        'image_url': image_url,
        'visualize': True
    }
    
    response = requests.post(f"{BASE_URL}/face-detect/url", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        if result['success']:
            print(f"✓ Face detection successful")
            print(f"  Faces detected: {result['face_count']}")
            print(f"  Processing time: {result.get('processing_time_ms', 'N/A')} ms")
            if result.get('visualization_path'):
                print(f"  Visualization: {BASE_URL}/visualization/{result['visualization_path']}")
        else:
            print(f"✗ Face detection failed: {result.get('error', 'Unknown error')}")
    else:
        print(f"✗ Request failed: {response.status_code}")
        print(response.text)
    print()

def main():
    print("=" * 60)
    print("YuNet Face Detection API Test Suite")
    print("=" * 60)
    print()
    
    # Test health endpoint
    test_health()
    
    # Test with a local image file (if provided)
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
    else:
        # Look for a test image in the current directory
        test_images = list(Path('.').glob('*.jpg')) + list(Path('.').glob('*.png'))
        if test_images:
            test_image = str(test_images[0])
            print(f"Using test image: {test_image}")
        else:
            print("No test image provided or found")
            print("Usage: python test_api.py [image_path]")
            return
    
    # Test file upload
    test_face_detection_file(test_image)
    
    # Test base64 encoding
    test_face_detection_base64(test_image)
    
    # Test with a sample URL (group photo with faces)
    sample_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Group_photo_of_participants_at_2023_Wikimedia_Summit_01.jpg/640px-Group_photo_of_participants_at_2023_Wikimedia_Summit_01.jpg"
    test_face_detection_url(sample_url)
    
    print("=" * 60)
    print("Test suite completed")
    print("=" * 60)

if __name__ == "__main__":
    main()