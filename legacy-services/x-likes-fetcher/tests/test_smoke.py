"""Smoke tests for x-likes-fetcher service."""

import pytest
from unittest.mock import patch
import os
from datetime import datetime, timezone

# Assuming the main module has similar structure to other fetchers
# Adjust imports based on actual implementation


class TestXLikesFetcherSmoke:
    """Smoke tests to ensure the X likes fetcher service works."""

    @pytest.mark.asyncio
    async def test_fetch_likes_success(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test successful likes fetching with duplicate checking."""
        from app.main import fetch_likes

        # Run fetch_likes
        await fetch_likes()

        # Verify XLikesFetcher was called
        mock_x_likes_fetcher.fetch_likes.assert_called_once()

        # Verify duplicate checking was performed for each tweet
        assert mock_db_checker.check_duplicate.call_count == 2

        # Verify Kafka messages were sent (no duplicates)
        assert mock_kafka_producer.send_message.call_count == 2
        mock_kafka_producer.close.assert_called_once()

        # Verify message structure
        first_call = mock_kafka_producer.send_message.call_args_list[0]
        assert first_call[1]["topic"] == "external.twitter.liked.raw"
        assert first_call[1]["key"] == "1234567890123456789"

        message = first_call[1]["value"]
        assert message["schema_version"] == "v1"
        assert message["device_id"] == "x-likes-fetcher"
        assert "trace_id" in message
        assert "timestamp" in message
        assert "data" in message

    @pytest.mark.asyncio
    async def test_fetch_likes_with_duplicates(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test handling of duplicate tweets."""
        from app.main import fetch_likes

        # Make first tweet a duplicate
        mock_db_checker.check_duplicate.side_effect = [True, False]

        # Run fetch_likes
        await fetch_likes()

        # Verify only non-duplicate was sent to Kafka
        assert mock_kafka_producer.send_message.call_count == 1

        # Verify it was the second tweet
        call_args = mock_kafka_producer.send_message.call_args
        assert call_args[1]["key"] == "9876543210987654321"

    @pytest.mark.asyncio
    async def test_fetch_likes_no_duplicate_check(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test fetching without duplicate checking."""
        from app.main import fetch_likes

        # Disable duplicate checking
        os.environ["LOOM_X_DUPLICATE_CHECK"] = "false"

        # Run fetch_likes
        await fetch_likes()

        # Verify duplicate checking was NOT performed
        mock_db_checker.check_duplicate.assert_not_called()

        # Verify all tweets were sent
        assert mock_kafka_producer.send_message.call_count == 2

    @pytest.mark.asyncio
    async def test_fetch_likes_empty_response(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test handling of no liked tweets."""
        from app.main import fetch_likes

        # Mock empty likes list
        mock_x_likes_fetcher.fetch_likes.return_value = []

        # Run fetch_likes
        await fetch_likes()

        # Verify no messages were sent
        mock_kafka_producer.send_message.assert_not_called()

        # Verify producer was still closed
        mock_kafka_producer.close.assert_called_once()

    @pytest.mark.asyncio
    async def test_fetch_likes_error_handling(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test error handling during likes fetch."""
        from app.main import fetch_likes

        # Make fetch_likes raise an exception
        mock_x_likes_fetcher.fetch_likes.side_effect = Exception("Twitter API error")

        # Run fetch_likes - should not raise exception
        await fetch_likes()

        # Verify error was handled gracefully
        mock_x_likes_fetcher.fetch_likes.assert_called_once()
        mock_kafka_producer.send_message.assert_not_called()

    @pytest.mark.asyncio
    async def test_fetch_likes_db_error_handling(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test handling of database errors during duplicate check."""
        from app.main import fetch_likes

        # Make duplicate check raise exception
        mock_db_checker.check_duplicate.side_effect = Exception(
            "Database connection error"
        )

        # Run fetch_likes
        await fetch_likes()

        # Should still send messages despite DB error
        assert mock_kafka_producer.send_message.call_count == 2

    def test_main_startup_with_immediate_run(self, mock_x_likes_fetcher, mock_schedule):
        """Test main function with immediate run on startup."""
        from app.main import main

        with patch("app.main.fetch_likes"):
            with patch("asyncio.run") as mock_async_run:
                with patch("time.sleep"):
                    mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                    with pytest.raises(KeyboardInterrupt):
                        main()

                    # Verify schedule was set up
                    mock_schedule.every.assert_called_with(30)

                    # Verify fetch_likes was called immediately
                    mock_async_run.assert_called()

    def test_main_startup_without_immediate_run(
        self, mock_x_likes_fetcher, mock_schedule
    ):
        """Test main function without immediate run on startup."""
        from app.main import main

        # Disable run on startup
        os.environ["LOOM_X_RUN_ON_STARTUP"] = "false"

        with patch("app.main.fetch_likes"):
            with patch("asyncio.run") as mock_async_run:
                with patch("time.sleep"):
                    mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                    with pytest.raises(KeyboardInterrupt):
                        main()

                    # Verify fetch_likes was NOT called immediately
                    assert mock_async_run.call_count == 0

    def test_custom_fetch_interval(self, mock_schedule):
        """Test custom fetch interval from environment."""
        from app.main import main

        # Set custom interval
        os.environ["LOOM_X_FETCH_INTERVAL_MINUTES"] = "60"

        with patch("app.main.fetch_likes"):
            with patch("asyncio.run"):
                with patch("time.sleep"):
                    mock_schedule.run_pending.side_effect = KeyboardInterrupt()

                    with pytest.raises(KeyboardInterrupt):
                        main()

                    # Verify custom interval
                    mock_schedule.every.assert_called_with(60)

    @pytest.mark.asyncio
    async def test_message_structure_compliance(
        self,
        mock_x_likes_fetcher,
        mock_db_checker,
        mock_kafka_producer,
        sample_tweet_data,
    ):
        """Test that messages comply with expected schema."""
        from app.main import fetch_likes

        # Set up mock to return our sample data
        mock_x_likes_fetcher.fetch_likes.return_value = [sample_tweet_data]
        mock_db_checker.check_duplicate.return_value = False

        # Run fetch_likes
        await fetch_likes()

        # Get the sent message
        call_args = mock_kafka_producer.send_message.call_args
        message = call_args[1]["value"]

        # Verify message structure
        assert message["schema_version"] == "v1"
        assert message["device_id"] == "x-likes-fetcher"
        assert "trace_id" in message
        assert "x-like" in message["trace_id"]
        assert isinstance(message["timestamp"], str)

        # Verify data matches input
        assert message["data"]["tweet_id"] == "1234567890123456789"
        assert message["data"]["author_username"] == "elonmusk"
        assert message["data"]["has_media"] is True
        assert len(message["data"]["media_urls"]) == 2

        # Verify metadata
        assert "metadata" in message
        assert "fetched_at" in message["metadata"]
        assert "user_agent" in message["metadata"]

    @pytest.mark.asyncio
    async def test_retweet_handling(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test proper handling of retweets."""
        from app.main import fetch_likes

        # Create a retweet
        retweet = {
            "tweet_id": "1111111111111111111",
            "tweet_url": "https://twitter.com/user/status/1111111111111111111",
            "tweet_text": "RT @original_author: This is the original tweet content",
            "author_username": "retweeter",
            "author_display_name": "Person Who Retweeted",
            "created_at": datetime.now(timezone.utc),
            "like_count": 10,
            "retweet_count": 5,
            "reply_count": 2,
            "is_retweet": True,
            "has_media": False,
            "media_urls": [],
        }

        mock_x_likes_fetcher.fetch_likes.return_value = [retweet]
        mock_db_checker.check_duplicate.return_value = False

        # Run fetch_likes
        await fetch_likes()

        # Verify retweet was processed
        call_args = mock_kafka_producer.send_message.call_args
        message = call_args[1]["value"]

        assert message["data"]["is_retweet"] is True
        assert message["data"]["tweet_text"].startswith("RT @")

    @pytest.mark.asyncio
    async def test_trace_id_generation(
        self, mock_x_likes_fetcher, mock_db_checker, mock_kafka_producer
    ):
        """Test trace_id generation for tweets."""
        from app.main import fetch_likes

        # Run fetch_likes
        await fetch_likes()

        # Check both messages have unique trace_ids
        calls = mock_kafka_producer.send_message.call_args_list

        trace_id_1 = calls[0][1]["value"]["trace_id"]
        trace_id_2 = calls[1][1]["value"]["trace_id"]

        # Verify format
        assert trace_id_1.startswith("x-like-")
        assert trace_id_2.startswith("x-like-")

        # Verify uniqueness
        assert trace_id_1 != trace_id_2

        # Verify includes tweet_id
        assert "1234567890123456789" in trace_id_1
        assert "9876543210987654321" in trace_id_2
