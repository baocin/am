import caldav
from datetime import datetime, timedelta
import os
import logging
import requests
from typing import List, Dict, Any
from shared.deduplication import content_hasher
from ical_fetcher import ICalFetcher


class CalendarFetcher:
    def __init__(self):
        """Initialize calendar fetcher with account configurations"""
        self.accounts = self._load_accounts()
        self.processed_events = set()  # Keep track of processed events in memory
        self.nominatim_base_url = os.getenv(
            "LOOM_NOMINATIM_BASE_URL", "http://localhost:8080"
        )
        self.enable_gps_lookup = (
            os.getenv("LOOM_CALENDAR_ENABLE_GPS_LOOKUP", "true").lower() == "true"
        )

    def _load_accounts(self) -> List[Dict[str, Any]]:
        """Load calendar accounts from environment variables"""
        all_accounts = []

        # Support up to 10 calendar accounts
        max_accounts = int(os.getenv("LOOM_CALENDAR_MAX_ACCOUNTS", "10"))
        for i in range(1, max_accounts + 1):
            # Check for iCal URL first
            ical_url_env = f"LOOM_ICAL_URL_{i}"
            ical_url = os.getenv(ical_url_env)
            
            if ical_url:
                # iCal account (no auth needed)
                account = {
                    "type": "ical",
                    "url": ical_url,
                    "name": os.getenv(f"LOOM_ICAL_NAME_{i}", f"iCal Calendar {i}"),
                    "disabled": os.getenv(f"LOOM_ICAL_DISABLED_{i}", "false").lower() == "true",
                    "index": i
                }
                if not account["disabled"]:
                    all_accounts.append(account)
                    logging.info(f"Loaded iCal account: {account['name']}")
            else:
                # Check for CalDAV account
                url_env = f"LOOM_CALDAV_URL_{i}"
                username_env = f"LOOM_CALDAV_USERNAME_{i}"
                password_env = f"LOOM_CALDAV_PASSWORD_{i}"
                disabled_env = f"LOOM_CALDAV_DISABLED_{i}"
                name_env = f"LOOM_CALDAV_NAME_{i}"

                url = os.getenv(url_env)
                if not url:
                    continue

                account = {
                    "type": "caldav",
                    "url": url,
                    "username": os.getenv(username_env),
                    "password": os.getenv(password_env),
                    "disabled": os.getenv(disabled_env, "false").lower() == "true",
                    "name": os.getenv(name_env, f"Calendar {i}"),
                    "index": i
                }

                if not account["disabled"] and account["username"] and account["password"]:
                    all_accounts.append(account)
                    logging.info(f"Loaded CalDAV account: {account['name']}")

        logging.info(f"Loaded {len(all_accounts)} total calendar accounts")
        return all_accounts

    def fetch_all_calendar_events(self) -> List[Dict[str, Any]]:
        """Fetch calendar events from all configured accounts"""
        all_events = []

        for account in self.accounts:
            try:
                if account["type"] == "ical":
                    events = self._fetch_ical_events(account)
                else:  # caldav
                    events = self._fetch_caldav_events(account)
                
                # Add account info to each event
                for event in events:
                    event["calendar_index"] = account["index"]
                    event["calendar_name"] = account["name"]
                
                all_events.extend(events)
            except Exception as e:
                account_identifier = account.get('username', account.get('name', 'Unknown'))
                logging.error(
                    f"Error fetching calendar events for {account_identifier}: {e}"
                )

        return all_events

    def _fetch_ical_events(self, account: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Fetch events from an iCal URL"""
        try:
            # Get time range from environment
            days_past = int(os.getenv("LOOM_CALENDAR_DAYS_PAST", "30"))
            days_future = int(os.getenv("LOOM_CALENDAR_DAYS_FUTURE", "365"))
            
            # Create iCal fetcher
            fetcher = ICalFetcher(account["url"], account["name"])
            
            # Fetch events
            events = fetcher.fetch_events(days_past, days_future)
            
            # Process events for Kafka
            processed_events = []
            for event in events:
                # Add GPS lookup if enabled and location is present
                if self.enable_gps_lookup and event.get("location"):
                    gps_point = self._get_location_coordinates(event["location"])
                    if gps_point:
                        event["gps_point"] = gps_point
                
                # Add source account info
                event["source_account"] = account["name"]
                event["account_name"] = account["name"]
                
                processed_events.append(event)
            
            logging.info(f"Fetched {len(processed_events)} events from iCal: {account['name']}")
            return processed_events
            
        except Exception as e:
            logging.error(f"Error fetching iCal events from {account['name']}: {e}")
            return []
    
    def _fetch_caldav_events(self, account: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Fetch events from a single CalDAV account"""
        events = []

        try:
            client = caldav.DAVClient(
                url=account["url"],
                username=account["username"],
                password=account["password"],
            )
            principal = client.principal()
            calendars = principal.calendars()

            logging.info(
                f"Fetching events for {account['username']} from {len(calendars)} calendars"
            )

            for calendar in calendars:
                try:
                    # Get time range from environment
                    days_past = int(os.getenv("LOOM_CALENDAR_DAYS_PAST", "30"))
                    days_future = int(os.getenv("LOOM_CALENDAR_DAYS_FUTURE", "365"))

                    calendar_events = calendar.search(
                        start=datetime.now() - timedelta(days=days_past),
                        end=datetime.now() + timedelta(days=days_future),
                        event=True,
                    )

                    for event in calendar_events:
                        try:
                            event_data = self._parse_event(event, account, calendar)
                            if event_data:
                                # Use content hash for deduplication
                                content_hash = event_data.get("content_hash")
                                if (
                                    content_hash
                                    and content_hash not in self.processed_events
                                ):
                                    events.append(event_data)
                                    self.processed_events.add(content_hash)
                                    logging.debug(
                                        f"Added event with hash: {content_hash[:16]}..."
                                    )
                        except Exception as e:
                            logging.error(f"Error parsing event: {e}")

                except Exception as e:
                    logging.error(f"Error searching calendar {calendar.name}: {e}")

        except Exception as e:
            logging.error(f"CalDAV connection error for {account['username']}: {e}")

        return events

    def _parse_event(self, event, account: Dict[str, Any], calendar) -> Dict[str, Any]:
        """Parse individual calendar event"""
        try:
            vevent = event.vobject_instance.vevent

            # Generate unique event ID
            event_id = f"{calendar.url}_{vevent.uid.value}"

            # Extract basic information
            summary = getattr(vevent, "summary", None)
            summary = summary.value if summary else "No Title"

            description = getattr(vevent, "description", None)
            description = description.value if description else ""

            location = getattr(vevent, "location", None)
            location = location.value if location else ""

            # Extract dates
            start_time = getattr(vevent, "dtstart", None)
            start_time = start_time.value if start_time else None

            end_time = getattr(vevent, "dtend", None)
            end_time = end_time.value if end_time else None

            # Convert datetime objects to timestamps
            if start_time and hasattr(start_time, "isoformat"):
                start_time = start_time
            elif start_time:
                start_time = datetime.combine(start_time, datetime.min.time())

            if end_time and hasattr(end_time, "isoformat"):
                end_time = end_time
            elif end_time:
                end_time = datetime.combine(end_time, datetime.min.time())

            # Get GPS coordinates for location if available and enabled
            gps_point = None
            if location and self.enable_gps_lookup:
                gps_point = self._get_location_coordinates(location)

            # Extract organizer if available
            organizer = getattr(vevent, "organizer", None)
            organizer_email = None
            if organizer:
                # Organizer can be in format "MAILTO:email@example.com"
                organizer_value = (
                    organizer.value if hasattr(organizer, "value") else str(organizer)
                )
                if organizer_value.startswith("MAILTO:"):
                    organizer_email = organizer_value[7:]  # Remove "MAILTO:" prefix
                else:
                    organizer_email = organizer_value

            # Generate content hash for deduplication
            try:
                # Try to use the iCalendar UID first
                uid = getattr(vevent, "uid", None)
                uid_value = uid.value if uid and hasattr(uid, "value") else None

                content_hash = content_hasher.generate_calendar_hash(
                    uid=uid_value,
                    start_time=start_time,
                    end_time=end_time,
                    title=summary,
                    location=location,
                    organizer=organizer_email,
                )
            except Exception as e:
                logging.warning(f"Failed to generate content hash for event: {e}")
                # Use event_id as fallback hash
                content_hash = content_hasher._sha256(event_id)

            return {
                "event_id": event_id,
                "source_calendar": f"{account['name']} - {calendar.name}",
                "summary": summary,
                "description": description,
                "location": location,
                "start_time": start_time,
                "end_time": end_time,
                "gps_point": gps_point,
                "source_account": account["username"],
                "account_name": account["name"],
                "organizer": organizer_email,
                "uid": uid_value,
                "content_hash": content_hash,
            }

        except Exception as e:
            logging.error(f"Error parsing event details: {e}")
            return None

    def _get_location_coordinates(self, location: str) -> str:
        """Get GPS coordinates for a location using Nominatim"""
        try:
            if not self.nominatim_base_url or not location:
                return None

            endpoint = "/search"
            params = {"q": location, "format": "json", "limit": 1}

            response = requests.get(
                self.nominatim_base_url + endpoint, params=params, timeout=5
            )

            if response.status_code == 200:
                data = response.json()
                if data:
                    lat = data[0]["lat"]
                    lon = data[0]["lon"]
                    gps_point = f"POINT({lon} {lat})"
                    logging.debug(f"GPS point for location '{location}': {gps_point}")
                    return gps_point
            else:
                logging.warning(
                    f"Nominatim request failed with status {response.status_code}"
                )

        except Exception as e:
            logging.error(f"Error fetching GPS coordinates for '{location}': {e}")

        return None
