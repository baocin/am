"""Async Kafka consumer for GPS geocoding"""

import asyncio
import json
from typing import Any, Optional
from datetime import datetime


# Create optimized consumer with database config
async def create_optimized_consumer():
    db_url = os.getenv("DATABASE_URL", "postgresql://loom:loom@postgres:5432/loom")
    db_pool = await asyncpg.create_pool(db_url)
    loader = KafkaConsumerConfigLoader(db_pool)

    consumer = await loader.create_consumer(
        service_name="gps-geocoding-consumer",
        topics=["device.sensor.gps.raw"],  # Update with actual topics
        bootstrap_servers=os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"),
    )

    return consumer, loader, db_pool


# Use it in your main function:
# consumer, loader, db_pool = await create_optimized_consumer()

import structlog

# Kafka consumer optimization
import asyncpg
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

from .config import settings
from .models import Base

logger = structlog.get_logger()


class AsyncGPSGeocodingConsumer:
    def __init__(self):
        # Initialize async database
        self.engine = None
        self.async_session = None

        # Initialize Kafka
        self.consumer: Optional[AIOKafkaConsumer] = None
        self.producer: Optional[AIOKafkaProducer] = None

        # Tracking
        self._running = False
        self._messages_processed = 0
        self._last_commit_time = 0.0
        self._commit_interval = 5.0
        self._commit_batch_size = 100

        # Rate limiting
        self.last_api_call = 0.0
        self.daily_calls = 0
        self.daily_reset = datetime.utcnow().date()

    async def start(self):
        """Start the consumer"""
        try:
            # Create async database engine
            # Convert sync URL to async
            db_url = settings.database_url.replace(
                "postgresql://", "postgresql+asyncpg://"
            )
            self.engine = create_async_engine(db_url)
            self.async_session = async_sessionmaker(self.engine, expire_on_commit=False)

            # Create tables if needed
            async with self.engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)

            # Create Kafka consumer
            self.consumer = AIOKafkaConsumer(
                settings.kafka_input_topic,
                bootstrap_servers=settings.kafka_bootstrap_servers.split(","),
                group_id=settings.kafka_consumer_group_id,
                value_deserializer=lambda m: json.loads(m.decode("utf-8")),
                auto_offset_reset="earliest",
                enable_auto_commit=False,  # Manual commit for better control
                max_poll_records=10,
                session_timeout_ms=30000,
                heartbeat_interval_ms=3000,
                max_poll_interval_ms=300000,
                consumer_timeout_ms=5000,
            )

            # Create Kafka producer
            self.producer = AIOKafkaProducer(
                bootstrap_servers=settings.kafka_bootstrap_servers.split(","),
                value_serializer=lambda v: json.dumps(v).encode("utf-8"),
                compression_type="gzip",
                acks="all",
                enable_idempotence=True,
            )

            await self.consumer.start()
            await self.producer.start()

            # Initialize commit tracking
            import time

            self._last_commit_time = time.time()
            self._running = True

            logger.info(
                "Async GPS geocoding consumer started",
                input_topic=settings.kafka_input_topic,
                output_topic=settings.kafka_output_topic,
            )

        except Exception as e:
            logger.error("Failed to start consumer", error=str(e))
            raise

    async def stop(self):
        """Stop the consumer gracefully"""
        self._running = False

        # Commit any pending offsets
        if self.consumer and self._messages_processed > 0:
            try:
                await self.consumer.commit()
                logger.info(
                    "Final commit before shutdown",
                    messages_processed=self._messages_processed,
                )
            except Exception as e:
                logger.error("Failed to commit final offsets", error=str(e))

        # Close Kafka clients
        if self.consumer:
            await self.consumer.stop()
        if self.producer:
            await self.producer.stop()

        # Close database
        if self.engine:
            await self.engine.dispose()

        logger.info("Consumer stopped")

    async def consume(self):
        """Main consumer loop"""
        if not self.consumer or not self.producer:
            raise RuntimeError("Consumer not started")

        logger.info("Starting message processing loop")

        while self._running:
            try:
                # Fetch messages
                messages = await self.consumer.getmany(timeout_ms=5000)

                if not messages:
                    # Check if we need to commit based on time
                    await self._maybe_commit()
                    continue

                # Process messages
                for tp, partition_messages in messages.items():
                    for message in partition_messages:
                        try:
                            await self._process_message(message)
                            self._messages_processed += 1
                        except Exception as e:
                            logger.error(
                                "Error processing message",
                                error=str(e),
                                topic=message.topic,
                                partition=message.partition,
                                offset=message.offset,
                            )
                            # Continue processing other messages

                # Batch commit
                await self._maybe_commit()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in consumer loop", error=str(e))
                await asyncio.sleep(1)

    async def _maybe_commit(self):
        """Commit offsets if batch size or time interval is reached"""
        import time

        current_time = time.time()
        time_since_last_commit = current_time - self._last_commit_time

        if (
            self._messages_processed >= self._commit_batch_size
            or time_since_last_commit >= self._commit_interval
        ):
            try:
                await self.consumer.commit()
                logger.info(
                    "Batch commit completed",
                    messages_processed=self._messages_processed,
                    time_since_last_commit=round(time_since_last_commit, 2),
                )
                self._messages_processed = 0
                self._last_commit_time = current_time
            except Exception as e:
                logger.error("Failed to commit offsets", error=str(e))

    async def _process_message(self, message: Any):
        """Process a single GPS message"""
        logger.info(
            "Processing message",
            key=message.key.decode("utf-8") if message.key else None,
            offset=message.offset,
        )

        # Extract GPS data
        data = message.value
        latitude = data.get("latitude")
        longitude = data.get("longitude")
        device_id = data.get("device_id")
        timestamp = data.get("timestamp")
        accuracy = data.get("accuracy")

        if latitude is None or longitude is None:
            logger.warning("Invalid GPS data - missing coordinates", message=data)
            return

        logger.info(
            "Processing GPS location",
            device_id=device_id,
            latitude=latitude,
            longitude=longitude,
            accuracy=accuracy,
        )

        # For now, just forward the message with a geocoding placeholder
        # Real geocoding would be done here with proper async rate limiting
        output_message = {
            "device_id": device_id,
            "timestamp": timestamp,
            "latitude": latitude,
            "longitude": longitude,
            "accuracy": accuracy,
            "geocoded": {
                "address": f"Near {latitude:.4f}, {longitude:.4f}",
                "city": "Unknown",
                "state": "Unknown",
                "country": "Unknown",
                "cached": False,
            },
            "schema_version": "v1",
        }

        # Send to output topic
        await self.producer.send(
            settings.kafka_output_topic,
            key=device_id.encode("utf-8") if device_id else None,
            value=output_message,
        )

        logger.info(
            "Sent geocoded location to Kafka",
            output_topic=settings.kafka_output_topic,
            device_id=device_id,
        )


async def main():
    """Main entry point"""
    consumer = AsyncGPSGeocodingConsumer()

    try:
        await consumer.start()
        await consumer.consume()
    except KeyboardInterrupt:
        logger.info("Received interrupt signal")
    finally:
        await consumer.stop()


if __name__ == "__main__":
    asyncio.run(main())
