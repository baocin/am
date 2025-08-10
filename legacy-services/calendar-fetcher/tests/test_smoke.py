"""Smoke tests for calendar-fetcher service."""

import pytest
from unittest.mock import patch
import os
from datetime import datetime, timezone, timedelta

# Assuming main.py has fetch_events and main functions similar to email-fetcher
# If not, these tests will need adjustment based on actual implementation


class TestCalendarFetcherSmoke:
    """Smoke tests to ensure the calendar fetcher service works."""

    @patch("app.main.fetch_events")
    def test_main_startup_with_immediate_run(self, mock_fetch_events, mock_schedule):
        """Test main function with immediate run on startup."""
        from app.main import main

        # Mock time.sleep to prevent infinite loop
        with patch("time.sleep") as mock_sleep:
            # Make run_pending raise KeyboardInterrupt after first iteration
            mock_schedule.run_pending.side_effect = KeyboardInterrupt()

            # Run main
            with pytest.raises(KeyboardInterrupt):
                main()

            # Verify schedule was set up
            mock_schedule.every.assert_called_with(15)  # Default interval
            mock_schedule.every().minutes.do.assert_called_once()

            # Verify fetch_events was called immediately (run_on_startup=true)
            mock_fetch_events.assert_called_once()

    @patch("app.main.fetch_events")
    def test_main_startup_without_immediate_run(self, mock_fetch_events, mock_schedule):
        """Test main function without immediate run on startup."""
        from app.main import main

        # Set environment to not run on startup
        os.environ["LOOM_CALENDAR_RUN_ON_STARTUP"] = "false"

        # Mock time.sleep
        with patch("time.sleep") as mock_sleep:
            # Make run_pending raise KeyboardInterrupt
            mock_schedule.run_pending.side_effect = KeyboardInterrupt()

            # Run main
            with pytest.raises(KeyboardInterrupt):
                main()

            # Verify fetch_events was NOT called immediately
            mock_fetch_events.assert_not_called()

    def test_fetch_events_success(self, mock_calendar_fetcher, mock_kafka_producer):
        """Test successful event fetching and Kafka sending."""
        from app.main import fetch_events

        # Run fetch_events
        fetch_events()

        # Verify CalendarFetcher was initialized and called
        mock_calendar_fetcher.fetch_all_events.assert_called_once()

        # Verify KafkaProducer was initialized
        mock_kafka_producer.send_message.assert_called()
        mock_kafka_producer.close.assert_called_once()

        # Verify correct number of messages sent
        assert mock_kafka_producer.send_message.call_count == 2

        # Verify message structure
        first_call = mock_kafka_producer.send_message.call_args_list[0]
        assert first_call[1]["topic"] == "external.calendar.events.raw"
        assert first_call[1]["key"] == "test-event-1"

        message = first_call[1]["value"]
        assert message["schema_version"] == "v1"
        assert message["device_id"] is None
        assert "timestamp" in message
        assert "data" in message

    def test_fetch_events_empty_calendar(
        self, mock_calendar_fetcher, mock_kafka_producer
    ):
        """Test handling of empty calendar."""
        from app.main import fetch_events

        # Mock empty event list
        mock_calendar_fetcher.fetch_all_events.return_value = []

        # Run fetch_events
        fetch_events()

        # Verify CalendarFetcher was called
        mock_calendar_fetcher.fetch_all_events.assert_called_once()

        # Verify no messages were sent to Kafka
        mock_kafka_producer.send_message.assert_not_called()

        # Verify producer was still closed
        mock_kafka_producer.close.assert_called_once()

    def test_fetch_events_error_handling(
        self, mock_calendar_fetcher, mock_kafka_producer
    ):
        """Test error handling during calendar fetch."""
        from app.main import fetch_events

        # Make fetch_all_events raise an exception
        mock_calendar_fetcher.fetch_all_events.side_effect = Exception(
            "CalDAV connection failed"
        )

        # Run fetch_events - should not raise exception
        fetch_events()

        # Verify error was handled gracefully
        mock_calendar_fetcher.fetch_all_events.assert_called_once()
        mock_kafka_producer.send_message.assert_not_called()

    def test_custom_fetch_interval(self, mock_calendar_fetcher, mock_schedule):
        """Test custom fetch interval from environment."""
        from app.main import main

        # Set custom interval
        os.environ["LOOM_CALENDAR_FETCH_INTERVAL_MINUTES"] = "30"

        with patch("time.sleep"):
            with patch("app.main.fetch_events"):
                mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                with pytest.raises(KeyboardInterrupt):
                    main()

                # Verify schedule was set up with custom interval
                mock_schedule.every.assert_called_with(30)

    def test_custom_output_topic(self, mock_calendar_fetcher, mock_kafka_producer):
        """Test custom Kafka output topic."""
        from app.main import fetch_events

        # Set custom topic
        os.environ["LOOM_KAFKA_OUTPUT_TOPIC"] = "custom.calendar.topic"

        # Run fetch_events
        fetch_events()

        # Verify messages were sent to custom topic
        first_call = mock_kafka_producer.send_message.call_args_list[0]
        assert first_call[1]["topic"] == "custom.calendar.topic"

    def test_message_structure_compliance(
        self, mock_calendar_fetcher, mock_kafka_producer, sample_calendar_event
    ):
        """Test that messages comply with expected schema."""
        from app.main import fetch_events

        # Set up mock to return our sample data
        mock_calendar_fetcher.fetch_all_events.return_value = [sample_calendar_event]

        # Run fetch_events
        fetch_events()

        # Get the sent message
        call_args = mock_kafka_producer.send_message.call_args
        message = call_args[1]["value"]

        # Verify message structure
        assert message["schema_version"] == "v1"
        assert message["device_id"] is None
        assert isinstance(message["timestamp"], str)

        # Verify data contains calendar event
        assert message["data"]["event_id"] == "sample-event-123"
        assert message["data"]["title"] == "Project Review"
        assert message["data"]["is_recurring"] is False

    def test_recurring_events_handling(
        self, mock_calendar_fetcher, mock_kafka_producer
    ):
        """Test handling of recurring events."""
        from app.main import fetch_events

        # Mock calendar with recurring events
        start = datetime.now(timezone.utc)
        mock_calendar_fetcher.fetch_all_events.return_value = [
            {
                "event_id": "recurring-daily-1",
                "title": "Daily Standup",
                "description": "Team standup",
                "start_time": start,
                "end_time": start + timedelta(minutes=15),
                "location": "Virtual",
                "attendees": ["team@example.com"],
                "calendar_name": "Work",
                "is_recurring": True,
            },
            {
                "event_id": "recurring-weekly-1",
                "title": "Weekly Review",
                "description": "Sprint review",
                "start_time": start + timedelta(days=7),
                "end_time": start + timedelta(days=7, hours=1),
                "location": "Conference Room",
                "attendees": ["team@example.com", "pm@example.com"],
                "calendar_name": "Work",
                "is_recurring": True,
            },
        ]

        # Run fetch_events
        fetch_events()

        # Verify both recurring events were sent
        assert mock_kafka_producer.send_message.call_count == 2

        # Verify recurring flag is preserved
        calls = mock_kafka_producer.send_message.call_args_list
        assert calls[0][1]["value"]["data"]["is_recurring"] is True
        assert calls[1][1]["value"]["data"]["is_recurring"] is True

    def test_multiple_calendars_handling(
        self, mock_calendar_fetcher, mock_kafka_producer
    ):
        """Test handling events from multiple calendars."""
        from app.main import fetch_events

        # Mock events from different calendars
        start = datetime.now(timezone.utc)
        mock_calendar_fetcher.fetch_all_events.return_value = [
            {
                "event_id": "work-event-1",
                "title": "Work Meeting",
                "description": "Important work meeting",
                "start_time": start,
                "end_time": start + timedelta(hours=1),
                "location": "Office",
                "attendees": ["colleague@work.com"],
                "calendar_name": "Work Calendar",
                "is_recurring": False,
            },
            {
                "event_id": "personal-event-1",
                "title": "Doctor Appointment",
                "description": "Annual checkup",
                "start_time": start + timedelta(days=1),
                "end_time": start + timedelta(days=1, hours=1),
                "location": "Medical Center",
                "attendees": [],
                "calendar_name": "Personal Calendar",
                "is_recurring": False,
            },
        ]

        # Run fetch_events
        fetch_events()

        # Verify both events were sent
        assert mock_kafka_producer.send_message.call_count == 2

        # Verify different calendars
        calls = mock_kafka_producer.send_message.call_args_list
        assert calls[0][1]["value"]["data"]["calendar_name"] == "Work Calendar"
        assert calls[1][1]["value"]["data"]["calendar_name"] == "Personal Calendar"
