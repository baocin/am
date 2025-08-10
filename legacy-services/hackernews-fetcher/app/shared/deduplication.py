"""
Loom v2 Content Hashing and Deduplication Module

Implements the universal deduplication strategy as defined in docs/syncing-dedupe-strategy.md
This module provides consistent content hashing across all data types in the Loom ecosystem.
"""

import hashlib
import re
from datetime import datetime
from typing import Any, Optional, Union


class ContentHasher:
    """Universal content hasher for Loom v2 deduplication"""

    VERSION = "v1"

    @staticmethod
    def normalize_text(text: str) -> str:
        """
        Normalize text for consistent hashing.
        Preserves content but normalizes whitespace.
        """
        if not text:
            return ""
        # Collapse multiple spaces and strip
        text = " ".join(text.split())
        text = text.strip()
        # Do NOT lowercase - preserves information
        return text

    @staticmethod
    def normalize_phone(phone: str) -> str:
        """Convert phone number to E.164 format"""
        if not phone:
            return ""
        # Remove all non-digits
        digits = re.sub(r"\D", "", phone)

        # Handle country codes (example for US)
        if len(digits) == 10:
            return f"+1{digits}"
        elif len(digits) == 11 and digits[0] == "1":
            return f"+{digits}"
        else:
            # Keep as-is if format unclear
            return f"+{digits}"

    @staticmethod
    def normalize_timestamp(ts: Any) -> int:
        """Convert any timestamp to Unix milliseconds (UTC)"""
        if ts is None:
            return 0

        if isinstance(ts, int):
            # Assume Unix timestamp
            if ts < 10000000000:  # Seconds
                return ts * 1000
            return ts  # Already milliseconds
        elif isinstance(ts, str):
            # Parse ISO format
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            return int(dt.timestamp() * 1000)
        elif isinstance(ts, datetime):
            return int(ts.timestamp() * 1000)
        else:
            # Try to convert to datetime
            try:
                if hasattr(ts, "isoformat"):
                    return int(ts.timestamp() * 1000)
            except Exception:
                pass
            return 0

    @staticmethod
    def normalize_id(id_value: str) -> str:
        """Normalize IDs while preserving structure"""
        if not id_value:
            return ""
        # Keep alphanumeric + common ID chars
        # Preserve: letters, numbers, dash, underscore, colon
        return re.sub(r"[^a-zA-Z0-9\-_:]", "", str(id_value))

    @staticmethod
    def normalize_url(url: str) -> str:
        """Normalize URL for consistent hashing"""
        from urllib.parse import urlparse, urlunparse

        if not url:
            return ""

        parsed = urlparse(url.lower())
        # Remove fragment, normalize host
        normalized = urlunparse(
            (
                parsed.scheme,
                parsed.netloc,
                parsed.path.rstrip("/"),
                parsed.params,
                parsed.query,
                "",  # Remove fragment
            )
        )
        return normalized

    @staticmethod
    def normalize_mac(mac: str) -> str:
        """Normalize MAC address format"""
        if not mac:
            return ""
        # Remove all separators and uppercase
        mac_clean = re.sub(r"[:\-\.]", "", mac).upper()
        # Format as XX:XX:XX:XX:XX:XX
        if len(mac_clean) == 12:
            return ":".join(mac_clean[i : i + 2] for i in range(0, 12, 2))
        return mac_clean

    def _sha256(self, content: str) -> str:
        """Generate SHA-256 hash of content"""
        return hashlib.sha256(content.encode("utf-8")).hexdigest()

    def generate_sms_hash(
        self, phone: str, timestamp: Any, body: str, thread_id: Optional[int] = None
    ) -> str:
        """Generate hash for SMS message"""
        phone = self.normalize_phone(phone)
        timestamp = self.normalize_timestamp(timestamp)
        body = self.normalize_text(body)
        thread_id_str = str(thread_id) if thread_id is not None else ""

        content = f"sms:{self.VERSION}:{phone}:{timestamp}:{body}:{thread_id_str}"
        return self._sha256(content)

    def generate_email_hash(
        self,
        message_id: Optional[str] = None,
        from_address: Optional[str] = None,
        to_address: Optional[Union[str, list]] = None,
        date: Optional[Any] = None,
        subject: Optional[str] = None,
    ) -> str:
        """Generate hash for email with fallback strategies"""
        # Strategy 1: Use Message-ID (most reliable)
        if message_id:
            message_id = self.normalize_id(message_id)
            content = f"email:{self.VERSION}:msgid:{message_id}"
            return self._sha256(content)

        # Strategy 2: Use immutable headers
        if from_address and date:
            from_addr = from_address.lower().strip()
            subject_norm = self.normalize_text(subject or "")
            date_unix = self.normalize_timestamp(date)

            # Include recipient for uniqueness
            to_addr = ""
            if to_address:
                if isinstance(to_address, list) and to_address:
                    to_addr = to_address[0].lower().strip()
                elif isinstance(to_address, str):
                    to_addr = to_address.lower().strip()

            content = f"email:{self.VERSION}:headers:{from_addr}:{to_addr}:{date_unix}:{subject_norm}"
            return self._sha256(content)

        raise ValueError("Insufficient data to generate email hash")

    def generate_calendar_hash(
        self,
        uid: Optional[str] = None,
        start_time: Optional[Any] = None,
        end_time: Optional[Any] = None,
        title: Optional[str] = None,
        location: Optional[str] = None,
        organizer: Optional[str] = None,
    ) -> str:
        """Generate hash for calendar events"""
        # Strategy 1: Use iCalendar UID (RFC 5545)
        if uid:
            uid = self.normalize_id(uid)
            content = f"cal:{self.VERSION}:uid:{uid}"
            return self._sha256(content)

        # Strategy 2: Use event properties
        if start_time and end_time and title:
            start_unix = self.normalize_timestamp(start_time)
            end_unix = self.normalize_timestamp(end_time)
            title_norm = self.normalize_text(title)
            location_norm = self.normalize_text(location or "")

            # Include organizer for uniqueness
            organizer_norm = organizer.lower().strip() if organizer else ""

            content = f"cal:{self.VERSION}:event:{start_unix}:{end_unix}:{title_norm}:{location_norm}:{organizer_norm}"
            return self._sha256(content)

        raise ValueError("Insufficient data to generate calendar hash")

    def generate_browser_history_hash(self, url: str, visit_time: Any) -> str:
        """Generate hash for browser history entries"""
        url_norm = self.normalize_url(url)
        visit_unix = self.normalize_timestamp(visit_time)

        content = f"browser:{self.VERSION}:{url_norm}:{visit_unix}"
        return self._sha256(content)

    def generate_app_usage_hash(
        self, package_name: str, event_type: str, timestamp: Any, duration_ms: int = 0
    ) -> str:
        """Generate hash for app usage events"""
        timestamp_unix = self.normalize_timestamp(timestamp)

        content = f"appusage:{self.VERSION}:{package_name}:{event_type}:{timestamp_unix}:{duration_ms}"
        return self._sha256(content)

    def generate_location_hash(
        self,
        latitude: float,
        longitude: float,
        timestamp: Any,
        accuracy: Optional[float] = None,
    ) -> str:
        """Generate hash for GPS location points"""
        # Round to ~11m precision to handle GPS drift
        lat = round(latitude, 4)
        lon = round(longitude, 4)
        timestamp_unix = self.normalize_timestamp(timestamp)

        # Include accuracy for filtering
        accuracy_rounded = round(accuracy, 0) if accuracy else 0

        content = (
            f"location:{self.VERSION}:{lat}:{lon}:{timestamp_unix}:{accuracy_rounded}"
        )
        return self._sha256(content)

    def generate_wifi_hash(
        self, bssid: str, ssid: str, timestamp: Any, is_connected: bool = False
    ) -> str:
        """Generate hash for WiFi network observations"""
        bssid_norm = self.normalize_mac(bssid)
        timestamp_unix = self.normalize_timestamp(timestamp)
        ssid_norm = self.normalize_text(ssid)

        # Include connection state for context
        connected_flag = "1" if is_connected else "0"

        content = f"wifi:{self.VERSION}:{bssid_norm}:{ssid_norm}:{timestamp_unix}:{connected_flag}"
        return self._sha256(content)

    def generate_bluetooth_hash(
        self,
        bluetooth_mac: str,
        timestamp: Any,
        is_connected: bool = False,
        is_paired: bool = False,
    ) -> str:
        """Generate hash for Bluetooth device observations"""
        mac_norm = self.normalize_mac(bluetooth_mac)
        timestamp_unix = self.normalize_timestamp(timestamp)

        # Include connection state
        connected_flag = "1" if is_connected else "0"
        paired_flag = "1" if is_paired else "0"

        content = f"bluetooth:{self.VERSION}:{mac_norm}:{timestamp_unix}:{connected_flag}:{paired_flag}"
        return self._sha256(content)

    def generate_notification_hash(
        self,
        app_identifier: str,
        timestamp: Any,
        notification_id: Optional[str] = None,
        title: Optional[str] = None,
        body: Optional[str] = None,
    ) -> str:
        """Generate hash for system notifications"""
        timestamp_unix = self.normalize_timestamp(timestamp)
        app_id = self.normalize_id(app_identifier)

        # Use notification ID if available, otherwise hash content
        if notification_id:
            notif_id = self.normalize_id(notification_id)
            content = (
                f"notification:{self.VERSION}:{app_id}:{notif_id}:{timestamp_unix}"
            )
        else:
            # Fallback for systems without notification IDs
            title_norm = self.normalize_text(title or "")
            body_norm = self.normalize_text(body or "")
            content_hash = hashlib.sha256(
                f"{title_norm}:{body_norm}".encode("utf-8")
            ).hexdigest()[:16]
            content = (
                f"notification:{self.VERSION}:{app_id}:{timestamp_unix}:{content_hash}"
            )

        return self._sha256(content)

    def generate_generic_hash(self, data_type: str, **kwargs) -> str:
        """
        Generate hash for any data type based on type string.
        This is a convenience method that routes to the appropriate hash function.
        """
        hash_methods = {
            "sms": self.generate_sms_hash,
            "email": self.generate_email_hash,
            "calendar": self.generate_calendar_hash,
            "browser_history": self.generate_browser_history_hash,
            "app_usage": self.generate_app_usage_hash,
            "location": self.generate_location_hash,
            "wifi": self.generate_wifi_hash,
            "bluetooth": self.generate_bluetooth_hash,
            "notification": self.generate_notification_hash,
        }

        if data_type not in hash_methods:
            raise ValueError(f"Unknown data type: {data_type}")

        return hash_methods[data_type](**kwargs)


# Singleton instance for easy import
content_hasher = ContentHasher()
