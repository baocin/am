from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel, HttpUrl
from rapidocr_onnxruntime import RapidOCR
import base64
import io
import os
import tempfile
from PIL import Image
import numpy as np
from typing import Optional, List, Dict, Any
import requests
import logging
import shutil
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="RapidOCR Raw API", version="1.0.0")

# Model paths configuration
MODEL_DIR = os.environ.get("MODEL_DIR", "/app/models")
AUTO_DOWNLOAD_MODELS = os.environ.get("AUTO_DOWNLOAD_MODELS", "true").lower() == "true"

def download_default_models():
    """
    Download default RapidOCR models to the volume mount if they don't exist.
    This extracts models from the installed package and saves them to the volume.
    """
    os.makedirs(MODEL_DIR, exist_ok=True)
    
    # Try to find the installed rapidocr package models
    try:
        import rapidocr_onnxruntime
        package_dir = Path(rapidocr_onnxruntime.__file__).parent
        
        # Common model file names in the package
        model_files = {
            "ch_PP-OCRv4_det_infer.onnx": "models/ch_PP-OCRv4_det_infer.onnx",
            "ch_PP-OCRv4_rec_infer.onnx": "models/ch_PP-OCRv4_rec_infer.onnx", 
            "ch_PP-OCRv4_cls_infer.onnx": "models/ch_PP-OCRv4_cls_infer.onnx",
            "ch_ppocr_mobile_v2.0_det_infer.onnx": "models/ch_ppocr_mobile_v2.0_det_infer.onnx",
            "ch_ppocr_mobile_v2.0_rec_infer.onnx": "models/ch_ppocr_mobile_v2.0_rec_infer.onnx",
            "ch_ppocr_mobile_v2.0_cls_infer.onnx": "models/ch_ppocr_mobile_v2.0_cls_infer.onnx",
        }
        
        models_copied = []
        
        # Search for models in the package directory
        for root, dirs, files in os.walk(package_dir):
            for file in files:
                if file.endswith('.onnx'):
                    source_path = os.path.join(root, file)
                    dest_path = os.path.join(MODEL_DIR, file)
                    
                    if not os.path.exists(dest_path):
                        logger.info(f"Copying model {file} to {dest_path}")
                        shutil.copy2(source_path, dest_path)
                        models_copied.append(file)
                    else:
                        logger.info(f"Model {file} already exists in {MODEL_DIR}")
        
        if models_copied:
            logger.info(f"Successfully copied {len(models_copied)} models to {MODEL_DIR}")
            return True
        else:
            logger.info("No new models copied - models may already exist or package structure is different")
            return False
            
    except Exception as e:
        logger.error(f"Error copying default models: {e}")
        return False

def initialize_engine():
    """Initialize RapidOCR engine with proper model paths"""
    
    # Check if models directory exists and has models
    models_exist = os.path.exists(MODEL_DIR) and any(f.endswith('.onnx') for f in os.listdir(MODEL_DIR))
    
    if not models_exist and AUTO_DOWNLOAD_MODELS:
        logger.info(f"No models found in {MODEL_DIR}, attempting to copy from package...")
        download_default_models()
        # Re-check after download attempt
        models_exist = os.path.exists(MODEL_DIR) and any(f.endswith('.onnx') for f in os.listdir(MODEL_DIR))
    
    if models_exist:
        logger.info(f"Loading models from {MODEL_DIR}")
        model_files = [f for f in os.listdir(MODEL_DIR) if f.endswith('.onnx')]
        logger.info(f"Found model files: {model_files}")
        
        # Try to find the specific model files
        det_model = None
        rec_model = None
        cls_model = None
        
        for file in model_files:
            file_path = os.path.join(MODEL_DIR, file)
            if 'det' in file.lower():
                det_model = file_path
                logger.info(f"Using detection model: {file}")
            elif 'rec' in file.lower():
                rec_model = file_path
                logger.info(f"Using recognition model: {file}")
            elif 'cls' in file.lower():
                cls_model = file_path
                logger.info(f"Using classification model: {file}")
        
        # Initialize with found models
        if det_model or rec_model:
            return RapidOCR(
                det_model_path=det_model,
                rec_model_path=rec_model,
                cls_model_path=cls_model
            )
        else:
            logger.warning("Found ONNX files but couldn't identify model types, using defaults")
            return RapidOCR()
    else:
        logger.warning(f"No models found in {MODEL_DIR}, using default models from package")
        return RapidOCR()

# Initialize the engine and track model loading status
engine = initialize_engine()
models_loaded_from_volume = os.path.exists(MODEL_DIR) and any(f.endswith('.onnx') for f in os.listdir(MODEL_DIR) if os.path.exists(MODEL_DIR))

class OCRRequest(BaseModel):
    """Request model for OCR with base64 image"""
    image_base64: str
    visualize: bool = False

class OCRURLRequest(BaseModel):
    """Request model for OCR with image URL"""
    image_url: HttpUrl
    visualize: bool = False

class OCRResponse(BaseModel):
    """Response model for OCR results"""
    success: bool
    text: Optional[str] = None
    boxes: Optional[List[Dict[str, Any]]] = None
    error: Optional[str] = None
    visualization_path: Optional[str] = None

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "RapidOCR Raw API",
        "version": "1.0.0",
        "endpoints": {
            "/ocr/file": "POST - Upload image file for OCR",
            "/ocr/base64": "POST - Send base64 encoded image for OCR",
            "/ocr/url": "POST - Send image URL for OCR",
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
        "service": "rapidocr",
        "model_dir": MODEL_DIR,
        "models_loaded_from_volume": models_loaded_from_volume
    }

@app.post("/ocr/file", response_model=OCRResponse)
async def ocr_from_file(
    file: UploadFile = File(...),
    visualize: bool = False
):
    """
    Perform OCR on an uploaded image file
    
    Args:
        file: Image file (JPEG, PNG, etc.)
        visualize: Whether to generate visualization of detected text boxes
    
    Returns:
        OCR results with detected text and bounding boxes
    """
    try:
        # Read file content
        content = await file.read()
        
        # Process with RapidOCR
        result = engine(content)
        
        if result is None or (isinstance(result, tuple) and result[0] is None):
            return OCRResponse(
                success=False,
                error="No text detected in the image"
            )
        
        # Extract text and boxes
        texts = []
        boxes = []
        
        # Debug logging
        logger.info(f"Result type: {type(result)}")
        if isinstance(result, tuple):
            logger.info(f"Result tuple length: {len(result)}")
            for i, item in enumerate(result):
                logger.info(f"Result[{i}] type: {type(item)}, is None: {item is None}")
        
        # RapidOCR can return different formats based on version
        try:
            if isinstance(result, tuple):
                if len(result) == 2:
                    # Format: (result_list, elapsed_time) 
                    actual_results, elapsed = result
                    if actual_results is not None:
                        for item in actual_results:
                            if len(item) == 3:
                                box, text, score = item
                                texts.append(text)
                                boxes.append({
                                    "box": box.tolist() if hasattr(box, 'tolist') else box,
                                    "text": text,
                                    "score": float(score)
                                })
                elif len(result) == 3:
                    # Format: (boxes, texts, scores)
                    boxes_list, texts_list, scores_list = result
                    if boxes_list is not None and texts_list is not None:
                        for box, text, score in zip(boxes_list, texts_list, scores_list):
                            texts.append(text)
                            boxes.append({
                                "box": box.tolist() if hasattr(box, 'tolist') else box,
                                "text": text,
                                "score": float(score)
                            })
            elif isinstance(result, list):
                # Format: list of [box, text, score]
                for item in result:
                    if len(item) == 3:
                        box, text, score = item
                        texts.append(text)
                        boxes.append({
                            "box": box.tolist() if hasattr(box, 'tolist') else box,
                            "text": text,
                            "score": float(score)
                        })
            else:
                logger.error(f"Unexpected result format: {type(result)}")
                return OCRResponse(
                    success=False,
                    error=f"Unexpected OCR result format: {type(result)}"
                )
        except Exception as e:
            logger.error(f"Error processing OCR result: {str(e)}")
            logger.error(f"Result structure: {result}")
            return OCRResponse(
                success=False,
                error=f"Error processing OCR result: {str(e)}"
            )
        
        response = OCRResponse(
            success=True,
            text="\n".join(texts),
            boxes=boxes
        )
        
        # Generate visualization if requested
        if visualize and len(boxes) > 0:
            # Note: Visualization is currently not supported with the new result format
            # You would need to implement custom visualization using PIL/OpenCV
            # For now, we'll skip visualization
            logger.info("Visualization requested but not implemented for current result format")
            response.visualization_path = None
        
        return response
        
    except Exception as e:
        return OCRResponse(
            success=False,
            error=str(e)
        )

@app.post("/ocr/base64", response_model=OCRResponse)
async def ocr_from_base64(request: OCRRequest):
    """
    Perform OCR on a base64 encoded image
    
    Args:
        request: OCRRequest with base64 encoded image
    
    Returns:
        OCR results with detected text and bounding boxes
    """
    try:
        # Decode base64 image
        image_data = base64.b64decode(request.image_base64)
        
        # Process with RapidOCR
        result = engine(image_data)
        
        if result is None:
            return OCRResponse(
                success=False,
                error="No text detected in the image"
            )
        
        # Extract text and boxes
        # RapidOCR returns: (boxes_list, texts_list, scores_list) or list of [box, text, score]
        texts = []
        boxes = []
        
        # Check the format of the result
        if isinstance(result, tuple) and len(result) == 3:
            # New format: (boxes_list, texts_list, scores_list)
            boxes_list, texts_list, scores_list = result
            if boxes_list is not None and texts_list is not None:
                for box, text, score in zip(boxes_list, texts_list, scores_list):
                    texts.append(text)
                    boxes.append({
                        "box": box.tolist() if hasattr(box, 'tolist') else box,
                        "text": text,
                        "score": float(score)
                    })
        elif isinstance(result, list):
            # Old format: list of [box, text, score]
            for detection in result:
                if len(detection) == 3:
                    box, text, score = detection
                    texts.append(text)
                    boxes.append({
                        "box": box.tolist() if hasattr(box, 'tolist') else box,
                        "text": text,
                        "score": float(score)
                    })
        else:
            logger.warning(f"Unexpected result format: {type(result)}")
            return OCRResponse(
                success=False,
                error="Unexpected OCR result format"
            )
        
        response = OCRResponse(
            success=True,
            text="\n".join(texts),
            boxes=boxes
        )
        
        # Generate visualization if requested
        if request.visualize:
            vis_path = f"/tmp/vis_{os.urandom(8).hex()}.jpg"
            result.vis(vis_path)
            response.visualization_path = vis_path
        
        return response
        
    except Exception as e:
        return OCRResponse(
            success=False,
            error=str(e)
        )

@app.post("/ocr/url", response_model=OCRResponse)
async def ocr_from_url(request: OCRURLRequest):
    """
    Perform OCR on an image from URL
    
    Args:
        request: OCRURLRequest with image URL
    
    Returns:
        OCR results with detected text and bounding boxes
    """
    try:
        # Download image from URL
        response = requests.get(str(request.image_url), timeout=30)
        response.raise_for_status()
        
        # Process with RapidOCR
        result = engine(response.content)
        
        if result is None:
            return OCRResponse(
                success=False,
                error="No text detected in the image"
            )
        
        # Extract text and boxes
        texts = []
        boxes = []
        for detection in result:
            box, text, score = detection
            texts.append(text)
            boxes.append({
                "box": box.tolist() if hasattr(box, 'tolist') else box,
                "text": text,
                "score": float(score)
            })
        
        response_data = OCRResponse(
            success=True,
            text="\n".join(texts),
            boxes=boxes
        )
        
        # Generate visualization if requested
        if request.visualize:
            vis_path = f"/tmp/vis_{os.urandom(8).hex()}.jpg"
            result.vis(vis_path)
            response_data.visualization_path = vis_path
        
        return response_data
        
    except requests.RequestException as e:
        return OCRResponse(
            success=False,
            error=f"Failed to download image: {str(e)}"
        )
    except Exception as e:
        return OCRResponse(
            success=False,
            error=str(e)
        )

@app.get("/visualization/{filename}")
async def get_visualization(filename: str):
    """
    Retrieve a generated visualization image
    
    Args:
        filename: Name of the visualization file
    
    Returns:
        The visualization image file
    """
    filepath = f"/tmp/{filename}"
    if os.path.exists(filepath):
        return FileResponse(filepath, media_type="image/jpeg")
    else:
        raise HTTPException(status_code=404, detail="Visualization not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)