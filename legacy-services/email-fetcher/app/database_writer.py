"""Database writer for email data."""

import logging
from typing import Dict, Any, List
import asyncpg
import os
import uuid
import json
import aiofiles
from pathlib import Path


class DatabaseWriter:
    """Write email data directly to PostgreSQL database."""

    def __init__(self):
        """Initialize database connection."""
        self.database_url = os.getenv(
            "LOOM_DATABASE_URL", "postgresql://loom:loom@postgres:5432/loom"
        )
        self.connection_pool = None
        # Use a persistent volume mount for failed emails
        self.failed_emails_path = Path("/app/data/failed_emails.json")  # nosec B108

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

    async def write_email(self, email_data: Dict[str, Any]) -> bool:
        """
        Write email data to external_email_events_raw table.

        Args:
            email_data: Email data dictionary containing all required fields

        Returns:
            bool: True if write was successful, False otherwise
        """
        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                # Insert email data into external_email_events_raw table
                import json

                # Generate trace ID for tracing
                trace_id = str(uuid.uuid4())

                await conn.execute(
                    """
                    INSERT INTO external_email_events_raw (
                        device_id, timestamp, schema_version, message_id, thread_id,
                        from_address, to_addresses, cc_addresses, subject, body_text, body_html,
                        attachments, labels, is_read, is_starred, importance, received_date, metadata, trace_id
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
                    ) ON CONFLICT (device_id, message_id, timestamp) DO NOTHING
                    """,
                    email_data["device_id"],
                    email_data["timestamp"],
                    email_data.get("schema_version", "v1"),
                    email_data["message_id"],
                    email_data.get("thread_id"),
                    email_data["from_address"],
                    email_data.get("to_addresses", []),
                    email_data.get("cc_addresses", []),
                    email_data["subject"],
                    email_data.get("body_text"),
                    email_data.get("body_html"),
                    email_data.get("attachments"),
                    email_data.get("labels", []),
                    email_data.get("is_read", False),
                    email_data.get("is_starred", False),
                    email_data.get("importance"),
                    email_data["received_date"],
                    json.dumps(email_data.get("metadata", {})),
                    trace_id,
                )

            logging.debug(
                f"Successfully wrote email {email_data['message_id']} to database"
            )
            return True

        except asyncpg.UniqueViolationError:
            # Email already exists, this is expected for deduplication
            logging.debug(
                f"Email {email_data['message_id']} already exists in database"
            )
            return True

        except Exception as e:
            logging.error(f"Failed to write email to database: {e}")
            return False

    async def write_emails_batch(self, emails: List[Dict[str, Any]]) -> int:
        """
        Write multiple emails in a batch transaction.

        Args:
            emails: List of email data dictionaries

        Returns:
            int: Number of emails successfully written
        """
        if not emails:
            return 0

        if not self.connection_pool:
            logging.error("Database connection pool not initialized")
            return 0

        successful_writes = 0

        try:
            async with self.connection_pool.acquire() as conn:
                async with conn.transaction():
                    for email_data in emails:
                        try:
                            import json

                            # Generate trace ID for tracing
                            trace_id = str(uuid.uuid4())

                            await conn.execute(
                                """
                                INSERT INTO external_email_events_raw (
                                    device_id, timestamp, schema_version, message_id, thread_id,
                                    from_address, to_addresses, cc_addresses, subject, body_text, body_html,
                                    attachments, labels, is_read, is_starred, importance, received_date, metadata, trace_id
                                ) VALUES (
                                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
                                ) ON CONFLICT (device_id, message_id, timestamp) DO NOTHING
                                """,
                                email_data["device_id"],
                                email_data["timestamp"],
                                email_data.get("schema_version", "v1"),
                                email_data["message_id"],
                                email_data.get("thread_id"),
                                email_data["from_address"],
                                email_data.get("to_addresses", []),
                                email_data.get("cc_addresses", []),
                                email_data["subject"],
                                email_data.get("body_text"),
                                email_data.get("body_html"),
                                email_data.get("attachments"),
                                email_data.get("labels", []),
                                email_data.get("is_read", False),
                                email_data.get("is_starred", False),
                                email_data.get("importance"),
                                email_data["received_date"],
                                json.dumps(email_data.get("metadata", {})),
                                trace_id,
                            )
                            successful_writes += 1

                        except Exception as e:
                            logging.warning(
                                f"Failed to write email {email_data.get('message_id', 'unknown')}: {e}"
                            )

            logging.info(
                f"Successfully wrote {successful_writes}/{len(emails)} emails to database"
            )
            return successful_writes

        except Exception as e:
            logging.error(f"Failed to write email batch to database: {e}")
            return 0

    async def check_email_exists(self, device_id: str, message_id: str) -> bool:
        """
        Check if an email already exists in the database.

        Args:
            device_id: Device ID
            message_id: Email message ID

        Returns:
            bool: True if email exists, False otherwise
        """
        if not self.connection_pool:
            return False

        try:
            async with self.connection_pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT 1 FROM external_email_events_raw WHERE device_id = $1 AND message_id = $2 LIMIT 1",
                    device_id,
                    message_id,
                )
                return result is not None

        except Exception as e:
            logging.error(f"Failed to check if email exists: {e}")
            return False

    async def save_failed_emails(self, failed_emails: List[Dict[str, Any]]):
        """
        Save failed emails to a temporary file for retry in next run.

        Args:
            failed_emails: List of email data that failed to write
        """
        try:
            # Ensure directory exists
            self.failed_emails_path.parent.mkdir(parents=True, exist_ok=True)

            # Write failed emails to temporary file
            async with aiofiles.open(self.failed_emails_path, "w") as f:
                await f.write(json.dumps(failed_emails, default=str))
            logging.info(f"Saved {len(failed_emails)} failed emails for retry")
        except Exception as e:
            logging.error(f"Failed to save failed emails: {e}")

    async def load_failed_emails(self) -> List[Dict[str, Any]]:
        """
        Load previously failed emails for retry.

        Returns:
            List of email data that previously failed
        """
        if not self.failed_emails_path.exists():
            return []

        try:
            async with aiofiles.open(self.failed_emails_path, "r") as f:
                content = await f.read()
                failed_emails = json.loads(content)

            # Delete the file after loading
            self.failed_emails_path.unlink()
            logging.info(f"Loaded {len(failed_emails)} failed emails for retry")
            return failed_emails
        except Exception as e:
            logging.error(f"Failed to load failed emails: {e}")
            return []
