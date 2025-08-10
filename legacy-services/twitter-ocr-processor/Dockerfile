FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create non-root user
RUN useradd -m -u 1000 processor && chown -R processor:processor /app

# Switch to non-root user
USER processor

# Expose port for health checks and monitoring
EXPOSE 8008

# Run the application
CMD ["python", "-m", "app.main"]
