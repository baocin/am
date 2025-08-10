# YuNet Face Detection Docker Implementation Plan

## Overview
Containerized implementation of YuNet face detection model using the quantized int8 version for optimal performance.

## Architecture

### Container Base
- **Base Image**: `python:3.10-slim` or `ubuntu:22.04`
- **OpenCV**: 4.10.0+ with DNN module
- **Python Dependencies**: opencv-python, numpy

### Model Selection
- **Primary Model**: `face_detection_yunet_2023mar_int8.onnx` (quantized version)
- **Backup Model**: `face_detection_yunet_2023mar_int8bq.onnx` (block-quantized, block_size=64)
- **Performance**: ~830ms on CPU for 640x480 image

## Directory Structure
```
docker/yunet-face-detection/
├── Dockerfile
├── requirements.txt
├── docker-compose.yml
├── src/
│   ├── detector.py         # Main detection service
│   ├── api.py              # REST API endpoints
│   └── utils.py            # Helper functions
├── models/
│   └── (downloaded ONNX models)
├── config/
│   └── settings.yaml       # Configuration parameters
└── examples/
    └── test_images/
```

## Implementation Steps

### Phase 1: Core Setup
1. **Dockerfile Creation**
   - Multi-stage build for minimal image size
   - Install OpenCV with DNN support
   - Copy model files and source code
   - Set up non-root user for security

2. **Model Integration**
   - Download quantized ONNX models from OpenCV Zoo
   - Implement model loading with OpenCV DNN
   - Configure input preprocessing (resize, normalization)

3. **Detection Pipeline**
   - Input: Raw image (JPEG/PNG)
   - Processing: Face detection with confidence scores
   - Output: Bounding boxes + 5 facial landmarks

### Phase 2: API Development
1. **REST API Endpoints**
   - `POST /detect` - Single image detection
   - `POST /detect/batch` - Multiple images
   - `GET /health` - Health check
   - `GET /metrics` - Performance metrics

2. **Input/Output Format**
   ```json
   {
     "image": "base64_encoded_string",
     "options": {
       "confidence_threshold": 0.7,
       "nms_threshold": 0.3,
       "top_k": 5000
     }
   }
   ```

3. **Response Format**
   ```json
   {
     "faces": [
       {
         "bbox": [x, y, width, height],
         "confidence": 0.95,
         "landmarks": [[x1,y1], [x2,y2], ...]
       }
     ],
     "processing_time_ms": 25
   }
   ```

### Phase 3: Optimization
1. **Performance Tuning**
   - Batch processing for multiple images
   - Connection pooling for API requests
   - Model warm-up on container start

2. **Resource Management**
   - CPU/Memory limits in docker-compose
   - Graceful shutdown handling
   - Request queuing for high load

### Phase 4: Production Features
1. **Monitoring**
   - Prometheus metrics export
   - Request/response logging
   - Error tracking

2. **Security**
   - Input validation (file size, format)
   - Rate limiting
   - API key authentication (optional)

## Configuration Parameters

### Model Settings
```yaml
model:
  path: "/app/models/face_detection_yunet_2023mar_int8.onnx"
  input_size: [320, 320]  # Can be adjusted
  score_threshold: 0.7
  nms_threshold: 0.3
  top_k: 5000
```

### API Settings
```yaml
api:
  host: "0.0.0.0"
  port: 8080
  max_request_size: "10MB"
  timeout: 30
  workers: 4
```

## Docker Commands

### Build
```bash
docker build -t yunet-face-detection:latest .
```

### Run Standalone
```bash
docker run -p 8080:8080 yunet-face-detection:latest
```

### Docker Compose
```bash
docker-compose up -d
```

## Testing Strategy

1. **Unit Tests**
   - Model loading
   - Preprocessing functions
   - Detection accuracy

2. **Integration Tests**
   - API endpoints
   - Error handling
   - Concurrent requests

3. **Performance Benchmarks**
   - Latency measurements
   - Throughput testing
   - Resource utilization

## Expected Performance

- **Single Image (640x480)**: ~25-30ms
- **Batch (10 images)**: ~200-250ms
- **Memory Usage**: ~500MB
- **CPU Usage**: 1-2 cores under load

## Next Steps

1. Download model files from OpenCV Zoo
2. Create Dockerfile with OpenCV installation
3. Implement core detection module
4. Add REST API layer
5. Create docker-compose configuration
6. Add comprehensive testing
7. Optimize for production deployment