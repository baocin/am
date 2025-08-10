# Voice API

A comprehensive speech processing API service conforming to the API Docker Contract Specification. Provides Text-to-Speech (TTS), Automatic Speech Recognition (ASR using Parakeet/Whisper models), and Speaker Identification capabilities.

## Features

- **Text-to-Speech (TTS)**: Convert text to natural speech using Kokoro
- **Speech Recognition (ASR)**: Real-time speech-to-text using Parakeet NEMO  
- **Speaker Identification**: Identify speakers using NeMo SpeakerNet
- **Speaker Registration**: Register and manage speaker voice profiles

## Quick Start

### Using Docker (Recommended)

```bash
# Download models and run
make run

# API will be available at http://localhost:8257
# API docs at http://localhost:8257/docs
```

### Manual Setup

1. Download models:
```bash
make download-models
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Run the API:
```bash
python app.py
```

## API Documentation

Interactive API documentation is available at `/docs` when the service is running.

### REST API Endpoints (Following API Contract)

#### Core Endpoints
- `GET /` - Service information and endpoint listing
- `GET /health` - Health check endpoint
- `GET /healthz` - Kubernetes-compatible health check
- `GET /docs` - OpenAPI documentation
- `GET /demo` - Interactive demo page

#### Processing Endpoints
- `POST /process/audio` - Process audio file for transcription
- `POST /process/base64` - Process base64 encoded audio for transcription
- `POST /tts/generate` - Generate speech from text

#### Speaker Management
- `GET /speakers` - List registered speakers
- `POST /speakers/register` - Register speaker with embeddings or audio
- `DELETE /speakers/{speaker_name}` - Delete a registered speaker

### WebSocket Endpoints

- `ws://localhost:8257/ws/asr` - Speech Recognition streaming
- `ws://localhost:8257/ws/tts` - Text-to-Speech streaming  
- `ws://localhost:8257/ws/speaker_id` - Speaker Identification streaming
- `ws://localhost:8257/ws/speaker_register` - Speaker Registration via audio streaming

Note: Legacy endpoints without `/ws` prefix are maintained for backward compatibility.

## Frontend

The API includes a built-in demo web interface accessible at the root endpoint.

```bash
# Run the API
make run

# Access the demo interface
# Open http://localhost:8257/demo
```

The demo interface provides:
- Interactive TTS with voice selection (53 Kokoro voices)
- Real-time speech recognition with speaker identification
- Speaker registration via microphone
- Speaker identification testing

## Models

### Default Models
- **ASR**: Parakeet NEMO (sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16)
- **TTS**: Kokoro Multi-Language v1.0
- **Speaker ID**: NeMo SpeakerNet

### Model Management
```bash
# Download all models
make download-models

# Check installed models
make check-models

# Clean models
make clean-models
```

## Known Speakers Configuration

The API can preload known speakers for identification on startup:

1. Create a `known_speakers.json` file (see `known_speakers.json.example`)
2. Add speakers with their embeddings (256-dimensional arrays from NeMo SpeakerNet)
3. The file will be loaded automatically when the container starts

### Getting Speaker Embeddings

To obtain embeddings for a speaker:
1. Register them via the web interface or API
2. Copy the returned embeddings from the response
3. Add them to `known_speakers.json`

Example:
```bash
# Register a speaker and get embeddings
curl -X POST http://localhost:8257/speakers/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"John","audio_base64":"<base64_audio>"}'

# Response includes embeddings array
# Copy the embeddings to known_speakers.json
```

## Development

### Running locally
```bash
python app.py \
  --port 8000 \
  --asr-model parakeet-offline \
  --tts-model kokoro-multi-lang-v1_0 \
  --speaker-model nemo-speakernet
```

### Configuration Options
- `--port`: API port (default: 8000)
- `--addr`: Bind address (default: 0.0.0.0)
- `--asr-provider`: cpu or cuda
- `--tts-provider`: cpu or cuda
- `--speaker-threshold`: Speaker identification threshold (0.0-1.0, default: 0.6)
- `--threads`: Number of threads (default: 4)

### Environment Variables
See `.env.example` for all available configuration options.

## Docker

### Build and Run
```bash
# Build CPU-optimized image
make build

# Run with Docker Compose
make run

# View logs
make logs

# Stop
make stop

# Clean up
make clean
```

### Docker Features
- CPU-optimized with 4 threads
- Health checks
- Volume mounts for models
- Resource limits (4 CPUs, 4GB RAM)
- Non-root user for security

## Testing

Run the integration test suite to verify all endpoints:

```bash
# Run tests
./test.sh

# Run with verbose output
VERBOSE=true ./test.sh

# Test against different host
BASE_URL=http://api.example.com:8257 ./test.sh
```

## API Contract Compliance

This service follows the API Docker Contract Specification with:
- Standard health check endpoints (`/health`, `/healthz`)
- Structured request/response models
- Comprehensive error handling
- RESTful endpoint design
- Integration test script (`test.sh`)
- Docker Compose configuration with resource limits
- Environment-based configuration

## License

MIT