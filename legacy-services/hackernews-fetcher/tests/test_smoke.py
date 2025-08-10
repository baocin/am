"""Smoke tests for hackernews-fetcher service."""

import pytest
from unittest.mock import patch
import os


class TestHackerNewsFetcherSmoke:
    """Smoke tests to ensure the HackerNews fetcher service works."""

    def test_fetch_activity_success(self, mock_hackernews_fetcher, mock_kafka_producer):
        """Test successful activity fetching and Kafka sending."""
        from app.main import fetch_activity

        # Run fetch_activity
        fetch_activity()

        # Verify HackerNewsFetcher was called
        mock_hackernews_fetcher.fetch_user_activity.assert_called_once_with("testuser")

        # Verify Kafka messages were sent for all activities
        # 2 submitted + 1 upvoted + 1 favorite = 4 total
        assert mock_kafka_producer.send_message.call_count == 4
        mock_kafka_producer.close.assert_called_once()

        # Verify message structure for a story
        story_call = None
        for call in mock_kafka_producer.send_message.call_args_list:
            if call[1]["key"] == "40849399":
                story_call = call
                break

        assert story_call is not None
        message = story_call[1]["value"]
        assert message["schema_version"] == "v1"
        assert message["device_id"] == "hackernews-fetcher"
        assert "trace_id" in message
        assert "timestamp" in message
        assert message["data"]["item_type"] == "story"
        assert message["data"]["activity_type"] == "submitted"

    def test_fetch_activity_no_username(
        self, mock_hackernews_fetcher, mock_kafka_producer
    ):
        """Test handling when no username is configured."""
        from app.main import fetch_activity

        # Remove username from environment
        os.environ.pop("LOOM_HN_USERNAME", None)

        # Run fetch_activity - should handle gracefully
        fetch_activity()

        # Verify no API calls were made
        mock_hackernews_fetcher.fetch_user_activity.assert_not_called()
        mock_kafka_producer.send_message.assert_not_called()

    def test_fetch_activity_empty_response(
        self, mock_hackernews_fetcher, mock_kafka_producer
    ):
        """Test handling of user with no activity."""
        from app.main import fetch_activity

        # Mock empty activity
        mock_hackernews_fetcher.fetch_user_activity.return_value = {
            "submitted": [],
            "upvoted": [],
            "favorites": [],
        }

        # Run fetch_activity
        fetch_activity()

        # Verify API was called
        mock_hackernews_fetcher.fetch_user_activity.assert_called_once()

        # Verify no messages were sent
        mock_kafka_producer.send_message.assert_not_called()

        # Verify producer was still closed
        mock_kafka_producer.close.assert_called_once()

    def test_fetch_activity_error_handling(
        self, mock_hackernews_fetcher, mock_kafka_producer
    ):
        """Test error handling during activity fetch."""
        from app.main import fetch_activity

        # Make fetch raise an exception
        mock_hackernews_fetcher.fetch_user_activity.side_effect = Exception(
            "HN API error"
        )

        # Run fetch_activity - should not raise exception
        fetch_activity()

        # Verify error was handled gracefully
        mock_hackernews_fetcher.fetch_user_activity.assert_called_once()
        mock_kafka_producer.send_message.assert_not_called()

    def test_main_startup_with_immediate_run(
        self, mock_hackernews_fetcher, mock_schedule
    ):
        """Test main function with immediate run on startup."""
        from app.main import main

        with patch("app.main.fetch_activity") as mock_fetch:
            with patch("time.sleep"):
                mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                with pytest.raises(KeyboardInterrupt):
                    main()

                # Verify schedule was set up
                mock_schedule.every.assert_called_with(60)

                # Verify fetch_activity was called immediately
                mock_fetch.assert_called_once()

    def test_main_startup_without_immediate_run(
        self, mock_hackernews_fetcher, mock_schedule
    ):
        """Test main function without immediate run on startup."""
        from app.main import main

        # Disable run on startup
        os.environ["LOOM_HN_RUN_ON_STARTUP"] = "false"

        with patch("app.main.fetch_activity") as mock_fetch:
            with patch("time.sleep"):
                mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                with pytest.raises(KeyboardInterrupt):
                    main()

                # Verify fetch_activity was NOT called immediately
                mock_fetch.assert_not_called()

    def test_custom_fetch_interval(self, mock_schedule):
        """Test custom fetch interval from environment."""
        from app.main import main

        # Set custom interval
        os.environ["LOOM_HN_FETCH_INTERVAL_MINUTES"] = "120"

        with patch("app.main.fetch_activity"):
            with patch("time.sleep"):
                mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                with pytest.raises(KeyboardInterrupt):
                    main()

                # Verify custom interval
                mock_schedule.every.assert_called_with(120)

    def test_message_structure_compliance(
        self, mock_hackernews_fetcher, mock_kafka_producer, sample_hn_story
    ):
        """Test that messages comply with expected schema."""
        from app.main import fetch_activity

        # Set up mock to return our sample data
        mock_hackernews_fetcher.fetch_user_activity.return_value = {
            "submitted": [sample_hn_story],
            "upvoted": [],
            "favorites": [],
        }

        # Run fetch_activity
        fetch_activity()

        # Get the sent message
        call_args = mock_kafka_producer.send_message.call_args
        message = call_args[1]["value"]

        # Verify message structure
        assert message["schema_version"] == "v1"
        assert message["device_id"] == "hackernews-fetcher"
        assert "trace_id" in message
        assert "hn-40850000" in message["trace_id"]

        # Verify data
        assert message["data"]["item_id"] == "40850000"
        assert message["data"]["item_type"] == "story"
        assert message["data"]["activity_type"] == "submitted"
        assert message["data"]["title"] == sample_hn_story["title"]
        assert message["data"]["score"] == 342

        # Verify metadata
        assert message["metadata"]["user"] == "testuser"

    def test_comment_handling(
        self, mock_hackernews_fetcher, mock_kafka_producer, sample_hn_comment
    ):
        """Test proper handling of comments."""
        from app.main import fetch_activity

        # Mock activity with comment
        mock_hackernews_fetcher.fetch_user_activity.return_value = {
            "submitted": [sample_hn_comment],
            "upvoted": [],
            "favorites": [],
        }

        # Run fetch_activity
        fetch_activity()

        # Verify comment was processed
        call_args = mock_kafka_producer.send_message.call_args
        message = call_args[1]["value"]

        assert message["data"]["item_type"] == "comment"
        assert message["data"]["text"] == sample_hn_comment["text"]
        assert message["data"]["parent_id"] == "40850000"
        assert message["data"]["title"] is None  # Comments don't have titles

    def test_activity_type_classification(
        self, mock_hackernews_fetcher, mock_kafka_producer
    ):
        """Test correct classification of activity types."""
        from app.main import fetch_activity

        # Run with default mock data
        fetch_activity()

        # Collect all activity types
        activity_types = []
        for call in mock_kafka_producer.send_message.call_args_list:
            message = call[1]["value"]
            activity_types.append(message["data"]["activity_type"])

        # Verify we have all activity types
        assert "submitted" in activity_types
        assert "upvoted" in activity_types
        assert "favorited" in activity_types

    def test_trace_id_generation(self, mock_hackernews_fetcher, mock_kafka_producer):
        """Test trace_id generation for HN items."""
        from app.main import fetch_activity

        # Run fetch_activity
        fetch_activity()

        # Check all messages have unique trace_ids
        trace_ids = set()
        for call in mock_kafka_producer.send_message.call_args_list:
            message = call[1]["value"]
            trace_id = message["trace_id"]

            # Verify format
            assert trace_id.startswith("hn-")
            assert len(trace_id.split("-")) >= 4  # hn-{id}-{type}-{timestamp}

            # Verify uniqueness
            assert trace_id not in trace_ids
            trace_ids.add(trace_id)

    def test_custom_output_topic(self, mock_hackernews_fetcher, mock_kafka_producer):
        """Test custom Kafka output topic."""
        from app.main import fetch_activity

        # Set custom topic
        os.environ["LOOM_KAFKA_OUTPUT_TOPIC"] = "custom.hn.topic"

        # Run fetch_activity
        fetch_activity()

        # Verify messages were sent to custom topic
        for call in mock_kafka_producer.send_message.call_args_list:
            assert call[1]["topic"] == "custom.hn.topic"

    def test_multiple_users_handling(
        self, mock_hackernews_fetcher, mock_kafka_producer
    ):
        """Test handling multiple usernames (if supported)."""
        from app.main import fetch_activity

        # Set multiple usernames (comma-separated)
        os.environ["LOOM_HN_USERNAME"] = "user1,user2,user3"

        # Run fetch_activity
        fetch_activity()

        # Verify fetch was called for first user (or all if supported)
        # Note: Adjust this test based on actual implementation
        assert mock_hackernews_fetcher.fetch_user_activity.call_count >= 1
