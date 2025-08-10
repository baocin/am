"""Database writer for HackerNews data."""

import logging
from typing import Dict, Any, List
import asyncpg
import os


class DatabaseWriter:
    """Write HackerNews data directly to PostgreSQL database."""

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

    async def write_hackernews_item(self, item_data: Dict[str, Any]) -> bool:
        """
        Write HackerNews item to external_hackernews_activity_raw table.

        Args:
            item_data: HackerNews item data dictionary containing all required fields

        Returns:
            bool: True if write was successful, False otherwise
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                # Insert item data into external_hackernews_activity_raw table
                await conn.execute(
                    """
                    INSERT INTO external_hackernews_activity_raw (
                        device_id, timestamp, schema_version, message_id, item_id, item_type,
                        title, url, text, author, score, comments_count, created_at,
                        interacted_at, interaction_type
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
                    ) ON CONFLICT (device_id, item_id, timestamp) DO NOTHING
                    """,
                    item_data["device_id"],
                    item_data["timestamp"],
                    item_data.get("schema_version", "v1"),
                    item_data["message_id"],
                    item_data["item_id"],
                    item_data["item_type"],
                    item_data.get("title"),
                    item_data.get("url"),
                    item_data.get("text"),
                    item_data["author"],
                    item_data.get("score", 0),
                    item_data.get("comments_count", 0),
                    item_data["created_at"],
                    item_data["interacted_at"],
                    item_data["interaction_type"],
                )

            logging.debug(
                f"Successfully wrote HackerNews item {item_data['item_id']} to database"
            )
            return True

        except asyncpg.UniqueViolationError:
            # Item already exists, this is expected for deduplication
            logging.debug(
                f"HackerNews item {item_data['item_id']} already exists in database"
            )
            return True

        except Exception as e:
            logging.error(f"Failed to write HackerNews item to database: {e}")
            return False

    async def write_hackernews_items_batch(self, items: List[Dict[str, Any]]) -> int:
        """
        Write multiple HackerNews items in a batch transaction.

        Args:
            items: List of HackerNews item data dictionaries

        Returns:
            int: Number of items successfully written
        """
        if not items:
            return 0

        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return 0

        successful_writes = 0

        try:
            async with self.connection_pool.acquire() as conn:
                async with conn.transaction():
                    for item_data in items:
                        try:
                            await conn.execute(
                                """
                                INSERT INTO external_hackernews_activity_raw (
                                    device_id, timestamp, schema_version, message_id, item_id, item_type,
                                    title, url, text, author, score, comments_count, created_at,
                                    interacted_at, interaction_type
                                ) VALUES (
                                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
                                ) ON CONFLICT (device_id, item_id, timestamp) DO NOTHING
                                """,
                                item_data["device_id"],
                                item_data["timestamp"],
                                item_data.get("schema_version", "v1"),
                                item_data["message_id"],
                                item_data["item_id"],
                                item_data["item_type"],
                                item_data.get("title"),
                                item_data.get("url"),
                                item_data.get("text"),
                                item_data["author"],
                                item_data.get("score", 0),
                                item_data.get("comments_count", 0),
                                item_data["created_at"],
                                item_data["interacted_at"],
                                item_data["interaction_type"],
                            )
                            successful_writes += 1

                        except Exception as e:
                            logging.warning(
                                f"Failed to write HackerNews item {item_data.get('item_id', 'unknown')}: {e}"
                            )

            logging.info(
                f"Successfully wrote {successful_writes}/{len(items)} HackerNews items to database"
            )
            return successful_writes

        except Exception as e:
            logging.error(f"Failed to write HackerNews items batch to database: {e}")
            return 0

    async def get_existing_item_ids(self) -> set:
        """
        Get all existing HackerNews item IDs from the database.

        Returns:
            set: Set of existing item IDs
        """
        if not self.connection_pool:
            return set()

        try:
            async with self.connection_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT DISTINCT item_id FROM external_hackernews_activity_raw"
                )
                return {row["item_id"] for row in rows}

        except Exception as e:
            logging.error(f"Failed to get existing HackerNews item IDs: {e}")
            return set()

    async def check_item_exists(self, device_id: str, item_id: int) -> bool:
        """
        Check if a HackerNews item already exists in the database.

        Args:
            device_id: Device ID
            item_id: HackerNews item ID

        Returns:
            bool: True if item exists, False otherwise
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT 1 FROM external_hackernews_activity_raw WHERE device_id = $1 AND item_id = $2 LIMIT 1",
                    device_id,
                    item_id,
                )
                return result is not None

        except Exception as e:
            logging.error(f"Failed to check if HackerNews item exists: {e}")
            return False
