"""Geocoding service with caching and rate limiting"""

import time
from typing import Optional, Dict, Any
from datetime import datetime
from geopy.distance import distance as geopy_distance
from opencage.geocoder import OpenCageGeocode
from sqlalchemy.orm import Session
from sqlalchemy import and_
import structlog

from .models import CachedGeocoding
from .config import settings

logger = structlog.get_logger()


class GeocodingService:
    def __init__(self):
        self.geocoder = (
            OpenCageGeocode(settings.opencage_api_key)
            if settings.opencage_api_key
            else None
        )
        self.last_api_call = 0.0
        self.daily_calls = 0
        self.daily_reset = datetime.utcnow().date()
        self.first_point_processed = False

    def _reset_daily_counter_if_needed(self):
        """Reset daily call counter if it's a new day"""
        today = datetime.utcnow().date()
        if today > self.daily_reset:
            self.daily_calls = 0
            self.daily_reset = today
            logger.info("Reset daily API call counter", date=str(today))

    def _enforce_rate_limit(self):
        """Enforce 1 request per second rate limit"""
        now = time.time()
        time_since_last = now - self.last_api_call
        if time_since_last < settings.opencage_rate_limit:
            sleep_time = settings.opencage_rate_limit - time_since_last
            logger.debug("Rate limiting", sleep_seconds=sleep_time)
            time.sleep(sleep_time)
        self.last_api_call = time.time()

    def _can_make_api_call(self) -> bool:
        """Check if we can make an API call within limits"""
        self._reset_daily_counter_if_needed()
        return self.daily_calls < settings.opencage_daily_limit

    def _calculate_distance(
        self, lat1: float, lon1: float, lat2: float, lon2: float
    ) -> float:
        """Calculate distance between two points in meters"""
        return geopy_distance((lat1, lon1), (lat2, lon2)).meters

    def _find_cached_location(
        self, session: Session, latitude: float, longitude: float
    ) -> Optional[CachedGeocoding]:
        """Find a cached location within the cache radius"""
        # Simple bounding box search (approximation)
        # 1 degree latitude ≈ 111 km
        # 1 degree longitude varies by latitude, but we'll use a simple approximation
        lat_delta = settings.cache_radius_meters / 111000.0
        lon_delta = settings.cache_radius_meters / (
            111000.0 * abs(latitude + 0.001)
        )  # Avoid division by zero

        cached_locations = (
            session.query(CachedGeocoding)
            .filter(
                and_(
                    CachedGeocoding.latitude.between(
                        latitude - lat_delta, latitude + lat_delta
                    ),
                    CachedGeocoding.longitude.between(
                        longitude - lon_delta, longitude + lon_delta
                    ),
                )
            )
            .all()
        )

        # Find the closest one within cache radius
        closest = None
        min_distance = float("inf")

        for location in cached_locations:
            dist = self._calculate_distance(
                latitude, longitude, location.latitude, location.longitude
            )
            if dist <= settings.cache_radius_meters and dist < min_distance:
                min_distance = dist
                closest = location

        if closest:
            logger.debug(
                "Found cached location",
                distance_meters=min_distance,
                cached_id=closest.id,
            )

        return closest

    def _should_process_location(
        self, session: Session, latitude: float, longitude: float
    ) -> bool:
        """Determine if we should process this location"""
        # Always process the first point after startup
        if not self.first_point_processed:
            logger.info("Processing first GPS point after startup")
            return True

        # Find all cached locations to check distance
        all_cached = session.query(CachedGeocoding).all()

        if not all_cached:
            logger.info("No cached locations found, processing new point")
            return True

        # Check if this point is significantly far from all cached points
        for cached in all_cached:
            dist = self._calculate_distance(
                latitude, longitude, cached.latitude, cached.longitude
            )
            if dist <= settings.min_distance_meters:
                logger.debug(
                    "Location too close to cached point",
                    distance_meters=dist,
                    min_required=settings.min_distance_meters,
                )
                return False

        logger.info("Location is far enough from all cached points, processing")
        return True

    def geocode_location(
        self, session: Session, latitude: float, longitude: float
    ) -> Optional[Dict[str, Any]]:
        """Geocode a location with caching"""
        # Check cache first
        cached = self._find_cached_location(session, latitude, longitude)
        if cached:
            # Update usage stats
            cached.last_used_at = datetime.utcnow()
            cached.use_count += 1
            session.commit()

            logger.info(
                "Using cached geocoding result",
                cached_id=cached.id,
                use_count=cached.use_count,
            )

            self.first_point_processed = True
            return {
                "address": cached.geocoded_address,
                "city": cached.city,
                "state": cached.state,
                "country": cached.country,
                "postal_code": cached.postal_code,
                "place_name": cached.place_name,
                "place_type": cached.place_type,
                "provider": "opencage",
                "cached": True,
                "cache_id": cached.id,
            }

        # Check if we should process this location
        if not self._should_process_location(session, latitude, longitude):
            logger.debug(
                "Skipping geocoding for location",
                latitude=latitude,
                longitude=longitude,
            )
            self.first_point_processed = True
            return None

        # Check API limits
        if not self._can_make_api_call():
            logger.warning(
                "Daily API limit reached",
                daily_calls=self.daily_calls,
                daily_limit=settings.opencage_daily_limit,
            )
            return None

        # No cache hit and we should process - make API call
        if not self.geocoder:
            logger.warning("OpenCage API key not configured")
            return None

        try:
            self._enforce_rate_limit()

            logger.info(
                "Making OpenCage API call", latitude=latitude, longitude=longitude
            )

            results = self.geocoder.reverse_geocode(latitude, longitude)
            self.daily_calls += 1
            self.first_point_processed = True

            if not results:
                logger.warning("No geocoding results returned")
                return None

            result = results[0]
            components = result.get("components", {})

            # Extract relevant fields
            geocoded_data = {
                "address": result.get("formatted"),
                "city": components.get("city")
                or components.get("town")
                or components.get("village"),
                "state": components.get("state") or components.get("province"),
                "country": components.get("country"),
                "postal_code": components.get("postcode"),
                "place_name": components.get("neighbourhood")
                or components.get("suburb"),
                "place_type": components.get("_type"),
                "provider": "opencage",
                "cached": False,
            }

            # Save to cache
            cached_location = CachedGeocoding(
                latitude=latitude,
                longitude=longitude,
                geocoded_address=geocoded_data["address"],
                city=geocoded_data["city"],
                state=geocoded_data["state"],
                country=geocoded_data["country"],
                postal_code=geocoded_data["postal_code"],
                place_name=geocoded_data["place_name"],
                place_type=geocoded_data["place_type"],
                raw_response=result,
            )

            session.add(cached_location)
            session.commit()

            logger.info(
                "Geocoded and cached location",
                address=geocoded_data["address"],
                cache_id=cached_location.id,
                daily_calls=self.daily_calls,
            )

            geocoded_data["cache_id"] = cached_location.id
            return geocoded_data

        except Exception as e:
            logger.error("Geocoding error", error=str(e))
            return None
