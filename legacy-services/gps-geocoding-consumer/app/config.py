"""Configuration for GPS Geocoding Consumer"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Kafka Configuration
    kafka_bootstrap_servers: str = "localhost:9092"
    kafka_consumer_group_id: str = "gps-geocoding-consumer"
    kafka_input_topic: str = "device.sensor.gps.raw"
    kafka_output_topic: str = "location.address.geocoded"

    # Database Configuration
    database_url: str = "postgresql://loom:loom@localhost:5432/loom"

    # OpenCage API Configuration
    opencage_api_key: str = ""
    opencage_rate_limit: float = 1.0  # requests per second
    opencage_daily_limit: int = 2500  # requests per day

    # Geocoding Configuration
    min_distance_meters: float = 10.0  # Minimum distance to consider a new location
    cache_radius_meters: float = 10.0  # Radius to search for cached locations

    # Service Configuration
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"

    class Config:
        env_prefix = "LOOM_"
        case_sensitive = False


settings = Settings()
