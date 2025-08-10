from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, HttpUrl
import torch
from transformers import AutoModel, AutoTokenizer, AutoImageProcessor
import base64
import io
import os
import tempfile
import numpy as np
from typing import Optional, List, Dict, Any, Union
import requests
import logging
from pathlib import Path
from PIL import Image
import time

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Nomic Embed Vision Raw API", version="1.0.0")

# Model configuration
MODEL_DIR = os.environ.get("MODEL_DIR", "/app/models")
MODEL_NAME = os.environ.get("MODEL_NAME", "nomic-ai/nomic-embed-vision-v1.5")
AUTO_DOWNLOAD_MODELS = os.environ.get("AUTO_DOWNLOAD_MODELS", "true").lower() == "true"
DEVICE = os.environ.get("DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
MAX_TEXT_LENGTH = int(os.environ.get("MAX_TEXT_LENGTH", "8192"))
MAX_BATCH_SIZE = int(os.environ.get("MAX_BATCH_SIZE", "32"))

# Global model, tokenizer, and processor
model = None
tokenizer = None
processor = None
models_loaded_from_volume = False

def initialize_model():
    """Initialize Nomic embedding model with tokenizer and image processor"""
    global model, tokenizer, processor, models_loaded_from_volume
    
    try:
        # Set cache directory if models should be stored locally
        if MODEL_DIR != "/app/models":
            os.environ['TRANSFORMERS_CACHE'] = MODEL_DIR
            os.environ['HF_HOME'] = MODEL_DIR
        
        logger.info(f"Loading Nomic model from {MODEL_NAME}...")
        logger.info(f"Using device: {DEVICE}")
        
        # Check if model exists locally
        local_model_path = os.path.join(MODEL_DIR, "nomic-embed-vision-v1.5")
        use_local = os.path.exists(local_model_path) and os.path.exists(os.path.join(local_model_path, "config.json"))
        
        if use_local:
            logger.info(f"Loading model from local path: {local_model_path}")
            model_path = local_model_path
        else:
            if not AUTO_DOWNLOAD_MODELS:
                logger.error("Model not found locally and AUTO_DOWNLOAD_MODELS is false")
                return False
            logger.info(f"Downloading model from Hugging Face: {MODEL_NAME}")
            model_path = MODEL_NAME
        
        # Load the unified model
        model = AutoModel.from_pretrained(
            model_path,
            trust_remote_code=True,
            cache_dir=MODEL_DIR if AUTO_DOWNLOAD_MODELS else None
        )
        
        # Move model to device
        model = model.to(DEVICE)
        model.eval()
        
        # Load tokenizer for text
        tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            trust_remote_code=True,
            cache_dir=MODEL_DIR if AUTO_DOWNLOAD_MODELS else None
        )
        
        # Load image processor
        processor = AutoImageProcessor.from_pretrained(
            model_path,
            trust_remote_code=True,
            cache_dir=MODEL_DIR if AUTO_DOWNLOAD_MODELS else None
        )
        
        models_loaded_from_volume = True
        logger.info("Successfully loaded Nomic embedding model")
        
        # Log model info
        logger.info(f"Model device: {next(model.parameters()).device}")
        logger.info(f"Model dtype: {next(model.parameters()).dtype}")
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        models_loaded_from_volume = False
        return False

# Initialize model on startup
initialize_model()

class TextEmbeddingRequest(BaseModel):
    """Request model for text embedding"""
    text: Union[str, List[str]]
    task: Optional[str] = "search_document"  # search_document, search_query, classification, clustering
    normalize: bool = True

class ImageEmbeddingRequest(BaseModel):
    """Request model for image embedding with base64"""
    image_base64: Union[str, List[str]]
    normalize: bool = True

class ImageURLEmbeddingRequest(BaseModel):
    """Request model for image embedding with URL"""
    image_url: Union[HttpUrl, List[HttpUrl]]
    normalize: bool = True

class MultiModalEmbeddingRequest(BaseModel):
    """Request model for mixed text and image embedding"""
    inputs: List[Dict[str, str]]  # List of {"type": "text"|"image", "content": str}
    normalize: bool = True

class EmbeddingResponse(BaseModel):
    """Response model for embedding results"""
    success: bool
    embeddings: Optional[List[List[float]]] = None
    embedding_dim: Optional[int] = None
    num_embeddings: Optional[int] = None
    error: Optional[str] = None
    processing_time_ms: Optional[float] = None

def embed_text(texts: List[str], task: str = "search_document", normalize: bool = True) -> np.ndarray:
    """
    Generate embeddings for text inputs
    
    Args:
        texts: List of text strings to embed
        task: Task type for embedding (affects prefix)
        normalize: Whether to normalize embeddings
    
    Returns:
        Numpy array of embeddings
    """
    if model is None or tokenizer is None:
        raise RuntimeError("Model not initialized")
    
    # Add task-specific prefix
    task_prefixes = {
        "search_document": "search_document: ",
        "search_query": "search_query: ",
        "classification": "classification: ",
        "clustering": "clustering: "
    }
    prefix = task_prefixes.get(task, "")
    
    # Add prefix to texts
    prefixed_texts = [prefix + text for text in texts]
    
    # Tokenize
    encoded = tokenizer(
        prefixed_texts,
        padding=True,
        truncation=True,
        max_length=MAX_TEXT_LENGTH,
        return_tensors="pt"
    )
    
    # Move to device
    encoded = {k: v.to(DEVICE) for k, v in encoded.items()}
    
    # Generate embeddings
    with torch.no_grad():
        outputs = model.text_model(**encoded)
        embeddings = outputs.last_hidden_state.mean(dim=1)  # Mean pooling
        
        if normalize:
            embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
    
    return embeddings.cpu().numpy()

def embed_images(images: List[Image.Image], normalize: bool = True) -> np.ndarray:
    """
    Generate embeddings for image inputs
    
    Args:
        images: List of PIL Image objects
        normalize: Whether to normalize embeddings
    
    Returns:
        Numpy array of embeddings
    """
    if model is None or processor is None:
        raise RuntimeError("Model not initialized")
    
    # Process images
    pixel_values = processor(images=images, return_tensors="pt")["pixel_values"]
    pixel_values = pixel_values.to(DEVICE)
    
    # Generate embeddings
    with torch.no_grad():
        outputs = model.vision_model(pixel_values=pixel_values)
        embeddings = outputs.last_hidden_state.mean(dim=1)  # Mean pooling
        
        if normalize:
            embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
    
    return embeddings.cpu().numpy()

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "Nomic Embed Vision Raw API",
        "version": "1.0.0",
        "model": MODEL_NAME,
        "capabilities": ["text_embedding", "image_embedding", "multimodal"],
        "endpoints": {
            "/embed/text": "POST - Generate embeddings for text",
            "/embed/image/file": "POST - Generate embeddings for uploaded images",
            "/embed/image/base64": "POST - Generate embeddings for base64 images",
            "/embed/image/url": "POST - Generate embeddings for image URLs",
            "/embed/multimodal": "POST - Generate embeddings for mixed text and images",
            "/health": "GET - Health check",
            "/healthz": "GET - Health check (Kubernetes-style)",
            "/docs": "GET - API documentation"
        }
    }

@app.get("/health")
@app.get("/healthz")
async def health_check():
    """Health check endpoint (available at both /health and /healthz)"""
    return {
        "status": "healthy",
        "service": "nomic-embed-vision",
        "model_dir": MODEL_DIR,
        "model_name": MODEL_NAME,
        "models_loaded_from_volume": models_loaded_from_volume,
        "auto_download_models": AUTO_DOWNLOAD_MODELS,
        "device": DEVICE,
        "settings": {
            "max_text_length": MAX_TEXT_LENGTH,
            "max_batch_size": MAX_BATCH_SIZE
        }
    }

@app.post("/embed/text", response_model=EmbeddingResponse)
async def embed_text_endpoint(request: TextEmbeddingRequest):
    """
    Generate embeddings for text input(s)
    
    Args:
        request: TextEmbeddingRequest with text and parameters
    
    Returns:
        Embeddings for the input text(s)
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return EmbeddingResponse(
                success=False,
                error="Model not loaded. Please ensure model is initialized."
            )
        
        # Ensure text is a list
        texts = request.text if isinstance(request.text, list) else [request.text]
        
        # Check batch size
        if len(texts) > MAX_BATCH_SIZE:
            return EmbeddingResponse(
                success=False,
                error=f"Batch size {len(texts)} exceeds maximum {MAX_BATCH_SIZE}"
            )
        
        # Generate embeddings
        embeddings = embed_text(texts, request.task, request.normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return EmbeddingResponse(
            success=True,
            embeddings=embeddings.tolist(),
            embedding_dim=embeddings.shape[1],
            num_embeddings=len(embeddings),
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        return EmbeddingResponse(
            success=False,
            error=str(e)
        )

@app.post("/embed/image/file", response_model=EmbeddingResponse)
async def embed_image_file(
    files: List[UploadFile] = File(...),
    normalize: bool = True
):
    """
    Generate embeddings for uploaded image file(s)
    
    Args:
        files: Image file(s) (JPEG, PNG, etc.)
        normalize: Whether to normalize embeddings
    
    Returns:
        Embeddings for the input image(s)
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return EmbeddingResponse(
                success=False,
                error="Model not loaded. Please ensure model is initialized."
            )
        
        # Check batch size
        if len(files) > MAX_BATCH_SIZE:
            return EmbeddingResponse(
                success=False,
                error=f"Batch size {len(files)} exceeds maximum {MAX_BATCH_SIZE}"
            )
        
        # Load images
        images = []
        for file in files:
            content = await file.read()
            image = Image.open(io.BytesIO(content)).convert("RGB")
            images.append(image)
        
        # Generate embeddings
        embeddings = embed_images(images, normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return EmbeddingResponse(
            success=True,
            embeddings=embeddings.tolist(),
            embedding_dim=embeddings.shape[1],
            num_embeddings=len(embeddings),
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        return EmbeddingResponse(
            success=False,
            error=str(e)
        )

@app.post("/embed/image/base64", response_model=EmbeddingResponse)
async def embed_image_base64(request: ImageEmbeddingRequest):
    """
    Generate embeddings for base64 encoded image(s)
    
    Args:
        request: ImageEmbeddingRequest with base64 image(s)
    
    Returns:
        Embeddings for the input image(s)
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return EmbeddingResponse(
                success=False,
                error="Model not loaded. Please ensure model is initialized."
            )
        
        # Ensure image_base64 is a list
        image_data_list = request.image_base64 if isinstance(request.image_base64, list) else [request.image_base64]
        
        # Check batch size
        if len(image_data_list) > MAX_BATCH_SIZE:
            return EmbeddingResponse(
                success=False,
                error=f"Batch size {len(image_data_list)} exceeds maximum {MAX_BATCH_SIZE}"
            )
        
        # Decode and load images
        images = []
        for image_base64 in image_data_list:
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data)).convert("RGB")
            images.append(image)
        
        # Generate embeddings
        embeddings = embed_images(images, request.normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return EmbeddingResponse(
            success=True,
            embeddings=embeddings.tolist(),
            embedding_dim=embeddings.shape[1],
            num_embeddings=len(embeddings),
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        return EmbeddingResponse(
            success=False,
            error=str(e)
        )

@app.post("/embed/image/url", response_model=EmbeddingResponse)
async def embed_image_url(request: ImageURLEmbeddingRequest):
    """
    Generate embeddings for image(s) from URL(s)
    
    Args:
        request: ImageURLEmbeddingRequest with image URL(s)
    
    Returns:
        Embeddings for the input image(s)
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return EmbeddingResponse(
                success=False,
                error="Model not loaded. Please ensure model is initialized."
            )
        
        # Ensure image_url is a list
        urls = request.image_url if isinstance(request.image_url, list) else [request.image_url]
        
        # Check batch size
        if len(urls) > MAX_BATCH_SIZE:
            return EmbeddingResponse(
                success=False,
                error=f"Batch size {len(urls)} exceeds maximum {MAX_BATCH_SIZE}"
            )
        
        # Download and load images
        images = []
        for url in urls:
            response = requests.get(str(url), timeout=30)
            response.raise_for_status()
            image = Image.open(io.BytesIO(response.content)).convert("RGB")
            images.append(image)
        
        # Generate embeddings
        embeddings = embed_images(images, request.normalize)
        
        processing_time = (time.time() - start_time) * 1000
        
        return EmbeddingResponse(
            success=True,
            embeddings=embeddings.tolist(),
            embedding_dim=embeddings.shape[1],
            num_embeddings=len(embeddings),
            processing_time_ms=processing_time
        )
        
    except requests.RequestException as e:
        return EmbeddingResponse(
            success=False,
            error=f"Failed to download image: {str(e)}"
        )
    except Exception as e:
        return EmbeddingResponse(
            success=False,
            error=str(e)
        )

@app.post("/embed/multimodal", response_model=EmbeddingResponse)
async def embed_multimodal(request: MultiModalEmbeddingRequest):
    """
    Generate embeddings for mixed text and image inputs
    
    Args:
        request: MultiModalEmbeddingRequest with mixed inputs
    
    Returns:
        Embeddings for all inputs in order
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return EmbeddingResponse(
                success=False,
                error="Model not loaded. Please ensure model is initialized."
            )
        
        # Check batch size
        if len(request.inputs) > MAX_BATCH_SIZE:
            return EmbeddingResponse(
                success=False,
                error=f"Batch size {len(request.inputs)} exceeds maximum {MAX_BATCH_SIZE}"
            )
        
        # Separate text and image inputs
        text_inputs = []
        text_indices = []
        image_inputs = []
        image_indices = []
        
        for i, item in enumerate(request.inputs):
            if item["type"] == "text":
                text_inputs.append(item["content"])
                text_indices.append(i)
            elif item["type"] == "image":
                # Assume base64 encoded image
                image_data = base64.b64decode(item["content"])
                image = Image.open(io.BytesIO(image_data)).convert("RGB")
                image_inputs.append(image)
                image_indices.append(i)
            else:
                return EmbeddingResponse(
                    success=False,
                    error=f"Unknown input type: {item['type']}"
                )
        
        # Generate embeddings
        all_embeddings = np.zeros((len(request.inputs), 768))  # Assuming 768-dim embeddings
        
        if text_inputs:
            text_embeddings = embed_text(text_inputs, normalize=request.normalize)
            for idx, orig_idx in enumerate(text_indices):
                all_embeddings[orig_idx] = text_embeddings[idx]
        
        if image_inputs:
            image_embeddings = embed_images(image_inputs, normalize=request.normalize)
            for idx, orig_idx in enumerate(image_indices):
                all_embeddings[orig_idx] = image_embeddings[idx]
        
        processing_time = (time.time() - start_time) * 1000
        
        return EmbeddingResponse(
            success=True,
            embeddings=all_embeddings.tolist(),
            embedding_dim=all_embeddings.shape[1],
            num_embeddings=len(all_embeddings),
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        return EmbeddingResponse(
            success=False,
            error=str(e)
        )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)