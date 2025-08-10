# Google Calendar Setup for Loom v2

## Prerequisites

1. **Google Account** with calendar access
2. **Two-factor authentication** enabled (required for app passwords)
3. **PostgreSQL/TimescaleDB** running in your Loom environment

## Step 1: Generate App-Specific Password

1. Go to https://myaccount.google.com/apppasswords
2. Sign in to your Google account
3. You may need to verify with 2FA
4. In "Select app" dropdown, choose "Other (Custom name)"
5. Enter "Loom Calendar Sync" as the name
6. Click "Generate"
7. **Copy the 16-character password** (format: xxxx xxxx xxxx xxxx)
   - Remove spaces when using it
   - You won't be able to see it again!

## Step 2: Configure Environment Variables

### Important: Google Calendar CalDAV URL Format

Google Calendar uses a specific CalDAV URL format:
- **Primary Calendar**: `https://apidata.googleusercontent.com/caldav/v2/YOUR-EMAIL/events`
- **Specific Calendar**: `https://apidata.googleusercontent.com/caldav/v2/CALENDAR-ID/events`

Where:
- `YOUR-EMAIL` is your full email address (e.g., `john.doe@gmail.com`)
- `CALENDAR-ID` is found in Google Calendar Settings → Calendar → Calendar ID

Create a `.env` file or set these environment variables:

```bash
# Google Calendar Configuration
# Note: Replace 'your-email@gmail.com' in the URL with your actual email address
LOOM_CALDAV_URL_1="https://apidata.googleusercontent.com/caldav/v2/your-email@gmail.com/events"
LOOM_CALDAV_USERNAME_1="your-email@gmail.com"
LOOM_CALDAV_PASSWORD_1="xxxxxxxxxxxxxx"  # 16-char app password (no spaces)
LOOM_CALDAV_NAME_1="Google Calendar"

# Optional: Enable GPS lookup for event locations
LOOM_CALENDAR_ENABLE_GPS_LOOKUP=true
LOOM_NOMINATIM_BASE_URL="https://nominatim.openstreetmap.org"

# Sync settings
LOOM_CALENDAR_FETCH_INTERVAL_MINUTES=30
LOOM_CALENDAR_DAYS_PAST=30
LOOM_CALENDAR_DAYS_FUTURE=365
LOOM_CALENDAR_RUN_ON_STARTUP=true

# Database settings (adjust for your environment)
LOOM_DATABASE_URL=postgresql://loom:loom@postgres:5432/loom
LOOM_DB_OUTPUT_TABLE=external_calendar_events_raw
```

## Step 3: Deploy the Calendar Fetcher

### Option A: Local Development (Docker Compose)

```bash
cd services/calendar-fetcher
docker-compose up -d
```

### Option B: Production Deployment

Use environment variables or a `.env` file to configure credentials, then:

```bash
docker-compose -f docker-compose.prod.yml up -d calendar-fetcher
```

## Step 4: Verify It's Working

1. **Check logs**:
```bash
# Docker
docker logs calendar-fetcher

# Production
docker-compose -f docker-compose.prod.yml logs calendar-fetcher
```

2. **Check database for events**:
```bash
# Connect to database and query calendar events
docker-compose exec postgres psql -U loom -d loom -c \
  "SELECT * FROM external_calendar_events_raw ORDER BY timestamp DESC LIMIT 10;"
```

## Troubleshooting

### Common Issues:

1. **Authentication Failed**
   - Ensure you're using the app password, not your regular Google password
   - Remove any spaces from the app password
   - Check that 2FA is enabled on your Google account

2. **No Events Fetched**
   - Verify you have events in your calendar within the configured time range
   - Check that the calendar is not empty or private

3. **Connection Errors**
   - Ensure your network can reach `apidata.googleusercontent.com`
   - Check firewall rules

4. **Multiple Calendars**
   - Google Calendar CalDAV typically syncs your primary calendar
   - For specific calendars, you may need the calendar ID

### Viewing Fetched Events

Events will be stored in the database with this structure:
```json
{
  "schema_version": "v1",
  "device_id": "calendar-fetcher-google-calendar",
  "timestamp": "2024-01-15T10:00:00Z",
  "data": {
    "event_id": "abc123@google.com",
    "summary": "Team Meeting",
    "description": "Weekly sync",
    "location": "Conference Room A",
    "start_time": "2024-01-15T14:00:00Z",
    "end_time": "2024-01-15T15:00:00Z",
    "organizer": "manager@company.com",
    "attendees": ["colleague1@company.com", "colleague2@company.com"],
    "source_calendar": "Google Calendar",
    "source_account": "your-email@gmail.com"
  }
}
```

## Security Notes

- App passwords are revokable - you can manage them at https://myaccount.google.com/apppasswords
- Store credentials securely (use environment variables or secure vaults, not plain text)
- Consider using a service account for production deployments
- The fetcher only has read access to your calendar

## Next Steps

Once calendar events are stored in the database, they will be:
1. Enriched by the `calendar-enricher` service
2. Embedded for semantic search by `embedding-generator`
3. Stored in TimescaleDB with 90-day retention
4. Available for querying and analysis in your Loom pipeline
