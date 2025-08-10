#!/usr/bin/env python3
"""Twitter OCR Processor - Processes Twitter images using Moondream OCR."""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from typing import Dict, Any, Optional

import asyncpg
import httpx
import structlog
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ValidationError
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

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
        structlog.processors.JSONRenderer(),
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

# Set up logger
logger = structlog.get_logger()

# Create FastAPI app for health checks and monitoring
app = FastAPI(
    title="Twitter OCR Processor",
    description="Processes Twitter images using Moondream OCR service",
    version="1.0.0",
)

# Prometheus metrics
messages_processed = Counter(
    "twitter_ocr_messages_processed_total",
    "Total number of Twitter messages processed",
    ["status"],  # success, error, validation_error
)
processing_duration = Histogram(
    "twitter_ocr_processing_duration_seconds", "Time spent processing Twitter images"
)
database_operations = Counter(
    "twitter_ocr_database_operations_total",
    "Total database operations",
    ["operation", "status"],  # operation: update, status: success/error
)

# Global processor instance for health checks
processor_instance: Optional["TwitterOCRProcessor"] = None


class TwitterImageMessage(BaseModel):
    """Message schema for Twitter images."""

    trace_id: str
    device_id: Optional[str] = None
    recorded_at: str
    data: Dict[str, Any]
    
    @property
    def tweet_id(self) -> str:
        """Extract tweet_id from data field."""
        return self.data.get("tweet_id", "")
    
    @property
    def tweet_url(self) -> str:
        """Extract tweet_url from data field."""
        return self.data.get("tweet_url", "")


# Health check and monitoring endpoints
@app.get("/")
async def root():
    """Root endpoint with service information."""
    return {
        "service": "Twitter OCR Processor",
        "version": "1.0.0",
        "status": "running",
        "description": "Processes Twitter images using Moondream OCR service",
    }


@app.get("/healthz")
async def health_check():
    """Health check endpoint for Kubernetes liveness probe."""
    if processor_instance is None:
        raise HTTPException(status_code=503, detail="Processor not initialized")

    # Check if processor is not shutdown
    if processor_instance.shutdown:
        raise HTTPException(status_code=503, detail="Processor is shutting down")

    return {"status": "healthy"}


@app.get("/readyz")
async def readiness_check():
    """Readiness check endpoint for Kubernetes readiness probe."""
    if processor_instance is None:
        raise HTTPException(status_code=503, detail="Processor not initialized")

    # Check database connection
    if processor_instance.db_pool is None:
        raise HTTPException(status_code=503, detail="Database not connected")

    try:
        # Test database connection
        async with processor_instance.db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database check failed: {str(e)}")

    # Check Moondream OCR service
    try:
        response = await processor_instance.http_client.get(
            f"{processor_instance.moondream_url}/healthz", timeout=5.0
        )
        if response.status_code != 200:
            raise HTTPException(
                status_code=503, detail="Moondream OCR service not healthy"
            )
    except Exception as e:
        raise HTTPException(
            status_code=503, detail=f"Moondream OCR check failed: {str(e)}"
        )

    return {"status": "ready"}


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    from fastapi import Response

    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/status")
async def status():
    """Detailed status information."""
    if processor_instance is None:
        return {
            "processor_initialized": False,
            "database_connected": False,
            "moondream_available": False,
        }

    # Check database
    db_connected = False
    if processor_instance.db_pool:
        try:
            async with processor_instance.db_pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
            db_connected = True
        except:
            pass

    # Check Moondream OCR
    moondream_available = False
    try:
        response = await processor_instance.http_client.get(
            f"{processor_instance.moondream_url}/healthz", timeout=5.0
        )
        moondream_available = response.status_code == 200
    except:
        pass

    return {
        "processor_initialized": True,
        "database_connected": db_connected,
        "moondream_available": moondream_available,
        "shutdown_requested": processor_instance.shutdown,
    }


class TwitterOCRProcessor:
    """Processes Twitter images by sending them to Moondream OCR and updating the database."""

    def __init__(self):
        # Kafka configuration
        self.kafka_bootstrap_servers = os.getenv(
            "KAFKA_BOOTSTRAP_SERVERS", "kafka:29092"
        )
        self.input_topic = "external.twitter.images.raw"
        self.consumer_group = "twitter-ocr-processor"

        # Database configuration
        self.db_url = os.getenv(
            "DATABASE_URL", "postgresql://loom:loom@postgres:5432/loom"
        )

        # Moondream OCR configuration
        self.moondream_url = os.getenv("MOONDREAM_OCR_URL", "http://moondream-ocr:8007")

        # HTTP client
        self.http_client = httpx.AsyncClient(timeout=60.0)

        # Database pool
        self.db_pool = None

        # Shutdown flag
        self.shutdown = False

    async def init_db(self):
        """Initialize database connection pool."""
        try:
            self.db_pool = await asyncpg.create_pool(
                self.db_url, min_size=5, max_size=20, command_timeout=10
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error("Failed to initialize database pool", error=str(e))
            raise

    async def close(self):
        """Clean up resources."""
        if self.db_pool:
            await self.db_pool.close()
        await self.http_client.aclose()

    async def process_image(
        self, message_data: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Send image to Moondream OCR for processing."""
        try:
            # Extract image data
            image_data = message_data.get("data", {}).get("image_data")
            if not image_data:
                logger.warning(
                    "No image data in message", trace_id=message_data.get("trace_id")
                )
                return None

            # Prepare OCR request
            ocr_request = {
                "image_data": image_data,
                "prompt": "Extract all text from this Twitter/X screenshot. Include tweets, usernames, timestamps, and any other visible text.",
            }

            # Send to Moondream OCR
            start_time = time.time()
            response = await self.http_client.post(
                f"{self.moondream_url}/ocr", json=ocr_request
            )
            processing_time_ms = (time.time() - start_time) * 1000

            if response.status_code != 200:
                logger.error(
                    "OCR request failed",
                    status_code=response.status_code,
                    response=response.text,
                    trace_id=message_data.get("trace_id"),
                )
                return None

            ocr_result = response.json()

            # Prepare result for database
            return {
                "full_text": ocr_result.get("ocr_text", ""),
                "description": ocr_result.get("description", ""),
                "processing_time_ms": processing_time_ms,
                "model_version": "moondream2",
                "success": ocr_result.get("success", False),
                "error": ocr_result.get("error"),
            }

        except httpx.TimeoutException as e:
            logger.error(
                "OCR request timed out",
                error=str(e),
                trace_id=message_data.get("trace_id"),
                timeout_seconds=60,
            )
            return None
        except Exception as e:
            logger.error(
                "Error processing image with OCR",
                error=str(e) if str(e) else repr(e),
                error_type=type(e).__name__,
                trace_id=message_data.get("trace_id"),
                traceback=True,
            )
            return None

    async def update_database(self, tweet_id: str, ocr_data: Dict[str, Any]):
        """Update twitter_extraction_results table with OCR data."""
        try:
            async with self.db_pool.acquire() as conn:
                query = """
                UPDATE twitter_extraction_results
                SET ocred_data = $2,
                    timestamp = NOW()
                WHERE tweet_id = $1
                """

                result = await conn.execute(query, tweet_id, json.dumps(ocr_data))

                # Check if update was successful
                if result.split()[-1] == "0":
                    database_operations.labels(
                        operation="update", status="not_found"
                    ).inc()
                    logger.warning(
                        "No rows updated - tweet_id not found in database",
                        tweet_id=tweet_id,
                    )
                else:
                    database_operations.labels(
                        operation="update", status="success"
                    ).inc()
                    logger.info(
                        "Successfully updated OCR data",
                        tweet_id=tweet_id,
                        text_length=len(ocr_data.get("full_text", "")),
                    )

        except Exception as e:
            database_operations.labels(operation="update", status="error").inc()
            logger.error("Error updating database", error=str(e), tweet_id=tweet_id)

    async def consume_messages(self):
        """Consume messages from Kafka and process them."""
        consumer = KafkaConsumer(
            self.input_topic,
            bootstrap_servers=self.kafka_bootstrap_servers.split(","),
            auto_offset_reset="earliest",
            enable_auto_commit=True,
            group_id=self.consumer_group,
            value_deserializer=lambda m: json.loads(m.decode("utf-8")),
        )

        logger.info(
            "Started consuming messages",
            topic=self.input_topic,
            consumer_group=self.consumer_group,
        )

        try:
            for message in consumer:
                if self.shutdown:
                    break

                try:
                    with processing_duration.time():
                        # Parse message
                        msg_data = TwitterImageMessage(**message.value)

                        logger.info(
                            "Processing Twitter image",
                            trace_id=msg_data.trace_id,
                            tweet_id=msg_data.tweet_id,
                        )

                        # Process with OCR
                        ocr_result = await self.process_image(msg_data.dict())

                        if ocr_result:
                            # Update database
                            await self.update_database(msg_data.tweet_id, ocr_result)
                            messages_processed.labels(status="success").inc()
                        else:
                            messages_processed.labels(status="error").inc()

                except ValidationError as e:
                    messages_processed.labels(status="validation_error").inc()
                    logger.error(
                        "Invalid message format",
                        error=str(e),
                        error_details=e.errors() if hasattr(e, 'errors') else None,
                        raw_message=str(message.value)[:200],  # First 200 chars
                    )
                except Exception as e:
                    messages_processed.labels(status="error").inc()
                    logger.error(
                        "Error processing message",
                        error=str(e) if str(e) else repr(e),
                        error_type=type(e).__name__,
                        traceback=True,
                    )

        finally:
            consumer.close()

    def handle_shutdown(self, signum, frame):
        """Handle shutdown signals."""
        logger.info("Shutdown signal received", signal=signum)
        self.shutdown = True

    async def run(self):
        """Main run loop."""
        # Set up signal handlers
        signal.signal(signal.SIGINT, self.handle_shutdown)
        signal.signal(signal.SIGTERM, self.handle_shutdown)

        # Initialize database
        await self.init_db()

        # Wait for Moondream OCR to be ready
        logger.info("Waiting for Moondream OCR service...")
        retry_count = 0
        while retry_count < 30:  # Wait up to 5 minutes
            try:
                response = await self.http_client.get(f"{self.moondream_url}/healthz")
                if response.status_code == 200:
                    logger.info("Moondream OCR service is ready")
                    break
            except:
                pass

            retry_count += 1
            await asyncio.sleep(10)
        else:
            logger.error("Moondream OCR service not available after 5 minutes")
            return

        # Start consuming messages
        try:
            await self.consume_messages()
        finally:
            await self.close()


async def run_fastapi_server():
    """Run FastAPI server for health checks and monitoring."""
    config = uvicorn.Config(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8008")),
        log_level=os.getenv("LOG_LEVEL", "info").lower(),
        access_log=False,  # Disable access logs to reduce noise
    )
    server = uvicorn.Server(config)
    await server.serve()


async def run_processor():
    """Run the main processor logic."""
    global processor_instance
    processor_instance = TwitterOCRProcessor()
    await processor_instance.run()


async def main():
    """Main entry point - runs both FastAPI server and processor concurrently."""
    # Run both the FastAPI server and the processor concurrently
    await asyncio.gather(run_fastapi_server(), run_processor(), return_exceptions=True)


if __name__ == "__main__":
    # Set up logging
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"), format="%(message)s", stream=sys.stdout
    )

    # Run both server and processor
    asyncio.run(main())
