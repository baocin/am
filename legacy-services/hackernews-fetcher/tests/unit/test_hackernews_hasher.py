"""Unit tests for HackerNewsHasher."""

from datetime import datetime, timezone

import sys
from pathlib import Path

# Add app directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "app"))

from hackernews_hasher import hackernews_hasher


class TestHackerNewsHasher:
    """Test suite for HackerNewsHasher functionality."""

    def test_generate_hackernews_hash_with_all_fields(self):
        """Test hash generation with all fields provided."""
        story_id = 123456
        url = "https://example.com/article"
        timestamp = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)

        hash1 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, url=url, timestamp=timestamp
        )

        # Should produce consistent hash
        hash2 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, url=url, timestamp=timestamp
        )

        assert hash1 == hash2
        assert len(hash1) == 64  # SHA-256 hex length

    def test_generate_hackernews_hash_story_id_only(self):
        """Test hash generation with only story ID."""
        story_id = 987654

        hash1 = hackernews_hasher.generate_hackernews_hash(story_id=story_id)

        # Should still produce consistent hash
        hash2 = hackernews_hasher.generate_hackernews_hash(story_id=story_id)

        assert hash1 == hash2
        assert len(hash1) == 64

    def test_generate_hackernews_hash_different_stories(self):
        """Test that different story IDs produce different hashes."""
        hash1 = hackernews_hasher.generate_hackernews_hash(story_id=111111)
        hash2 = hackernews_hasher.generate_hackernews_hash(story_id=222222)

        assert hash1 != hash2

    def test_generate_hackernews_hash_url_normalization(self):
        """Test URL normalization in hash generation."""
        story_id = 333333

        # These URLs should normalize to the same value
        url1 = "https://EXAMPLE.com/article/"
        url2 = "https://example.com/article"
        url3 = "https://example.com/article#section"

        hash1 = hackernews_hasher.generate_hackernews_hash(story_id=story_id, url=url1)
        hash2 = hackernews_hasher.generate_hackernews_hash(story_id=story_id, url=url2)
        hash3 = hackernews_hasher.generate_hackernews_hash(story_id=story_id, url=url3)

        # URL normalization should make url1 and url2 produce same hash
        assert hash1 == hash2
        # Fragment removal should make url3 same as url2
        assert hash2 == hash3

    def test_generate_hackernews_hash_timestamp_formats(self):
        """Test various timestamp formats produce consistent hashes."""
        story_id = 444444

        # Different timestamp representations of same moment
        ts_datetime = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)
        ts_iso = "2024-01-15T10:30:00+00:00"
        ts_unix = int(ts_datetime.timestamp())
        ts_unix_ms = int(ts_datetime.timestamp() * 1000)

        hash1 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, timestamp=ts_datetime
        )
        hash2 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, timestamp=ts_iso
        )
        hash3 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, timestamp=ts_unix
        )
        hash4 = hackernews_hasher.generate_hackernews_hash(
            story_id=story_id, timestamp=ts_unix_ms
        )

        # All should produce the same hash after normalization
        assert hash1 == hash2
        assert hash2 == hash3
        assert hash3 == hash4

    def test_generate_hackernews_comment_hash(self):
        """Test comment hash generation."""
        comment_id = 555555
        parent_story_id = 123456
        timestamp = datetime(2024, 1, 15, 12, 0, 0, tzinfo=timezone.utc)

        hash1 = hackernews_hasher.generate_hackernews_comment_hash(
            comment_id=comment_id, parent_story_id=parent_story_id, timestamp=timestamp
        )

        # Should produce consistent hash
        hash2 = hackernews_hasher.generate_hackernews_comment_hash(
            comment_id=comment_id, parent_story_id=parent_story_id, timestamp=timestamp
        )

        assert hash1 == hash2
        assert len(hash1) == 64

    def test_comment_hash_different_from_story_hash(self):
        """Test that comment and story hashes are different even with same IDs."""
        same_id = 123456

        story_hash = hackernews_hasher.generate_hackernews_hash(story_id=same_id)
        comment_hash = hackernews_hasher.generate_hackernews_comment_hash(
            comment_id=same_id, parent_story_id=999999
        )

        assert story_hash != comment_hash

    def test_hackernews_hasher_version(self):
        """Test that hasher has correct version."""
        assert hackernews_hasher.VERSION == "v1"
