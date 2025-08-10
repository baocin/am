"""Common test fixtures for x-likes-fetcher tests."""

import pytest
from unittest.mock import MagicMock, patch, AsyncMock
from datetime import datetime, timezone
import os


@pytest.fixture
def mock_x_likes_fetcher():
    """Mock XLikesFetcher class."""
    with patch("app.main.XLikesFetcher") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock fetch_likes to return sample liked tweets
        mock_instance.fetch_likes.return_value = [
            {
                "tweet_id": "1234567890123456789",
                "tweet_url": "https://twitter.com/user/status/1234567890123456789",
                "tweet_text": "This is an amazing tweet about Python programming!",
                "author_username": "pythonista",
                "author_display_name": "Python Developer",
                "created_at": datetime(2025, 6, 25, 10, 0, 0, tzinfo=timezone.utc),
                "like_count": 100,
                "retweet_count": 50,
                "reply_count": 25,
                "is_retweet": False,
                "has_media": True,
                "media_urls": ["https://pbs.twimg.com/media/example.jpg"],
            },
            {
                "tweet_id": "9876543210987654321",
                "tweet_url": "https://twitter.com/another/status/9876543210987654321",
                "tweet_text": "RT @original: Great thread about microservices architecture",
                "author_username": "techblogger",
                "author_display_name": "Tech Blogger",
                "created_at": datetime(2025, 6, 24, 15, 30, 0, tzinfo=timezone.utc),
                "like_count": 250,
                "retweet_count": 100,
                "reply_count": 40,
                "is_retweet": True,
                "has_media": False,
                "media_urls": [],
            },
        ]

        yield mock_instance


@pytest.fixture
def mock_db_checker():
    """Mock DBChecker class."""
    with patch("app.main.DBChecker") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock check_duplicate to return False (not duplicate)
        mock_instance.check_duplicate = AsyncMock(return_value=False)
        mock_instance.close = AsyncMock()

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
def sample_tweet_data():
    """Sample tweet data structure."""
    return {
        "tweet_id": "1234567890123456789",
        "tweet_url": "https://twitter.com/elonmusk/status/1234567890123456789",
        "tweet_text": "Just shipped a major update to our service. The team did an incredible job!",
        "author_username": "elonmusk",
        "author_display_name": "Elon Musk",
        "created_at": datetime(2025, 6, 26, 8, 0, 0, tzinfo=timezone.utc),
        "like_count": 50000,
        "retweet_count": 10000,
        "reply_count": 5000,
        "view_count": 1000000,
        "is_retweet": False,
        "has_media": True,
        "is_reply": False,
        "is_quote": False,
        "media_urls": [
            "https://pbs.twimg.com/media/rocket.jpg",
            "https://pbs.twimg.com/media/launch.jpg",
        ],
        "quoted_tweet_id": None,
        "in_reply_to_id": None,
    }


@pytest.fixture
def sample_kafka_message():
    """Sample Kafka message structure for liked tweet."""
    return {
        "schema_version": "v1",
        "device_id": "x-likes-fetcher",
        "timestamp": "2025-06-26T12:00:00+00:00",
        "trace_id": "x-like-1234567890123456789-1735228800",
        "data": {
            "tweet_id": "1234567890123456789",
            "tweet_url": "https://twitter.com/elonmusk/status/1234567890123456789",
            "tweet_text": "Just shipped a major update to our service. The team did an incredible job!",
            "author_username": "elonmusk",
            "author_display_name": "Elon Musk",
            "created_at": "2025-06-26T08:00:00+00:00",
            "like_count": 50000,
            "retweet_count": 10000,
            "reply_count": 5000,
            "is_retweet": False,
            "has_media": True,
            "media_urls": [
                "https://pbs.twimg.com/media/rocket.jpg",
                "https://pbs.twimg.com/media/launch.jpg",
            ],
        },
        "metadata": {
            "fetched_at": "2025-06-26T12:00:00+00:00",
            "user_agent": "x-likes-fetcher/1.0",
        },
    }


@pytest.fixture(autouse=True)
def setup_environment():
    """Set up test environment variables."""
    test_env = {
        "LOOM_LOG_LEVEL": "INFO",
        "LOOM_KAFKA_OUTPUT_TOPIC": "external.twitter.liked.raw",
        "LOOM_X_FETCH_INTERVAL_MINUTES": "30",
        "LOOM_X_RUN_ON_STARTUP": "true",
        "LOOM_DATABASE_URL": "postgresql://test:test@localhost:5432/test",
        "LOOM_X_DUPLICATE_CHECK": "true",
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
