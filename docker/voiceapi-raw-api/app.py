from typing import *
from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect, Query, File, UploadFile
from typing import Union, Optional, Dict, Any, List
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
import asyncio
import logging
from pydantic import BaseModel, Field
import uvicorn
from voiceapi.tts import TTSResult, start_tts_stream, TTSStream, _tts_engines as tts_engines
from voiceapi.asr import start_asr_stream, ASRStream, ASRResult, _asr_engines as asr_engines
from voiceapi.speaker_id import start_speaker_stream, SpeakerStream, SpeakerResult, load_speaker_engine, _speaker_engines as speaker_engines
import argparse
import os
import numpy as np
import json
import base64
import time
from datetime import datetime
from uuid import uuid4

# Service metadata
SERVICE_NAME = "Voice API"
SERVICE_VERSION = "2.0.0"

app = FastAPI(title=SERVICE_NAME, version=SERVICE_VERSION)

# Configuration from environment
CONFIG = {
    "MODEL_DIR": os.environ.get("MODEL_DIR", "/app/models"),
    "AUTO_DOWNLOAD": os.environ.get("AUTO_DOWNLOAD_MODELS", "true").lower() == "true",
    "LOG_LEVEL": os.environ.get("LOG_LEVEL", "INFO"),
    "MAX_WORKERS": int(os.environ.get("MAX_WORKERS", "4")),
    "TIMEOUT": int(os.environ.get("TIMEOUT", "300")),
    "DEBUG": os.environ.get("DEBUG", "false").lower() == "true"
}

# Logging setup
logging.basicConfig(level=getattr(logging, CONFIG["LOG_LEVEL"]))
logger = logging.getLogger(__name__)

# Add CORS middleware
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def initialize_models():
    """Initialize all models on startup"""
    logger.info("Initializing models on startup...")
    
    try:
        # Initialize ASR model
        logger.info(f"Loading ASR model: {args.asr_model}")
        from voiceapi.asr import load_asr_engine
        asr_engine = load_asr_engine(16000, args)
        logger.info(f"ASR model loaded successfully")
        
        # Initialize TTS model
        logger.info(f"Loading TTS model: {args.tts_model}")
        from voiceapi.tts import get_tts_engine
        tts_engine, _ = get_tts_engine(args)
        logger.info(f"TTS model loaded successfully")
        
        # Initialize Speaker ID model
        logger.info(f"Loading Speaker ID model: {args.speaker_model}")
        speaker_engine = load_speaker_engine(16000, args)
        logger.info(f"Speaker ID model loaded successfully")
        
    except Exception as e:
        logger.error(f"Failed to initialize models: {e}")
        raise


@app.on_event("startup")
async def load_known_speakers():
    """Load known speakers from JSON file on startup"""
    # Look for known_speakers.json in the models volume first
    known_speakers_file = os.path.join(args.models_root, "known_speakers.json")
    
    # If not in models volume, try other locations
    if not os.path.exists(known_speakers_file):
        for location in ["/app/known_speakers.json", "./known_speakers.json", "known_speakers.json"]:
            if os.path.exists(location):
                known_speakers_file = location
                break
    
    if not os.path.exists(known_speakers_file):
        logger.info("No known_speakers.json file found, starting with empty speaker list")
        return
    
    try:
        with open(known_speakers_file, 'r') as f:
            data = json.load(f)
            
        if 'speakers' not in data:
            logger.warning("known_speakers.json missing 'speakers' key")
            return
            
        # Determine speaker file based on model
        model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
        if model_name == 'nemo-speakernet':
            speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
            expected_dim = 256  # NeMo SpeakerNet actually uses 256 dimensions
        else:
            speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
            expected_dim = 512  # Default for other models
        
        existing_speakers = {}
        
        if os.path.exists(speaker_file):
            with open(speaker_file, 'r') as f:
                existing_speakers = json.load(f)
        
        # Add known speakers
        loaded_count = 0
        for speaker in data['speakers']:
            if 'name' not in speaker or 'embeddings' not in speaker:
                logger.warning(f"Skipping invalid speaker entry: {speaker}")
                continue
                
            name = speaker['name']
            embeddings = speaker['embeddings']
            
            # Skip if embeddings are empty (example entries)
            if not embeddings:
                logger.info(f"Skipping speaker '{name}' with empty embeddings")
                continue
                
            # Validate embedding dimensions
            if len(embeddings) != expected_dim:
                logger.warning(f"Skipping speaker '{name}' with invalid embedding dimensions: {len(embeddings)} (expected {expected_dim} for {model_name})")
                logger.info(f"To use this speaker, either change the speaker model to one that supports {len(embeddings)}-dim embeddings, or re-register the speaker with the current model")
                continue
            
            # Add to speakers
            existing_speakers[name] = embeddings
            loaded_count += 1
            logger.info(f"Loaded known speaker: {name}")
        
        # Save updated speakers file
        if loaded_count > 0:
            os.makedirs(os.path.dirname(speaker_file), exist_ok=True)
            with open(speaker_file, 'w') as f:
                json.dump(existing_speakers, f, indent=2)
            logger.info(f"Loaded {loaded_count} known speakers from {known_speakers_file}")
            
            # Reload speakers into the engine's memory
            await reload_speakers_into_engine()
        else:
            logger.info("No valid speakers found in known_speakers.json")
            
    except Exception as e:
        logger.error(f"Failed to load known speakers: {e}")


async def reload_speakers_into_engine():
    """Reload speakers from file into the speaker engine's memory"""
    try:
        import sherpa_onnx
        from voiceapi.speaker_id import load_speaker_engine
        
        # Get the speaker engine
        extractor, manager = load_speaker_engine(16000, args)
        
        # Clear existing speakers in memory
        model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
        if model_name == 'nemo-speakernet':
            speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
            # Create new manager to clear existing speakers
            manager = sherpa_onnx.SpeakerEmbeddingManager(256)
        else:
            speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
            # Create new manager to clear existing speakers
            manager = sherpa_onnx.SpeakerEmbeddingManager(512)
        
        # Load speakers from file
        if os.path.exists(speaker_file):
            with open(speaker_file, 'r') as f:
                speakers = json.load(f)
                logger.info(f'speaker_id: Reloading {len(speakers)} speakers into engine memory')
                for name, embedding in speakers.items():
                    emb_array = np.array(embedding, dtype=np.float32)
                    manager.add(name, emb_array)
                    logger.info(f'speaker_id: Reloaded speaker: {name} (embedding dim: {len(emb_array)})')
        
        # Update the cached engine with the new manager
        from voiceapi.speaker_id import _speaker_engines
        _speaker_engines[model_name] = (extractor, manager)
        logger.info(f"speaker_id: Successfully reloaded {len(speakers) if os.path.exists(speaker_file) else 0} speakers into engine memory")
        
    except Exception as e:
        logger.error(f"Failed to reload speakers into engine: {e}")


# Global args variable for startup event
args = None


def update_known_speakers_json(name: str, embeddings: List[float]):
    """Update known_speakers.json with new speaker"""
    try:
        known_speakers_file = os.path.join(args.models_root, "known_speakers.json")
        
        # Load existing data or create new structure
        if os.path.exists(known_speakers_file):
            with open(known_speakers_file, 'r') as f:
                data = json.load(f)
        else:
            data = {"speakers": []}
        
        # Check if speaker already exists
        speaker_exists = False
        for i, speaker in enumerate(data.get("speakers", [])):
            if speaker.get("name") == name:
                # Update existing speaker
                data["speakers"][i] = {
                    "name": name,
                    "embeddings": embeddings,
                    "embedding_dim": len(embeddings),
                    "updated_at": time.strftime("%Y-%m-%d %H:%M:%S")
                }
                speaker_exists = True
                break
        
        # Add new speaker if not exists
        if not speaker_exists:
            data["speakers"].append({
                "name": name,
                "embeddings": embeddings,
                "embedding_dim": len(embeddings),
                "created_at": time.strftime("%Y-%m-%d %H:%M:%S")
            })
        
        # Save updated file
        os.makedirs(os.path.dirname(known_speakers_file), exist_ok=True)
        with open(known_speakers_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        logger.info(f"Updated known_speakers.json with speaker: {name}")
        
    except Exception as e:
        logger.error(f"Failed to update known_speakers.json: {e}")


# Base request/response models following API contract
class BaseRequest(BaseModel):
    """Base request model with common fields"""
    request_id: Optional[str] = Field(default_factory=lambda: str(uuid4()))
    timestamp: Optional[datetime] = Field(default_factory=datetime.utcnow)

class BaseResponse(BaseModel):
    """Base response model with standard fields"""
    success: bool
    request_id: Optional[str] = None
    error: Optional[str] = None
    processing_time_ms: Optional[float] = None

class ErrorResponse(BaseModel):
    """Standard error response"""
    success: bool = False
    error: str
    error_code: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

# Service-specific models
class AudioProcessRequest(BaseRequest):
    """Audio processing request"""
    audio_base64: str = Field(..., description="Base64 encoded audio data")
    language: Optional[str] = Field(None, description="Language code (e.g., 'en', 'es')")
    options: Optional[Dict[str, Any]] = Field(default_factory=dict)

class AudioProcessResponse(BaseResponse):
    """Audio processing response"""
    text: Optional[str] = None
    language: Optional[str] = None
    confidence: Optional[float] = None
    speaker: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)

class TTSRequest(BaseRequest):
    """Text-to-speech request"""
    text: str = Field(..., description="Text to convert to speech")
    voice: Optional[Union[str, int]] = Field(0, description="Voice ID to use (0-109 for Kokoro)")
    speed: Optional[float] = Field(1.0, description="Speech speed multiplier")
    options: Optional[Dict[str, Any]] = Field(default_factory=dict)

class TTSResponse(BaseResponse):
    """Text-to-speech response"""
    audio_base64: Optional[str] = None
    duration_ms: Optional[float] = None
    voice_used: Optional[str] = None

class RegisterSpeakerRequest(BaseModel):
    name: str = Field(..., description="Name of the speaker to register")
    embeddings: Optional[List[float]] = Field(None, description="Pre-computed speaker embeddings")
    audio_base64: Optional[str] = Field(None, description="Base64 encoded audio data")

class SpeakerInfo(BaseModel):
    name: str
    embedding_dim: int
    registered_at: Optional[str] = None


@app.get("/")
async def root():
    """Root information endpoint following API contract"""
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "endpoints": {
            "/": "GET - Service information",
            "/health": "GET - Health check",
            "/healthz": "GET - Kubernetes health check",
            "/docs": "GET - API documentation",
            "/demo": "GET - Interactive demo page",
            "/process/audio": "POST - Process audio file for transcription",
            "/process/base64": "POST - Process base64 audio for transcription",
            "/tts/generate": "POST - Generate speech from text",
            "/speakers": "GET - List registered speakers",
            "/speakers/register": "POST - Register new speaker",
            "/speakers/{speaker_name}": "DELETE - Delete registered speaker",
            "/ws/asr": "WebSocket - Real-time speech recognition",
            "/ws/tts": "WebSocket - Real-time text-to-speech",
            "/ws/speaker_id": "WebSocket - Real-time speaker identification"
        },
        "models": {
            "asr": getattr(args, 'asr_model', 'unknown'),
            "tts": getattr(args, 'tts_model', 'unknown'),
            "speaker_id": getattr(args, 'speaker_model', 'unknown')
        }
    }

@app.get("/demo", response_class=HTMLResponse)
async def demo_page():
    """Serve interactive demo page"""
    # Try to find index.html relative to this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    index_path = os.path.join(script_dir, "index.html")
    
    try:
        with open(index_path, "r") as f:
            return HTMLResponse(content=f.read())
    except FileNotFoundError:
        # Try current directory
        try:
            with open("index.html", "r") as f:
                return HTMLResponse(content=f.read())
        except FileNotFoundError:
            # Fallback
            return HTMLResponse(content="<h1>STT-Whisper Demo</h1><p>Demo page not found. API is running.</p>")


@app.get("/health")
@app.get("/healthz")
async def health_check():
    """Health check endpoint following API contract"""
    try:
        # Check if ASR model is loaded
        asr_model = asr_engines.get(args.asr_model) if hasattr(args, 'asr_model') else None
        asr_healthy = asr_model is not None
        
        # Check if TTS model is loaded
        tts_model = tts_engines.get(args.tts_model) if hasattr(args, 'tts_model') else None
        tts_healthy = tts_model is not None
        
        # Check if speaker model is loaded (if speaker features are being used)
        speaker_healthy = True
        if hasattr(args, 'speaker_model') and args.speaker_model:
            speaker_model = speaker_engines.get(args.speaker_model)
            speaker_healthy = speaker_model is not None
        
        all_healthy = asr_healthy and tts_healthy and speaker_healthy
        
        response = {
            "status": "healthy" if all_healthy else "degraded",
            "service": "voice-api",
            "version": SERVICE_VERSION,
            "timestamp": datetime.utcnow().isoformat(),
            "dependencies": {
                "asr_model": asr_healthy,
                "tts_model": tts_healthy,
                "speaker_model": speaker_healthy,
                "models_loaded": all_healthy
            }
        }
        
        if not all_healthy:
            return JSONResponse(status_code=503, content=response)
        
        return response
        
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "service": "voice-api",
                "version": SERVICE_VERSION,
                "timestamp": datetime.utcnow().isoformat(),
                "error": str(e)
            }
        )


@app.get("/speakers", response_model=List[SpeakerInfo])
async def get_registered_speakers():
    """Get list of all registered speakers"""
    speakers = []
    
    # Check both speaker files based on model
    model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
    if model_name == 'nemo-speakernet':
        speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
    else:
        speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
    
    if os.path.exists(speaker_file):
        try:
            with open(speaker_file, 'r') as f:
                speaker_data = json.load(f)
                for name, embedding in speaker_data.items():
                    speakers.append(SpeakerInfo(
                        name=name,
                        embedding_dim=len(embedding)
                    ))
        except Exception as e:
            logger.error(f"Failed to load speakers: {e}")
    
    return speakers


@app.post("/speakers/register")
async def register_speaker_direct(request: RegisterSpeakerRequest):
    """Register a speaker with embeddings or audio"""
    try:
        # Load speaker engine
        extractor, manager = load_speaker_engine(16000, args)
        
        if request.embeddings:
            # Direct embedding registration
            embeddings = np.array(request.embeddings, dtype=np.float32)
        elif request.audio_base64:
            # Extract embeddings from audio
            audio_bytes = base64.b64decode(request.audio_base64)
            audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            
            stream = extractor.create_stream()
            stream.accept_waveform(16000, audio_array)
            
            if not extractor.is_ready(stream):
                raise HTTPException(status_code=400, detail="Not enough audio for speaker identification")
            
            embeddings = extractor.compute(stream)
        else:
            raise HTTPException(status_code=400, detail="Either embeddings or audio_base64 must be provided")
        
        # Ensure embeddings is numpy array
        if isinstance(embeddings, list):
            embeddings = np.array(embeddings, dtype=np.float32)
        
        # Add to manager
        manager.add(request.name, embeddings)
        
        # Save to persistence file
        embeddings_list = embeddings.tolist() if hasattr(embeddings, 'tolist') else list(embeddings)
        
        # Determine speaker file based on embedding dimension
        if len(embeddings) == 256:
            speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
        else:
            speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
        
        # Load existing speakers
        existing_speakers = {}
        if os.path.exists(speaker_file):
            with open(speaker_file, 'r') as f:
                existing_speakers = json.load(f)
        
        # Add new speaker
        existing_speakers[request.name] = embeddings_list
        
        # Save back to file
        with open(speaker_file, 'w') as f:
            json.dump(existing_speakers, f, indent=2)
        
        # Update known_speakers.json
        update_known_speakers_json(request.name, embeddings_list)
        
        return {
            "status": "success",
            "name": request.name,
            "embeddings": embeddings_list,
            "embedding_dim": len(embeddings_list)
        }
        
    except HTTPException:
        # Let HTTPException propagate with its original status code
        raise
    except Exception as e:
        logger.error(f"Failed to register speaker: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/speakers/{speaker_name}")
async def delete_speaker(speaker_name: str):
    """Delete a registered speaker"""
    try:
        # Determine speaker file based on model
        model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
        if model_name == 'nemo-speakernet':
            speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
        else:
            speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
        
        if not os.path.exists(speaker_file):
            raise HTTPException(status_code=404, detail="No speakers registered")
        
        # Load existing speakers
        with open(speaker_file, 'r') as f:
            existing_speakers = json.load(f)
        
        if speaker_name not in existing_speakers:
            raise HTTPException(status_code=404, detail=f"Speaker '{speaker_name}' not found")
        
        # Remove speaker
        del existing_speakers[speaker_name]
        
        # Save back to file
        with open(speaker_file, 'w') as f:
            json.dump(existing_speakers, f, indent=2)
        
        return {"status": "success", "message": f"Speaker '{speaker_name}' deleted"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete speaker: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# New processing endpoints following API contract
@app.post("/process/audio", response_model=AudioProcessResponse)
async def process_audio_file(
    file: UploadFile = File(..., description="Audio file to transcribe"),
    language: Optional[str] = None,
    include_speaker: bool = False
):
    """Process audio file for transcription"""
    start_time = time.time()
    request_id = str(uuid4())
    
    try:
        # Validate file type
        if not file.content_type.startswith("audio/"):
            raise HTTPException(400, "Invalid file type. Must be an audio file.")
        
        # Read audio data
        audio_bytes = await file.read()
        
        # Convert to numpy array
        audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        
        # Process with ASR
        asr_engine = asr_engines.get(args.asr_model)
        if not asr_engine:
            raise HTTPException(503, "ASR model not available")
        
        # Create stream and process
        stream = asr_engine.create_stream()
        asr_engine.accept_waveform(16000, audio_array, stream)
        
        # Get transcription
        text = ""
        while asr_engine.is_ready(stream):
            result = asr_engine.get(stream)
            text += result.text + " "
        
        # Speaker identification if requested
        speaker = None
        if include_speaker and hasattr(args, 'speaker_model'):
            speaker_engine = speaker_engines.get(args.speaker_model)
            if speaker_engine:
                extractor, manager = speaker_engine
                speaker_stream = extractor.create_stream()
                speaker_stream.accept_waveform(16000, audio_array)
                if extractor.is_ready(speaker_stream):
                    embedding = extractor.compute(speaker_stream)
                    speaker_name = manager.search(embedding, threshold=args.speaker_threshold)
                    if speaker_name:
                        speaker = speaker_name
        
        processing_time = (time.time() - start_time) * 1000
        
        return AudioProcessResponse(
            success=True,
            request_id=request_id,
            text=text.strip(),
            language=language,
            speaker=speaker,
            processing_time_ms=processing_time
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error processing audio: {e}")
        processing_time = (time.time() - start_time) * 1000
        return AudioProcessResponse(
            success=False,
            request_id=request_id,
            error=str(e),
            processing_time_ms=processing_time
        )


@app.post("/process/base64", response_model=AudioProcessResponse)
async def process_audio_base64(request: AudioProcessRequest):
    """Process base64 encoded audio for transcription"""
    start_time = time.time()
    
    try:
        # Decode base64 audio
        audio_bytes = base64.b64decode(request.audio_base64)
        
        # Convert to numpy array
        audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        
        # Process with ASR
        asr_engine = asr_engines.get(args.asr_model)
        if not asr_engine:
            raise HTTPException(503, "ASR model not available")
        
        # Create stream and process
        stream = asr_engine.create_stream()
        asr_engine.accept_waveform(16000, audio_array, stream)
        
        # Get transcription
        text = ""
        while asr_engine.is_ready(stream):
            result = asr_engine.get(stream)
            text += result.text + " "
        
        # Speaker identification if requested
        speaker = None
        if request.options.get("include_speaker") and hasattr(args, 'speaker_model'):
            speaker_engine = speaker_engines.get(args.speaker_model)
            if speaker_engine:
                extractor, manager = speaker_engine
                speaker_stream = extractor.create_stream()
                speaker_stream.accept_waveform(16000, audio_array)
                if extractor.is_ready(speaker_stream):
                    embedding = extractor.compute(speaker_stream)
                    speaker_name = manager.search(embedding, threshold=args.speaker_threshold)
                    if speaker_name:
                        speaker = speaker_name
        
        processing_time = (time.time() - start_time) * 1000
        
        return AudioProcessResponse(
            success=True,
            request_id=request.request_id,
            text=text.strip(),
            language=request.language,
            speaker=speaker,
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        logger.error(f"Error processing base64 audio: {e}")
        processing_time = (time.time() - start_time) * 1000
        return AudioProcessResponse(
            success=False,
            request_id=request.request_id,
            error=str(e),
            processing_time_ms=processing_time
        )


@app.post("/tts/generate", response_model=TTSResponse)
async def generate_speech(request: TTSRequest):
    """Generate speech from text"""
    start_time = time.time()
    
    try:
        # Get TTS engine
        tts_engine = tts_engines.get(args.tts_model)
        if not tts_engine:
            raise HTTPException(503, "TTS model not available")
        
        # Generate speech
        sample_rate = tts_engine.sample_rate
        
        # Convert voice name to ID if needed
        voice_id = request.voice
        if isinstance(voice_id, str) and not voice_id.isdigit():
            # Map voice name to ID (default to 0 if not found)
            voice_id = 0  # Default voice
        elif isinstance(voice_id, str) and voice_id.isdigit():
            voice_id = int(voice_id)
        
        audio_result = tts_engine.generate(
            request.text,
            sid=voice_id,
            speed=request.speed
        )
        
        # Extract audio samples from the result object
        if hasattr(audio_result, 'samples'):
            audio_data = audio_result.samples
            actual_sample_rate = audio_result.sample_rate if hasattr(audio_result, 'sample_rate') else sample_rate
        else:
            audio_data = audio_result
            actual_sample_rate = sample_rate
        
        # Convert to numpy array if it's a list
        if isinstance(audio_data, list):
            audio_data = np.array(audio_data, dtype=np.float32)
        elif not isinstance(audio_data, np.ndarray):
            audio_data = np.array(audio_data, dtype=np.float32)
        
        # Convert to base64
        audio_bytes = (audio_data * 32768).astype(np.int16).tobytes()
        audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')
        
        processing_time = (time.time() - start_time) * 1000
        duration_ms = len(audio_data) / actual_sample_rate * 1000
        
        return TTSResponse(
            success=True,
            request_id=request.request_id,
            audio_base64=audio_base64,
            duration_ms=duration_ms,
            voice_used=request.voice,
            processing_time_ms=processing_time
        )
        
    except Exception as e:
        logger.error(f"Error generating speech: {e}")
        processing_time = (time.time() - start_time) * 1000
        return TTSResponse(
            success=False,
            request_id=request.request_id,
            error=str(e),
            processing_time_ms=processing_time
        )


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler following API contract"""
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content=ErrorResponse(
            error="Internal server error",
            error_code="INTERNAL_ERROR",
            details={"message": str(exc)} if CONFIG["DEBUG"] else None
        ).dict()
    )


# Keep old endpoint for backward compatibility
@app.websocket("/asr")
# New endpoint following API contract
@app.websocket("/ws/asr")
async def websocket_asr(websocket: WebSocket,
                        samplerate: int = Query(16000, title="Sample Rate",
                                                description="The sample rate of the audio."),):
    await websocket.accept()
    logger.info(f"ASR WebSocket connected, sample rate: {samplerate}")
    
    # Check if we have registered speakers for identification
    speaker_engine = None
    try:
        # Determine speaker file based on model
        model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
        if model_name == 'nemo-speakernet':
            speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
        else:
            speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
            
        if os.path.exists(speaker_file):
            with open(speaker_file, 'r') as f:
                speakers = json.load(f)
                if speakers:  # If we have registered speakers
                    speaker_engine = load_speaker_engine(16000, args)
                    logger.info(f"ASR: Speaker identification enabled with {len(speakers)} registered speakers")
    except Exception as e:
        logger.error(f"Failed to load speaker engine for ASR: {e}")
    
    asr_stream: ASRStream = await start_asr_stream(samplerate, args, speaker_engine)
    if not asr_stream:
        logger.error("failed to start ASR stream")
        await websocket.close()
        return

    bytes_received = 0
    async def task_recv_pcm():
        nonlocal bytes_received
        while True:
            pcm_bytes = await websocket.receive_bytes()
            if not pcm_bytes:
                return
            bytes_received += len(pcm_bytes)
            if bytes_received % 32000 == 0:  # Log every ~1 second of audio
                logger.info(f"ASR received {bytes_received} bytes of audio data")
            await asr_stream.write(pcm_bytes)

    async def task_send_result():
        while True:
            result: ASRResult = await asr_stream.read()
            if not result:
                return
            logger.info(f"ASR result: {result.to_dict()}")
            await websocket.send_json(result.to_dict())
    try:
        await asyncio.gather(task_recv_pcm(), task_send_result())
    except WebSocketDisconnect:
        logger.info("asr: disconnected")
    finally:
        await asr_stream.close()


# Keep old endpoint for backward compatibility
@app.websocket("/speaker_id")
# New endpoint following API contract
@app.websocket("/ws/speaker_id")
async def websocket_speaker_id(websocket: WebSocket,
                               samplerate: int = Query(16000, title="Sample Rate",
                                                       description="The sample rate of the audio."),):
    await websocket.accept()
    
    speaker_stream: SpeakerStream = await start_speaker_stream(samplerate, args)
    if not speaker_stream:
        logger.error("failed to start speaker identification stream")
        await websocket.close()
        return

    async def task_recv_pcm():
        while True:
            pcm_bytes = await websocket.receive_bytes()
            if not pcm_bytes:
                return
            await speaker_stream.write(pcm_bytes)

    async def task_send_result():
        while True:
            result: SpeakerResult = await speaker_stream.read()
            if not result:
                return
            await websocket.send_json(result.to_dict())
    try:
        await asyncio.gather(task_recv_pcm(), task_send_result())
    except WebSocketDisconnect:
        logger.info("speaker_id: disconnected")
    finally:
        await speaker_stream.close()


# Keep old endpoint for backward compatibility
@app.websocket("/speaker_register")
# New endpoint following API contract  
@app.websocket("/ws/speaker_register")
async def websocket_speaker_register(websocket: WebSocket,
                                   name: str = Query(..., title="Speaker Name",
                                                    description="Name to register for this speaker."),
                                   samplerate: int = Query(16000, title="Sample Rate",
                                                          description="The sample rate of the audio."),):
    await websocket.accept()
    
    speaker_stream: SpeakerStream = await start_speaker_stream(samplerate, args)
    if not speaker_stream:
        logger.error("failed to start speaker registration stream")
        await websocket.close()
        return

    # Collect audio samples for registration
    audio_buffer = []
    min_duration = 5.0  # Need 5 seconds for registration
    
    try:
        while True:
            pcm_bytes = await websocket.receive_bytes()
            if not pcm_bytes:
                break
                
            pcm_data = np.frombuffer(pcm_bytes, dtype=np.int16)
            samples = pcm_data.astype(np.float32) / 32768.0
            audio_buffer.extend(samples)
            
            # Check if we have enough audio
            duration = len(audio_buffer) / samplerate
            if duration >= min_duration:
                # Register the speaker
                audio_array = np.array(audio_buffer, dtype=np.float32)
                success = await speaker_stream.register_speaker(name, audio_array)
                
                if success:
                    # Get the embeddings that were just registered
                    embeddings_list = speaker_stream.registered_speakers.get(name, [])
                    
                    # Update known_speakers.json
                    update_known_speakers_json(name, embeddings_list)
                    
                    await websocket.send_json({
                        "status": "success",
                        "message": f"Speaker '{name}' registered successfully!",
                        "duration": duration,
                        "embeddings": embeddings_list,
                        "embedding_dim": len(embeddings_list)
                    })
                    logger.info(f"speaker_register: Registered speaker '{name}'")
                else:
                    await websocket.send_json({
                        "status": "error",
                        "message": f"Failed to register speaker '{name}'",
                        "duration": duration,
                        "embeddings": [],
                        "embedding_dim": 0
                    })
                    logger.error(f"speaker_register: Failed to register speaker '{name}'")
                break
            else:
                # Send progress update
                await websocket.send_json({
                    "status": "recording",
                    "progress": min(100, int((duration / min_duration) * 100)),
                    "duration": duration
                })
                
    except WebSocketDisconnect:
        logger.info("speaker_register: disconnected")
    finally:
        await speaker_stream.close()


# Keep old endpoint for backward compatibility
@app.websocket("/tts")
# New endpoint following API contract
@app.websocket("/ws/tts")
async def websocket_tts(websocket: WebSocket,
                        samplerate: int = Query(16000,
                                                title="Sample Rate",
                                                description="The sample rate of the generated audio."),
                        interrupt: bool = Query(True,
                                                title="Interrupt",
                                                description="Interrupt the current TTS stream when a new text is received."),
                        sid: Union[int, str] = Query(0,
                                         title="Speaker ID",
                                         description="The ID of the speaker to use for TTS. For Kokoro, use voice name like 'af_bella'."),
                        chunk_size: int = Query(1024,
                                                title="Chunk Size",
                                                description="The size of the chunk to send to the client."),
                        speed: float = Query(1.0,
                                             title="Speed",
                                             description="The speed of the generated audio."),
                        split: bool = Query(True,
                                            title="Split",
                                            description="Split the text into sentences.")):

    await websocket.accept()
    tts_stream: TTSStream = None

    async def task_recv_text():
        nonlocal tts_stream
        while True:
            text = await websocket.receive_text()
            if not text:
                return

            if interrupt or not tts_stream:
                if tts_stream:
                    await tts_stream.close()
                    logger.info("tts: stream interrupt")

                tts_stream = await start_tts_stream(sid, samplerate, speed, args)
                if not tts_stream:
                    logger.error("tts: failed to allocate tts stream")
                    await websocket.close()
                    return
            logger.info(f"tts: received: {text} (split={split})")
            await tts_stream.write(text, split)

    async def task_send_pcm():
        nonlocal tts_stream
        while not tts_stream:
            # wait for tts stream to be created
            await asyncio.sleep(0.1)

        while True:
            result: TTSResult = await tts_stream.read()
            if not result:
                return

            if result.finished:
                await websocket.send_json(result.to_dict())
            else:
                for i in range(0, len(result.pcm_bytes), chunk_size):
                    await websocket.send_bytes(result.pcm_bytes[i:i+chunk_size])

    try:
        await asyncio.gather(task_recv_text(), task_send_pcm())
    except WebSocketDisconnect:
        logger.info("tts: disconnected")
    finally:
        if tts_stream:
            await tts_stream.close()


class TTSRequest(BaseModel):
    text: str = Field(..., title="Text",
                      description="The text to be converted to speech.",
                      examples=["Hello, world!"])
    sid: int = Field(0, title="Speaker ID",
                     description="The ID of the speaker to use for TTS.")
    samplerate: int = Field(16000, title="Sample Rate",
                            description="The sample rate of the generated audio.")
    speed: float = Field(1.0, title="Speed",
                         description="The speed of the generated audio.")


@ app.post("/tts",
           description="Generate speech audio from text.",
           response_class=StreamingResponse, responses={200: {"content": {"audio/wav": {}}}})
async def tts_generate(req: TTSRequest):
    if not req.text:
        raise HTTPException(status_code=400, detail="text is required")

    tts_stream = await start_tts_stream(req.sid, req.samplerate, req.speed,  args)
    if not tts_stream:
        raise HTTPException(
            status_code=500, detail="failed to start TTS stream")

    r = await tts_stream.generate(req.text)
    return StreamingResponse(r, media_type="audio/wav")


if __name__ == "__main__":
    models_root = './models'

    for d in ['.', '..', '../..']:
        if os.path.isdir(f'{d}/models'):
            models_root = f'{d}/models'
            break

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000, help="port number")
    parser.add_argument("--addr", type=str,
                        default="0.0.0.0", help="serve address")

    parser.add_argument("--asr-provider", type=str,
                        default="cpu", help="asr provider, cpu or cuda")
    parser.add_argument("--tts-provider", type=str,
                        default="cpu", help="tts provider, cpu or cuda")

    parser.add_argument("--threads", type=int, default=2,
                        help="number of threads")

    parser.add_argument("--models-root", type=str, default=models_root,
                        help="model root directory")

    parser.add_argument("--asr-model", type=str, default='parakeet-offline',
                        help="ASR model name: zipformer-bilingual, sensevoice, paraformer-trilingual, paraformer-en, parakeet-offline, fireredasr")

    parser.add_argument("--asr-lang", type=str, default='en',
                        help="ASR language, zh, en, ja, ko, yue")

    parser.add_argument("--tts-model", type=str, default='kokoro-multi-lang-v1_0',
                        help="TTS model name: vits-zh-hf-theresa, vits-melo-tts-zh_en, kokoro-multi-lang-v1_0")
    
    parser.add_argument("--speaker-model", type=str, default='nemo-speakernet',
                        help="Speaker ID model name: wespeaker-voxceleb, 3dspeaker, nemo-speakernet")
    
    parser.add_argument("--speaker-threshold", type=float, default=0.7,
                        help="Similarity threshold for speaker identification (0.0-1.0, higher = stricter)")

    # Parse args (args is already declared at module level)
    args = parser.parse_args()

    if args.tts_model == 'vits-melo-tts-zh_en' and args.tts_provider == 'cuda':
        logger.warning(
            "vits-melo-tts-zh_en does not support CUDA fallback to CPU")
        args.tts_provider = 'cpu'

    # API only - no static files
    # Frontend should be served separately

    logging.basicConfig(format='%(levelname)s: %(asctime)s %(name)s:%(lineno)s %(message)s',
                        level=logging.INFO)
    uvicorn.run(app, host=args.addr, port=args.port)
