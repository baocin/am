"""Kafka consumer for GPS geocoding"""

import json
import asyncio
from typing import Dict, Any
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import structlog

from .config import settings
from .geocoding import GeocodingService
from .models import Base

logger = structlog.get_logger()


class GPSGeocodingConsumer(ConsumerActivityLogger):
    def __init__(self):
        # Initialize activity logger
        super().__init__(service_name="gps-geocoding-consumer")

        # Initialize database
        self.engine = create_engine(settings.database_url)
        Base.metadata.create_all(self.engine)
        self.SessionLocal = sessionmaker(bind=self.engine)

        # Initialize services
        self.geocoding_service = GeocodingService()

        # Initialize Kafka
        self.consumer = None
        self.producer = None

        # Create async loop for activity logging in sync context
        self._loop = None

    def start(self):
        """Start the consumer"""
        try:
            # Create event loop for async operations in sync context
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)

            # Initialize activity logger
            self._loop.run_until_complete(self.init_activity_logger())

            # Create Kafka consumer
            self.consumer = KafkaConsumer(
                settings.kafka_input_topic,
                bootstrap_servers=settings.kafka_bootstrap_servers.split(","),
                group_id=settings.kafka_consumer_group_id,
                value_deserializer=lambda m: json.loads(m.decode("utf-8")),
                auto_offset_reset="earliest",
                enable_auto_commit=True,
                max_poll_records=1,  # Process one at a time for rate limiting
            )

            # Create Kafka producer
            self.producer = KafkaProducer(
                bootstrap_servers=settings.kafka_bootstrap_servers.split(","),
                value_serializer=lambda v: json.dumps(v).encode("utf-8"),
                compression_type="gzip",
            )

            logger.info(
                "GPS geocoding consumer started",
                input_topic=settings.kafka_input_topic,
                output_topic=settings.kafka_output_topic,
            )

            # Process messages
            logger.info("Starting message processing loop")
            message_count = 0
            for message in self.consumer:
                try:
                    message_count += 1
                    logger.info(
                        "Received message",
                        count=message_count,
                        topic=message.topic,
                        partition=message.partition,
                        offset=message.offset,
                        key=message.key.decode("utf-8") if message.key else None,
                        value_preview=(
                            str(message.value)[:100] if message.value else None
                        ),
                    )

                    # Log consumption (convert kafka-python message to aiokafka-like format)
                    if self._loop:
                        mock_message = type(
                            "obj",
                            (object,),
                            {
                                "topic": message.topic,
                                "partition": message.partition,
                                "offset": message.offset,
                                "value": message.value,
                                "key": message.key,
                            },
                        )
                        self._loop.run_until_complete(
                            self.log_consumption(mock_message)
                        )

                    self._process_message(message.value)
                except Exception as e:
                    logger.error(
                        "Error processing message",
                        error=str(e),
                        topic=message.topic,
                        partition=message.partition,
                        offset=message.offset,
                    )

        except Exception as e:
            logger.error("Consumer error", error=str(e))
            raise
        finally:
            self.cleanup()

    def _process_message(self, message: Dict[str, Any]):
        """Process a single GPS message"""
        logger.info(
            "Entering _process_message",
            message_keys=list(message.keys()) if message else None,
        )

        # Extract GPS data
        latitude = message.get("latitude")
        longitude = message.get("longitude")
        device_id = message.get("device_id")
        timestamp = message.get("timestamp")
        accuracy = message.get("accuracy")

        logger.info(
            "Extracted GPS data",
            latitude=latitude,
            longitude=longitude,
            device_id=device_id,
            timestamp=timestamp,
            accuracy=accuracy,
        )

        if latitude is None or longitude is None:
            logger.warning("Invalid GPS data - missing coordinates", message=message)
            return

        logger.info(
            "Processing GPS location",
            device_id=device_id,
            latitude=latitude,
            longitude=longitude,
            accuracy=accuracy,
        )

        # Get database session
        session = self.SessionLocal()
        try:
            # Geocode the location
            geocoded_data = self.geocoding_service.geocode_location(
                session, latitude, longitude
            )

            if geocoded_data:
                # Prepare output message
                output_message = {
                    "device_id": device_id,
                    "timestamp": timestamp,
                    "latitude": latitude,
                    "longitude": longitude,
                    "accuracy": accuracy,
                    "geocoded": geocoded_data,
                    "schema_version": "v1",
                }

                # Send to output topic
                future = self.producer.send(
                    settings.kafka_output_topic,
                    key=device_id.encode("utf-8") if device_id else None,
                    value=output_message,
                )

                # Wait for send to complete
                try:
                    record_metadata = future.get(timeout=10)
                    logger.info(
                        "Sent geocoded location to Kafka",
                        topic=record_metadata.topic,
                        partition=record_metadata.partition,
                        offset=record_metadata.offset,
                        address=geocoded_data.get("address"),
                    )

                    # Log production
                    if self._loop:
                        self._loop.run_until_complete(
                            self.log_production(
                                settings.kafka_output_topic, output_message, device_id
                            )
                        )
                except KafkaError as e:
                    logger.error("Failed to send to Kafka", error=str(e))

        finally:
            session.close()

    def cleanup(self):
        """Clean up resources"""
        if self.consumer:
            self.consumer.close()
        if self.producer:
            self.producer.close()

        # Close activity logger
        if self._loop:
            self._loop.run_until_complete(self.close_activity_logger())
            self._loop.close()

        logger.info("Consumer cleaned up")
