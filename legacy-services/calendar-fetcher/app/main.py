import os
import logging
import schedule
import time
import asyncio
from datetime import datetime
from calendar_fetcher import CalendarFetcher
from database_writer import DatabaseWriter

# Configure logging
log_level = os.getenv("LOOM_LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, log_level),
    format="%(asctime)s - calendar-fetcher - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],  # Remove file handler for container deployments
)


async def fetch_calendar_events():
    """Fetch calendar events and write to database"""
    db_writer = None
    try:
        logging.info("Starting calendar fetch process")

        # Initialize services
        calendar_fetcher = CalendarFetcher()
        db_writer = DatabaseWriter()
        await db_writer.initialize()

        # Fetch events from all configured calendars
        events = calendar_fetcher.fetch_all_calendar_events()

        # Get existing event IDs from database for duplicate checking
        existing_event_ids = await db_writer.get_existing_event_ids()
        logging.info(
            f"Found {len(existing_event_ids)} existing calendar events in database"
        )

        # Convert events to database format and write
        new_events = 0
        skipped_events = 0
        db_events = []

        for event_data in events:
            event_id = event_data.get("event_id")

            # Skip if event already exists in database
            if event_id and event_id in existing_event_ids:
                skipped_events += 1
                logging.debug(f"Skipping already processed calendar event: {event_id}")
                continue

            new_events += 1
            logging.info(f"Processing new calendar event {new_events}: {event_id}")

            # Generate device_id based on calendar
            calendar_name = event_data.get("calendar_name", "default")
            device_id = f"calendar-fetcher-{calendar_name.lower().replace(' ', '-')}"

            # Handle timestamps - convert to datetime if needed
            start_time = event_data.get("start_time")
            end_time = event_data.get("end_time")

            if isinstance(start_time, str):
                try:
                    start_time = datetime.fromisoformat(
                        start_time.replace("Z", "+00:00")
                    )
                except ValueError:
                    start_time = datetime.utcnow()

            if isinstance(end_time, str):
                try:
                    end_time = datetime.fromisoformat(end_time.replace("Z", "+00:00"))
                except ValueError:
                    end_time = start_time if start_time else datetime.utcnow()

            # Convert to database schema format
            db_event = {
                "device_id": device_id,
                "timestamp": datetime.utcnow(),
                "schema_version": "v1",
                "event_id": event_id or f"cal-{int(datetime.utcnow().timestamp())}",
                "calendar_id": event_data.get("calendar_id", calendar_name),
                "title": event_data.get("title", "No Title"),
                "description": event_data.get("description"),
                "location": event_data.get("location"),
                "start_time": start_time or datetime.utcnow(),
                "end_time": end_time or datetime.utcnow(),
                "all_day": event_data.get("all_day", False),
                "recurring_rule": event_data.get("recurring_rule"),
                "attendees": event_data.get("attendees"),
                "organizer_email": event_data.get("organizer_email"),
                "status": event_data.get("status", "confirmed"),
                "visibility": event_data.get("visibility"),
                "reminders": event_data.get("reminders"),
                "conference_data": event_data.get("conference_data"),
                "color_id": event_data.get("color_id"),
                "last_modified": event_data.get("last_modified"),
                "metadata": {
                    "content_hash": event_data.get("content_hash"),
                    "calendar_name": calendar_name,
                    "calendar_index": event_data.get("calendar_index"),
                    "fetched_at": datetime.utcnow().isoformat(),
                },
            }
            db_events.append(db_event)

        # Write events to database in batch
        if db_events:
            written_count = await db_writer.write_calendar_events_batch(db_events)
            logging.info(
                f"Successfully wrote {written_count}/{len(db_events)} calendar events to database"
            )
        else:
            logging.info("No new calendar events to write")

        logging.info(
            f"Fetch completed - Total found: {len(events)}, "
            f"New: {new_events}, Skipped (already processed): {skipped_events}"
        )

    except Exception as e:
        logging.error(f"Error in calendar fetch process: {e}")
    finally:
        if db_writer:
            await db_writer.close()


def run_async_fetch():
    """Wrapper to run async function in scheduler"""
    asyncio.run(fetch_calendar_events())


def main():
    """Main application entry point"""
    logging.info("Calendar fetcher service starting...")

    # Get fetch interval from environment (default 30 minutes)
    fetch_interval = int(os.getenv("LOOM_CALENDAR_FETCH_INTERVAL_MINUTES", "30"))
    run_on_startup = os.getenv("LOOM_CALENDAR_RUN_ON_STARTUP", "true").lower() == "true"

    # Schedule calendar fetching
    schedule.every(fetch_interval).minutes.do(run_async_fetch)
    logging.info(f"Scheduled calendar fetching every {fetch_interval} minutes")

    # Run immediately on startup if configured
    if run_on_startup:
        run_async_fetch()

    # Keep the service running
    while True:
        schedule.run_pending()
        time.sleep(60)


if __name__ == "__main__":
    main()
