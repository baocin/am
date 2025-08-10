# X Likes Fetcher Service

This service fetches liked tweets from X.com (formerly Twitter) and sends them to Kafka for storage and processing.

## Configuration

All configuration is done via environment variables:

### Kafka Configuration
- `LOOM_KAFKA_BOOTSTRAP_SERVERS` - Kafka bootstrap servers (default: "localhost:9092")
- `LOOM_KAFKA_TOPIC_PREFIX` - Topic prefix to add (default: "", no prefix)
- `LOOM_KAFKA_OUTPUT_TOPIC` - Topic for raw liked tweet data (default: "external.twitter.liked.raw")
- `LOOM_KAFKA_URL_TOPIC` - Topic for URL processing (default: "task.url.ingest")
- `LOOM_SEND_TO_URL_PROCESSOR` - Whether to send URLs for deeper processing (default: "true")

### Service Configuration
- `LOOM_LOG_LEVEL` - Log level (default: "INFO")
- `LOOM_FETCH_INTERVAL_HOURS` - Hours between fetches (default: "6")
- `LOOM_RUN_ON_STARTUP` - Whether to run immediately on startup (default: "true")

## Data Flow

1. Scrapes liked tweets from X.com using browser automation
2. Sends complete tweet data to `external.twitter.liked.raw` topic
3. Optionally sends tweet URLs to `task.url.ingest` for deeper processing

## Output Schema

### Raw Tweet Data (external.twitter.liked.raw)
```json
{
  "schema_version": "v1",
  "device_id": null,
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "url": "https://x.com/user/status/123456789",
    "source": "x.com",
    "type": "liked_tweet",
    "profile_link": "https://x.com/user",
    "text": "Tweet content...",
    "author": "@user",
    "metrics": {
      "likes": 100,
      "retweets": 50,
      "replies": 10
    }
  }
}
```

### URL for Processing (task.url.ingest)
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
      "preview_text": "First 200 characters of tweet..."
    }
  }
}
```
