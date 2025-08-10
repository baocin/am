"""Common test fixtures for calendar-fetcher tests."""

import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone, timedelta
import os


@pytest.fixture
def mock_calendar_fetcher():
    """Mock CalendarFetcher class."""
    with patch("app.main.CalendarFetcher") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Mock fetch_all_events to return sample events
        start_time = datetime.now(timezone.utc)
        end_time = start_time + timedelta(hours=1)

        mock_instance.fetch_all_events.return_value = [
            {
                "event_id": "test-event-1",
                "title": "Team Meeting",
                "description": "Weekly team sync",
                "start_time": start_time,
                "end_time": end_time,
                "location": "Conference Room A",
                "attendees": ["user1@example.com", "user2@example.com"],
                "calendar_name": "Work Calendar",
                "is_recurring": False,
            },
            {
                "event_id": "test-event-2",
                "title": "Recurring Standup",
                "description": "Daily standup meeting",
                "start_time": start_time + timedelta(days=1),
                "end_time": end_time + timedelta(days=1),
                "location": "Virtual",
                "attendees": ["team@example.com"],
                "calendar_name": "Work Calendar",
                "is_recurring": True,
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
def sample_calendar_event():
    """Sample calendar event data structure."""
    start = datetime(2025, 6, 26, 14, 0, 0, tzinfo=timezone.utc)
    end = datetime(2025, 6, 26, 15, 0, 0, tzinfo=timezone.utc)

    return {
        "event_id": "sample-event-123",
        "title": "Project Review",
        "description": "Quarterly project review with stakeholders",
        "start_time": start,
        "end_time": end,
        "location": "Board Room",
        "attendees": ["ceo@company.com", "cto@company.com", "team@company.com"],
        "calendar_name": "Corporate Calendar",
        "is_recurring": False,
        "organizer": "pm@company.com",
        "status": "confirmed",
    }


@pytest.fixture
def sample_kafka_message():
    """Sample Kafka message structure for calendar event."""
    return {
        "schema_version": "v1",
        "device_id": None,
        "timestamp": "2025-06-26T14:00:00+00:00",
        "data": {
            "event_id": "sample-event-123",
            "title": "Project Review",
            "description": "Quarterly project review with stakeholders",
            "start_time": "2025-06-26T14:00:00+00:00",
            "end_time": "2025-06-26T15:00:00+00:00",
            "location": "Board Room",
            "attendees": ["ceo@company.com", "cto@company.com", "team@company.com"],
            "calendar_name": "Corporate Calendar",
            "is_recurring": False,
        },
    }


@pytest.fixture(autouse=True)
def setup_environment():
    """Set up test environment variables."""
    test_env = {
        "LOOM_LOG_LEVEL": "INFO",
        "LOOM_KAFKA_OUTPUT_TOPIC": "external.calendar.events.raw",
        "LOOM_CALENDAR_FETCH_INTERVAL_MINUTES": "15",
        "LOOM_CALENDAR_RUN_ON_STARTUP": "true",
        "LOOM_CALENDAR_DAYS_AHEAD": "7",
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
