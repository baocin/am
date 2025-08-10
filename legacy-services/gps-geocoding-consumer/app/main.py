"""Main entry point for GPS geocoding consumer"""
import signal
import sys
import threading
from contextlib import asynccontextmanager
import uvicorn
from fastapi import FastAPI
from prometheus_client import Counter, Gauge, Histogram, generate_latest
from fastapi.responses import PlainTextResponse
import structlog

from .config import settings
from .consumer import GPSGeocodingConsumer

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Prometheus metrics
messages_processed = Counter('gps_messages_processed_total', 'Total GPS messages processed')
geocoding_requests = Counter('geocoding_api_requests_total', 'Total geocoding API requests')
cache_hits = Counter('geocoding_cache_hits_total', 'Total geocoding cache hits')
processing_errors = Counter('gps_processing_errors_total', 'Total processing errors')
processing_duration = Histogram('gps_processing_duration_seconds', 'Time spent processing messages')

# Global consumer instance
consumer = None
consumer_thread = None


def run_consumer():
    """Run the Kafka consumer in a separate thread"""
    global consumer
    print("DEBUG: run_consumer() called", file=sys.stderr)
    logger.info("run_consumer() called")
    try:
        print("DEBUG: Creating GPSGeocodingConsumer", file=sys.stderr)
        consumer = GPSGeocodingConsumer()
        print("DEBUG: Starting consumer", file=sys.stderr)
        consumer.start()
    except Exception as e:
        print(f"DEBUG: Consumer failed: {e}", file=sys.stderr)
        logger.error("Consumer failed", error=str(e))
        sys.exit(1)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle"""
    global consumer_thread
    
    # Startup
    print("DEBUG: lifespan startup called", file=sys.stderr)
    logger.info("Starting GPS geocoding consumer", 
                kafka_servers=settings.kafka_bootstrap_servers,
                input_topic=settings.kafka_input_topic,
                output_topic=settings.kafka_output_topic)
    
    # Start consumer in background thread
    print("DEBUG: Creating consumer thread", file=sys.stderr)
    consumer_thread = threading.Thread(target=run_consumer, daemon=True)
    print("DEBUG: Starting consumer thread", file=sys.stderr)
    consumer_thread.start()
    print(f"DEBUG: Consumer thread started, is_alive={consumer_thread.is_alive()}", file=sys.stderr)
    
    yield
    
    # Shutdown
    logger.info("Shutting down GPS geocoding consumer")
    if consumer:
        consumer.cleanup()


# Create FastAPI app for health checks and metrics
app = FastAPI(
    title="GPS Geocoding Consumer",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/healthz")
async def healthz():
    """Liveness probe"""
    return {"status": "healthy"}


@app.get("/readyz")
async def readyz():
    """Readiness probe"""
    # Check if consumer thread is alive
    if consumer_thread and consumer_thread.is_alive():
        return {"status": "ready"}
    return {"status": "not ready"}, 503


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()


def signal_handler(sig, frame):
    """Handle shutdown signals"""
    logger.info("Received shutdown signal", signal=sig)
    if consumer:
        consumer.cleanup()
    sys.exit(0)


if __name__ == "__main__":
    # Configure Python logging
    import logging
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        stream=sys.stderr
    )
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Run the application
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level.lower(),
        log_config=None  # Don't let uvicorn override logging config
    )