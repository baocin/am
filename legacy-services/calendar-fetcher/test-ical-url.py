#!/usr/bin/env python3
"""
Test script to verify iCal URL access and parsing
"""
import os
import sys
from datetime import datetime, timedelta
import requests
from icalendar import Calendar

def test_ical_url(url=None):
    """Test fetching and parsing an iCal URL"""
    
    # Get URL from argument or environment
    if not url:
        url = os.getenv('LOOM_ICAL_URL_1')
    
    if not url:
        print("❌ Error: Please provide an iCal URL")
        print("\nUsage:")
        print("  ./test-ical-url.py 'https://calendar.google.com/calendar/ical/...'")
        print("\nOr set environment variable:")
        print("  export LOOM_ICAL_URL_1='https://calendar.google.com/calendar/ical/...'")
        return False
    
    print(f"🔍 Testing iCal URL")
    print(f"   URL: {url[:50]}..." if len(url) > 50 else f"   URL: {url}")
    
    try:
        # Convert webcal:// to https:// if needed
        fetch_url = url.replace('webcal://', 'https://')
        
        # Fetch the calendar
        print("\n📡 Fetching calendar data...")
        response = requests.get(fetch_url, timeout=30, headers={
            'User-Agent': 'Loom Calendar Test/1.0'
        })
        response.raise_for_status()
        
        print(f"✅ Successfully fetched {len(response.content)} bytes")
        
        # Parse the calendar
        print("\n📅 Parsing calendar...")
        cal = Calendar.from_ical(response.content)
        
        # Get calendar properties
        cal_name = cal.get('X-WR-CALNAME', 'Unknown')
        cal_desc = cal.get('X-WR-CALDESC', '')
        print(f"✅ Calendar Name: {cal_name}")
        if cal_desc:
            print(f"   Description: {cal_desc}")
        
        # Count components
        events = []
        todos = 0
        journals = 0
        
        for component in cal.walk():
            if component.name == "VEVENT":
                events.append(component)
            elif component.name == "VTODO":
                todos += 1
            elif component.name == "VJOURNAL":
                journals += 1
        
        print(f"\n📊 Found {len(events)} events")
        if todos:
            print(f"   Also found {todos} tasks")
        if journals:
            print(f"   Also found {journals} journal entries")
        
        # Show recent and upcoming events
        now = datetime.now()
        recent_events = []
        upcoming_events = []
        
        for event in events:
            dtstart = event.get('dtstart')
            if dtstart:
                # Handle different date formats
                if hasattr(dtstart.dt, 'date'):
                    event_date = dtstart.dt
                    if hasattr(event_date, 'replace') and event_date.tzinfo is None:
                        event_date = event_date.replace(tzinfo=None)
                else:
                    event_date = datetime.combine(dtstart.dt, datetime.min.time())
                
                # Compare dates (ignore timezone for simplicity in test)
                if hasattr(event_date, 'replace'):
                    event_date_compare = event_date.replace(tzinfo=None) if hasattr(event_date, 'tzinfo') else event_date
                else:
                    event_date_compare = event_date
                    
                days_diff = (event_date_compare - now).days
                
                if -7 <= days_diff <= 0:
                    recent_events.append((days_diff, event))
                elif 0 < days_diff <= 30:
                    upcoming_events.append((days_diff, event))
        
        # Show recent events
        if recent_events:
            print(f"\n📆 Recent Events (past 7 days):")
            for days_diff, event in sorted(recent_events, reverse=True)[:5]:
                summary = event.get('summary', 'No title')
                location = event.get('location', '')
                dtstart = event.get('dtstart').dt
                
                if hasattr(dtstart, 'strftime'):
                    date_str = dtstart.strftime('%Y-%m-%d %H:%M')
                else:
                    date_str = str(dtstart)
                
                location_str = f" @ {location}" if location else ""
                print(f"   • {summary}{location_str} ({date_str})")
        
        # Show upcoming events
        if upcoming_events:
            print(f"\n📅 Upcoming Events (next 30 days):")
            for days_diff, event in sorted(upcoming_events)[:5]:
                summary = event.get('summary', 'No title')
                location = event.get('location', '')
                dtstart = event.get('dtstart').dt
                
                if hasattr(dtstart, 'strftime'):
                    date_str = dtstart.strftime('%Y-%m-%d %H:%M')
                else:
                    date_str = str(dtstart)
                
                location_str = f" @ {location}" if location else ""
                days_str = f"in {days_diff} day{'s' if days_diff != 1 else ''}"
                print(f"   • {summary}{location_str} ({date_str}) - {days_str}")
        
        if not recent_events and not upcoming_events:
            print("\n   No events in the past 7 days or next 30 days")
        
        print(f"\n✅ iCal URL test successful!")
        print(f"   This calendar can be synced with Loom")
        
        # Show how to get the secret URL
        if 'calendar.google.com' in url:
            print("\n💡 Tip: This appears to be a Google Calendar")
            print("   To get your secret iCal URL:")
            print("   1. Open Google Calendar settings")
            print("   2. Click on your calendar")
            print("   3. Find 'Secret address in iCal format'")
            print("   4. Copy the URL and use it with Loom")
        
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Failed to fetch calendar: {e}")
        print("\n🔧 Troubleshooting:")
        print("1. Check that the URL is correct")
        print("2. Ensure the calendar is publicly accessible or you're using the secret URL")
        print("3. Try opening the URL in a web browser")
        return False
    except Exception as e:
        print(f"\n❌ Failed to parse calendar: {e}")
        print("\n🔧 This might not be a valid iCal/ICS file")
        return False

if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else None
    success = test_ical_url(url)
    sys.exit(0 if success else 1)