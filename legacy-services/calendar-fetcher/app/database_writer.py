"""Database writer for calendar data."""

import logging
from typing import Dict, Any, List
import asyncpg
import os


class DatabaseWriter:
    """Write calendar data directly to PostgreSQL database."""

    def __init__(self):
        """Initialize database connection."""
        self.database_url = os.getenv(
            "LOOM_DATABASE_URL", "postgresql://loom:loom@postgres:5432/loom"
        )
        self.connection_pool = None

    async def initialize(self):
        """Initialize connection pool."""
        try:
            self.connection_pool = await asyncpg.create_pool(
                self.database_url, min_size=1, max_size=5, command_timeout=30
            )
            logging.info("Database connection pool initialized")
        except Exception as e:
            logging.error(f"Failed to initialize database connection: {e}")
            raise

    async def close(self):
        """Close database connections."""
        if self.connection_pool:
            await self.connection_pool.close()
            logging.info("Database connection pool closed")

    async def write_calendar_event(self, event_data: Dict[str, Any]) -> bool:
        """
        Write calendar event to external_calendar_events_raw table.

        Args:
            event_data: Calendar event data dictionary containing all required fields

        Returns:
            bool: True if write was successful, False otherwise
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                # Insert event data into external_calendar_events_raw table
                await conn.execute(
                    """
                    INSERT INTO external_calendar_events_raw (
                        device_id, timestamp, schema_version, event_id, calendar_id,
                        title, description, location, start_time, end_time, all_day,
                        recurring_rule, attendees, organizer_email, status, visibility,
                        reminders, conference_data, color_id, last_modified, metadata
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
                    ) ON CONFLICT (device_id, event_id, timestamp) DO NOTHING
                    """,
                    event_data["device_id"],
                    event_data["timestamp"],
                    event_data.get("schema_version", "v1"),
                    event_data["event_id"],
                    event_data["calendar_id"],
                    event_data["title"],
                    event_data.get("description"),
                    event_data.get("location"),
                    event_data["start_time"],
                    event_data["end_time"],
                    event_data.get("all_day", False),
                    event_data.get("recurring_rule"),
                    event_data.get("attendees"),
                    event_data.get("organizer_email"),
                    event_data.get("status", "confirmed"),
                    event_data.get("visibility"),
                    event_data.get("reminders"),
                    event_data.get("conference_data"),
                    event_data.get("color_id"),
                    event_data.get("last_modified"),
                    event_data.get("metadata", {}),
                )

            logging.debug(
                f"Successfully wrote calendar event {event_data['event_id']} to database"
            )
            return True

        except asyncpg.UniqueViolationError:
            # Event already exists, this is expected for deduplication
            logging.debug(
                f"Calendar event {event_data['event_id']} already exists in database"
            )
            return True

        except Exception as e:
            logging.error(f"Failed to write calendar event to database: {e}")
            return False

    async def write_calendar_events_batch(self, events: List[Dict[str, Any]]) -> int:
        """
        Write multiple calendar events in a batch transaction.

        Args:
            events: List of calendar event data dictionaries

        Returns:
            int: Number of events successfully written
        """
        if not events:
            return 0

        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return 0

        successful_writes = 0

        try:
            async with self.connection_pool.acquire() as conn:
                async with conn.transaction():
                    for event_data in events:
                        try:
                            await conn.execute(
                                """
                                INSERT INTO external_calendar_events_raw (
                                    device_id, timestamp, schema_version, event_id, calendar_id,
                                    title, description, location, start_time, end_time, all_day,
                                    recurring_rule, attendees, organizer_email, status, visibility,
                                    reminders, conference_data, color_id, last_modified, metadata
                                ) VALUES (
                                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
                                ) ON CONFLICT (device_id, event_id, timestamp) DO NOTHING
                                """,
                                event_data["device_id"],
                                event_data["timestamp"],
                                event_data.get("schema_version", "v1"),
                                event_data["event_id"],
                                event_data["calendar_id"],
                                event_data["title"],
                                event_data.get("description"),
                                event_data.get("location"),
                                event_data["start_time"],
                                event_data["end_time"],
                                event_data.get("all_day", False),
                                event_data.get("recurring_rule"),
                                event_data.get("attendees"),
                                event_data.get("organizer_email"),
                                event_data.get("status", "confirmed"),
                                event_data.get("visibility"),
                                event_data.get("reminders"),
                                event_data.get("conference_data"),
                                event_data.get("color_id"),
                                event_data.get("last_modified"),
                                event_data.get("metadata", {}),
                            )
                            successful_writes += 1

                        except Exception as e:
                            logging.warning(
                                f"Failed to write calendar event {event_data.get('event_id', 'unknown')}: {e}"
                            )

            logging.info(
                f"Successfully wrote {successful_writes}/{len(events)} calendar events to database"
            )
            return successful_writes

        except Exception as e:
            logging.error(f"Failed to write calendar events batch to database: {e}")
            return 0

    async def get_existing_event_ids(self) -> set:
        """
        Get all existing calendar event IDs from the database.

        Returns:
            set: Set of existing event IDs
        """
        if not self.connection_pool:
            return set()

        try:
            async with self.connection_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT DISTINCT event_id FROM external_calendar_events_raw"
                )
                return {row["event_id"] for row in rows}

        except Exception as e:
            logging.error(f"Failed to get existing calendar event IDs: {e}")
            return set()

    async def check_event_exists(self, device_id: str, event_id: str) -> bool:
        """
        Check if a calendar event already exists in the database.

        Args:
            device_id: Device ID
            event_id: Calendar event ID

        Returns:
            bool: True if event exists, False otherwise
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT 1 FROM external_calendar_events_raw WHERE device_id = $1 AND event_id = $2 LIMIT 1",
                    device_id,
                    event_id,
                )
                return result is not None

        except Exception as e:
            logging.error(f"Failed to check if calendar event exists: {e}")
            return False
