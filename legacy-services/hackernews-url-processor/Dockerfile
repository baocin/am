FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for Playwright
RUN apt-get update && apt-get install -y \
    gcc \
    wget \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy loom-common first
COPY loom-common ./loom-common/

# Copy requirements first for better caching
COPY hackernews-url-processor/requirements.txt .
# Install loom-common package
RUN cd loom-common && pip install --no-cache-dir -e .
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright browsers
RUN playwright install chromium
RUN playwright install-deps chromium

# Copy application code
COPY hackernews-url-processor/app/ ./app/

# Create logs directory
RUN mkdir -p /app/logs

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Run the application
CMD ["python", "app/main.py"]
