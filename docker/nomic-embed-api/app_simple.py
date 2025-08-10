#!/usr/bin/env python3
"""
Simplified Nomic Embed Vision API - Mock Implementation
Returns dummy embeddings for testing API contract compliance
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Union, Optional, Dict, Any
import numpy as np
import base64
from io import BytesIO
from PIL import Image
import time
import logging
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Nomic Embed Vision Raw API",
    version="1.0.0",
    description="Simplified mock embedding API for text and images"
)

# Constants
EMBEDDING_DIM = 768  # Standard embedding dimension
MOCK_PROCESSING_TIME = 50  # Simulated processing time in ms

# Pydantic models
class TextEmbedRequest(BaseModel):
    text: Union[str, List[str]]
    task: Optional[str] = "search_document"
    normalize: bool = True

class ImageBase64Request(BaseModel):
    image_base64: str
    normalize: bool = True

class ImageURLRequest(BaseModel):
    image_url: str
    normalize: bool = True

class MultimodalInput(BaseModel):
    type: str  # "text" or "image"
    content: str

class MultimodalRequest(BaseModel):
    inputs: List[MultimodalInput]
    normalize: bool = True

# Helper functions
def generate_mock_embedding(seed: int = None, normalize: bool = True) -> List[float]:
    """Generate a mock embedding vector"""
    if seed is not None:
        np.random.seed(seed)
    
    embedding = np.random.randn(EMBEDDING_DIM)
    
    if normalize:
        # L2 normalization
        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm
    
    return embedding.tolist()

def process_image_base64(base64_string: str) -> bool:
    """Validate base64 image string"""
    try:
        # Remove data URL prefix if present
        if "," in base64_string:
            base64_string = base64_string.split(",")[1]
        
        # Decode base64
        img_data = base64.b64decode(base64_string)
        
        # Try to open as image to validate
        img = Image.open(BytesIO(img_data))
        
        return True
    except Exception as e:
        logger.error(f"Invalid base64 image: {e}")
        return False

def download_image(url: str) -> bool:
    """Validate image URL by attempting to download"""
    try:
        response = requests.get(url, timeout=10, stream=True)
        response.raise_for_status()
        
        # Check content type
        content_type = response.headers.get('content-type', '')
        if not content_type.startswith('image/'):
            return False
        
        # Try to open as image
        img = Image.open(BytesIO(response.content))
        
        return True
    except Exception as e:
        logger.error(f"Failed to download image from {url}: {e}")
        return False

# API Endpoints
@app.get("/")
async def root():
    """Root endpoint with API info"""
    return {
        "service": "Nomic Embed Vision Raw API",
        "version": "1.0.0",
        "description": "Simplified mock embedding API for text and images",
        "endpoints": {
            "/health": "Health check",
            "/healthz": "Kubernetes-style health check",
            "/embed/text": "Text embedding",
            "/embed/image/base64": "Image embedding from base64",
            "/embed/image/url": "Image embedding from URL",
            "/embed/multimodal": "Multimodal embedding"
        }
    }

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "nomic-embed-api",
        "mock_mode": True
    }

@app.get("/healthz")
async def healthz():
    """Kubernetes-style health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.post("/embed/text")
async def embed_text(request: TextEmbedRequest):
    """Generate text embeddings"""
    start_time = time.time()
    
    try:
        # Handle single text or batch
        if isinstance(request.text, str):
            texts = [request.text]
        else:
            texts = request.text
        
        if not texts:
            raise HTTPException(status_code=422, detail="No text provided")
        
        # Generate mock embeddings
        embeddings = []
        for i, text in enumerate(texts):
            # Use text length as seed for consistent mock embeddings
            seed = len(text) + i
            embedding = generate_mock_embedding(seed=seed, normalize=request.normalize)
            embeddings.append(embedding)
        
        # Calculate processing time
        processing_time = (time.time() - start_time) * 1000
        
        # Return appropriate response
        if isinstance(request.text, str):
            # Single text response
            return {
                "success": True,
                "embedding": embeddings[0],
                "embedding_dim": EMBEDDING_DIM,
                "normalized": request.normalize,
                "task": request.task,
                "processing_time_ms": processing_time
            }
        else:
            # Batch response
            return {
                "success": True,
                "embeddings": embeddings,
                "num_embeddings": len(embeddings),
                "embedding_dim": EMBEDDING_DIM,
                "normalized": request.normalize,
                "task": request.task,
                "processing_time_ms": processing_time
            }
    
    except Exception as e:
        logger.error(f"Error in text embedding: {e}")
        return {
            "success": False,
            "error": str(e),
            "processing_time_ms": (time.time() - start_time) * 1000
        }

@app.post("/embed/image/base64")
async def embed_image_base64(request: ImageBase64Request):
    """Generate image embedding from base64"""
    start_time = time.time()
    
    try:
        # Validate base64 image
        if not process_image_base64(request.image_base64):
            return {
                "success": False,
                "error": "Invalid base64 image data",
                "processing_time_ms": (time.time() - start_time) * 1000
            }
        
        # Generate mock embedding
        # Use base64 length as seed for consistency
        seed = len(request.image_base64) % 10000
        embedding = generate_mock_embedding(seed=seed, normalize=request.normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return {
            "success": True,
            "embedding": embedding,
            "embedding_dim": EMBEDDING_DIM,
            "normalized": request.normalize,
            "processing_time_ms": processing_time
        }
    
    except Exception as e:
        logger.error(f"Error in image base64 embedding: {e}")
        return {
            "success": False,
            "error": str(e),
            "processing_time_ms": (time.time() - start_time) * 1000
        }

@app.post("/embed/image/url")
async def embed_image_url(request: ImageURLRequest):
    """Generate image embedding from URL"""
    start_time = time.time()
    
    try:
        # Validate and download image
        if not download_image(request.image_url):
            return {
                "success": False,
                "error": "Failed to download or validate image from URL",
                "processing_time_ms": (time.time() - start_time) * 1000
            }
        
        # Generate mock embedding
        # Use URL length as seed for consistency
        seed = len(request.image_url) % 10000
        embedding = generate_mock_embedding(seed=seed, normalize=request.normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return {
            "success": True,
            "embedding": embedding,
            "embedding_dim": EMBEDDING_DIM,
            "normalized": request.normalize,
            "url": request.image_url,
            "processing_time_ms": processing_time
        }
    
    except Exception as e:
        logger.error(f"Error in image URL embedding: {e}")
        return {
            "success": False,
            "error": str(e),
            "processing_time_ms": (time.time() - start_time) * 1000
        }

@app.post("/embed/multimodal")
async def embed_multimodal(request: MultimodalRequest):
    """Generate multimodal embeddings"""
    start_time = time.time()
    
    try:
        if not request.inputs:
            raise HTTPException(status_code=422, detail="No inputs provided")
        
        embeddings = []
        
        for i, input_item in enumerate(request.inputs):
            if input_item.type == "text":
                # Generate text embedding
                seed = len(input_item.content) + i
                embedding = generate_mock_embedding(seed=seed, normalize=request.normalize)
                embeddings.append(embedding)
            
            elif input_item.type == "image":
                # Assume it's base64 encoded
                if process_image_base64(input_item.content):
                    seed = len(input_item.content) % 10000 + i
                    embedding = generate_mock_embedding(seed=seed, normalize=request.normalize)
                    embeddings.append(embedding)
                else:
                    return {
                        "success": False,
                        "error": f"Invalid image data at input {i}",
                        "processing_time_ms": (time.time() - start_time) * 1000
                    }
            else:
                return {
                    "success": False,
                    "error": f"Unknown input type: {input_item.type}",
                    "processing_time_ms": (time.time() - start_time) * 1000
                }
        
        processing_time = (time.time() - start_time) * 1000
        
        return {
            "success": True,
            "embeddings": embeddings,
            "num_embeddings": len(embeddings),
            "embedding_dim": EMBEDDING_DIM,
            "normalized": request.normalize,
            "processing_time_ms": processing_time
        }
    
    except Exception as e:
        logger.error(f"Error in multimodal embedding: {e}")
        return {
            "success": False,
            "error": str(e),
            "processing_time_ms": (time.time() - start_time) * 1000
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)