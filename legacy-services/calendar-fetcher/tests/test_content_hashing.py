"""
Test content hashing for calendar events
"""

from datetime import datetime
from app.shared.deduplication import content_hasher


def test_calendar_hash_with_uid():
    """Test calendar hashing with UID (primary strategy)"""
    # Same UID should produce same hash regardless of other fields
    hash1 = content_hasher.generate_calendar_hash(
        uid="unique-calendar-uid-123",
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Meeting 1",
        location="Room A",
    )

    hash2 = content_hasher.generate_calendar_hash(
        uid="unique-calendar-uid-123",
        start_time=datetime(2024, 1, 2, 14, 0),  # Different time
        end_time=datetime(2024, 1, 2, 15, 0),
        title="Meeting 2",  # Different title
        location="Room B",  # Different location
    )

    assert hash1 == hash2, "Same UID should produce same hash"


def test_calendar_hash_without_uid():
    """Test calendar hashing without UID (fallback strategy)"""
    # Without UID, hash should be based on event properties
    hash1 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Team Meeting",
        location="Conference Room",
        organizer="john@example.com",
    )

    # Same event properties should produce same hash
    hash2 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Team Meeting",
        location="Conference Room",
        organizer="john@example.com",
    )

    assert hash1 == hash2, "Same event properties should produce same hash"

    # Different properties should produce different hash
    hash3 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Different Meeting",  # Changed
        location="Conference Room",
        organizer="john@example.com",
    )

    assert hash1 != hash3, "Different event properties should produce different hash"


def test_calendar_hash_text_normalization():
    """Test that text normalization works correctly"""
    # Extra whitespace should be normalized
    hash1 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Team   Meeting",  # Extra spaces
        location="  Conference Room  ",  # Leading/trailing spaces
    )

    hash2 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="Team Meeting",  # Normalized
        location="Conference Room",  # Normalized
    )

    assert hash1 == hash2, "Normalized text should produce same hash"


def test_calendar_hash_timestamp_formats():
    """Test that different timestamp formats are handled correctly"""
    dt = datetime(2024, 1, 1, 10, 0, 0)

    # Test with datetime object
    hash1 = content_hasher.generate_calendar_hash(
        start_time=dt, end_time=datetime(2024, 1, 1, 11, 0, 0), title="Meeting"
    )

    # Test with ISO string
    hash2 = content_hasher.generate_calendar_hash(
        start_time="2024-01-01T10:00:00",
        end_time="2024-01-01T11:00:00",
        title="Meeting",
    )

    # Test with Unix timestamp (milliseconds)
    hash3 = content_hasher.generate_calendar_hash(
        start_time=int(dt.timestamp() * 1000),
        end_time=int(datetime(2024, 1, 1, 11, 0, 0).timestamp() * 1000),
        title="Meeting",
    )

    assert (
        hash1 == hash2 == hash3
    ), "Different timestamp formats should produce same hash"


def test_calendar_hash_consistency():
    """Test hash consistency across multiple calls"""
    event_data = {
        "uid": "test-uid-456",
        "start_time": datetime(2024, 1, 1, 10, 0),
        "end_time": datetime(2024, 1, 1, 11, 0),
        "title": "Consistent Event",
        "location": "Room 101",
    }

    # Generate hash multiple times
    hashes = [content_hasher.generate_calendar_hash(**event_data) for _ in range(5)]

    # All hashes should be identical
    assert len(set(hashes)) == 1, "Multiple calls should produce same hash"


def test_calendar_hash_edge_cases():
    """Test edge cases for calendar hashing"""
    # Missing optional fields
    hash1 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="No Location Event",
        location=None,  # No location
        organizer=None,  # No organizer
    )

    hash2 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title="No Location Event",
        location="",  # Empty location
        organizer="",  # Empty organizer
    )

    assert hash1 == hash2, "None and empty string should be treated the same"

    # Test with very long title
    long_title = "A" * 1000
    hash3 = content_hasher.generate_calendar_hash(
        start_time=datetime(2024, 1, 1, 10, 0),
        end_time=datetime(2024, 1, 1, 11, 0),
        title=long_title,
    )

    assert len(hash3) == 64, "Hash should always be 64 characters (SHA-256)"
