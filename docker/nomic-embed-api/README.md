# Nomic Embed Vision API

A FastAPI-based REST API for generating embeddings from both text and images using Nomic's unified embedding model (`nomic-embed-vision-v1.5`).

## Features

- **Unified Model**: Single model handles both text and image embeddings
- **Multiple Input Methods**: 
  - Text: Single or batch processing
  - Images: File upload, base64, or URL
  - Multimodal: Mixed text and image inputs
- **Task-Specific Embeddings**: Support for different text embedding tasks (search_document, search_query, classification, clustering)
- **Automatic Model Download**: Downloads model from Hugging Face on first run
- **Normalization**: Optional L2 normalization of embeddings
- **Batch Processing**: Process multiple inputs efficiently

## Quick Start

### Using Docker Compose

```bash
# Build and start the service
docker-compose up --build

# The API will be available at http://localhost:8002
```

### Configuration

Environment variables can be set in `docker-compose.yml`:

- `MODEL_DIR`: Directory to store models (default: `/app/models`)
- `MODEL_NAME`: Hugging Face model name (default: `nomic-ai/nomic-embed-vision-v1.5`)
- `AUTO_DOWNLOAD_MODELS`: Auto-download models if not present (default: `true`)
- `DEVICE`: Computing device - `cpu` or `cuda` (default: `cpu`)
- `MAX_TEXT_LENGTH`: Maximum text length (default: `8192`)
- `MAX_BATCH_SIZE`: Maximum batch size (default: `32`)

## API Endpoints

### Health Check
- `GET /health` or `GET /healthz` - Service health status

### Text Embedding
- `POST /embed/text` - Generate embeddings for text

```json
{
  "text": "Your text here",
  "task": "search_document",
  "normalize": true
}
```

### Image Embedding
- `POST /embed/image/file` - Upload image file(s)
- `POST /embed/image/base64` - Base64 encoded image(s)
- `POST /embed/image/url` - Image URL(s)

### Multimodal Embedding
- `POST /embed/multimodal` - Mixed text and image inputs

```json
{
  "inputs": [
    {"type": "text", "content": "A description"},
    {"type": "image", "content": "base64_image_data"}
  ],
  "normalize": true
}
```

## Testing

Run the test suite:

```bash
python test_api.py [optional_image_path]
```

## Response Format

All endpoints return a consistent response format:

```json
{
  "success": true,
  "embeddings": [[...], [...]],
  "embedding_dim": 768,
  "num_embeddings": 2,
  "processing_time_ms": 123.45
}
```

## Use Cases

- **Semantic Search**: Find similar texts or images
- **Cross-Modal Search**: Search images with text queries or vice versa
- **Clustering**: Group similar items together
- **Classification**: Use embeddings as features for classification
- **Recommendation**: Find similar content based on embeddings

## Model Information

The Nomic Embed Vision v1.5 model:
- Unified architecture for both text and images
- 768-dimensional embeddings
- Supports long-context text (up to 8192 tokens)
- State-of-the-art performance on multimodal tasks

## GPU Support

To enable GPU support:

1. Ensure NVIDIA Docker runtime is installed
2. Uncomment the GPU section in `docker-compose.yml`
3. Set `DEVICE=cuda` in environment variables

## Volume Mounts

- `./models`: Persistent storage for downloaded models
- `./temp`: Temporary file storage

## Notes

- First startup will download the model (~1GB) which may take several minutes
- Models are cached locally for faster subsequent startups
- The API supports batch processing for efficient embedding generation