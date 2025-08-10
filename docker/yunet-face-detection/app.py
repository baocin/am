from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel, HttpUrl
import cv2
import base64
import io
import os
import tempfile
import numpy as np
from typing import Optional, List, Dict, Any
import requests
import logging
from pathlib import Path
from PIL import Image
import shutil
import time

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="YuNet Face Detection Raw API", version="1.0.0")

# Model configuration
MODEL_DIR = os.environ.get("MODEL_DIR", "/app/models")
MODEL_NAME = os.environ.get("MODEL_NAME", "face_detection_yunet_2023mar_int8.onnx")
SCORE_THRESHOLD = float(os.environ.get("SCORE_THRESHOLD", "0.7"))
NMS_THRESHOLD = float(os.environ.get("NMS_THRESHOLD", "0.3"))
TOP_K = int(os.environ.get("TOP_K", "5000"))
AUTO_DOWNLOAD_MODELS = os.environ.get("AUTO_DOWNLOAD_MODELS", "true").lower() == "true"

# Global face detector
face_detector = None
models_loaded_from_volume = False

def download_default_model():
    """
    Download the default YuNet model if it doesn't exist.
    This downloads the model from OpenCV Zoo GitHub repository.
    """
    os.makedirs(MODEL_DIR, exist_ok=True)
    
    model_path = os.path.join(MODEL_DIR, MODEL_NAME)
    
    if os.path.exists(model_path):
        logger.info(f"Model already exists at {model_path}")
        return True
    
    try:
        # Download YuNet model from OpenCV Zoo
        model_url = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar_int8.onnx"
        
        logger.info(f"Downloading YuNet model from {model_url}...")
        response = requests.get(model_url, stream=True, timeout=60)
        response.raise_for_status()
        
        # Save the model file
        with open(model_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        logger.info(f"Successfully downloaded model to {model_path}")
        return True
        
    except Exception as e:
        logger.error(f"Error downloading model: {e}")
        return False

def initialize_detector():
    """Initialize YuNet face detector with OpenCV DNN"""
    global face_detector, models_loaded_from_volume
    
    model_path = os.path.join(MODEL_DIR, MODEL_NAME)
    
    # Check if model exists
    if not os.path.exists(model_path):
        if AUTO_DOWNLOAD_MODELS:
            logger.info(f"Model not found at {model_path}, attempting to download...")
            if not download_default_model():
                logger.error("Failed to download model")
                models_loaded_from_volume = False
                return None
        else:
            logger.warning(f"Model file not found at {model_path}")
            logger.info("Please download the model from: https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet")
            logger.info("Or set AUTO_DOWNLOAD_MODELS=true to download automatically")
            models_loaded_from_volume = False
            return None
    
    try:
        # Create YuNet face detector
        face_detector = cv2.FaceDetectorYN.create(
            model=model_path,
            config="",
            input_size=(320, 320),  # Default input size, will be adjusted per image
            score_threshold=SCORE_THRESHOLD,
            nms_threshold=NMS_THRESHOLD,
            top_k=TOP_K,
            backend_id=cv2.dnn.DNN_BACKEND_DEFAULT,
            target_id=cv2.dnn.DNN_TARGET_CPU
        )
        models_loaded_from_volume = True
        logger.info(f"Successfully loaded YuNet model from {model_path}")
        logger.info(f"Model size: {os.path.getsize(model_path) / 1024 / 1024:.2f} MB")
        return face_detector
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        models_loaded_from_volume = False
        return None

# Initialize detector on startup
initialize_detector()

class FaceDetectionRequest(BaseModel):
    """Request model for face detection with base64 image"""
    image_base64: str
    score_threshold: Optional[float] = SCORE_THRESHOLD
    nms_threshold: Optional[float] = NMS_THRESHOLD
    top_k: Optional[int] = TOP_K
    visualize: bool = False

class FaceDetectionURLRequest(BaseModel):
    """Request model for face detection with image URL"""
    image_url: HttpUrl
    score_threshold: Optional[float] = SCORE_THRESHOLD
    nms_threshold: Optional[float] = NMS_THRESHOLD
    top_k: Optional[int] = TOP_K
    visualize: bool = False

class FaceDetectionResponse(BaseModel):
    """Response model for face detection results"""
    success: bool
    faces: Optional[List[Dict[str, Any]]] = None
    face_count: int = 0
    error: Optional[str] = None
    processing_time_ms: Optional[float] = None
    visualization_path: Optional[str] = None

def create_visualization(image: np.ndarray, faces: List[Dict[str, Any]]) -> str:
    """
    Create a visualization of detected faces with bounding boxes and landmarks.
    
    Args:
        image: Original image as numpy array
        faces: List of detected faces with bounding boxes and landmarks
    
    Returns:
        Path to the saved visualization image
    """
    vis_image = image.copy()
    
    for face in faces:
        bbox = face['bbox']
        x, y, w, h = bbox
        confidence = face['confidence']
        landmarks = face['landmarks']
        
        # Draw bounding box
        cv2.rectangle(vis_image, (x, y), (x + w, y + h), (0, 255, 0), 2)
        
        # Draw confidence score
        label = f"{confidence:.2f}"
        cv2.putText(vis_image, label, (x, y - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
        
        # Draw landmarks
        for landmark in landmarks:
            lx, ly = int(landmark[0]), int(landmark[1])
            cv2.circle(vis_image, (lx, ly), 3, (0, 0, 255), -1)
    
    # Save visualization
    vis_path = f"/tmp/vis_{os.urandom(8).hex()}.jpg"
    cv2.imwrite(vis_path, vis_image)
    
    return vis_path

def detect_faces(image: np.ndarray, score_threshold: float = SCORE_THRESHOLD, 
                 nms_threshold: float = NMS_THRESHOLD, top_k: int = TOP_K) -> List[Dict[str, Any]]:
    """
    Detect faces in an image using YuNet
    
    Args:
        image: Input image as numpy array (BGR format)
        score_threshold: Minimum confidence score for face detection
        nms_threshold: NMS threshold for duplicate removal
        top_k: Maximum number of faces to detect
    
    Returns:
        List of detected faces with bounding boxes and landmarks
    """
    if face_detector is None:
        raise RuntimeError("Face detector not initialized")
    
    height, width = image.shape[:2]
    
    # Update detector settings
    face_detector.setInputSize((width, height))
    face_detector.setScoreThreshold(score_threshold)
    face_detector.setNMSThreshold(nms_threshold)
    face_detector.setTopK(top_k)
    
    # Detect faces
    _, faces = face_detector.detect(image)
    
    if faces is None:
        return []
    
    # Parse detection results
    detected_faces = []
    for face in faces:
        # YuNet returns: x, y, width, height, landmark_x1, landmark_y1, ..., confidence
        x, y, w, h = face[:4].astype(int)
        confidence = float(face[-1])
        
        # Extract 5 facial landmarks (eyes, nose, mouth corners)
        landmarks = []
        for i in range(5):
            landmark_x = float(face[4 + i*2])
            landmark_y = float(face[4 + i*2 + 1])
            landmarks.append([landmark_x, landmark_y])
        
        detected_faces.append({
            "bbox": [int(x), int(y), int(w), int(h)],
            "confidence": confidence,
            "landmarks": landmarks,
            "landmark_labels": ["left_eye", "right_eye", "nose_tip", "left_mouth_corner", "right_mouth_corner"]
        })
    
    return detected_faces

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "YuNet Face Detection Raw API",
        "version": "1.0.0",
        "model": MODEL_NAME,
        "endpoints": {
            "/face-detect/file": "POST - Upload image file for face detection",
            "/face-detect/base64": "POST - Send base64 encoded image for face detection",
            "/face-detect/url": "POST - Send image URL for face detection",
            "/visualization/{filename}": "GET - Retrieve visualization image",
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
        "service": "yunet-face-detection",
        "model_dir": MODEL_DIR,
        "model_name": MODEL_NAME,
        "models_loaded_from_volume": models_loaded_from_volume,
        "auto_download_models": AUTO_DOWNLOAD_MODELS,
        "settings": {
            "score_threshold": SCORE_THRESHOLD,
            "nms_threshold": NMS_THRESHOLD,
            "top_k": TOP_K
        }
    }

@app.post("/face-detect/file", response_model=FaceDetectionResponse)
async def face_detect_from_file(
    file: UploadFile = File(...),
    score_threshold: float = SCORE_THRESHOLD,
    nms_threshold: float = NMS_THRESHOLD,
    top_k: int = TOP_K,
    visualize: bool = False
):
    """
    Perform face detection on an uploaded image file
    
    Args:
        file: Image file (JPEG, PNG, etc.)
        score_threshold: Minimum confidence score for face detection
        nms_threshold: NMS threshold for duplicate removal
        top_k: Maximum number of faces to detect
        visualize: Whether to generate visualization of detected faces
    
    Returns:
        Face detection results with bounding boxes and landmarks
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return FaceDetectionResponse(
                success=False,
                error="Model not loaded. Please ensure model file exists in the models directory."
            )
        
        # Read file content
        content = await file.read()
        
        # Convert to OpenCV image
        nparr = np.frombuffer(content, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return FaceDetectionResponse(
                success=False,
                error="Invalid image file"
            )
        
        # Detect faces
        faces = detect_faces(image, score_threshold, nms_threshold, top_k)
        
        processing_time = (time.time() - start_time) * 1000  # Convert to ms
        
        response = FaceDetectionResponse(
            success=True,
            faces=faces,
            face_count=len(faces),
            processing_time_ms=processing_time
        )
        
        # Generate visualization if requested
        if visualize and len(faces) > 0:
            vis_path = create_visualization(image, faces)
            # Return just the filename for the visualization endpoint
            response.visualization_path = os.path.basename(vis_path)
        
        return response
        
    except Exception as e:
        return FaceDetectionResponse(
            success=False,
            error=str(e)
        )

@app.post("/face-detect/base64", response_model=FaceDetectionResponse)
async def face_detect_from_base64(request: FaceDetectionRequest):
    """
    Perform face detection on a base64 encoded image
    
    Args:
        request: FaceDetectionRequest with base64 encoded image and parameters
    
    Returns:
        Face detection results with bounding boxes and landmarks
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return FaceDetectionResponse(
                success=False,
                error="Model not loaded. Please ensure model file exists in the models directory."
            )
        
        # Decode base64 image
        image_data = base64.b64decode(request.image_base64)
        
        # Convert to OpenCV image
        nparr = np.frombuffer(image_data, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return FaceDetectionResponse(
                success=False,
                error="Invalid image data"
            )
        
        # Detect faces
        faces = detect_faces(
            image, 
            request.score_threshold, 
            request.nms_threshold, 
            request.top_k
        )
        
        processing_time = (time.time() - start_time) * 1000  # Convert to ms
        
        response = FaceDetectionResponse(
            success=True,
            faces=faces,
            face_count=len(faces),
            processing_time_ms=processing_time
        )
        
        # Generate visualization if requested
        if request.visualize and len(faces) > 0:
            vis_path = create_visualization(image, faces)
            response.visualization_path = os.path.basename(vis_path)
        
        return response
        
    except Exception as e:
        return FaceDetectionResponse(
            success=False,
            error=str(e)
        )

@app.post("/face-detect/url", response_model=FaceDetectionResponse)
async def face_detect_from_url(request: FaceDetectionURLRequest):
    """
    Perform face detection on an image from URL
    
    Args:
        request: FaceDetectionURLRequest with image URL and parameters
    
    Returns:
        Face detection results with bounding boxes and landmarks
    """
    start_time = time.time()
    
    try:
        if not models_loaded_from_volume:
            return FaceDetectionResponse(
                success=False,
                error="Model not loaded. Please ensure model file exists in the models directory."
            )
        
        # Download image from URL
        response = requests.get(str(request.image_url), timeout=30)
        response.raise_for_status()
        
        # Convert to OpenCV image
        nparr = np.frombuffer(response.content, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return FaceDetectionResponse(
                success=False,
                error="Invalid image from URL"
            )
        
        # Detect faces
        faces = detect_faces(
            image, 
            request.score_threshold, 
            request.nms_threshold, 
            request.top_k
        )
        
        processing_time = (time.time() - start_time) * 1000  # Convert to ms
        
        response = FaceDetectionResponse(
            success=True,
            faces=faces,
            face_count=len(faces),
            processing_time_ms=processing_time
        )
        
        # Generate visualization if requested
        if request.visualize and len(faces) > 0:
            vis_path = create_visualization(image, faces)
            response.visualization_path = os.path.basename(vis_path)
        
        return response
        
    except requests.RequestException as e:
        return FaceDetectionResponse(
            success=False,
            error=f"Failed to download image: {str(e)}"
        )
    except Exception as e:
        return FaceDetectionResponse(
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