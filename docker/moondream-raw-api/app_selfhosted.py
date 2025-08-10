"""
Self-hosted Moondream API - No API keys required!
Runs the Moondream2 model completely locally using Hugging Face Transformers
"""

import sys
import os
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from contextlib import asynccontextmanager
import base64
import io
from PIL import Image
import asyncio
from concurrent.futures import ThreadPoolExecutor
import uvicorn
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, AutoProcessor
import re

# Global model variables
model = None
tokenizer = None
processor = None
device = None

# Thread pool for CPU-bound operations
executor = ThreadPoolExecutor(max_workers=2)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global model, tokenizer, processor, device
    try:
        print("=" * 50)
        print("Initializing SELF-HOSTED Moondream2 model")
        print("No API key required - running 100% locally!")
        print("=" * 50)
        
        # Detect device
        if torch.cuda.is_available():
            device = "cuda"
            print(f"✓ CUDA available - using GPU")
        else:
            device = "cpu"
            print(f"✓ Using CPU (install CUDA for faster inference)")
        
        # Model ID
        model_id = "vikhyatk/moondream2"
        revision = "2024-08-26"
        
        print(f"Loading model from Hugging Face: {model_id}")
        print("This is cached locally after first download...")
        
        # Load tokenizer
        tokenizer = AutoTokenizer.from_pretrained(
            model_id,
            trust_remote_code=True,
            revision=revision
        )
        
        # Load model
        if device == "cuda":
            model = AutoModelForCausalLM.from_pretrained(
                model_id,
                trust_remote_code=True,
                revision=revision,
                torch_dtype=torch.float16,
                device_map="auto"
            )
        else:
            model = AutoModelForCausalLM.from_pretrained(
                model_id,
                trust_remote_code=True,
                revision=revision,
                torch_dtype=torch.float32
            )
            model = model.to(device)
        
        model.eval()
        
        print("=" * 50)
        print("✓ Model loaded successfully!")
        print("✓ Running in SELF-HOSTED mode")
        print("✓ No external API calls")
        print("=" * 50)
            
    except Exception as e:
        print(f"Error loading model: {e}")
        model = None
        tokenizer = None
    
    yield
    
    # Shutdown
    print("Shutting down self-hosted model...")

app = FastAPI(
    title="Moondream Self-Hosted API",
    version="1.0.0",
    description="100% self-hosted vision-language model - No API keys required!",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class CaptionRequest(BaseModel):
    image: str  # Base64 encoded image

class QueryRequest(BaseModel):
    image: str  # Base64 encoded image
    question: str

class DetectRequest(BaseModel):
    image: str  # Base64 encoded image
    object: str

class PointRequest(BaseModel):
    image: str  # Base64 encoded image
    object: str

@app.get("/")
async def root():
    return {
        "service": "Moondream Self-Hosted API",
        "version": "1.0.0",
        "model_loaded": model is not None,
        "device": device,
        "mode": "SELF-HOSTED - No API key required!",
        "endpoints": [
            "/caption",
            "/query", 
            "/detect",
            "/point",
            "/health"
        ]
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "device": device,
        "cuda_available": torch.cuda.is_available(),
        "mode": "self-hosted"
    }

def decode_base64_image(base64_string: str) -> Image.Image:
    """Decode base64 string to PIL Image"""
    try:
        if "," in base64_string:
            base64_string = base64_string.split(",")[1]
        
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data))
        
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
            
        return image
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid base64 image: {str(e)}")

def encode_image(image: Image.Image):
    """Encode image for the model"""
    return model.encode_image(image)

def generate_caption(image: Image.Image) -> str:
    """Generate a caption for the image"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not initialized")
    
    try:
        # Encode the image
        image_embeds = encode_image(image)
        
        # Generate caption
        prompt = "<image>\n\nQuestion: Describe this image in detail.\n\nAnswer:"
        
        # Tokenize the prompt
        inputs = tokenizer(prompt, return_tensors="pt").to(device)
        
        # Generate
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                image_embeds=image_embeds,
                max_new_tokens=150,
                temperature=0.7,
                do_sample=True
            )
        
        # Decode the output
        caption = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Extract just the answer part
        if "Answer:" in caption:
            caption = caption.split("Answer:")[-1].strip()
        
        return caption
        
    except Exception as e:
        # Fallback method
        try:
            enc_image = model.encode_image(image)
            caption = model.answer_question(enc_image, "Describe this image in detail.", tokenizer)
            return caption
        except:
            raise HTTPException(status_code=500, detail=f"Error generating caption: {str(e)}")

def answer_question(image: Image.Image, question: str) -> str:
    """Answer a question about the image"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not initialized")
    
    try:
        # Encode the image
        enc_image = model.encode_image(image)
        
        # Answer the question
        answer = model.answer_question(enc_image, question, tokenizer)
        
        return answer
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error answering question: {str(e)}")

def detect_objects(image: Image.Image, object_name: str) -> List[Dict]:
    """Detect objects in the image"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not initialized")
    
    try:
        question = f"Can you detect and locate any {object_name} in this image? Please describe their positions."
        answer = answer_question(image, question)
        
        # Parse the answer to extract detection info
        detections = []
        if object_name.lower() in answer.lower():
            detections.append({
                "object": object_name,
                "found": True,
                "description": answer
            })
        else:
            detections.append({
                "object": object_name,
                "found": False,
                "description": answer
            })
        
        return detections
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error detecting objects: {str(e)}")

def point_to_object(image: Image.Image, object_name: str) -> Dict:
    """Get location of object in the image"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not initialized")
    
    try:
        question = f"Where exactly is the {object_name} located in this image? Please describe its position using terms like top, bottom, left, right, center."
        answer = answer_question(image, question)
        
        return {
            "object": object_name,
            "location": answer
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error locating object: {str(e)}")

@app.post("/caption")
async def caption_endpoint(request: CaptionRequest):
    """Generate a caption for an image - NO API KEY REQUIRED"""
    image = decode_base64_image(request.image)
    
    loop = asyncio.get_event_loop()
    caption = await loop.run_in_executor(executor, generate_caption, image)
    
    return {
        "caption": caption,
        "status": "success",
        "mode": "self-hosted"
    }

@app.post("/query")
async def query_endpoint(request: QueryRequest):
    """Answer a question about an image - NO API KEY REQUIRED"""
    image = decode_base64_image(request.image)
    
    loop = asyncio.get_event_loop()
    answer = await loop.run_in_executor(executor, answer_question, image, request.question)
    
    return {
        "answer": answer,
        "question": request.question,
        "status": "success",
        "mode": "self-hosted"
    }

@app.post("/detect")
async def detect_endpoint(request: DetectRequest):
    """Detect objects in an image - NO API KEY REQUIRED"""
    image = decode_base64_image(request.image)
    
    loop = asyncio.get_event_loop()
    detections = await loop.run_in_executor(executor, detect_objects, image, request.object)
    
    return {
        "detections": detections,
        "object": request.object,
        "status": "success",
        "mode": "self-hosted"
    }

@app.post("/point")
async def point_endpoint(request: PointRequest):
    """Point to object in an image - NO API KEY REQUIRED"""
    image = decode_base64_image(request.image)
    
    loop = asyncio.get_event_loop()
    location = await loop.run_in_executor(executor, point_to_object, image, request.object)
    
    return {
        "coordinates": location,
        "object": request.object,
        "status": "success",
        "mode": "self-hosted"
    }

@app.post("/upload/caption")
async def upload_caption(file: UploadFile = File(...)):
    """Generate caption for uploaded image - NO API KEY REQUIRED"""
    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        loop = asyncio.get_event_loop()
        caption = await loop.run_in_executor(executor, generate_caption, image)
        
        return {
            "caption": caption,
            "filename": file.filename,
            "status": "success",
            "mode": "self-hosted"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error: {str(e)}")

@app.post("/upload/query")
async def upload_query(question: str, file: UploadFile = File(...)):
    """Answer question about uploaded image - NO API KEY REQUIRED"""
    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        loop = asyncio.get_event_loop()
        answer = await loop.run_in_executor(executor, answer_question, image, question)
        
        return {
            "answer": answer,
            "question": question,
            "filename": file.filename,
            "status": "success",
            "mode": "self-hosted"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error: {str(e)}")

if __name__ == "__main__":
    print("Starting SELF-HOSTED Moondream API - No API keys required!")
    uvicorn.run(app, host="0.0.0.0", port=8001)