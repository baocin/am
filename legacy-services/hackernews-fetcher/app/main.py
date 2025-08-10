import os
import logging
import schedule
import time
import asyncio
from datetime import datetime
from hackernews_fetcher import HackerNewsFetcher
from database_writer import DatabaseWriter

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level),
    format="%(asctime)s - hackernews-fetcher - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],  # Remove file handler for container deployments
)


async def fetch_hackernews():
    """Fetch personal Hacker News favorites/upvoted items and write to database"""
    db_writer = None
    try:
        logging.info("Starting Hacker News personal favorites fetch process")

        # Initialize services
        hn_fetcher = HackerNewsFetcher()
        db_writer = DatabaseWriter()
        await db_writer.initialize()

        fetch_type = os.getenv(
            "LOOM_HACKERNEWS_FETCH_TYPE", "favorites"
        )  # favorites or submissions

        # Fetch user's favorites/upvoted items or submissions
        if fetch_type == "submissions":
            items = hn_fetcher.fetch_user_submissions_direct()
        else:
            items = hn_fetcher.fetch_user_favorites()

        # Get existing item IDs from database for duplicate checking
        existing_item_ids = await db_writer.get_existing_item_ids()
        logging.info(
            f"Found {len(existing_item_ids)} existing HackerNews items in database"
        )

        # Process items and convert to database format
        new_items = 0
        skipped_items = 0
        db_items = []

        for story_data in items:
            item_id = story_data["id"]

            # Skip if item already exists in database
            if item_id in existing_item_ids:
                skipped_items += 1
                logging.debug(f"Skipping already processed HackerNews item: {item_id}")
                continue

            new_items += 1
            logging.info(f"Processing new HackerNews item {new_items}: {item_id}")

            # Convert timestamp to datetime
            item_timestamp = (
                datetime.fromtimestamp(story_data.get("time", 0))
                if story_data.get("time")
                else datetime.utcnow()
            )

            # Convert to database schema format
            db_item = {
                "device_id": "hackernews-fetcher-default",
                "timestamp": datetime.utcnow(),
                "schema_version": "v1",
                "message_id": f"hn-{item_id}-{int(datetime.utcnow().timestamp())}",
                "item_id": item_id,
                "item_type": "story",
                "title": story_data.get("title"),
                "url": story_data.get("url"),
                "text": story_data.get("text"),
                "author": story_data.get("by", ""),
                "score": story_data.get("score", 0),
                "comments_count": story_data.get("descendants", 0),
                "created_at": item_timestamp,
                "interacted_at": datetime.utcnow(),
                "interaction_type": fetch_type,  # 'favorites' or 'submissions'
            }
            db_items.append(db_item)

        # Write items to database in batch
        if db_items:
            written_count = await db_writer.write_hackernews_items_batch(db_items)
            logging.info(
                f"Successfully wrote {written_count}/{len(db_items)} HackerNews items to database"
            )
        else:
            logging.info("No new HackerNews items to write")

        logging.info(
            f"Fetch completed - Total found: {len(items)}, "
            f"New: {new_items}, Skipped (already processed): {skipped_items}"
        )

    except Exception as e:
        logging.error(f"Error in Hacker News fetch process: {e}")
    finally:
        if db_writer:
            await db_writer.close()


def run_async_fetch():
    """Wrapper to run async function in scheduler"""
    asyncio.run(fetch_hackernews())


def main():
    """Main application entry point"""
    logging.info("Hacker News fetcher service starting...")

    # Get fetch interval from environment (default 2 hours = 120 minutes)
    fetch_interval = int(os.getenv("LOOM_HACKERNEWS_FETCH_INTERVAL_MINUTES", "120"))
    run_on_startup = (
        os.getenv("LOOM_HACKERNEWS_RUN_ON_STARTUP", "true").lower() == "true"
    )

    # Schedule Hacker News fetching
    if fetch_interval < 60:
        schedule.every(fetch_interval).minutes.do(run_async_fetch)
        logging.info(f"Scheduled Hacker News fetching every {fetch_interval} minutes")
    else:
        hours = fetch_interval // 60
        schedule.every(hours).hours.do(run_async_fetch)
        logging.info(f"Scheduled Hacker News fetching every {hours} hours")

    # Run immediately on startup if configured
    if run_on_startup:
        run_async_fetch()

    # Keep the service running
    while True:
        schedule.run_pending()
        time.sleep(60)  # Check every minute


if __name__ == "__main__":
    main()
