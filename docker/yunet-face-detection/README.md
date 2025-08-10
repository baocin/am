# YuNet Face Detection API

A containerized face detection service using OpenCV's YuNet model, following the api-docker-contract standards.

## Quick Start

### 1. Build and Start the Container

```bash
# Default port 8000 (if available)
docker compose up -d --build

# Or specify a different port if 8000 is in use
PORT=8002 docker compose up -d --build
```

### 2. Check Container Status

```bash
# Check if container is running
docker ps | grep yunet

# Check health status
curl http://localhost:8000/health

# View logs
docker logs yunet-face-detection -f
```

### 3. Run Tests

```bash
# Run test suite (default port 8000)
./test.sh

# Run with different port
BASE_URL=http://localhost:8002 ./test.sh

# Run with verbose output
VERBOSE=true BASE_URL=http://localhost:8002 ./test.sh
```

## API Endpoints

### Health Check
- `GET /health` - Health check endpoint
- `GET /healthz` - Kubernetes-style health check

### Root Information
- `GET /` - API information and available endpoints

### Face Detection

#### From File Upload
```bash
curl -X POST \
  -F "file=@path/to/image.jpg" \
  -F "score_threshold=0.7" \
  -F "visualize=true" \
  http://localhost:8000/face-detect/file
```

#### From Base64
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "image_base64": "base64_encoded_image_data",
    "score_threshold": 0.7,
    "nms_threshold": 0.3,
    "top_k": 5000
  }' \
  http://localhost:8000/face-detect/base64
```

#### From URL
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://example.com/image.jpg",
    "score_threshold": 0.7
  }' \
  http://localhost:8000/face-detect/url
```

### Visualization
- `GET /visualization/{filename}` - Retrieve generated visualization images

## Configuration

See `.env.example` for available configuration options:

```bash
# Service Configuration
PORT=8000                    # Port to expose the service on
LOG_LEVEL=INFO              # Logging level
DEBUG=false                 # Debug mode

# Model Configuration
MODEL_DIR=/app/models
MODEL_NAME=face_detection_yunet_2023mar_int8.onnx
AUTO_DOWNLOAD_MODELS=true   # Automatically download model if not present

# Detection Parameters
SCORE_THRESHOLD=0.7         # Minimum confidence score for face detection
NMS_THRESHOLD=0.3          # Non-maximum suppression threshold
TOP_K=5000                 # Maximum number of faces to detect
```

## Response Format

### Successful Response
```json
{
  "success": true,
  "faces": [
    {
      "bbox": [x, y, width, height],
      "confidence": 0.89,
      "landmarks": [[x1, y1], [x2, y2], ...],
      "landmark_labels": ["left_eye", "right_eye", "nose_tip", "left_mouth_corner", "right_mouth_corner"]
    }
  ],
  "face_count": 1,
  "processing_time_ms": 16.73,
  "visualization_path": null
}
```

### Error Response
```json
{
  "success": false,
  "faces": null,
  "face_count": 0,
  "error": "Error message",
  "processing_time_ms": null,
  "visualization_path": null
}
```

## Testing

### Run All Tests
```bash
./test.sh
```

### Run Performance Benchmark
```bash
cd test
./benchmark.sh
```

### Test Files
The `test/` directory contains:
- `test-face.jpg` - Sample face image for testing
- `test-base64.txt` - Base64 encoded test image
- `test-data.json` - Sample JSON configuration
- `benchmark.sh` - Performance testing script

## Troubleshooting

### Port Already in Use
If you get "port is already allocated" error:
```bash
# Check what's using the port
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 8000

# Use a different port
PORT=8002 docker compose up -d
BASE_URL=http://localhost:8002 ./test.sh
```

### Model Not Found
The container will automatically download the YuNet model on first startup if `AUTO_DOWNLOAD_MODELS=true`. Check logs:
```bash
docker logs yunet-face-detection | grep model
```

### Container Not Starting
Check the logs for errors:
```bash
docker logs yunet-face-detection --tail 50
```

## Model Information

This service uses the YuNet face detection model from OpenCV Zoo:
- Model: `face_detection_yunet_2023mar_int8.onnx`
- Size: ~100KB (very lightweight)
- Performance: Fast inference suitable for real-time applications
- Outputs: Face bounding boxes and 5 facial landmarks

## API Documentation

When the service is running, visit:
- Interactive API docs: http://localhost:8000/docs
- OpenAPI schema: http://localhost:8000/openapi.json

## License

This service follows the api-docker-contract.md standards for containerized APIs.