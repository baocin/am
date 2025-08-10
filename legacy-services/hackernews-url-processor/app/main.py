import asyncio
import logging
import os
from url_processor import URLProcessor

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level),
    format="%(asctime)s - hackernews-url-processor - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],  # Remove file handler for container deployments
)


class HackerNewsUrlProcessorService:
    def __init__(self):
        
        
        self.url_processor = URLProcessor()

    async def process_message(self, message):
        """Process a single URL message from Kafka"""
        try:
            data = message.get("data", {})
            url = data.get("url")

            # Only process URLs from HackerNews topic (should already be filtered, but double-check)
            if not url:
                return

            logging.info(f"Processing Hacker News URL: {url}")

            # Process the URL
            result = await self.url_processor.process_url(url, data)

            if result:
                # Send processed data to Kafka
                output_message = {
                    "schema_version": "v1",
                    "device_id": None,
                    "timestamp": result.get("timestamp"),
                    "data": {
                        "url": url,
                        "source": "hackernews",
                        "title": data.get("title"),
                        "score": data.get("score"),
                        "story_id": data.get("story_id"),
                        "comments_url": data.get("comments_url"),
                        "processed_content": result,
                        "screenshot_available": result.get("screenshot_data")
                        is not None,
                    },
                }

                # Get output topic from environment
                output_topic = os.getenv(
                    "LOOM_KAFKA_OUTPUT_TOPIC", "task.url.processed.hackernews_archived"
                )

                await self.kafka_producer.send_message(
                    topic=output_topic, key=url, value=output_message
                )

                logging.info(
                    f"Successfully processed and archived Hacker News URL: {url}"
                )
            else:
                logging.warning(f"Failed to process Hacker News URL: {url}")

        except Exception as e:
            logging.error(f"Error processing message: {e}")

    async def run(self):
        """Main service loop"""
        logging.info("Hacker News URL processor service starting...")

        # Get input topic from environment
        input_topic = os.getenv("LOOM_KAFKA_INPUT_TOPIC", "task.likes.hackernews")
        logging.info(f"Consuming from topic: {input_topic}")

        await self.kafka_consumer.start()

        try:
            async for message in self.kafka_consumer.consume_messages(input_topic):
                await self.process_message(message)
        except KeyboardInterrupt:
            logging.info("Received shutdown signal")
        finally:
            await self.kafka_consumer.stop()
            self.kafka_producer.close()
            await self.url_processor.cleanup()


async def main():
    service = HackerNewsUrlProcessorService()
    await service.run()


if __name__ == "__main__":
    asyncio.run(main())
