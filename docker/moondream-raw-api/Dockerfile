FROM python:3.11

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    wget \
    && git lfs install \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fix NumPy compatibility issue - install specific version
RUN pip install --no-cache-dir numpy==1.26.4

# Install PyTorch (CPU version for compatibility)
RUN pip install --no-cache-dir \
    torch==2.1.0 \
    torchvision==0.16.0 \
    --index-url https://download.pytorch.org/whl/cpu

# Install Transformers and dependencies
RUN pip install --no-cache-dir \
    transformers==4.36.2 \
    accelerate==0.25.0 \
    pillow==10.4.0 \
    einops==0.7.0 \
    scipy

# Install FastAPI
RUN pip install --no-cache-dir \
    fastapi==0.115.0 \
    uvicorn[standard]==0.32.0 \
    python-multipart==0.0.12 \
    pydantic==2.9.2

# Copy application FIRST before downloading model
COPY app_selfhosted.py app.py

# Create directories
RUN mkdir -p /app/temp /app/models

# Set environment variables for model caching
ENV TRANSFORMERS_CACHE=/app/models
ENV HF_HOME=/app/models
ENV TORCH_HOME=/app/models

# Expose port
EXPOSE 8001

# Run the application
CMD ["python", "app.py"]