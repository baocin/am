# Moondream Raw API Docker Container

A FastAPI-based REST API service for the Moondream2 vision-language model from Hugging Face, providing image captioning, visual question answering, object detection, and object pointing capabilities.

## Version 2.0

This version uses the official Moondream2 model from Hugging Face Spaces with:
- CUDA 11.8 support for GPU acceleration
- CPU-only fallback option
- Improved model loading from Hugging Face
- Better error handling and device detection

## Features

- **Caption Generation**: Generate detailed descriptions of images
- **Visual Question Answering**: Answer natural language questions about images
- **Object Detection**: Identify and locate objects within images
- **Object Pointing**: Get precise coordinates for objects mentioned in prompts
- Support for both base64-encoded images and direct file uploads
- Async request handling with thread pool for CPU-bound operations
- Docker containerization for easy deployment

## Getting Started

### 1. Get a Moondream API Key

The Moondream Raw API requires an API key to function. Get your free key:

1. Visit [moondream.ai](https://moondream.ai/)
2. Sign up for a free account
3. Copy your API key from the dashboard

### 2. Set Your API Key

```bash
export MOONDREAM_API_KEY="md-your-actual-api-key-here"
```

## Quick Start

### For NVIDIA GPU Systems

1. Build and start the container with GPU support:
```bash
docker-compose up --build
```

2. The API will be available at `http://localhost:8001`

### For CPU-Only Systems

1. Build and start the CPU version:
```bash
docker-compose -f docker-compose.cpu.yml up --build
```

2. The API will be available at `http://localhost:8001`

### Using Docker Directly

#### GPU Version:
```bash
docker build -t moondream-raw-api .
docker run --gpus all -p 8001:8001 moondream-raw-api
```

#### CPU Version:
```bash
docker build -f Dockerfile.cpu -t moondream-raw-api-cpu .
docker run -p 8001:8001 moondream-raw-api-cpu
```

## API Endpoints

### Health Check
- **GET** `/health` - Check if the service is running and model is loaded

### Caption Generation
- **POST** `/caption` - Generate a caption for a base64-encoded image
- **POST** `/upload/caption` - Generate a caption for an uploaded image file

### Visual Question Answering
- **POST** `/query` - Answer a question about a base64-encoded image
- **POST** `/upload/query` - Answer a question about an uploaded image file

### Object Detection
- **POST** `/detect` - Detect objects in a base64-encoded image

### Object Pointing
- **POST** `/point` - Get coordinates for objects in a base64-encoded image

## Request Examples

### Caption Generation (Base64)
```bash
curl -X POST "http://localhost:8001/caption" \
  -H "Content-Type: application/json" \
  -H "X-Moondream-Auth: YOUR_API_KEY" \
  -d '{
    "image": "data:image/jpeg;base64,/9j/4AAQSkZJRg..."
  }'
```

### Caption Generation (File Upload)
```bash
curl -X POST "http://localhost:8001/upload/caption" \
  -H "X-Moondream-Auth: YOUR_API_KEY" \
  -F "file=@image.jpg"
```

### Visual Question Answering
```bash
curl -X POST "http://localhost:8001/query" \
  -H "Content-Type: application/json" \
  -H "X-Moondream-Auth: YOUR_API_KEY" \
  -d '{
    "image": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
    "question": "What is in this image?"
  }'
```

### Object Detection
```bash
curl -X POST "http://localhost:8001/detect" \
  -H "Content-Type: application/json" \
  -H "X-Moondream-Auth: YOUR_API_KEY" \
  -d '{
    "image": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
    "object": "person"
  }'
```

### Object Pointing
```bash
curl -X POST "http://localhost:8001/point" \
  -H "Content-Type: application/json" \
  -H "X-Moondream-Auth: YOUR_API_KEY" \
  -d '{
    "image": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
    "object": "cat"
  }'
```

## Response Format

All endpoints return JSON responses with the following structure:

### Success Response
```json
{
  "status": "success",
  "caption": "A detailed description of the image...",
  // or
  "answer": "The answer to your question...",
  // or
  "detections": [...],
  // or
  "coordinates": {...}
}
```

### Error Response
```json
{
  "detail": "Error message describing what went wrong"
}
```

## Environment Variables

- `MOONDREAM_API_KEY`: Your Moondream API key (optional, for cloud-based features)
- `PYTHONUNBUFFERED`: Set to 1 for immediate log output

## System Requirements

### GPU Version
- Docker and Docker Compose
- NVIDIA GPU with CUDA 11.8+ support
- NVIDIA Docker runtime (nvidia-docker2)
- At least 8GB RAM (4GB minimum)
- ~15GB disk space for model and dependencies

### CPU Version
- Docker and Docker Compose
- At least 8GB RAM (4GB minimum)
- ~10GB disk space for model and dependencies

## Model Information

The Docker containers automatically download and set up the Moondream2 model from Hugging Face Spaces (vikhyatk/moondream2). The model is loaded on container startup and includes:

- Vision encoder for image understanding
- Language model for text generation
- Support for captioning, Q&A, detection, and pointing tasks

No manual model installation is required - everything is handled in the Docker build process.

## Development

### Running Locally

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Install Moondream (see options above)

3. Run the application:
```bash
uvicorn app:app --host 0.0.0.0 --port 8001 --reload
```

### Testing

Use the provided test script:
```bash
./test.sh
```

## API Documentation

Once the service is running, you can access the interactive API documentation at:
- Swagger UI: `http://localhost:8001/docs`
- ReDoc: `http://localhost:8001/redoc`

## Notes

- The Moondream model will be downloaded on first run
- Images are processed in memory; no persistent storage is required
- The API uses thread pooling for CPU-bound operations to maintain responsiveness
- Authentication via `X-Moondream-Auth` header is optional but recommended for production use

## License

This Docker container is provided as-is for use with the Moondream model. Please refer to Moondream's licensing terms for model usage.