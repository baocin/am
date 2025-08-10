# X-Likes-Fetcher Deduplication Update

## Overview
Enhanced the x-likes-fetcher service to use standardized content hashing alongside the existing database-based deduplication.

## Changes Made

### 1. Added Shared Deduplication Module
- Copied `/services/shared/deduplication.py` to `/services/x-likes-fetcher/app/shared/`
- Extended `ContentHasher` class with a new `generate_twitter_hash()` method that uses tweet ID as the primary identifier
- Created `__init__.py` for the shared module

### 2. Updated Main Application
- Imported `content_hasher` from the shared deduplication module
- Added content hash generation for each tweet using the tweet ID
- Added `content_hash` field to both Kafka message types:
  - `external.twitter.liked.raw` topic messages
  - `task.url.ingest` topic messages (when enabled)

### 3. Backward Compatibility
- Kept existing database-based deduplication (`DatabaseChecker`) intact
- Content hash generation includes error handling with graceful fallback
- If hash generation fails, the service continues with a `None` value

## Content Hash Format
The Twitter content hash follows the pattern:
```
twitter:v1:id:{normalized_tweet_id}
```

Example: For tweet ID "1234567890123456789", the hash would be:
```
SHA256("twitter:v1:id:1234567890123456789")
```

## Benefits
1. **Dual-layer deduplication**: Database check prevents reprocessing, content hash enables downstream deduplication
2. **Consistent hashing**: Uses the same standardized approach as other Loom services
3. **Immutable identifier**: Tweet IDs are unique and permanent, making them ideal for content hashing
4. **Future-proof**: Downstream consumers can use content_hash for deduplication without database access
