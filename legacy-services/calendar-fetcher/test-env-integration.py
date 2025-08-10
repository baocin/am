#!/usr/bin/env python3
"""
Test the calendar fetcher with .env file configuration
"""
import os
import sys
import json
from pathlib import Path
from datetime import datetime

# Add the app directory to Python path
sys.path.insert(0, str(Path(__file__).parent / "app"))

# Load .env file if it exists
env_file = Path(__file__).parent / ".env"
if env_file.exists():
    print(f"📄 Loading environment from {env_file}")
    with open(env_file) as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    # Remove quotes if present
                    value = value.strip('"').strip("'")
                    os.environ[key] = value
                    if key.startswith('LOOM_ICAL_URL'):
                        print(f"✅ Found {key}")

# Import after setting environment
from calendar_fetcher import CalendarFetcher

def test_integration():
    """Test the complete integration"""
    print("\n🔍 Testing Calendar Fetcher Integration\n")
    
    try:
        # Initialize the fetcher
        print("📅 Initializing calendar fetcher...")
        fetcher = CalendarFetcher()
        
        if not fetcher.accounts:
            print("❌ No calendar accounts found!")
            print("\nMake sure your .env file contains:")
            print('LOOM_ICAL_URL_1="https://calendar.google.com/calendar/ical/..."')
            print('LOOM_ICAL_NAME_1="My Google Calendar"')
            return False
        
        print(f"✅ Found {len(fetcher.accounts)} calendar account(s)")
        
        for account in fetcher.accounts:
            print(f"\n📊 Account: {account['name']}")
            print(f"   Type: {account['type']}")
            if account['type'] == 'ical':
                print(f"   URL: {account['url'][:60]}...")
        
        # Fetch events
        print("\n🔄 Fetching calendar events...")
        events = fetcher.fetch_all_calendar_events()
        
        print(f"\n✅ Fetched {len(events)} total events")
        
        # Show sample events
        if events:
            print("\n📋 Sample events (first 3):")
            for i, event in enumerate(events[:3]):
                print(f"\n Event {i+1}:")
                print(f"   Title: {event.get('summary', 'No title')}")
                print(f"   Start: {event.get('start_time', 'No start time')}")
                print(f"   Location: {event.get('location', 'No location')}")
                print(f"   Calendar: {event.get('calendar_name', 'Unknown')}")
                if event.get('gps_point'):
                    print(f"   GPS: {event['gps_point']}")
                
            # Show what would be sent to Kafka
            print("\n📤 Sample Kafka message:")
            sample_event = events[0]
            device_id = f"calendar-fetcher-{sample_event.get('calendar_name', 'default').lower().replace(' ', '-')}"
            
            timestamp = sample_event.get("start_time")
            if timestamp and hasattr(timestamp, 'isoformat'):
                timestamp = timestamp.isoformat()
            
            kafka_message = {
                "schema_version": "v1",
                "device_id": device_id,
                "timestamp": timestamp,
                "data": sample_event
            }
            
            print(json.dumps(kafka_message, indent=2, default=str))
            print(f"\n✅ This message would be sent to topic: {os.getenv('LOOM_KAFKA_OUTPUT_TOPIC', 'external.calendar.events.raw')}")
            print(f"   With key: {sample_event['event_id']}")
        
        return True
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_integration()
    sys.exit(0 if success else 1)