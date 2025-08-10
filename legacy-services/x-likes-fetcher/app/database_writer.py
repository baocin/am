"""Database writer for X/Twitter liked tweets data."""

import logging
from typing import Dict, Any, List
import asyncpg
import os
import uuid
from datetime import datetime


class DatabaseWriter:
    """Write X/Twitter data directly to PostgreSQL database."""

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

    async def write_tweet(self, tweet_data: Dict[str, Any]) -> bool:
        """
        Write tweet data to external_twitter_liked_raw table.

        Args:
            tweet_data: Tweet data dictionary containing all required fields

        Returns:
            bool: True if write was successful, False otherwise
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                # Generate trace ID for tracing
                trace_id = str(uuid.uuid4())

                # Insert tweet data into external_twitter_liked_raw table
                # Insert tweet data into external_twitter_liked_raw table
                import json

                await conn.execute(
                    """
                    INSERT INTO external_twitter_liked_raw (
                        device_id, timestamp, schema_version, tweet_id, author_username,
                        author_display_name, tweet_text, tweet_html, media_urls, hashtags, mentions,
                        urls, reply_to_id, quote_tweet_id, retweet_count, like_count, reply_count,
                        created_at_twitter, liked_at, metadata, trace_id
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
                    ) ON CONFLICT (device_id, tweet_id, timestamp) DO NOTHING
                    """,
                    tweet_data["device_id"],
                    tweet_data["timestamp"],
                    tweet_data.get("schema_version", "v1"),
                    tweet_data["tweet_id"],
                    tweet_data["author_username"],
                    tweet_data.get("author_display_name"),
                    tweet_data["tweet_text"],
                    tweet_data.get("tweet_html"),
                    tweet_data.get("media_urls", []),
                    tweet_data.get("hashtags", []),
                    tweet_data.get("mentions", []),
                    tweet_data.get("urls", []),
                    tweet_data.get("reply_to_id"),
                    tweet_data.get("quote_tweet_id"),
                    tweet_data.get("retweet_count", 0),
                    tweet_data.get("like_count", 0),
                    tweet_data.get("reply_count", 0),
                    tweet_data["created_at_twitter"],
                    tweet_data["liked_at"],
                    json.dumps(tweet_data.get("metadata", {})),
                    trace_id,
                )

            logging.debug(
                f"Successfully wrote tweet {tweet_data['tweet_id']} to database"
            )
            return True

        except asyncpg.UniqueViolationError:
            # Tweet already exists, this is expected for deduplication
            logging.debug(f"Tweet {tweet_data['tweet_id']} already exists in database")
            return True

        except Exception as e:
            logging.error(f"Failed to write tweet to database: {e}")
            return False

    async def write_tweets_batch(self, tweets: List[Dict[str, Any]]) -> int:
        """
        Write multiple tweets in a batch transaction.

        Args:
            tweets: List of tweet data dictionaries

        Returns:
            int: Number of tweets successfully written
        """
        if not tweets:
            return 0

        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return 0

        successful_writes = 0

        try:
            async with self.connection_pool.acquire() as conn:
                async with conn.transaction():
                    for tweet_data in tweets:
                        try:
                            # Generate trace ID for tracing
                            trace_id = str(uuid.uuid4())

                            import json

                            await conn.execute(
                                """
                                INSERT INTO external_twitter_liked_raw (
                                    device_id, timestamp, schema_version, tweet_id, author_username,
                                    author_display_name, tweet_text, tweet_html, media_urls, hashtags, mentions,
                                    urls, reply_to_id, quote_tweet_id, retweet_count, like_count, reply_count,
                                    created_at_twitter, liked_at, metadata, trace_id
                                ) VALUES (
                                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
                                ) ON CONFLICT (device_id, tweet_id, timestamp) DO NOTHING
                                """,
                                tweet_data["device_id"],
                                tweet_data["timestamp"],
                                tweet_data.get("schema_version", "v1"),
                                tweet_data["tweet_id"],
                                tweet_data["author_username"],
                                tweet_data.get("author_display_name"),
                                tweet_data["tweet_text"],
                                tweet_data.get("tweet_html"),
                                tweet_data.get("media_urls", []),
                                tweet_data.get("hashtags", []),
                                tweet_data.get("mentions", []),
                                tweet_data.get("urls", []),
                                tweet_data.get("reply_to_id"),
                                tweet_data.get("quote_tweet_id"),
                                tweet_data.get("retweet_count", 0),
                                tweet_data.get("like_count", 0),
                                tweet_data.get("reply_count", 0),
                                tweet_data["created_at_twitter"],
                                tweet_data["liked_at"],
                                json.dumps(tweet_data.get("metadata", {})),
                                trace_id,
                            )
                            successful_writes += 1

                        except Exception as e:
                            logging.warning(
                                f"Failed to write tweet {tweet_data.get('tweet_id', 'unknown')}: {e}"
                            )

            logging.info(
                f"Successfully wrote {successful_writes}/{len(tweets)} tweets to database"
            )
            return successful_writes

        except Exception as e:
            logging.error(f"Failed to write tweet batch to database: {e}")
            return 0

    async def get_existing_tweet_ids(self) -> set:
        """
        Get all existing tweet IDs from the database.

        Returns:
            set: Set of existing tweet IDs
        """
        if not self.connection_pool:
            return set()

        try:
            async with self.connection_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT DISTINCT tweet_id FROM external_twitter_liked_raw"
                )
                return {row["tweet_id"] for row in rows}

        except Exception as e:
            logging.error(f"Failed to get existing tweet IDs: {e}")
            return set()

    async def check_tweet_exists(self, device_id: str, tweet_id: str) -> bool:
        """
        Check if a tweet already exists in the database.

        Args:
            device_id: Device ID
            tweet_id: Tweet ID

        Returns:
            bool: True if tweet exists, False otherwise
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT 1 FROM external_twitter_liked_raw WHERE device_id = $1 AND tweet_id = $2 LIMIT 1",
                    device_id,
                    tweet_id,
                )
                return result is not None

        except Exception as e:
            logging.error(f"Failed to check if tweet exists: {e}")
            return False

    async def get_processing_stats(self) -> Dict[str, int]:
        """
        Get processing statistics for tweets.

        Returns:
            Dict[str, int]: Statistics about processed tweets
        """
        if not self.connection_pool:
            return {"total_processed": 0, "with_screenshots": 0, "errors": 0}

        try:
            async with self.connection_pool.acquire() as conn:
                total = await conn.fetchval(
                    "SELECT COUNT(*) FROM external_twitter_liked_raw"
                )
                with_media = await conn.fetchval(
                    "SELECT COUNT(*) FROM external_twitter_liked_raw WHERE array_length(media_urls, 1) > 0"
                )

                return {
                    "total_processed": total or 0,
                    "with_screenshots": with_media or 0,
                    "errors": 0,  # Could be enhanced with error tracking
                }

        except Exception as e:
            logging.error(f"Failed to get processing stats: {e}")
            return {"total_processed": 0, "with_screenshots": 0, "errors": 1}

    async def write_url_task(
        self, url: str, source_type: str, metadata: Dict[str, Any], trace_id: str
    ) -> bool:
        """
        Write URL task to task_url_ingest table for processing.

        Args:
            url: URL to process
            source_type: Source of the URL (e.g., 'x-likes-fetcher')
            metadata: Additional metadata about the URL
            trace_id: Trace ID for tracking

        Returns:
            bool: True if write was successful, False otherwise
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                import json

                await conn.execute(
                    """
                    INSERT INTO task_url_ingest (
                        url, timestamp, source_type, metadata, trace_id
                    ) VALUES (
                        $1, $2, $3, $4, $5
                    ) ON CONFLICT (url, timestamp) DO NOTHING
                    """,
                    url,
                    datetime.utcnow(),
                    source_type,
                    json.dumps(metadata),
                    trace_id,
                )

            logging.debug(f"Successfully wrote URL task for {url}")
            return True

        except asyncpg.UniqueViolationError:
            # URL already exists for this timestamp
            logging.debug(f"URL task for {url} already exists")
            return True

        except Exception as e:
            logging.error(f"Failed to write URL task: {e}")
            return False
