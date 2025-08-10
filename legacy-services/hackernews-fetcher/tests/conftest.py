"""Common test fixtures for hackernews-fetcher tests."""

import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone
import os


@pytest.fixture
def mock_hackernews_fetcher():
    """Mock HackerNewsFetcher class."""
    with patch("app.main.HackerNewsFetcher") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock fetch methods to return sample HN activity
        mock_instance.fetch_user_activity.return_value = {
            "submitted": [
                {
                    "id": "40849399",
                    "type": "story",
                    "title": "Show HN: I built a personal data pipeline",
                    "url": "https://example.com/my-project",
                    "text": None,
                    "score": 150,
                    "by": "testuser",
                    "time": int(datetime.now(timezone.utc).timestamp()),
                    "descendants": 45,
                },
                {
                    "id": "40849400",
                    "type": "comment",
                    "text": "This is a great point about distributed systems...",
                    "parent": "40849300",
                    "by": "testuser",
                    "time": int(datetime.now(timezone.utc).timestamp()) - 3600,
                },
            ],
            "upvoted": [
                {
                    "id": "40849500",
                    "type": "story",
                    "title": "Understanding Rust's Ownership Model",
                    "url": "https://rustlang.org/ownership",
                    "score": 250,
                    "by": "rustfan",
                    "time": int(datetime.now(timezone.utc).timestamp()) - 7200,
                    "descendants": 100,
                }
            ],
            "favorites": [
                {
                    "id": "40849600",
                    "type": "story",
                    "title": "The Architecture of Open Source Applications",
                    "url": "http://aosabook.org",
                    "score": 500,
                    "by": "architect",
                    "time": int(datetime.now(timezone.utc).timestamp()) - 86400,
                    "descendants": 200,
                }
            ],
        }

        yield mock_instance


@pytest.fixture
def mock_kafka_producer():
    """Mock KafkaProducer class."""
    with patch("app.main.KafkaProducer") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock methods
        mock_instance.send_message = MagicMock()
        mock_instance.close = MagicMock()

        yield mock_instance


@pytest.fixture
def mock_schedule():
    """Mock schedule module."""
    with patch("app.main.schedule") as mock:
        mock.every = MagicMock()
        mock.run_pending = MagicMock()
        yield mock


@pytest.fixture
def sample_hn_story():
    """Sample HackerNews story data."""
    return {
        "id": "40850000",
        "type": "story",
        "title": "Why I Switched from AWS to Self-Hosting",
        "url": "https://blog.example.com/aws-to-selfhost",
        "text": None,
        "score": 342,
        "by": "devops_guru",
        "time": int(datetime(2025, 6, 26, 10, 0, 0, tzinfo=timezone.utc).timestamp()),
        "descendants": 156,
        "kids": ["40850001", "40850002", "40850003"],
    }


@pytest.fixture
def sample_hn_comment():
    """Sample HackerNews comment data."""
    return {
        "id": "40850100",
        "type": "comment",
        "text": "I've been self-hosting for years and the key insight is...",
        "parent": "40850000",
        "by": "experienced_dev",
        "time": int(datetime(2025, 6, 26, 11, 0, 0, tzinfo=timezone.utc).timestamp()),
        "kids": ["40850101", "40850102"],
    }


@pytest.fixture
def sample_kafka_message():
    """Sample Kafka message structure for HN activity."""
    return {
        "schema_version": "v1",
        "device_id": "hackernews-fetcher",
        "timestamp": "2025-06-26T12:00:00+00:00",
        "trace_id": "hn-40850000-story-1735228800",
        "data": {
            "item_id": "40850000",
            "item_type": "story",
            "activity_type": "submitted",
            "title": "Why I Switched from AWS to Self-Hosting",
            "url": "https://blog.example.com/aws-to-selfhost",
            "text": None,
            "score": 342,
            "author": "devops_guru",
            "created_at": 1735214400,
            "descendants": 156,
            "parent_id": None,
        },
        "metadata": {"fetched_at": "2025-06-26T12:00:00+00:00", "user": "testuser"},
    }


@pytest.fixture(autouse=True)
def setup_environment():
    """Set up test environment variables."""
    test_env = {
        "LOOM_LOG_LEVEL": "INFO",
        "LOOM_KAFKA_OUTPUT_TOPIC": "external.hackernews.activity.raw",
        "LOOM_HN_FETCH_INTERVAL_MINUTES": "60",
        "LOOM_HN_RUN_ON_STARTUP": "true",
        "LOOM_HN_USERNAME": "testuser",
    }

    # Save original environment
    original_env = {}
    for key, value in test_env.items():
        original_env[key] = os.environ.get(key)
        os.environ[key] = value

    yield

    # Restore original environment
    for key, original_value in original_env.items():
        if original_value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = original_value
