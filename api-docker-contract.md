# API Docker Contract Specification

## Overview
This document defines the standard contract for containerized API services based on the RapidOCR implementation pattern. All API containers should follow these conventions for consistency, maintainability, and operational excellence.

## Directory Structure

```
docker/
├── <service-name>/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── requirements.txt (Python) / package.json (Node.js)
│   ├── app.py / app.js / main.go (main application file)
│   ├── test.sh (endpoint testing script)
│   ├── test/ (test files and data)
│   │   ├── test-image.jpg
│   │   ├── test-data.json
│   │   └── expected-responses/
│   ├── models/ (if ML service)
│   ├── temp/ (temporary file storage)
│   └── .env.example
```

## 1. Dockerfile Standards

### Base Image Selection

#### Standard Images
- **Python**: `python:3.11-slim` (or latest stable slim variant)
- **Node.js**: `node:20-alpine` (or latest LTS alpine variant)
- **Go**: Multi-stage build with `golang:1.21-alpine` → `alpine:latest`

#### GPU/CUDA Images
For services requiring GPU acceleration (ML inference, computer vision, etc.):

- **NVIDIA CUDA Python**: 
  ```dockerfile
  FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04  # For inference
  FROM nvidia/cuda:12.2.0-devel-ubuntu22.04    # For compilation
  FROM nvcr.io/nvidia/pytorch:23.12-py3         # PyTorch pre-built
  FROM nvcr.io/nvidia/tensorflow:23.12-tf2-py3  # TensorFlow pre-built
  ```

- **NVIDIA CUDA with Python (custom)**:
  ```dockerfile
  FROM nvidia/cuda:12.2.0-cudnn8-runtime-ubuntu22.04
  
  # Install Python
  RUN apt-get update && apt-get install -y \
      python3.11 python3-pip \
      && rm -rf /var/lib/apt/lists/*
  ```

- **Multi-stage for smaller GPU images**:
  ```dockerfile
  # Build stage
  FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 as builder
  # ... build CUDA code ...
  
  # Runtime stage
  FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04
  # ... copy built artifacts ...
  ```

### Required Structure

```dockerfile
FROM <base-image>

# System dependencies (minimize layers)
RUN apt-get update && apt-get install -y \
    <required-packages> \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependency installation (leverages layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code
COPY <app-files> .

# Port exposure
EXPOSE <port>

# Runtime command
CMD ["<runtime-command>"]
```

### Best Practices
- Use slim/alpine variants to minimize image size
- Group RUN commands to reduce layers
- Clean package manager caches in the same layer
- Copy dependency files before application code for better caching
- Use specific version tags, never `latest` in production

## 2. Application Code Structure

### Core Requirements

#### Service Initialization
```python
# Example Python FastAPI structure
app = FastAPI(title="<Service Name> API", version="1.0.0")

# Configuration from environment
CONFIG = {
    "MODEL_DIR": os.environ.get("MODEL_DIR", "/app/models"),
    "AUTO_DOWNLOAD": os.environ.get("AUTO_DOWNLOAD", "true").lower() == "true",
    "LOG_LEVEL": os.environ.get("LOG_LEVEL", "INFO")
}

# Logging setup
logging.basicConfig(level=getattr(logging, CONFIG["LOG_LEVEL"]))
logger = logging.getLogger(__name__)
```

#### Required Endpoints

##### 1. Root Information Endpoint
```python
@app.get("/")
async def root():
    return {
        "service": "<Service Name> API",
        "version": "1.0.0",
        "endpoints": {
            "/health": "GET - Health check",
            "/healthz": "GET - Kubernetes health check",
            "/<main-endpoint>": "POST - Main service endpoint",
            "/docs": "GET - API documentation"
        }
    }
```

##### 2. Health Check Endpoints
```python
@app.get("/health")
@app.get("/healthz")
async def health_check():
    return {
        "status": "healthy",
        "service": "<service-name>",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "dependencies": {
            "database": check_database_health(),  # if applicable
            "models_loaded": models_loaded,       # if ML service
            "external_api": check_external_api()  # if dependent
        }
    }
```

##### 3. Main Service Endpoints
Follow RESTful conventions:
- POST for processing/creation: `/process`, `/analyze`, `/generate`
- GET for retrieval: `/status/{id}`, `/results/{id}`
- PUT/PATCH for updates: `/update/{id}`
- DELETE for removal: `/delete/{id}`

### Request/Response Models

#### Pydantic Models (Python)
```python
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

class ServiceRequest(BaseRequest):
    """Service-specific request"""
    # Add service-specific fields
    data: Union[str, Dict[str, Any]]
    options: Optional[Dict[str, Any]] = {}

class ServiceResponse(BaseResponse):
    """Service-specific response"""
    # Add service-specific fields
    result: Optional[Any] = None
    metadata: Optional[Dict[str, Any]] = {}
```

### Error Handling

#### Standard Error Response
```python
class ErrorResponse(BaseModel):
    success: bool = False
    error: str
    error_code: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content=ErrorResponse(
            error="Internal server error",
            error_code="INTERNAL_ERROR",
            details={"message": str(exc)} if DEBUG else None
        ).dict()
    )
```

#### HTTP Status Codes
- 200: Success
- 400: Bad Request (validation errors)
- 401: Unauthorized
- 403: Forbidden
- 404: Not Found
- 422: Unprocessable Entity (business logic errors)
- 429: Too Many Requests
- 500: Internal Server Error
- 503: Service Unavailable

## 3. Docker Compose Configuration

### Standard Structure
```yaml
version: '3.8'

services:
  <service-name>:
    build: .
    # Or use image: <registry>/<image>:<tag>
    container_name: <service-name>
    
    ports:
      - "${PORT:-8000}:8000"
    
    volumes:
      - ./temp:/tmp                    # Temporary files
      - ./models:/app/models           # ML models
      - ./config:/app/config           # Configuration files
    
    environment:
      - PYTHONUNBUFFERED=1
      - LOG_LEVEL=${LOG_LEVEL:-INFO}
      - MODEL_DIR=/app/models
      - AUTO_DOWNLOAD_MODELS=${AUTO_DOWNLOAD:-true}
      - MAX_WORKERS=${MAX_WORKERS:-4}
      - TIMEOUT=${TIMEOUT:-300}
    
    restart: unless-stopped
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    resources:
      limits:
        cpus: '2'
        memory: 4G
      reservations:
        cpus: '0.5'
        memory: 512M
    
    networks:
      - api-network

networks:
  api-network:
    driver: bridge

# GPU-enabled service example
services:
  <gpu-service-name>:
    image: <registry>/<gpu-image>:<tag>
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1  # or "all"
              capabilities: [gpu]
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - CUDA_VISIBLE_DEVICES=0
```

## 4. Environment Variables

### Required Variables
```bash
# .env.example
# Service Configuration
PORT=8000
LOG_LEVEL=INFO
DEBUG=false

# Performance
MAX_WORKERS=4
TIMEOUT=300
REQUEST_LIMIT=100

# Model/Data Configuration (if applicable)
MODEL_DIR=/app/models
AUTO_DOWNLOAD_MODELS=true
CACHE_DIR=/app/cache

# External Services (if applicable)
DATABASE_URL=postgresql://user:pass@localhost/db
REDIS_URL=redis://localhost:6379
API_KEY=your-api-key-here

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090
```

## 5. Logging Standards

### Structured Logging
```python
import json
from datetime import datetime

class StructuredLogger:
    def __init__(self, service_name):
        self.service_name = service_name
    
    def log(self, level, message, **kwargs):
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "service": self.service_name,
            "level": level,
            "message": message,
            **kwargs
        }
        print(json.dumps(log_entry))

logger = StructuredLogger("<service-name>")

# Usage
logger.log("INFO", "Processing request", 
          request_id=request_id, 
          method="OCR",
          duration_ms=processing_time)
```

### Log Levels
- **DEBUG**: Detailed diagnostic information
- **INFO**: General informational messages
- **WARNING**: Warning messages for potentially harmful situations
- **ERROR**: Error events that might still allow the application to continue
- **CRITICAL**: Critical problems that might cause the application to abort

## 6. Model Management (ML Services)

### Model Loading Pattern
```python
def initialize_model():
    """Initialize ML model with proper error handling"""
    model_path = CONFIG["MODEL_DIR"]
    
    # Check for existing models
    if not os.path.exists(model_path):
        if CONFIG["AUTO_DOWNLOAD"]:
            logger.info("Downloading models...")
            download_models(model_path)
        else:
            raise RuntimeError("Models not found and auto-download disabled")
    
    # Load models
    try:
        model = load_model(model_path)
        logger.info(f"Model loaded from {model_path}")
        return model
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

# Initialize at startup
model = initialize_model()
```

## 7. Performance Optimization

### Async Processing
```python
from concurrent.futures import ThreadPoolExecutor
import asyncio

executor = ThreadPoolExecutor(max_workers=CONFIG["MAX_WORKERS"])

async def process_async(data):
    """Run CPU-intensive tasks in thread pool"""
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, cpu_intensive_task, data)
    return result
```

### Request Validation & Limits
```python
from fastapi import File, UploadFile, HTTPException

@app.post("/process")
async def process_file(
    file: UploadFile = File(..., max_size=10*1024*1024)  # 10MB limit
):
    # Validate file type
    if file.content_type not in ["image/jpeg", "image/png"]:
        raise HTTPException(400, "Invalid file type")
    
    # Process file
    return await process_async(file)
```

### Caching Strategy
```python
from functools import lru_cache
import hashlib

@lru_cache(maxsize=100)
def get_cached_result(data_hash):
    """Cache frequently accessed results"""
    return expensive_computation(data_hash)

def process_with_cache(data):
    data_hash = hashlib.md5(data.encode()).hexdigest()
    return get_cached_result(data_hash)
```

## 8. Security Considerations

### Input Validation
```python
from pydantic import BaseModel, validator, Field

class SecureRequest(BaseModel):
    data: str = Field(..., min_length=1, max_length=10000)
    
    @validator('data')
    def validate_data(cls, v):
        # Sanitize input
        if any(char in v for char in ['<', '>', 'script']):
            raise ValueError("Invalid characters in input")
        return v
```

### Rate Limiting
```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["100 per minute"]
)

app.state.limiter = limiter

@app.post("/process")
@limiter.limit("10 per minute")
async def process(request: Request):
    return {"result": "processed"}
```

### Authentication (if required)
```python
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    if not validate_token(token):
        raise HTTPException(401, "Invalid authentication")
    return token

@app.post("/secure-endpoint")
async def secure_endpoint(token: str = Depends(verify_token)):
    return {"message": "Authorized"}
```

## 9. Monitoring & Observability

### Metrics Endpoint
```python
from prometheus_client import Counter, Histogram, generate_latest
import time

# Define metrics
request_count = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint'])
request_duration = Histogram('api_request_duration_seconds', 'API request duration')

@app.middleware("http")
async def add_metrics(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time
    
    request_count.labels(
        method=request.method,
        endpoint=request.url.path
    ).inc()
    
    request_duration.observe(duration)
    return response

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")
```

## 10. Testing Requirements

### Integration Test Script (test.sh)

Every service MUST include a `test.sh` script in the root directory that tests all major endpoints using curl commands. This script should be executable and provide clear pass/fail feedback.

#### test.sh Template
```bash
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8000}"
VERBOSE="${VERBOSE:-false}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for running tests
run_test() {
    local test_name="$1"
    local curl_cmd="$2"
    local expected_status="$3"
    local expected_contains="$4"
    
    echo -n "Testing $test_name... "
    
    # Execute curl command
    if [ "$VERBOSE" == "true" ]; then
        response=$(eval "$curl_cmd -w '\n%{http_code}'" 2>&1)
        status_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | head -n -1)
    else
        response=$(eval "$curl_cmd -w '\n%{http_code}' -s" 2>&1)
        status_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | head -n -1)
    fi
    
    # Check status code
    if [ "$status_code" != "$expected_status" ]; then
        echo -e "${RED}FAILED${NC} (Status: $status_code, Expected: $expected_status)"
        [ "$VERBOSE" == "true" ] && echo "Response: $body"
        ((TESTS_FAILED++))
        return 1
    fi
    
    # Check response contains expected string
    if [ -n "$expected_contains" ]; then
        if [[ ! "$body" == *"$expected_contains"* ]]; then
            echo -e "${RED}FAILED${NC} (Response missing: $expected_contains)"
            [ "$VERBOSE" == "true" ] && echo "Response: $body"
            ((TESTS_FAILED++))
            return 1
        fi
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    return 0
}

echo "==================================="
echo "API Integration Tests"
echo "Base URL: $BASE_URL"
echo "==================================="

# Test 1: Health Check
run_test "Health Check" \
    "curl -X GET $BASE_URL/health" \
    "200" \
    '"status":"healthy"'

# Test 2: Root Endpoint
run_test "Root Info" \
    "curl -X GET $BASE_URL/" \
    "200" \
    '"service"'

# Test 3: File Upload (if applicable)
if [ -f "test/test-image.jpg" ]; then
    run_test "File Upload" \
        "curl -X POST -F 'file=@test/test-image.jpg' $BASE_URL/process/file" \
        "200" \
        '"success":true'
fi

# Test 4: JSON Request
if [ -f "test/test-data.json" ]; then
    run_test "JSON Processing" \
        "curl -X POST -H 'Content-Type: application/json' -d @test/test-data.json $BASE_URL/process" \
        "200" \
        '"success":true'
fi

# Test 5: Base64 Request (if applicable)
if [ -f "test/test-base64.txt" ]; then
    run_test "Base64 Processing" \
        "curl -X POST -H 'Content-Type: application/json' -d '{\"data\":\"'$(cat test/test-base64.txt)'\"}' $BASE_URL/process/base64" \
        "200" \
        '"success":true'
fi

# Test 6: Invalid Request (400/422 expected)
run_test "Invalid Request Handling" \
    "curl -X POST -H 'Content-Type: application/json' -d '{}' $BASE_URL/process" \
    "422" \
    '"error"'

# Test 7: Rate Limiting (if implemented)
run_test "Rate Limit Check" \
    "curl -I -X GET $BASE_URL/health" \
    "200" \
    ""

# Test 8: Metrics Endpoint (if available)
curl -s -o /dev/null -w "%{http_code}" $BASE_URL/metrics | grep -q "200" && \
run_test "Metrics Endpoint" \
    "curl -X GET $BASE_URL/metrics" \
    "200" \
    ""

echo "==================================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}"
echo "==================================="

# Exit with appropriate code
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
```

### Test Directory Structure

The `test/` directory should contain all necessary test files and expected responses:

```
test/
├── test-image.jpg           # Sample image for testing
├── test-image.png           # Alternative format
├── test-data.json           # Sample JSON request
├── test-base64.txt          # Base64 encoded test data
├── large-file.bin           # For testing size limits
├── invalid-data.json        # Malformed JSON for error testing
├── expected-responses/
│   ├── health.json          # Expected health check response
│   ├── process-success.json # Expected successful processing
│   └── error-400.json       # Expected error response
└── benchmark.sh             # Performance testing script
```

#### Sample Test Files

**test/test-data.json**
```json
{
    "data": "test input data",
    "options": {
        "format": "json",
        "timeout": 30
    }
}
```

**test/benchmark.sh**
```bash
#!/bin/bash

# Performance benchmark script
echo "Running performance benchmark..."

# Concurrent requests test
echo "Testing concurrent requests..."
for i in {1..10}; do
    curl -s -X GET http://localhost:8000/health &
done
wait

# Load test with timing
echo "Load test with 100 requests..."
time for i in {1..100}; do
    curl -s -X GET http://localhost:8000/health > /dev/null
done

# Memory usage check (if container is running)
docker stats --no-stream $(docker ps -qf "name=<service-name>")
```

### Unit Tests Structure
```python
# tests/test_api.py
import pytest
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_main_endpoint():
    response = client.post("/process", json={"data": "test"})
    assert response.status_code == 200
    assert response.json()["success"] == True

@pytest.mark.parametrize("invalid_input", [
    {"data": ""},
    {"data": None},
    {},
])
def test_validation(invalid_input):
    response = client.post("/process", json=invalid_input)
    assert response.status_code == 422
```

### Docker Compose Test Configuration

Include a test-specific docker-compose configuration:

**docker-compose.test.yml**
```yaml
version: '3.8'

services:
  <service-name>-test:
    build: .
    container_name: <service-name>-test
    ports:
      - "8001:8000"  # Different port for testing
    environment:
      - DEBUG=true
      - LOG_LEVEL=DEBUG
      - TEST_MODE=true
    volumes:
      - ./test:/app/test:ro
      - ./temp:/tmp
    command: >
      sh -c "
        uvicorn app:app --host 0.0.0.0 --port 8000 --reload &
        sleep 5 &&
        cd /app && ./test.sh &&
        kill %1
      "
```

### Running Tests

```bash
# Make test script executable
chmod +x test.sh

# Run tests against local container
./test.sh

# Run with verbose output
VERBOSE=true ./test.sh

# Run against different host
BASE_URL=http://api.example.com:8000 ./test.sh

# Run in Docker
docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit

# Run performance benchmark
./test/benchmark.sh
```

## 11. Deployment Checklist

### Pre-deployment
- [ ] All tests passing (unit tests and `test.sh`)
- [ ] Docker image builds successfully
- [ ] Health check endpoint responds correctly
- [ ] Test directory with sample files created
- [ ] `test.sh` script executable and passing
- [ ] Environment variables documented in `.env.example`
- [ ] Resource limits defined in docker-compose
- [ ] GPU requirements specified (if applicable)
- [ ] Logging configured properly
- [ ] Error handling comprehensive

### Production Configuration
- [ ] Use specific image tags (no `latest`)
- [ ] Enable structured logging
- [ ] Configure proper restart policies
- [ ] Set resource limits
- [ ] Enable monitoring/metrics
- [ ] Configure rate limiting
- [ ] Implement authentication (if required)
- [ ] Set up proper networking

### Operational Requirements
- [ ] Graceful shutdown handling
- [ ] Log rotation configured
- [ ] Backup strategy for persistent data
- [ ] Monitoring alerts configured
- [ ] Documentation up to date
- [ ] Security scanning of container image
- [ ] Performance testing completed

## 12. Example Implementation

See the `docker/rapidocr-raw-api/` directory for a complete reference implementation following this contract.

### Example test.sh for RapidOCR service
```bash
#!/bin/bash

# RapidOCR API Test Script
BASE_URL="${BASE_URL:-http://localhost:8000}"

# Test health check
curl -s $BASE_URL/health | jq .

# Test OCR with file upload
curl -X POST \
  -F "file=@test/test-document.jpg" \
  $BASE_URL/ocr/file | jq .

# Test OCR with base64
IMAGE_BASE64=$(base64 -w 0 test/test-document.jpg)
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\":\"$IMAGE_BASE64\"}" \
  $BASE_URL/ocr/base64 | jq .

# Test invalid request
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{}" \
  $BASE_URL/ocr/base64 | jq .
```

## 13. GPU Service Considerations

### NVIDIA Docker Runtime Setup
```bash
# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### GPU-Enabled Dockerfile Example
```dockerfile
FROM nvidia/cuda:12.2.0-cudnn8-runtime-ubuntu22.04

# Install Python and system dependencies
RUN apt-get update && apt-get install -y \
    python3.11 python3-pip \
    libgomp1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install PyTorch with CUDA support
RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install other requirements
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Copy application
COPY app.py .

# Health check for GPU
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD python3 -c "import torch; assert torch.cuda.is_available()" || exit 1

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

### GPU Test Script
```bash
#!/bin/bash
# test-gpu.sh - Test GPU availability in container

echo "Testing GPU availability..."

# Check NVIDIA driver
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi

# Test PyTorch CUDA
docker run --rm --gpus all <service-name> python3 -c "
import torch
print(f'CUDA Available: {torch.cuda.is_available()}')
print(f'CUDA Device Count: {torch.cuda.device_count()}')
if torch.cuda.is_available():
    print(f'CUDA Device Name: {torch.cuda.get_device_name(0)}')
"
```

## Version History

- **v1.1.0** - Added test.sh requirements, test/ directory structure, and NVIDIA/CUDA guidelines
- **v1.0.0** - Initial specification based on RapidOCR implementation
- Created: 2025-01-10
- Last Updated: 2025-01-10

---

This contract ensures consistency, maintainability, and operational excellence across all containerized API services in the project.