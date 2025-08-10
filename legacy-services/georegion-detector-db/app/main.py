#!/usr/bin/env python3
"""Georegion detector that reads GPS data from database instead of Kafka."""

import asyncio
import os
import sys
from datetime import datetime
from typing import Dict, Any, List

import structlog

# Add parent directory to path for common imports
sys.path.append(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
from common.scheduled_db_consumer import ScheduledDatabaseConsumer

logger = structlog.get_logger(__name__)


class GeoregionDetector(ScheduledDatabaseConsumer):
    """Detects when devices enter/exit predefined geographic regions."""

    def __init__(self):
        super().__init__(
            consumer_name="georegion-detector-db",
            source_table="device_sensor_gps_raw",
            poll_interval_seconds=30,  # Check every 30 seconds
            batch_size=1000,
        )

        # Load georegions from database
        self.georegions: List[Dict[str, Any]] = []

        # Track last known location per device
        self.device_locations: Dict[str, Dict[str, Any]] = {}

    async def start(self):
        """Start the georegion detector."""
        # Load georegions first
        await self._load_georegions()

        # Start the consumer
        await super().start()

    async def _load_georegions(self):
        """Load georegion definitions from database."""
        # Create temporary connection to load georegions
        import asyncpg

        conn = await asyncpg.connect(self.database_url)

        try:
            # Create georegions table if it doesn't exist
            await conn.execute(
                """
                CREATE TABLE IF NOT EXISTS georegions (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    latitude DOUBLE PRECISION NOT NULL,
                    longitude DOUBLE PRECISION NOT NULL,
                    radius_meters DOUBLE PRECISION NOT NULL,
                    category TEXT,
                    metadata JSONB,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                )
            """
            )

            # Load all georegions
            rows = await conn.fetch("SELECT * FROM georegions")
            self.georegions = [dict(row) for row in rows]

            logger.info("Loaded georegions", count=len(self.georegions))

            # Insert default georegions if none exist
            if not self.georegions:
                await self._insert_default_georegions(conn)
                rows = await conn.fetch("SELECT * FROM georegions")
                self.georegions = [dict(row) for row in rows]

        finally:
            await conn.close()

    async def _insert_default_georegions(self, conn):
        """Insert some default georegions for testing."""
        default_regions = [
            {
                "name": "Home",
                "latitude": 37.7749,  # Example: San Francisco
                "longitude": -122.4194,
                "radius_meters": 100,
                "category": "home",
            },
            {
                "name": "Work",
                "latitude": 37.7739,
                "longitude": -122.4312,
                "radius_meters": 200,
                "category": "work",
            },
        ]

        for region in default_regions:
            await conn.execute(
                """
                INSERT INTO georegions (name, latitude, longitude, radius_meters, category)
                VALUES ($1, $2, $3, $4, $5)
                """,
                region["name"],
                region["latitude"],
                region["longitude"],
                region["radius_meters"],
                region["category"],
            )

        logger.info("Inserted default georegions")

    async def process_row(self, row: Dict[str, Any]):
        """Process a GPS reading and check for georegion events."""
        device_id = row["device_id"]
        latitude = row["latitude"]
        longitude = row["longitude"]
        timestamp = row["timestamp"]

        # Get previous location for this device
        previous_location = self.device_locations.get(device_id)

        # Update current location
        current_location = {
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": timestamp,
            "in_regions": set(),
        }

        # Check which regions the device is currently in
        for region in self.georegions:
            distance = self._calculate_distance(
                latitude, longitude, region["latitude"], region["longitude"]
            )

            if distance <= region["radius_meters"]:
                current_location["in_regions"].add(region["name"])

        # Detect enter/exit events
        if previous_location:
            previous_regions = previous_location.get("in_regions", set())
            current_regions = current_location["in_regions"]

            # Regions entered
            entered = current_regions - previous_regions
            for region_name in entered:
                await self._emit_georegion_event(
                    device_id, region_name, "enter", timestamp, latitude, longitude
                )

            # Regions exited
            exited = previous_regions - current_regions
            for region_name in exited:
                await self._emit_georegion_event(
                    device_id, region_name, "exit", timestamp, latitude, longitude
                )

        # Store current location
        self.device_locations[device_id] = current_location

    async def _emit_georegion_event(
        self,
        device_id: str,
        region_name: str,
        event_type: str,
        timestamp: datetime,
        latitude: float,
        longitude: float,
    ):
        """Emit a georegion enter/exit event."""
        event = {
            "device_id": device_id,
            "timestamp": timestamp.isoformat(),
            "event_type": event_type,  # "enter" or "exit"
            "region_name": region_name,
            "latitude": latitude,
            "longitude": longitude,
        }

        # Log the event
        logger.info(
            "Georegion event",
            device_id=device_id,
            region=region_name,
            event_type=event_type,
        )

        # Store in database
        async with self.db_pool.acquire() as conn:
            # Create table if it doesn't exist
            await conn.execute(
                """
                CREATE TABLE IF NOT EXISTS location_georegion_detected (
                    id SERIAL PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    timestamp TIMESTAMPTZ NOT NULL,
                    event_type TEXT NOT NULL,
                    region_name TEXT NOT NULL,
                    latitude DOUBLE PRECISION,
                    longitude DOUBLE PRECISION,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )
            """
            )

            # Insert event
            await conn.execute(
                """
                INSERT INTO location_georegion_detected
                (device_id, timestamp, event_type, region_name, latitude, longitude)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                device_id,
                timestamp,
                event_type,
                region_name,
                latitude,
                longitude,
            )

    def _calculate_distance(
        self, lat1: float, lon1: float, lat2: float, lon2: float
    ) -> float:
        """Calculate distance between two points in meters using Haversine formula."""
        from math import radians, sin, cos, sqrt, atan2

        R = 6371000  # Earth's radius in meters

        lat1_rad = radians(lat1)
        lat2_rad = radians(lat2)
        delta_lat = radians(lat2 - lat1)
        delta_lon = radians(lon2 - lon1)

        a = (
            sin(delta_lat / 2) ** 2
            + cos(lat1_rad) * cos(lat2_rad) * sin(delta_lon / 2) ** 2
        )
        c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return R * c


async def main():
    """Main entry point."""
    # Configure logging
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.dev.ConsoleRenderer(),
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    # Create and start the detector
    detector = GeoregionDetector()

    try:
        await detector.start()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        await detector.stop()


if __name__ == "__main__":
    asyncio.run(main())
