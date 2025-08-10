# HackerNews Fetcher Service

This service fetches personal HackerNews favorites and submissions for the Loom v2 pipeline.

## Content Hashing

The service implements content hashing for deduplication as per the Loom v2 universal deduplication strategy. Each HackerNews story is assigned a unique content hash based on:

1. **Story ID** (primary key) - HackerNews assigns unique, immutable IDs to all stories
2. **URL** (normalized) - The story URL, normalized for consistent hashing
3. **Timestamp** - When the story was favorited/submitted (normalized to Unix milliseconds)

### Hash Format

```
hackernews:v1:story:{story_id}:{normalized_url}:{unix_timestamp_ms}
```

The resulting SHA-256 hash is included in the Kafka message as the `content_hash` field, allowing downstream consumers to:
- Detect and skip duplicate stories
- Track story updates (score changes, etc.)
- Maintain consistency across multiple fetches

### Deduplication

The service performs batch-level deduplication to avoid sending duplicate stories within the same fetch cycle. Downstream consumers should use the content_hash for persistent deduplication across multiple runs.

## Environment Variables

- `LOOM_HACKERNEWS_USERNAME` - HackerNews username (required)
- `LOOM_HACKERNEWS_PASSWORD` - HackerNews password (optional, for favorites)
- `LOOM_HACKERNEWS_FETCH_TYPE` - Type of items to fetch: "favorites" or "submissions" (default: "favorites")
- `LOOM_HACKERNEWS_MAX_ITEMS` - Maximum items to fetch per run (default: 50)
- `LOOM_HACKERNEWS_FETCH_INTERVAL_MINUTES` - Fetch interval in minutes (default: 120)
- `LOOM_HACKERNEWS_RUN_ON_STARTUP` - Run fetch on service startup (default: true)
- `LOOM_KAFKA_OUTPUT_TOPIC` - Kafka output topic (default: "task.likes.hackernews")

## Kafka Message Format

```json
{
  "schema_version": "v1",
  "device_id": null,
  "timestamp": "2024-01-15T10:30:00Z",
  "content_hash": "abc123...",  // SHA-256 hash for deduplication
  "data": {
    "url": "https://example.com/article",
    "source": "hackernews",
    "type": "liked_story",  // or "submitted_story"
    "title": "Story Title",
    "score": 42,
    "comments_url": "https://news.ycombinator.com/item?id=123456",
    "story_id": 123456,
    "author": "author_username",
    "comment_count": 10
  }
}
```
