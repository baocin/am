import json
import logging
import os
from typing import Any, Optional
import asyncpg
from datetime import datetime


class DatabaseWriter:
    def __init__(self):
        """Initialize database writer"""
        self.database_url = os.getenv("LOOM_DATABASE_URL")
        self.pool = None
        logging.info("Database writer initialized")

    async def connect(self):
        """Connect to database"""
        if self.database_url:
            self.pool = await asyncpg.create_pool(self.database_url)
            logging.info("Connected to database")

    async def close(self):
        """Close database connection"""
        if self.pool:
            await self.pool.close()

    async def send_message(self, table: str, value: Any, key: Optional[str] = None):
        """Write message to database table"""
        if not self.pool:
            logging.error("Database not connected")
            return

        try:
            # Map topic names to table names
            table_mapping = {
                "external.twitter.liked.raw": "external_twitter_liked_raw",
                "task.url.ingest": "task_url_ingest",
            }

            table_name = table_mapping.get(table, table.replace(".", "_"))

            async with self.pool.acquire() as conn:
                # Insert into appropriate table
                if table_name == "external_twitter_liked_raw":
                    await conn.execute(
                        f"""
                        INSERT INTO {table_name} (id, device_id, timestamp, data)
                        VALUES (gen_random_uuid(), $1, $2, $3)
                        """,
                        key or "x-likes-fetcher",
                        datetime.utcnow(),
                        json.dumps(value),
                    )
                elif table_name == "task_url_ingest":
                    await conn.execute(
                        f"""
                        INSERT INTO {table_name} (id, url, source, timestamp, metadata)
                        VALUES (gen_random_uuid(), $1, $2, $3, $4)
                        """,
                        value.get("url"),
                        value.get("source", "x-likes-fetcher"),
                        datetime.utcnow(),
                        json.dumps(value.get("metadata", {})),
                    )
                else:
                    # Generic insert
                    await conn.execute(
                        f"""
                        INSERT INTO {table_name} (id, device_id, timestamp, data)
                        VALUES (gen_random_uuid(), $1, $2, $3)
                        """,
                        key or "x-likes-fetcher",
                        datetime.utcnow(),
                        json.dumps(value),
                    )

            logging.info(f"Successfully wrote to {table_name}")

        except Exception as e:
            logging.error(f"Failed to write to database: {e}")
            raise

    def flush(self):
        """Flush any pending writes (no-op for database)"""
        pass
