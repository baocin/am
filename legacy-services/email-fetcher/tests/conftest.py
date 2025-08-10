"""Common test fixtures for email-fetcher tests."""

import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone
import os


@pytest.fixture
def mock_email_fetcher():
    """Mock EmailFetcher class."""
    with patch("app.main.EmailFetcher") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock fetch_all_emails to return sample emails with content hashes
        mock_instance.fetch_all_emails.return_value = [
            {
                "email_id": "test-email-1",
                "content_hash": "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890",
                "message_id": "<message-1@example.com>",
                "subject": "Test Email 1",
                "sender": "sender1@example.com",
                "receiver": "recipient@example.com",
                "body": "This is a test email...",
                "seen": False,
                "date_received": datetime.now(timezone.utc),
                "source_account": "test@example.com",
                "account_name": "test-account",
                "account_index": 1,
            },
            {
                "email_id": "test-email-2",
                "content_hash": "b2c3d4e5f67890123456789012345678901234567890123456789012345678901",
                "message_id": "<message-2@example.com>",
                "subject": "Test Email 2 with Attachment",
                "sender": "sender2@example.com",
                "receiver": "recipient@example.com",
                "body": "This email has an attachment...",
                "seen": True,
                "date_received": datetime.now(timezone.utc),
                "source_account": "test@example.com",
                "account_name": "test-account",
                "account_index": 1,
            },
        ]

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
def sample_email_data():
    """Sample email data structure."""
    return {
        "email_id": "sample-email-123",
        "content_hash": "c3d4e5f678901234567890123456789012345678901234567890123456789012",
        "message_id": "<sample-123@company.com>",
        "subject": "Important: Project Update",
        "sender": "boss@company.com",
        "receiver": "team@company.com",
        "body": "Here's the latest update on our project...",
        "seen": False,
        "date_received": datetime(2025, 6, 26, 12, 0, 0, tzinfo=timezone.utc),
        "source_account": "work@company.com",
        "account_name": "work-email",
        "account_index": 1,
    }


@pytest.fixture
def sample_kafka_message():
    """Sample Kafka message structure for email."""
    return {
        "schema_version": "v1",
        "device_id": "email-fetcher-account-1",
        "timestamp": "2025-06-26T12:00:00+00:00",
        "content_hash": "c3d4e5f678901234567890123456789012345678901234567890123456789012",
        "data": {
            "email_id": "sample-email-123",
            "content_hash": "c3d4e5f678901234567890123456789012345678901234567890123456789012",
            "message_id": "<sample-123@company.com>",
            "subject": "Important: Project Update",
            "sender": "boss@company.com",
            "receiver": "team@company.com",
            "body": "Here's the latest update on our project...",
            "seen": False,
            "date_received": "2025-06-26T12:00:00+00:00",
            "source_account": "work@company.com",
            "account_name": "work-email",
            "account_index": 1,
        },
    }


@pytest.fixture(autouse=True)
def setup_environment():
    """Set up test environment variables."""
    test_env = {
        "LOOM_LOG_LEVEL": "INFO",
        "LOOM_KAFKA_OUTPUT_TOPIC": "external.email.events.raw",
        "LOOM_EMAIL_FETCH_INTERVAL_MINUTES": "5",
        "LOOM_EMAIL_RUN_ON_STARTUP": "true",
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
