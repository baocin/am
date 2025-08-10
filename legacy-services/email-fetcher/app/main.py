import os
import logging
import schedule
import time
import asyncio
from datetime import datetime
from app.email_fetcher import EmailFetcher
from app.database_writer import DatabaseWriter

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level),
    format="%(asctime)s - email-fetcher - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],  # Remove file handler for container deployments
)


async def fetch_emails():
    """Fetch emails and write to database"""
    db_writer = None
    try:
        logging.info("Starting email fetch process")

        # Initialize services
        email_fetcher = EmailFetcher()
        db_writer = DatabaseWriter()
        await db_writer.initialize()

        # Load any previously failed emails for retry
        failed_from_previous = await db_writer.load_failed_emails()

        # Fetch new emails from all configured accounts
        new_emails = email_fetcher.fetch_all_emails()

        # Combine failed emails from previous run with new emails
        # Process failed emails first to give them priority
        emails = failed_from_previous + new_emails

        if failed_from_previous:
            logging.info(
                f"Retrying {len(failed_from_previous)} emails from previous run"
            )

        # Convert emails to database format and write immediately
        written_count = 0
        failed_count = 0
        total_emails = len(emails)
        failed_emails = []

        for i, email_data in enumerate(emails):
            try:
                # Generate device_id based on account
                account_index = email_data.get("account_index", 1)
                device_id = f"email-fetcher-account-{account_index}"

                # Convert to database schema format
                db_email = {
                    "device_id": device_id,
                    "timestamp": email_data["date_received"],
                    "schema_version": "v1",
                    "message_id": email_data.get("message_id", email_data["email_id"]),
                    "thread_id": email_data.get("thread_id"),
                    "from_address": email_data["sender"],
                    "to_addresses": [email_data["receiver"]],
                    "cc_addresses": email_data.get("cc", []),
                    "subject": email_data["subject"],
                    "body_text": email_data["body"],
                    "body_html": email_data.get("body_html"),
                    "attachments": email_data.get("attachments"),
                    "labels": email_data.get("labels", []),
                    "is_read": email_data.get("seen", False),
                    "is_starred": email_data.get("is_starred", False),
                    "importance": email_data.get("importance"),
                    "received_date": email_data["date_received"],
                    "metadata": {
                        "content_hash": email_data.get("content_hash"),
                        "account_email": email_data.get("source_account"),
                        "account_name": email_data.get("account_name"),
                        "account_index": account_index,
                        "fetched_at": datetime.utcnow().isoformat(),
                    },
                }

                # Write email immediately with individual transaction
                success = await db_writer.write_email(db_email)
                if success:
                    written_count += 1
                    if (i + 1) % 100 == 0:  # Log progress every 100 emails
                        logging.info(
                            f"Progress: {i + 1}/{total_emails} emails processed, "
                            f"{written_count} written, {failed_count} failed"
                        )
                else:
                    failed_count += 1
                    failed_emails.append(email_data)
                    logging.warning(
                        f"Failed to write email {db_email['message_id']} from {db_email['from_address']}"
                    )

            except Exception as e:
                failed_count += 1
                logging.error(f"Error processing email {i + 1}: {e}")
                continue

        logging.info(
            f"Email fetch completed: {written_count}/{total_emails} written, "
            f"{failed_count} failed"
        )

        # Save failed emails for retry in next run
        if failed_emails:
            await db_writer.save_failed_emails(failed_emails)

    except Exception as e:
        logging.error(f"Error in email fetch process: {e}")
    finally:
        if db_writer:
            await db_writer.close()


def run_async_fetch():
    """Wrapper to run async function in scheduler"""
    asyncio.run(fetch_emails())


def main():
    """Main application entry point"""
    logging.info("Email fetcher service starting...")

    # Get fetch interval from environment (default 5 minutes)
    fetch_interval = int(os.getenv("LOOM_EMAIL_FETCH_INTERVAL_MINUTES", "5"))
    run_on_startup = os.getenv("LOOM_EMAIL_RUN_ON_STARTUP", "true").lower() == "true"

    # Schedule email fetching
    schedule.every(fetch_interval).minutes.do(run_async_fetch)
    logging.info(f"Scheduled email fetching every {fetch_interval} minutes")

    # Run immediately on startup if configured
    if run_on_startup:
        run_async_fetch()

    # Keep the service running
    while True:
        schedule.run_pending()
        time.sleep(30)


if __name__ == "__main__":
    main()
