"""Database models for GPS geocoding cache"""
from sqlalchemy import Column, BigInteger, Float, String, DateTime, Integer, JSON, UniqueConstraint, Index
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from datetime import datetime

Base = declarative_base()


class CachedGeocoding(Base):
    __tablename__ = 'cached_geocoding'
    
    id = Column(BigInteger, primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    geocoded_address = Column(String)
    city = Column(String)
    state = Column(String)
    country = Column(String)
    postal_code = Column(String)
    place_name = Column(String)
    place_type = Column(String)
    raw_response = Column(JSON)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_used_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    use_count = Column(Integer, server_default='1', nullable=False)
    
    __table_args__ = (
        UniqueConstraint('latitude', 'longitude', name='uq_cached_geocoding_coords'),
        Index('idx_cached_geocoding_coords', 'latitude', 'longitude'),
        Index('idx_cached_geocoding_last_used', 'last_used_at'),
    )