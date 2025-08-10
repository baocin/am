from typing import *
import logging
import time
import sherpa_onnx
import os
import asyncio
import numpy as np
import json

logger = logging.getLogger(__file__)
_speaker_engines = {}


class SpeakerResult:
    def __init__(self, speaker_id: str, confidence: float, embeddings: List[float] = None):
        self.speaker_id = speaker_id
        self.confidence = confidence
        self.embeddings = embeddings

    def to_dict(self):
        return {
            "speaker_id": self.speaker_id,
            "confidence": self.confidence,
            "embeddings": self.embeddings if self.embeddings else []
        }


class SpeakerStream:
    def __init__(self, extractor: sherpa_onnx.SpeakerEmbeddingExtractor, 
                 manager: sherpa_onnx.SpeakerEmbeddingManager, sample_rate: int, models_root: str = "/app/models",
                 identification_threshold: float = 0.7) -> None:
        self.extractor = extractor
        self.manager = manager
        self.sample_rate = sample_rate
        self.models_root = models_root
        self.inbuf = asyncio.Queue()
        self.outbuf = asyncio.Queue()
        self.is_closed = False
        self.audio_buffer = []
        self.min_duration = 3.0  # Minimum 3 seconds of audio for identification
        self.registered_speakers = {}  # Cache of registered speakers
        self.identification_threshold = identification_threshold  # Similarity threshold for speaker matching

    async def start(self):
        asyncio.create_task(self.run())

    async def run(self):
        logger.info('speaker_id: start speaker identification')
        while not self.is_closed:
            samples = await self.inbuf.get()
            self.audio_buffer.extend(samples)
            
            # Check if we have enough audio (3 seconds)
            duration = len(self.audio_buffer) / self.sample_rate
            if duration >= self.min_duration:
                # Process the audio
                audio_array = np.array(self.audio_buffer, dtype=np.float32)
                
                # Create a stream and compute embeddings
                stream = self.extractor.create_stream()
                stream.accept_waveform(self.sample_rate, audio_array)
                
                if self.extractor.is_ready(stream):
                    embeddings = self.extractor.compute(stream)
                    
                    # Convert embeddings to list if it's a numpy array
                    embeddings_list = embeddings.tolist() if hasattr(embeddings, 'tolist') else list(embeddings)
                    
                    # Search for the speaker with configurable threshold
                    result = self.manager.search(embeddings, threshold=self.identification_threshold)
                    
                    if result:
                        speaker_name = result  # result is a string (the speaker name)
                        # Since we can't get actual confidence from the API, we'll use threshold as min confidence
                        confidence = self.identification_threshold + 0.05  # Slightly above threshold
                        logger.info(f'speaker_id: Identified speaker: {speaker_name} (threshold: {self.identification_threshold})')
                        self.outbuf.put_nowait(
                            SpeakerResult(speaker_name, confidence, embeddings_list)
                        )
                    else:
                        # Unknown speaker - threshold not met
                        logger.info(f'speaker_id: Unknown speaker detected (no match above {self.identification_threshold} threshold)')
                        self.outbuf.put_nowait(
                            SpeakerResult("unknown", 0.0, embeddings_list)
                        )
                    
                    # Clear buffer for next identification
                    self.audio_buffer = []

    async def close(self):
        self.is_closed = True
        self.outbuf.put_nowait(None)

    async def write(self, pcm_bytes: bytes):
        pcm_data = np.frombuffer(pcm_bytes, dtype=np.int16)
        samples = pcm_data.astype(np.float32) / 32768.0
        self.inbuf.put_nowait(samples)

    async def read(self) -> SpeakerResult:
        return await self.outbuf.get()

    async def register_speaker(self, name: str, audio_samples: np.ndarray) -> bool:
        """Register a new speaker with their voice sample"""
        try:
            stream = self.extractor.create_stream()
            stream.accept_waveform(self.sample_rate, audio_samples)
            
            if self.extractor.is_ready(stream):
                embeddings = self.extractor.compute(stream)
                # Ensure embeddings is a numpy array for the manager
                if isinstance(embeddings, list):
                    embeddings = np.array(embeddings, dtype=np.float32)
                    
                # Add to manager
                self.manager.add(name, embeddings)
                logger.info(f'speaker_id: Added speaker "{name}" to manager with {len(embeddings)} dimensional embedding')
                
                # Save to persistence file
                embeddings_list = embeddings.tolist() if hasattr(embeddings, 'tolist') else list(embeddings)
                self.registered_speakers[name] = embeddings_list
                
                # Determine speaker file based on embedding dimension
                if len(embeddings) == 256:
                    speaker_file = os.path.join(self.models_root, 'registered_speakers_nemo.json')
                else:
                    speaker_file = os.path.join(self.models_root, 'registered_speakers.json')
                
                try:
                    # Load existing speakers first
                    existing_speakers = {}
                    if os.path.exists(speaker_file):
                        with open(speaker_file, 'r') as f:
                            existing_speakers = json.load(f)
                    
                    # Add new speaker
                    existing_speakers[name] = embeddings_list
                    
                    # Save back to file
                    with open(speaker_file, 'w') as f:
                        json.dump(existing_speakers, f, indent=2)
                    
                    logger.info(f'speaker_id: Registered and saved new speaker: {name} to {speaker_file} (total speakers: {len(existing_speakers)})')
                except Exception as save_error:
                    logger.error(f'speaker_id: Failed to save speaker to file: {save_error}')
                
                return True
        except Exception as e:
            logger.error(f'speaker_id: Failed to register speaker {name}: {e}')
        return False


def create_wespeaker_voxceleb(samplerate: int, args):
    """Create WeSpeaker VoxCeleb model for speaker identification"""
    d = os.path.join(args.models_root, 'sherpa-onnx-wespeaker-voxceleb-resnet34')
    if not os.path.exists(d):
        raise ValueError(f"speaker_id: model not found {d}")
    
    model_path = os.path.join(d, 'model.onnx')
    
    # Create config for speaker embedding extractor
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig()
    config.model = model_path
    config.num_threads = args.threads
    config.debug = 0
    config.provider = args.speaker_provider if hasattr(args, 'speaker_provider') else args.asr_provider
    
    # Create the extractor with the config
    extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
    
    # Create manager with embedding dimension
    manager = sherpa_onnx.SpeakerEmbeddingManager(512)  # Embedding dimension
    
    # Load pre-registered speakers if available
    speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
    if os.path.exists(speaker_file):
        try:
            with open(speaker_file, 'r') as f:
                speakers = json.load(f)
                logger.info(f'speaker_id: Loading {len(speakers)} registered speakers from {speaker_file}')
                for name, embedding in speakers.items():
                    emb_array = np.array(embedding, dtype=np.float32)
                    manager.add(name, emb_array)
                    logger.info(f'speaker_id: Loaded speaker: {name} (embedding dim: {len(emb_array)})')
        except Exception as e:
            logger.error(f'speaker_id: Failed to load registered speakers: {e}')
    else:
        logger.info(f'speaker_id: No registered speakers file found at {speaker_file}')
    
    return extractor, manager


def create_3dspeaker(samplerate: int, args):
    """Create 3D-Speaker model for speaker identification"""
    d = os.path.join(args.models_root, 'sherpa-onnx-3dspeaker')
    if not os.path.exists(d):
        raise ValueError(f"speaker_id: model not found {d}")
    
    model_path = os.path.join(d, '3dspeaker_speech_eres2net_base_200k.onnx')
    
    # Create config for speaker embedding extractor
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig()
    config.model = model_path
    config.num_threads = args.threads
    config.debug = 0
    config.provider = args.speaker_provider if hasattr(args, 'speaker_provider') else args.asr_provider
    
    # Create the extractor with the config
    extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
    
    # Create manager with embedding dimension
    manager = sherpa_onnx.SpeakerEmbeddingManager(512)  # Embedding dimension
    
    # Load pre-registered speakers if available
    speaker_file = os.path.join(args.models_root, 'registered_speakers.json')
    if os.path.exists(speaker_file):
        try:
            with open(speaker_file, 'r') as f:
                speakers = json.load(f)
                logger.info(f'speaker_id: Loading {len(speakers)} registered speakers from {speaker_file}')
                for name, embedding in speakers.items():
                    emb_array = np.array(embedding, dtype=np.float32)
                    manager.add(name, emb_array)
                    logger.info(f'speaker_id: Loaded speaker: {name} (embedding dim: {len(emb_array)})')
        except Exception as e:
            logger.error(f'speaker_id: Failed to load registered speakers: {e}')
    else:
        logger.info(f'speaker_id: No registered speakers file found at {speaker_file}')
    
    return extractor, manager


def create_nemo_speakernet(samplerate: int, args):
    """Create NeMo SpeakerNet model for speaker identification"""
    # Try multiple possible paths
    possible_paths = [
        os.path.join(args.models_root, 'nemo-speakernet', 'nemo_en_speakerverification_speakernet.onnx'),
        os.path.join(args.models_root, 'nemo_en_speakerverification_speakernet.onnx'),
        os.path.join(args.models_root, 'sherpa-onnx-nemo-speakernet', 'nemo_en_speakerverification_speakernet.onnx')
    ]
    
    model_path = None
    for path in possible_paths:
        if os.path.exists(path):
            model_path = path
            break
    
    if model_path is None:
        raise ValueError(f"speaker_id: NeMo SpeakerNet model not found. Tried: {possible_paths}")
    
    logger.info(f"speaker_id: Loading NeMo SpeakerNet from {model_path}")
    
    # Create config for speaker embedding extractor
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig()
    config.model = model_path
    config.num_threads = args.threads
    config.debug = 0
    config.provider = args.speaker_provider if hasattr(args, 'speaker_provider') else args.asr_provider
    
    # Create the extractor with the config
    extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
    
    # Create manager with embedding dimension (NeMo SpeakerNet uses 256-dim embeddings)
    manager = sherpa_onnx.SpeakerEmbeddingManager(256)  # NeMo SpeakerNet embedding dimension
    
    # Load pre-registered speakers if available
    speaker_file = os.path.join(args.models_root, 'registered_speakers_nemo.json')
    if os.path.exists(speaker_file):
        try:
            with open(speaker_file, 'r') as f:
                speakers = json.load(f)
                logger.info(f'speaker_id: Loading {len(speakers)} registered speakers from {speaker_file}')
                for name, embedding in speakers.items():
                    emb_array = np.array(embedding, dtype=np.float32)
                    manager.add(name, emb_array)
                    logger.info(f'speaker_id: Loaded speaker: {name} (embedding dim: {len(emb_array)})')
        except Exception as e:
            logger.error(f'speaker_id: Failed to load registered speakers: {e}')
    else:
        logger.info(f'speaker_id: No registered speakers file found at {speaker_file}')
    
    return extractor, manager


def load_speaker_engine(samplerate: int, args) -> Tuple[sherpa_onnx.SpeakerEmbeddingExtractor, sherpa_onnx.SpeakerEmbeddingManager]:
    """Load speaker identification engine"""
    model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
    cache_key = model_name
    
    cache_engine = _speaker_engines.get(cache_key)
    if cache_engine:
        return cache_engine
    
    st = time.time()
    if model_name == 'wespeaker-voxceleb':
        extractor, manager = create_wespeaker_voxceleb(samplerate, args)
    elif model_name == '3dspeaker':
        extractor, manager = create_3dspeaker(samplerate, args)
    elif model_name == 'nemo-speakernet':
        extractor, manager = create_nemo_speakernet(samplerate, args)
    else:
        raise ValueError(f"speaker_id: unknown model {model_name}")
    
    cache_engine = (extractor, manager)
    _speaker_engines[cache_key] = cache_engine
    logger.info(f"speaker_id: engine loaded in {time.time() - st:.2f}s")
    return cache_engine


async def start_speaker_stream(samplerate: int, args) -> SpeakerStream:
    """Start a speaker identification stream"""
    extractor, manager = load_speaker_engine(samplerate, args)
    threshold = getattr(args, 'speaker_threshold', 0.7)
    
    # Adjust default threshold based on model
    model_name = getattr(args, 'speaker_model', 'nemo-speakernet')
    if model_name == 'nemo-speakernet' and threshold == 0.7:
        # NeMo SpeakerNet may need a different threshold
        threshold = 0.6
        logger.info(f"speaker_id: Using NeMo SpeakerNet with adjusted threshold: {threshold}")
    
    stream = SpeakerStream(extractor, manager, samplerate, args.models_root, threshold)
    await stream.start()
    return stream