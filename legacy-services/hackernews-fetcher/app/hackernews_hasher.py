"""
HackerNews-specific content hashing implementation
"""

from shared.deduplication import ContentHasher
from typing import Any, Optional


class HackerNewsHasher(ContentHasher):
    """Extended content hasher for HackerNews items"""

    def generate_hackernews_hash(
        self, story_id: int, url: Optional[str] = None, timestamp: Optional[Any] = None
    ) -> str:
        """
        Generate hash for HackerNews story.

        Uses story_id as the primary unique identifier since:
        1. Each HN story has a unique, immutable ID
        2. This handles updates to the same story (score changes, etc.)
        3. Works for both favorites and submissions

        Args:
            story_id: Unique HackerNews story ID
            url: Story URL (optional, for additional context)
            timestamp: When the story was favorited/submitted (optional)

        Returns:
            SHA-256 hash string
        """
        # HN story IDs are unique and immutable
        story_id_str = str(story_id)

        # Include URL for additional context (normalized)
        url_norm = self.normalize_url(url) if url else ""

        # Include timestamp for when it was favorited/submitted
        timestamp_unix = self.normalize_timestamp(timestamp) if timestamp else ""

        # Create deterministic content string
        content = f"hackernews:{self.VERSION}:story:{story_id_str}:{url_norm}:{timestamp_unix}"

        return self._sha256(content)

    def generate_hackernews_comment_hash(
        self, comment_id: int, parent_story_id: int, timestamp: Optional[Any] = None
    ) -> str:
        """
        Generate hash for HackerNews comment (for future use).

        Args:
            comment_id: Unique comment ID
            parent_story_id: ID of the story this comment belongs to
            timestamp: Comment creation time

        Returns:
            SHA-256 hash string
        """
        comment_id_str = str(comment_id)
        story_id_str = str(parent_story_id)
        timestamp_unix = self.normalize_timestamp(timestamp) if timestamp else ""

        content = f"hackernews:{self.VERSION}:comment:{comment_id_str}:{story_id_str}:{timestamp_unix}"

        return self._sha256(content)


# Singleton instance
hackernews_hasher = HackerNewsHasher()
