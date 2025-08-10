"""Database checker for avoiding duplicate tweet processing."""

import asyncpg
import logging
from typing import Set, Optional


class DatabaseChecker:
    """Check database for existing tweets to avoid duplicates."""

    def __init__(self, database_url: str):
        self.database_url = database_url
        self.pool: Optional[asyncpg.Pool] = None

    async def connect(self):
        """Connect to the database."""
        try:
            self.pool = await asyncpg.create_pool(
                self.database_url,
                min_size=1,
                max_size=3,
                command_timeout=30,
            )
            logging.info("Database connection established for duplicate checking")
        except Exception as e:
            logging.error(f"Failed to connect to database: {e}")
            raise

    async def disconnect(self):
        """Disconnect from the database."""
        if self.pool:
            await self.pool.close()
            logging.info("Database connection closed")

    async def get_existing_tweet_ids(self) -> Set[str]:
        """Get set of tweet IDs that already exist in twitter_extraction_results table."""
        if not self.pool:
            logging.warning("Database not connected, cannot check for existing tweets")
            return set()

        try:
            async with self.pool.acquire() as conn:
                # Query for existing tweet IDs
                rows = await conn.fetch(
                    "SELECT tweet_id FROM twitter_extraction_results WHERE tweet_id IS NOT NULL"
                )

                existing_ids = {row["tweet_id"] for row in rows}
                logging.info(f"Found {len(existing_ids)} existing tweets in database")
                return existing_ids

        except Exception as e:
            logging.error(f"Failed to query existing tweets: {e}")
            return set()

    async def is_tweet_processed(self, tweet_url: str) -> bool:
        """Check if a specific tweet URL has already been processed."""
        if not tweet_url:
            return False

        # Extract tweet ID from URL
        tweet_id = tweet_url.split("/")[-1] if tweet_url else None
        if not tweet_id:
            return False

        if not self.pool:
            return False

        try:
            async with self.pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT 1 FROM twitter_extraction_results WHERE tweet_id = $1",
                    tweet_id,
                )
                return result is not None

        except Exception as e:
            logging.error(f"Failed to check tweet {tweet_id}: {e}")
            return False

    async def get_processing_stats(self) -> dict:
        """Get statistics about processed tweets."""
        if not self.pool:
            return {"total_processed": 0, "with_screenshots": 0, "errors": 0}

        try:
            async with self.pool.acquire() as conn:
                stats = await conn.fetchrow(
                    """
                    SELECT
                        COUNT(*) as total_processed,
                        COUNT(screenshot_path) as with_screenshots,
                        COUNT(error_message) as errors
                    FROM twitter_extraction_results
                """
                )

                return {
                    "total_processed": stats["total_processed"],
                    "with_screenshots": stats["with_screenshots"],
                    "errors": stats["errors"],
                }

        except Exception as e:
            logging.error(f"Failed to get processing stats: {e}")
            return {"total_processed": 0, "with_screenshots": 0, "errors": 0}
