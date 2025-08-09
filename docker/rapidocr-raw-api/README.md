# RapidOCR Raw API Docker Service

A simple FastAPI wrapper around RapidOCR with ONNX Runtime for fast OCR processing, providing raw OCR results with support for loading custom models from a volume.

## Features

- OCR from uploaded files
- OCR from base64 encoded images
- OCR from image URLs
- Optional visualization of detected text boxes
- RESTful API with automatic documentation
- Docker containerized for easy deployment
- Support for custom model loading from volume

## Model Setup

### Automatic Model Management

The service now automatically handles model management:

1. **First Run**: If no models exist in `./models/rapidocr/`, the container will automatically extract and save the default models from the rapidocr-onnxruntime package to the volume.

2. **Persistent Storage**: Models are saved to `./models/rapidocr/` and persist between container restarts.

3. **Custom Models**: You can place your own ONNX models in `./models/rapidocr/`. The service identifies models by keywords in filenames:
   - `*det*.onnx` - Detection models
   - `*rec*.onnx` - Recognition models  
   - `*cls*.onnx` - Classification models

### Download Models Manually

Use the provided script to download models:

```bash
# Download models from official sources
chmod +x download_models.sh
./download_models.sh
```

The script downloads models from:
- [RapidOCR GitHub Releases](https://github.com/RapidAI/RapidOCR/releases)
- [Hugging Face Models](https://huggingface.co/SWHL/RapidOCR)

### Environment Variables

- `AUTO_DOWNLOAD_MODELS=true` - Automatically extract models from package if none exist (default: true)
- `MODEL_DIR=/app/models` - Directory where models are stored in container

## Quick Start

### Using Docker Compose

```bash
# Optional: Set up models directory
mkdir -p models/rapidocr
# Copy your ONNX models to models/rapidocr/

# Build and start the service
docker-compose up --build

# Or run in background
docker-compose up -d --build
```

The API will be available at `http://localhost:8000`

### Using Docker directly

```bash
# Build the image
docker build -t rapidocr-raw-api .

# Run the container with model volume
docker run -p 8000:8000 -v ./models/rapidocr:/app/models rapidocr-raw-api
```

## API Endpoints

- `GET /` - API information
- `GET /health` - Health check
- `GET /healthz` - Health check
- `POST /ocr/file` - Upload an image file for OCR
- `POST /ocr/base64` - Send base64 encoded image for OCR
- `POST /ocr/url` - Send image URL for OCR
- `GET /docs` - Interactive API documentation (Swagger UI)
- `GET /redoc` - Alternative API documentation (ReDoc)

## Usage Examples

### 1. OCR from File Upload

```bash
curl -X POST "http://localhost:8000/ocr/file" \
  -F "file=@image.jpg" \
  -F "visualize=false"
```

### 2. OCR from Base64

```python
import requests
import base64

with open("image.jpg", "rb") as f:
    image_base64 = base64.b64encode(f.read()).decode()

response = requests.post(
    "http://localhost:8000/ocr/base64",
    json={
        "image_base64": image_base64,
        "visualize": False
    }
)
print(response.json())
```

### 3. OCR from URL

```python
import requests

response = requests.post(
    "http://localhost:8000/ocr/url",
    json={
        "image_url": "https://example.com/image.jpg",
        "visualize": False
    }
)
print(response.json())
```

## Response Format

```json
{
    "success": true,
    "text": "Detected text from the image",
    "boxes": [
        {
            "box": [[x1, y1], [x2, y2], [x3, y3], [x4, y4]],
            "text": "detected text",
            "score": 0.98
        }
    ],
    "error": null,
    "visualization_path": null
}
```

## Development

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

### Testing

```bash
# Test with the example image
curl -X POST "http://localhost:8000/ocr/url" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://github.com/RapidAI/RapidOCR/blob/main/python/tests/test_files/ch_en_num.jpg?raw=true",
    "visualize": true
  }'
```

## Environment Variables

- `PYTHONUNBUFFERED=1` - Ensures stdout/stderr are unbuffered for better logging
- `MODEL_DIR=/app/models` - Directory where RapidOCR models are stored (default: `/app/models`)

## Notes

- The service uses ONNX Runtime for CPU inference by default
- Models are loaded from `/app/models` volume mount if available, otherwise uses bundled models
- Visualization files are saved to `/tmp` directory inside the container
- The container includes necessary system dependencies for image processing
- Health check endpoint is configured for container orchestration and reports model loading status