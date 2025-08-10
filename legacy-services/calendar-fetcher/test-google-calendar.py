#!/usr/bin/env python3
"""
Test script to verify Google Calendar CalDAV connectivity
"""
import os
import sys
from datetime import datetime, timedelta
import caldav
from caldav.elements import dav

def test_google_calendar_connection():
    # Get credentials from environment
    username = os.getenv('LOOM_CALDAV_USERNAME_1')
    password = os.getenv('LOOM_CALDAV_PASSWORD_1')
    # Build the correct Google Calendar CalDAV URL
    if username:
        url = os.getenv('LOOM_CALDAV_URL_1', f'https://apidata.googleusercontent.com/caldav/v2/{username}/events')
    else:
        url = os.getenv('LOOM_CALDAV_URL_1', 'https://apidata.googleusercontent.com/caldav/v2/')
    
    if not username or not password:
        print("❌ Error: Please set LOOM_CALDAV_USERNAME_1 and LOOM_CALDAV_PASSWORD_1")
        print("\nExample:")
        print("export LOOM_CALDAV_USERNAME_1='your-email@gmail.com'")
        print("export LOOM_CALDAV_PASSWORD_1='your-app-password'")
        return False
    
    print(f"🔍 Testing connection to Google Calendar")
    print(f"   URL: {url}")
    print(f"   Username: {username}")
    print(f"   Password: {'*' * len(password)}")
    
    try:
        # Connect to CalDAV server
        print("\n📡 Connecting to CalDAV server...")
        client = caldav.DAVClient(
            url=url,
            username=username,
            password=password
        )
        
        # Get principal (user's calendar home)
        print("👤 Getting principal...")
        principal = client.principal()
        print(f"✅ Connected as: {principal}")
        
        # Get calendars
        print("\n📅 Fetching calendars...")
        calendars = principal.calendars()
        print(f"✅ Found {len(calendars)} calendar(s)")
        
        for i, cal in enumerate(calendars):
            print(f"\n📌 Calendar {i+1}:")
            print(f"   Name: {cal.name}")
            print(f"   URL: {cal.url}")
            
            # Get events from the last 7 days
            print("\n   📊 Fetching recent events...")
            start_date = datetime.now() - timedelta(days=7)
            end_date = datetime.now() + timedelta(days=7)
            
            events = cal.date_search(
                start=start_date,
                end=end_date,
                expand=True
            )
            
            print(f"   ✅ Found {len(events)} events in the last/next 7 days")
            
            # Show first 3 events as examples
            for j, event in enumerate(events[:3]):
                event_data = event.instance.vevent
                summary = str(event_data.summary.value) if hasattr(event_data, 'summary') else 'No title'
                
                start_time = event_data.dtstart.value
                if hasattr(start_time, 'strftime'):
                    start_str = start_time.strftime('%Y-%m-%d %H:%M')
                else:
                    start_str = str(start_time)
                
                print(f"      Event {j+1}: {summary} ({start_str})")
            
            if len(events) > 3:
                print(f"      ... and {len(events) - 3} more events")
        
        print("\n✅ Google Calendar connection test successful!")
        return True
        
    except Exception as e:
        print(f"\n❌ Connection failed: {str(e)}")
        print("\n🔧 Troubleshooting tips:")
        print("1. Ensure you're using an app-specific password, not your regular password")
        print("2. Generate app password at: https://myaccount.google.com/apppasswords")
        print("3. Check that 2FA is enabled on your Google account")
        print("4. Remove any spaces from the app password")
        return False

if __name__ == "__main__":
    success = test_google_calendar_connection()
    sys.exit(0 if success else 1)