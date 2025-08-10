"""
iCal URL fetcher module for calendar-fetcher service
Supports fetching calendars from HTTP(S) iCal/ICS URLs
"""
import logging
import hashlib
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any, Optional
import requests
from icalendar import Calendar
from dateutil import parser
from dateutil.tz import tzutc

logger = logging.getLogger(__name__)


class ICalFetcher:
    """Fetches calendar events from iCal URLs"""
    
    def __init__(self, url: str, name: str = "iCal Calendar"):
        self.url = url
        self.name = name
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Loom Calendar Fetcher/1.0'
        })
    
    def fetch_events(self, days_past: int = 30, days_future: int = 365) -> List[Dict[str, Any]]:
        """
        Fetch events from iCal URL within the specified time range
        
        Args:
            days_past: Number of days in the past to fetch
            days_future: Number of days in the future to fetch
            
        Returns:
            List of event dictionaries
        """
        try:
            # Calculate time range
            now = datetime.now(timezone.utc)
            start_date = now - timedelta(days=days_past)
            end_date = now + timedelta(days=days_future)
            
            logger.info(f"Fetching iCal from {self.url}")
            
            # Handle webcal:// URLs by converting to https://
            fetch_url = self.url.replace('webcal://', 'https://')
            
            # Fetch the iCal data
            response = self.session.get(fetch_url, timeout=30)
            response.raise_for_status()
            
            # Parse the calendar
            cal = Calendar.from_ical(response.content)
            
            events = []
            for component in cal.walk():
                if component.name == "VEVENT":
                    event = self._parse_event(component, start_date, end_date)
                    if event:
                        events.append(event)
            
            logger.info(f"Fetched {len(events)} events from {self.name}")
            return events
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch iCal from {self.url}: {e}")
            return []
        except Exception as e:
            logger.error(f"Error parsing iCal data from {self.url}: {e}")
            return []
    
    def _parse_event(self, vevent, start_date: datetime, end_date: datetime) -> Optional[Dict[str, Any]]:
        """Parse a VEVENT component into our event format"""
        try:
            # Get event times
            dtstart = vevent.get('dtstart')
            dtend = vevent.get('dtend')
            
            if not dtstart:
                return None
            
            # Convert to datetime if needed
            start_time = self._to_datetime(dtstart.dt)
            end_time = self._to_datetime(dtend.dt) if dtend else start_time + timedelta(hours=1)
            
            # Check if event is within our time range
            if start_time < start_date or start_time > end_date:
                return None
            
            # Extract event data
            summary = str(vevent.get('summary', ''))
            description = str(vevent.get('description', ''))
            location = str(vevent.get('location', ''))
            uid = str(vevent.get('uid', ''))
            
            # Extract organizer
            organizer = vevent.get('organizer')
            if organizer:
                organizer_email = str(organizer).replace('mailto:', '')
            else:
                organizer_email = None
            
            # Extract attendees
            attendees = []
            for attendee in vevent.get('attendee', []):
                attendee_email = str(attendee).replace('mailto:', '')
                attendees.append(attendee_email)
            
            # Generate a unique event ID
            event_id = uid if uid else self._generate_event_id(
                start_time, end_time, summary, location
            )
            
            # Generate content hash for deduplication
            content_hash = self._generate_content_hash(
                start_time, end_time, summary, location, organizer_email
            )
            
            return {
                'event_id': event_id,
                'source_calendar': self.name,
                'summary': summary,
                'description': description,
                'location': location,
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat(),
                'organizer': organizer_email,
                'attendees': attendees,
                'uid': uid,
                'content_hash': content_hash,
                'source_url': self.url
            }
            
        except Exception as e:
            logger.warning(f"Failed to parse event: {e}")
            return None
    
    def _to_datetime(self, dt) -> datetime:
        """Convert various date formats to datetime with timezone"""
        if isinstance(dt, datetime):
            if dt.tzinfo is None:
                # Assume UTC for naive datetimes
                return dt.replace(tzinfo=timezone.utc)
            return dt
        elif isinstance(dt, str):
            parsed = parser.parse(dt)
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed
        else:
            # Handle date objects by converting to datetime at midnight UTC
            return datetime.combine(dt, datetime.min.time()).replace(tzinfo=timezone.utc)
    
    def _generate_event_id(self, start_time: datetime, end_time: datetime, 
                          summary: str, location: str) -> str:
        """Generate a unique event ID based on event properties"""
        id_parts = [
            start_time.isoformat(),
            end_time.isoformat(),
            summary,
            location,
            self.url
        ]
        id_string = '|'.join(str(p) for p in id_parts)
        return hashlib.sha256(id_string.encode()).hexdigest()[:16]
    
    def _generate_content_hash(self, start_time: datetime, end_time: datetime,
                              summary: str, location: str, organizer: Optional[str]) -> str:
        """Generate a content hash for deduplication"""
        hash_parts = [
            start_time.isoformat(),
            end_time.isoformat(),
            summary.lower().strip(),
            location.lower().strip(),
            (organizer or '').lower().strip()
        ]
        hash_string = '|'.join(str(p) for p in hash_parts)
        return hashlib.sha256(hash_string.encode()).hexdigest()