FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy common module
COPY services/common /app/common

# Copy requirements
COPY services/georegion-detector-db/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY services/georegion-detector-db/app /app/app

# Run the application
CMD ["python", "-m", "app.main"]
