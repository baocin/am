"""Database poller for URL processing tasks."""

import os
import json
import logging
import asyncpg
from typing import Dict, Any, List


class DatabasePoller:
    """Polls task_url_ingest table for URLs to process."""

    def __init__(self):
        """Initialize database poller."""
        self.database_url = os.getenv(
            "LOOM_DATABASE_URL", "postgresql://loom:loom@postgres:5432/loom"
        )
        self.poll_interval = int(os.getenv("LOOM_DB_POLL_INTERVAL", "30"))
        self.batch_size = int(os.getenv("LOOM_DB_BATCH_SIZE", "10"))
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

    async def get_pending_urls(self) -> List[Dict[str, Any]]:
        """
        Get pending URLs from task_url_ingest table.

        Returns:
            List of URL tasks to process
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return []

        try:
            async with self.connection_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT
                        id, url, timestamp, source_type, priority,
                        retry_count, metadata, trace_id
                    FROM task_url_ingest
                    WHERE status = 'pending'
                        AND retry_count < max_retries
                        AND source_type = 'x-likes-fetcher'
                    ORDER BY priority DESC, timestamp ASC
                    LIMIT $1
                    """,
                    self.batch_size,
                )

                tasks = []
                for row in rows:
                    task = {
                        "id": row["id"],
                        "url": row["url"],
                        "timestamp": row["timestamp"].isoformat(),
                        "source_type": row["source_type"],
                        "priority": row["priority"],
                        "retry_count": row["retry_count"],
                        "metadata": (
                            json.loads(row["metadata"]) if row["metadata"] else {}
                        ),
                        "trace_id": row["trace_id"],
                    }
                    tasks.append(task)

                if tasks:
                    logging.info(f"Found {len(tasks)} pending URLs to process")

                return tasks

        except Exception as e:
            logging.error(f"Failed to get pending URLs: {e}")
            return []

    async def mark_processing(self, task_id: int) -> bool:
        """
        Mark a URL task as processing.

        Args:
            task_id: ID of the task to mark

        Returns:
            bool: True if successful
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE task_url_ingest
                    SET status = 'processing',
                        updated_at = NOW()
                    WHERE id = $1
                    """,
                    task_id,
                )
            return True
        except Exception as e:
            logging.error(f"Failed to mark task {task_id} as processing: {e}")
            return False

    async def mark_completed(self, task_id: int) -> bool:
        """
        Mark a URL task as completed.

        Args:
            task_id: ID of the task to mark

        Returns:
            bool: True if successful
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE task_url_ingest
                    SET status = 'completed',
                        updated_at = NOW()
                    WHERE id = $1
                    """,
                    task_id,
                )
            return True
        except Exception as e:
            logging.error(f"Failed to mark task {task_id} as completed: {e}")
            return False

    async def mark_failed(self, task_id: int, error_message: str) -> bool:
        """
        Mark a URL task as failed.

        Args:
            task_id: ID of the task to mark
            error_message: Error message to store

        Returns:
            bool: True if successful
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE task_url_ingest
                    SET status = 'failed',
                        error_message = $2,
                        retry_count = retry_count + 1,
                        updated_at = NOW()
                    WHERE id = $1
                    """,
                    task_id,
                    error_message,
                )
            return True
        except Exception as e:
            logging.error(f"Failed to mark task {task_id} as failed: {e}")
            return False
