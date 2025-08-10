# Using Google Calendar's Secret iCal Link with Loom

## Why Use iCal Links?

iCal links are **much simpler** than CalDAV:
- ✅ No authentication required
- ✅ No app passwords needed
- ✅ Works with any calendar that provides iCal links
- ✅ Read-only access (perfect for monitoring)
- ✅ Easy to revoke/regenerate

## Step 1: Get Your Google Calendar's Secret iCal Link

1. **Open Google Calendar** in your web browser
2. Click the **⚙️ Settings** gear icon → **Settings**
3. In the left sidebar, find **My calendars** section
4. Click on the calendar you want to sync
5. Scroll down to **Integrate calendar** section
6. Find **Secret address in iCal format**
7. Click the **Copy** button next to the iCal URL

The URL will look like:
```
https://calendar.google.com/calendar/ical/YOUR_EMAIL%40gmail.com/private-LONG_RANDOM_STRING/basic.ics
```

> **⚠️ Important**: This is a SECRET link. Anyone with this URL can see your calendar events. Keep it secure!

## Step 2: Configure the Calendar Fetcher

Set these environment variables:

```bash
# Using iCal URL (NEW - requires code update)
LOOM_ICAL_URL_1="https://calendar.google.com/calendar/ical/YOUR_EMAIL%40gmail.com/private-XXXXX/basic.ics"
LOOM_ICAL_NAME_1="My Google Calendar"

# Optional: Multiple calendars
LOOM_ICAL_URL_2="https://calendar.google.com/calendar/ical/WORK_CALENDAR_ID/private-YYYYY/basic.ics"
LOOM_ICAL_NAME_2="Work Calendar"

# Fetch settings (same as before)
LOOM_CALENDAR_FETCH_INTERVAL_MINUTES=30
LOOM_CALENDAR_DAYS_PAST=30
LOOM_CALENDAR_DAYS_FUTURE=365
```

## Step 3: Test Your iCal URL

Quick test with curl:
```bash
# Test if the URL works
curl -s "YOUR_ICAL_URL" | head -20

# You should see something like:
# BEGIN:VCALENDAR
# VERSION:2.0
# PRODID:-//Google Inc//Google Calendar 70.9054//EN
# ...
```

## Step 4: Update Calendar Fetcher Code

The calendar fetcher needs to be updated to support iCal URLs. The main changes needed:

1. **Add iCal URL support** alongside CalDAV
2. **Use the ical_fetcher.py module** we just created
3. **Check for LOOM_ICAL_URL_* environment variables**

Example update to main.py:
```python
from app.ical_fetcher import ICalFetcher

# In the fetch loop, add:
# Check for iCal URLs
for i in range(1, max_accounts + 1):
    ical_url = os.getenv(f'LOOM_ICAL_URL_{i}')
    if ical_url:
        name = os.getenv(f'LOOM_ICAL_NAME_{i}', f'iCal Calendar {i}')
        fetcher = ICalFetcher(ical_url, name)
        events = fetcher.fetch_events(days_past, days_future)
        # Process events...
```

## Advantages of iCal Links

1. **Simplicity**: No passwords, no 2FA, no app-specific passwords
2. **Security**: Read-only access, easily revocable
3. **Flexibility**: Works with any calendar service that provides iCal
4. **Performance**: Simple HTTP GET request, no complex authentication

## Managing Multiple Calendars

You can add multiple calendars from different sources:

```bash
# Google Calendar (Personal)
LOOM_ICAL_URL_1="https://calendar.google.com/calendar/ical/..."
LOOM_ICAL_NAME_1="Personal Calendar"

# Google Calendar (Work)
LOOM_ICAL_URL_2="https://calendar.google.com/calendar/ical/..."
LOOM_ICAL_NAME_2="Work Calendar"

# Outlook Calendar
LOOM_ICAL_URL_3="https://outlook.live.com/owa/calendar/..."
LOOM_ICAL_NAME_3="Outlook Calendar"

# Public Holiday Calendar
LOOM_ICAL_URL_4="https://www.officeholidays.com/ics/usa"
LOOM_ICAL_NAME_4="US Holidays"
```

## Security Notes

- **Keep URLs Secret**: These URLs provide read access to your calendar
- **Regenerate if Compromised**: Google lets you regenerate the secret URL
- **Use HTTPS**: Always use HTTPS URLs, not HTTP
- **Monitor Access**: Check Google Calendar settings periodically

## Revoking Access

To revoke access:
1. Go to Google Calendar Settings
2. Find your calendar
3. Click **Reset** next to "Secret address in iCal format"
4. This generates a new URL and invalidates the old one

## Next Steps

Once implemented, the calendar fetcher will:
- Fetch your calendar every 30 minutes
- Parse all events in the time window
- Send them to Kafka for processing
- No authentication headaches!

This is much simpler than CalDAV and perfect for read-only calendar monitoring.