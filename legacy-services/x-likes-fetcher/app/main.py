import os
import logging
import schedule
import time
import asyncio
import uuid
from datetime import datetime
from x_likes_fetcher import XLikesFetcher
from database_writer import DatabaseWriter
from shared.deduplication import content_hasher

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level.upper()),
    format="%(asctime)s - x-likes-fetcher - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("/app/logs/x-likes-fetcher.log"),
        logging.StreamHandler(),
    ],
)


async def fetch_liked_tweets():
    """Fetch liked tweets and write to database"""
    db_writer = None
    x_fetcher = None
    try:
        logging.info("Starting X.com likes fetch process")

        # Initialize services
        x_fetcher = XLikesFetcher()
        db_writer = DatabaseWriter()
        await db_writer.initialize()

        # Setup browser and login
        await x_fetcher.setup()

        # Fetch ALL liked tweets first (no limits)
        logging.info("Fetching all liked tweets from X.com...")
        liked_tweets = await x_fetcher.scrape_likes()
        logging.info(
            f"Scraping completed. Found {len(liked_tweets)} total liked tweets"
        )

        # Get existing tweet IDs from database for duplicate checking
        existing_tweet_ids = await db_writer.get_existing_tweet_ids()
        logging.info(f"Found {len(existing_tweet_ids)} existing tweets in database")

        # Filter out already processed tweets and convert to database format
        new_tweets = 0
        skipped_tweets = 0
        db_tweets = []

        for tweet_data in liked_tweets:
            # Extract tweet ID from URL
            tweet_id = (
                tweet_data["tweetLink"].split("/")[-1]
                if tweet_data.get("tweetLink")
                else None
            )

            # Skip if tweet already exists in database
            if tweet_id and tweet_id in existing_tweet_ids:
                skipped_tweets += 1
                logging.debug(f"Skipping already processed tweet: {tweet_id}")
                continue

            new_tweets += 1
            logging.info(f"Processing new tweet {new_tweets}: {tweet_id}")

            # Generate content hash for this tweet
            try:
                content_hash = content_hasher.generate_twitter_hash(
                    tweet_id=tweet_id, url=tweet_data.get("tweetLink")
                )
                logging.debug(
                    f"Generated content hash for tweet {tweet_id}: {content_hash}"
                )
            except Exception as e:
                logging.warning(
                    f"Failed to generate content hash for tweet {tweet_id}: {e}"
                )
                content_hash = None

            # Convert to database schema format
            db_tweet = {
                "device_id": "x-likes-fetcher-default",
                "timestamp": (
                    datetime.fromisoformat(
                        tweet_data.get("time").replace("Z", "+00:00")
                    )
                    if tweet_data.get("time")
                    else datetime.utcnow()
                ),
                "schema_version": "v1",
                "tweet_id": tweet_id,
                "author_username": tweet_data.get("author", ""),
                "author_display_name": tweet_data.get("author", ""),
                "tweet_text": tweet_data.get("text", ""),
                "tweet_html": None,  # Not available in current scraper
                "media_urls": [],  # Could be extracted from tweet data if available
                "hashtags": [],  # Could be parsed from text
                "mentions": [],  # Could be parsed from text
                "urls": (
                    [tweet_data["tweetLink"]] if tweet_data.get("tweetLink") else []
                ),
                "reply_to_id": None,
                "quote_tweet_id": None,
                "retweet_count": tweet_data.get("retweets", 0),
                "like_count": tweet_data.get("likes", 0),
                "reply_count": tweet_data.get("replies", 0),
                "created_at_twitter": (
                    datetime.fromisoformat(
                        tweet_data.get("time").replace("Z", "+00:00")
                    )
                    if tweet_data.get("time")
                    else datetime.utcnow()
                ),
                "liked_at": datetime.utcnow(),
                "metadata": {
                    "content_hash": content_hash,
                    "profile_link": tweet_data.get("profileLink"),
                    "fetched_at": datetime.utcnow().isoformat(),
                    "trace_id": str(uuid.uuid4()),
                },
            }
            db_tweets.append(db_tweet)

        # Write tweets to database in batch
        if db_tweets:
            written_count = await db_writer.write_tweets_batch(db_tweets)
            logging.info(
                f"Successfully wrote {written_count}/{len(db_tweets)} tweets to database"
            )

            # Write tweet URLs to task_url_ingest table for x-url-processor
            send_to_processor = (
                os.getenv("LOOM_SEND_TO_URL_PROCESSOR_X", "true").lower() == "true"
            )

            if send_to_processor:
                urls_sent = 0
                for tweet in db_tweets:
                    if tweet.get("urls") and len(tweet["urls"]) > 0:
                        tweet_url = tweet["urls"][0]
                        trace_id = tweet.get("metadata", {}).get(
                            "trace_id", str(uuid.uuid4())
                        )

                        # Write URL task to database
                        success = await db_writer.write_url_task(
                            url=tweet_url,
                            source_type="x-likes-fetcher",
                            metadata={
                                "tweet_id": tweet.get("tweet_id"),
                                "device_id": tweet.get("device_id"),
                                "author_username": tweet.get("author_username"),
                                "tweet_text": tweet.get("tweet_text", "")[
                                    :200
                                ],  # First 200 chars
                            },
                            trace_id=trace_id,
                        )

                        if success:
                            urls_sent += 1
                        else:
                            logging.error(
                                f"Failed to write URL task for tweet {tweet.get('tweet_id')}"
                            )

                logging.info(
                    f"Wrote {urls_sent} tweet URLs to task_url_ingest table for screenshot processing"
                )
        else:
            logging.info("No new tweets to write")

        # Get processing statistics
        stats = await db_writer.get_processing_stats()

        # Log comprehensive summary
        logging.info(
            f"Fetch completed - Total found: {len(liked_tweets)}, "
            f"New: {new_tweets}, Skipped (already processed): {skipped_tweets}"
        )
        logging.info(
            f"Database stats - Total processed: {stats['total_processed']}, "
            f"With screenshots: {stats['with_screenshots']}, "
            f"Errors: {stats['errors']}"
        )

    except Exception as e:
        logging.error(f"Error in X.com likes fetch process: {e}")
    finally:
        # Cleanup
        if x_fetcher:
            try:
                await x_fetcher.cleanup()
            except Exception as cleanup_error:
                logging.error(f"Error during X fetcher cleanup: {cleanup_error}")

        if db_writer:
            try:
                await db_writer.close()
            except Exception as cleanup_error:
                logging.error(f"Error during database cleanup: {cleanup_error}")


def run_async_fetch():
    """Wrapper to run async function in scheduler"""
    asyncio.run(fetch_liked_tweets())


def main():
    """Main application entry point"""
    logging.info("X.com likes fetcher service starting...")

    # Get schedule interval from environment variable (fixed at 6 hours)
    schedule_interval_hours = 6

    # Schedule X.com likes fetching
    schedule.every(schedule_interval_hours).hours.do(run_async_fetch)
    logging.info(f"Scheduled to run every {schedule_interval_hours} hours")

    # Run immediately on startup if configured
    if os.getenv("LOOM_RUN_ON_STARTUP", "true").lower() == "true":
        logging.info("Running initial fetch on startup")
        run_async_fetch()

    # Keep the service running
    while True:
        schedule.run_pending()
        time.sleep(60)  # Check every minute


if __name__ == "__main__":
    main()
