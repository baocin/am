# X URL Processor Service

This service consumes URLs from Kafka, processes X.com/Twitter URLs to extract tweet data with screenshots, and sends the processed data to another Kafka topic.

## Configuration

All configuration is done via environment variables:

### Kafka Configuration
- `LOOM_KAFKA_BOOTSTRAP_SERVERS` - Kafka bootstrap servers (default: "localhost:9092")
- `LOOM_KAFKA_TOPIC_PREFIX` - Topic prefix to add (default: "", no prefix)
- `LOOM_KAFKA_INPUT_TOPIC` - Topic to consume URLs from (default: "task.url.ingest")
- `LOOM_KAFKA_OUTPUT_TOPIC` - Topic for processed tweet data (default: "task.url.processed.twitter_archived")
- `LOOM_KAFKA_CONSUMER_GROUP` - Kafka consumer group ID (default: "x-url-processor")

### Service Configuration
- `LOOM_LOG_LEVEL` - Log level (default: "INFO")

## Data Flow

1. Consumes messages from `task.url.ingest` topic
2. Filters to only process X.com/Twitter URLs
3. Uses browser automation to scrape tweet data and capture screenshots
4. Sends processed data to `task.url.processed.twitter_archived` topic

## Input Schema

Expects messages from `task.url.ingest` with this format:
```json
{
  "schema_version": "v1",
  "device_id": null,
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "url": "https://x.com/user/status/123456789",
    "source": "x.com",
    "type": "liked_tweet",
    "metadata": {
      "author": "@user",
      "preview_text": "Tweet preview..."
    }
  }
}
```

## Output Schema

Sends processed tweet data to `task.url.processed.twitter_archived`:
```json
{
  "schema_version": "v1",
  "device_id": null,
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "url": "https://x.com/user/status/123456789",
    "source": "x.com",
    "tweet_data": {
      "created_at": "2024-01-15T10:30:00Z",
      "text": "Full tweet text...",
      "author": "@user",
      "likes": 100,
      "retweets": 50,
      "replies": 10,
      "image_data": "base64_encoded_screenshot..."
    },
    "screenshot_available": true
  }
}
```

## URL Filtering

The service only processes URLs that start with:
- `https://x.com/`
- `https://twitter.com/`
- `http://x.com/`
- `http://twitter.com/`

All other URLs are skipped with a debug log message.
