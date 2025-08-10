import asyncio
import base64
import logging
import os
from database_poller import DatabasePoller
from x_tweet_processor import XTweetProcessor

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level.upper()),
    format="%(asctime)s - x-url-processor - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("/app/logs/x-url-processor.log"),
        logging.StreamHandler(),
    ],
)


class XUrlProcessorService:
    def __init__(self):
        self.db_poller = DatabasePoller()
        
        self.tweet_processor = XTweetProcessor()

    async def process_task(self, task):
        """Process a single URL task from database"""
        task_id = task.get("id")

        try:
            # Mark task as processing
            await self.db_poller.mark_processing(task_id)

            # Extract data from task
            url = task.get("url")
            metadata = task.get("metadata", {})
            trace_id = task.get("trace_id")
            tweet_id = metadata.get("tweet_id")

            # Only process X.com/Twitter URLs
            if not url:
                return

            if not (
                url.startswith("https://x.com/")
                or url.startswith("https://twitter.com/")
                or url.startswith("http://x.com/")
                or url.startswith("http://twitter.com/")
            ):
                logging.debug(f"Skipping non-X.com URL: {url}")
                return

            logging.info(
                f"Processing X.com URL: {url} (trace_id: {trace_id}, tweet_id: {tweet_id})"
            )

            # Setup browser and process tweet
            await self.tweet_processor.setup()
            tweet_data = await self.tweet_processor.scrape_tweet(
                url, trace_id, tweet_id
            )
            await self.tweet_processor.cleanup()

            if tweet_data:
                # Get output topic from environment variable
                output_topic = os.getenv(
                    "LOOM_KAFKA_OUTPUT_TOPIC", "task.url.processed.twitter_archived"
                )

                # Send processed tweet data to Kafka
                # Flatten the structure for the DB consumer
                output_message = {
                    "trace_id": tweet_data.get("trace_id"),
                    "tweet_id": tweet_data.get("tweet_id"),
                    "url": tweet_data.get("url"),
                    "extraction_timestamp": tweet_data.get("extraction_timestamp"),
                    "screenshot_path": tweet_data.get("screenshot_path"),
                    "extracted_text": tweet_data.get("extracted_text"),
                    "extracted_links": tweet_data.get("extracted_links", []),
                    "extracted_media": tweet_data.get("extracted_media", []),
                    "extracted_metadata": {
                        "author_name": tweet_data.get("author_name"),
                        "created_at": tweet_data.get("created_at"),
                        "full_data": tweet_data.get("tweet", {}),
                    },
                    "processor_version": "1.0.0",
                    "processing_duration_ms": tweet_data.get(
                        "processing_duration_ms", 0
                    ),
                }

                await self.kafka_producer.send_message(
                    topic=output_topic,
                    key=tweet_data.get("tweet_id", url),
                    value=output_message,
                )

                # If we have a screenshot, send it to the Twitter images topic for OCR
                if tweet_data.get("screenshot_path") and os.path.exists(
                    tweet_data["screenshot_path"]
                ):
                    try:
                        with open(tweet_data["screenshot_path"], "rb") as f:
                            image_data = base64.b64encode(f.read()).decode("utf-8")

                        image_message = {
                            "schema_version": "v1",
                            "device_id": None,
                            "recorded_at": tweet_data.get("extraction_timestamp"),
                            "trace_id": trace_id,
                            "data": {
                                "tweet_id": tweet_data.get("tweet_id"),
                                "tweet_url": url,
                                "image_data": image_data,
                                "screenshot_path": tweet_data["screenshot_path"],
                                "metadata": {
                                    "source": "x-url-processor",
                                    "author": tweet_data.get("author_name"),
                                },
                            },
                        }

                        self.kafka_producer.send_message(
                            topic="external.twitter.images.raw",
                            key=tweet_data.get("tweet_id", url),
                            value=image_message,
                        )
                        logging.info(
                            f"Sent screenshot to Twitter images topic for OCR: {url}"
                        )
                    except Exception as e:
                        logging.error(f"Failed to send screenshot for OCR: {e}")

                logging.info(f"Successfully processed and archived X.com URL: {url}")
                # Mark task as completed
                await self.db_poller.mark_completed(task_id)
            else:
                logging.warning(f"Failed to process X.com URL: {url}")
                # Mark task as failed
                await self.db_poller.mark_failed(task_id, "Failed to process tweet")

        except Exception as e:
            logging.error(f"Error processing task: {e}")
            # Mark task as failed
            await self.db_poller.mark_failed(task_id, str(e))

    async def run(self):
        """Main service loop"""
        logging.info("X.com URL processor service starting...")

        # Initialize database connection
        await self.db_poller.initialize()

        try:
            while True:
                # Get pending URLs from database
                tasks = await self.db_poller.get_pending_urls()

                if tasks:
                    logging.info(f"Processing {len(tasks)} URL tasks")
                    # Process tasks concurrently but limit concurrency
                    for task in tasks:
                        await self.process_task(task)
                else:
                    # No tasks found, wait before polling again
                    await asyncio.sleep(self.db_poller.poll_interval)

        except KeyboardInterrupt:
            logging.info("Received shutdown signal")
        except Exception as e:
            logging.error(f"Error in main loop: {e}")
        finally:
            await self.db_poller.close()
            self.kafka_producer.close()


async def main():
    service = XUrlProcessorService()
    await service.run()


if __name__ == "__main__":
    asyncio.run(main())
