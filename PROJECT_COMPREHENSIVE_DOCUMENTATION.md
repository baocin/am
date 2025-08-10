# AM (Allied Mastercomputer) - Comprehensive Project Documentation

## Table of Contents
1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [Data Flow Architecture](#data-flow-architecture)
4. [Authentication & Security](#authentication--security)
5. [Docker Container Infrastructure](#docker-container-infrastructure)
6. [Storage Layer](#storage-layer)
7. [Processing Pipeline](#processing-pipeline)
8. [Client Implementation](#client-implementation)
9. [Client Device Tracking & Notifications](#client-device-tracking--notifications)
10. [Complete Data Types & Inputs Catalog](#complete-data-types--inputs-catalog)
11. [Multi-Tenancy & Scaling](#multi-tenancy--scaling)
12. [Anomaly Detection System](#anomaly-detection-system)
13. [Deployment & Operations](#deployment--operations)

---

## Project Overview

### What is AM?
AM (Allied Mastercomputer) is a privacy-first, local-first system that aggregates, processes, and analyzes *all* available timeseries data from devices and digital life. It acts as a "second brain" that:
- Records life context passively
- Derives high-level insights from multi-modal data
- Provides proactive notifications and nudges
- Evolves into a DSPy-powered LLM agent for autonomous actions

### Core Principles
- **Local-First**: No cloud dependencies; all processing on-device or self-hosted
- **Privacy-Centric**: Encrypted storage, user-configurable data retention, no tracking
- **Extensible**: Plug in new ML models for custom analysis
- **Ambitious but Phased**: Start with data ingestion, build to full agent intelligence

### Licensing
- **Individual Use**: AGPL-3.0 License (free for personal use)
- **Commercial Use**: Commercial License Required (contact: loom@steele.red)

---

## System Architecture

### Technology Stack
- **Protocol**: gRPC with Protocol Buffers v3
- **Languages**: Go (services), Python (ML processors), Kotlin/Dart (clients)
- **Message Queue**: NATS JetStream
- **Database**: TimescaleDB with pgvector extension
- **Observability**: OpenTelemetry + Prometheus + Jaeger
- **Container**: Docker + Kubernetes/k3s
- **Storage**: MinIO for S3-compatible object storage

### High-Level Architecture
```
[Client Devices] → [gRPC] → [Go API Server] → [NATS JetStream] → [Data Router]
                                    ↓                                    ↓
                            [OpenTelemetry]                    [Processing Services]
                                    ↓                                    ↓
                                [Jaeger]                          [TimescaleDB]
                                                                        ↓
                                                                [Analytics/Agent]
```

### Performance Characteristics
- **Ingestion**: 10,000+ messages/second per API instance
- **Processing**: 100-1,000 messages/second depending on ML model
- **Storage**: 50,000+ writes/second to TimescaleDB
- **Query**: Sub-100ms for time-range queries with indexes
- **Latency**: 10-50ms gRPC round-trip, <1ms NATS publishing

---

## Data Flow Architecture

### Complete Flow with Authentication

```mermaid
graph TD
    subgraph "User Onboarding"
        Signup[User Signs Up] --> UserRecord[Users Table]
        UserRecord --> InviteCode[Generate Invite Code]
        InviteCode --> InviteTable[Invite Codes Table]
    end

    subgraph "Client Setup"
        App[Download App] --> EnterCode[Enter Invite Code/QR]
        EnterCode --> Validate[Validate & Link]
        Validate --> ClientRecord[Clients Table]
    end

    subgraph "Data Flow"
        Client[Client App] -->|JWT/API Key| WebSocket[Go WebSocket Server]
        WebSocket -->|Large Files| MinIO[MinIO S3]
        WebSocket -->|Metadata + S3 URLs| NATS[NATS Topics]
        
        NATS -->|user.{id}.audio| AudioConsumer[Audio Consumer]
        NATS -->|user.{id}.sensor| SensorConsumer[Sensor Consumer]
        NATS -->|user.{id}.image| ImageConsumer[Image Consumer]
        
        AudioConsumer -->|HTTP + API Key| AudioWorker[Audio Worker API]
        SensorConsumer -->|HTTP + API Key| SensorWorker[Sensor Worker API]
        ImageConsumer -->|HTTP + API Key| ImageWorker[Image Worker API]
        
        AudioWorker -->|Result| AudioConsumer
        SensorWorker -->|Result| SensorConsumer
        ImageWorker -->|Result| ImageConsumer
        
        AudioConsumer -->|Write| TimescaleDB[(TimescaleDB)]
        SensorConsumer -->|Write| TimescaleDB
        ImageConsumer -->|Write| TimescaleDB
    end
```

### Data Flow Stages

1. **Data Collection** (0-10ms)
   - Clients collect sensor data, media, and events
   - Local buffering for offline resilience
   - Batching for efficiency (100-500 messages)

2. **Protocol Transmission** (10-50ms)
   - gRPC bidirectional streaming
   - Protobuf serialization (3-10x smaller than JSON)
   - TLS encryption with certificate pinning
   - Automatic retry with exponential backoff

3. **API Ingestion** (50-100ms)
   - Authentication via JWT/API keys
   - Rate limiting per client (1000 req/min default)
   - OpenTelemetry span creation with trace_id
   - NATS JetStream publishing

4. **Message Routing** (100-200ms)
   - NATS consumer groups for scaling
   - Dynamic routing based on message type
   - Dead letter queue for failures
   - Parallel processing dispatch

5. **Processing** (200ms-30s depending on service)
   - ML inference (OCR, STT, embeddings)
   - Data transformation and enrichment
   - Anomaly detection
   - Result aggregation

6. **Storage** (50-100ms)
   - TimescaleDB hypertable insertion
   - pgvector embedding storage
   - Compression for historical data
   - Continuous aggregates update

---

## Authentication & Security

### JWT Token Flow
1. User signs up → Creates user record
2. Generate invite code → Links to user account
3. Client enters code → Validates and links device
4. Client receives JWT token with claims:
   - `user_id`: User identifier
   - `client_id`: Device identifier
   - `tier`: User subscription tier
   - `exp`: Token expiration

### API Key Authentication
- Each worker service has unique API keys
- Keys stored in environment variables
- Validated via middleware on each request
- Used for processor fan-out pattern

### Security Measures
- **Encryption**: TLS 1.3 for all network traffic, AES-256 at rest
- **Certificate Pinning**: Mobile clients verify server certificates
- **Row-Level Security**: TimescaleDB RLS policies based on user_id
- **Audit Logging**: All access logged with trace_id
- **Secrets Management**: Kubernetes secrets for sensitive data

---

## Docker Container Infrastructure

### Container Standards (API Docker Contract)

All Docker containers follow strict standards for consistency:

#### Required Endpoints
1. **Health Checks**: `/health` and `/healthz`
2. **Root Info**: `/` returns service info and endpoints
3. **Main Service**: Primary processing endpoint
4. **Metrics**: `/metrics` for Prometheus (optional)

#### Container Structure
```
docker/<service-name>/
├── Dockerfile
├── docker-compose.yml
├── requirements.txt / package.json
├── app.py / app.js / main.go
├── test.sh (required testing script)
├── test/ (test data and expected responses)
├── models/ (if ML service)
├── temp/ (temporary storage)
└── .env.example
```

### Deployed Services

#### 1. RapidOCR API (Port 8001)
- **Purpose**: Optical Character Recognition
- **Input Formats**:
  - Base64: `{"image_base64": "base64_data", "det": true, "rec": true, "cls": true}`
  - File Upload: Multipart form with image file
  - URL: `{"image_url": "https://example.com/image.jpg"}`
- **Supported Image Types**: JPEG, PNG, BMP, WebP
- **Output**: 
  ```json
  {
    "success": true,
    "text": "extracted text",
    "boxes": [[x1,y1,x2,y2,x3,y3,x4,y4]],
    "scores": [0.95],
    "processing_time_ms": 123.45
  }
  ```
- **Resources**: 2GB RAM, 2 CPU cores
- **Models**: Auto-downloads on first run

#### 2. Nomic Embed Vision API (Port 8002)
- **Purpose**: Unified text and image embeddings
- **Model**: nomic-embed-vision-v1.5
- **Input Formats**:
  - Text: `{"texts": ["text1", "text2"], "task_type": "search_query"}`
  - Image: `{"images": ["base64_image1"], "task_type": "search_document"}`
  - Mixed: `{"texts": [...], "images": [...], "task_type": "classification"}`
- **Task Types**: 
  - `search_query`: Optimized for search queries
  - `search_document`: Optimized for searchable documents
  - `classification`: For classification tasks
  - `clustering`: For clustering similar items
- **Features**:
  - 768-dimensional embeddings
  - Supports text up to 8192 tokens
  - Cross-modal search capabilities
- **Output**: `{"embeddings": [[768 floats]], "usage": {"prompt_tokens": 123}}`
- **Resources**: 4GB RAM, 2 CPU cores

#### 3. YuNet Face Detection API (Port 8003)
- **Purpose**: Face detection and facial landmarks
- **Input Formats**:
  - Base64: `{"image_base64": "base64_data", "score_threshold": 0.7}`
  - File Upload: Multipart form with image file
  - URL: `{"image_url": "https://example.com/face.jpg"}`
- **Parameters**:
  - `score_threshold`: Confidence threshold (0.0-1.0, default 0.7)
  - `nms_threshold`: Non-max suppression (0.0-1.0, default 0.3)
  - `top_k`: Max faces to detect (default 5000)
- **Output**: 
  ```json
  {
    "success": true,
    "faces": [{
      "bbox": [x, y, width, height],
      "landmarks": [[x1,y1], [x2,y2], ...],  // 5 points
      "confidence": 0.95
    }],
    "processing_time_ms": 45.67
  }
  ```
- **Resources**: 1GB RAM, 1 CPU core
- **Model**: YuNet CNN model

#### 4. Voice API (Port 8257)
- **Purpose**: Speech-to-text, text-to-speech, and speaker identification
- **Models**: 
  - ASR: Parakeet-offline (NEMO), Zipformer, SenseVoice, Paraformer, FireRedASR
  - TTS: Kokoro Multi-lang v1.0 (110 voices)
  - Speaker ID: NEMO SpeakerNet, 3D-Speaker, WeSpeaker
- **Features**:
  - Real-time speech recognition
  - Multi-language TTS (English, Japanese, French, Spanish, Portuguese, Chinese)
  - Speaker diarization and identification
  - Voice activity detection (Silero VAD)
  - WebSocket streaming support
- **Resources**: 4GB RAM minimum, 8GB recommended

### Testing Framework

Every container includes `test.sh` script that:
- Tests all endpoints
- Validates responses
- Provides color-coded output (GREEN/RED/YELLOW)
- Exits with proper codes for CI/CD

Example test execution:
```bash
./test.sh  # Default localhost:8000
BASE_URL=http://localhost:8080 ./test.sh  # Custom port
VERBOSE=true ./test.sh  # Detailed output
```

---

## Storage Layer

### TimescaleDB Schema

#### Core Tables
```sql
-- Users table (account level)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    tier TEXT NOT NULL DEFAULT 'free',
    max_clients INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Clients (devices)
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    invite_code TEXT REFERENCES invite_codes(code),
    device_info JSONB,
    api_key TEXT UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    last_seen TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Main sensor data hypertable
CREATE TABLE sensor_readings (
    device_id TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    reading_type TEXT NOT NULL,
    data JSONB NOT NULL,
    metadata JSONB,
    trace_id TEXT,
    PRIMARY KEY (device_id, recorded_at, reading_type)
);

-- Convert to hypertable with partitioning
SELECT create_hypertable(
    'sensor_readings',
    'recorded_at',
    partitioning_column => 'device_id',
    number_partitions => 4,
    chunk_time_interval => INTERVAL '1 day'
);

-- Embeddings table for semantic search
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id TEXT NOT NULL,
    source_type TEXT NOT NULL,
    embedding vector(768),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- HNSW index for fast similarity search
CREATE INDEX ON embeddings 
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
```

### MinIO S3 Storage
- **Purpose**: Store large files (audio, images, video)
- **Structure**: `{user_id}/{type}/{date}-{uuid}`
- **Integration**: NATS messages contain S3 URLs
- **Retention**: Configurable per user/tier

### Worker Registry
```sql
CREATE TABLE worker_types (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    endpoint_url TEXT NOT NULL,
    destination_table TEXT NOT NULL,
    input_schema JSONB,
    output_schema JSONB,
    enabled BOOLEAN DEFAULT TRUE,
    api_key TEXT
);
```

---

## Processing Pipeline

### Data Router Architecture

The Data Router is the central orchestrator that:
1. Consumes messages from NATS JetStream
2. Applies routing rules based on data type
3. Dispatches to appropriate ML processors
4. Stores results in TimescaleDB

#### Routing Configuration
```yaml
routing:
  rules:
    - name: "ocr_processing"
      conditions:
        - field: "data_type"
          operator: "equals"
          value: "image"
        - field: "metadata.requires_ocr"
          operator: "equals"
          value: "true"
      target:
        service: "rapidocr"
        endpoint: "/api/v1/ocr"
        timeout: 30s
        
    - name: "text_embedding"
      conditions:
        - field: "data_type"
          operator: "in"
          values: ["text", "transcript", "ocr_result"]
      target:
        service: "nomic"
        endpoint: "/api/v1/embed"
        timeout: 10s
```

### NATS Consumer Pattern
```python
class WorkerConsumer:
    def __init__(self, worker_type: str):
        self.worker_type = worker_type
        self.worker_config = self.load_worker_config(worker_type)
        self.db = TimescaleDBClient()
        self.http_client = httpx.AsyncClient(timeout=30.0)
        
    async def process_message(self, msg):
        data = json.loads(msg.data)
        
        # Download from S3 if needed
        if "s3_url" in data.get("data", {}):
            file_data = await self.download_from_s3(data["data"]["s3_url"])
            data["data"]["content"] = file_data
        
        # Call worker API with trace_id
        headers = {
            "X-API-Key": self.worker_config["api_key"],
            "X-Trace-ID": data.get("trace_id", str(uuid4()))
        }
        response = await self.http_client.post(
            self.worker_config["endpoint_url"],
            json=data,
            headers=headers
        )
        
        # Save result to TimescaleDB
        if response.status_code == 200:
            result = response.json()
            await self.save_to_db(
                table=self.worker_config["destination_table"],
                user_id=data["user_id"],
                client_id=data["client_id"],
                timestamp=data["timestamp"],
                trace_id=headers["X-Trace-ID"],
                result=result
            )
```

### Circuit Breaker Pattern
All service calls use circuit breakers to handle failures gracefully:
- Open circuit after 50% failure rate
- Retry with exponential backoff
- Fallback to cached results when available

---

## Client Implementation

### Android/Kotlin gRPC Client
```kotlin
class GrpcDataService(private val config: ClientConfig) {
    private lateinit var channel: ManagedChannel
    private lateinit var stub: DataIngestionServiceStub
    
    fun connect() {
        channel = ManagedChannelBuilder
            .forAddress(config.host, config.port)
            .keepAliveTime(30, TimeUnit.SECONDS)
            .maxInboundMessageSize(4 * 1024 * 1024)
            .intercept(AuthInterceptor(config.apiKey))
            .build()
            
        stub = DataIngestionServiceGrpc.newStub(channel)
        startBidirectionalStream()
    }
    
    fun sendSensorData(reading: SensorReading) {
        reading.traceId = UUID.randomUUID().toString()
        streamObserver.onNext(reading)
    }
}
```

### Flutter/Dart Client
```dart
class GrpcDataService {
  Future<void> sendSensorData(Map<String, dynamic> data) async {
    final reading = SensorReading()
      ..deviceId = _deviceId
      ..readingId = Uuid().v4()
      ..traceId = Uuid().v4()
      ..recordedAt = Timestamp.fromDateTime(DateTime.now())
      ..metadata.addAll(data['metadata'] ?? {});
      
    if (_controller != null && !_controller!.isClosed) {
      _controller!.add(reading);
    } else {
      _offlineQueue.add(reading);
    }
  }
}
```

### Data Sources Supported
- **Mobile/Wearable**: GPS, accelerometer, gyroscope, magnetometer, heart rate, steps, sleep
- **OS Events**: Screen on/off, app launches/closes, notifications, copied text
- **Media**: Environmental audio, passive photos, screenshots
- **External**: Calendars (CalDAV), emails (IMAP/SMTP), social media APIs
- **Custom**: Any timeseries via generic endpoints

---

## Multi-Tenancy & Scaling

### Implementation Phases

#### Immediate Value (No Auth Dependencies)
1. **ConfigMaps/Secrets** - Clean configuration management
2. **API Keys for Processors** - Simple authentication
3. **OpenTelemetry/Jaeger** - Distributed tracing with trace_id
4. **Basic HPA** - CPU/memory-based autoscaling
5. **Longhorn Storage** - Distributed persistent volumes

#### When Adding Users
1. **JWT/Keycloak** - Full authentication system
2. **Row-Level Security** - Database access control
3. **User-specific NATS topics** - `user.{id}.{type}`
4. **Namespaces** - Resource isolation (if needed)

### Hybrid Scaling Approach
```python
# Fan-out to external processors
async def process_message(msg):
    data = json.loads(msg.data)
    user_id = data.get("user_id", "default")
    
    # Route to processor with API key
    headers = {
        "X-API-Key": API_KEYS[hash(user_id) % len(API_KEYS)],
        "X-Trace-ID": data.get("trace_id")
    }
    await httpx.post("http://processor/analyze", json=data, headers=headers)
```

This allows:
- Core k3s cluster for orchestration
- Docker containers anywhere for processing
- API key authentication for security
- Load balancing across processors

---

## Client Device Tracking & Notifications

### Device Connection Tracking

#### Database Schema
```sql
-- Device connection tracking
CREATE TABLE device_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES clients(id),
    user_id UUID REFERENCES users(id),
    connection_type TEXT NOT NULL, -- 'websocket', 'grpc', 'http'
    ip_address INET,
    user_agent TEXT,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    disconnected_at TIMESTAMPTZ,
    last_ping TIMESTAMPTZ DEFAULT NOW(),
    session_duration INTERVAL GENERATED ALWAYS AS (
        COALESCE(disconnected_at, NOW()) - connected_at
    ) STORED,
    metadata JSONB,
    INDEX idx_active_connections (device_id, disconnected_at),
    INDEX idx_user_connections (user_id, connected_at DESC)
);

-- Connection events for audit trail
CREATE TABLE connection_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES clients(id),
    event_type TEXT NOT NULL, -- 'connect', 'disconnect', 'ping', 'timeout', 'error'
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    details JSONB,
    trace_id TEXT,
    INDEX idx_device_events (device_id, timestamp DESC)
);
```

#### Connection Monitoring Service
```go
type ConnectionMonitor struct {
    db         *sql.DB
    activeConns map[string]*DeviceConnection
    mu          sync.RWMutex
}

func (cm *ConnectionMonitor) OnConnect(deviceID, userID string, connType string, metadata map[string]interface{}) {
    cm.mu.Lock()
    defer cm.mu.Unlock()
    
    conn := &DeviceConnection{
        DeviceID:     deviceID,
        UserID:       userID,
        ConnectionType: connType,
        ConnectedAt:  time.Now(),
        LastPing:     time.Now(),
        Metadata:     metadata,
    }
    
    cm.activeConns[deviceID] = conn
    
    // Record in database
    _, err := cm.db.Exec(`
        INSERT INTO device_connections 
        (device_id, user_id, connection_type, ip_address, user_agent, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)`,
        deviceID, userID, connType, metadata["ip"], metadata["user_agent"], metadata)
    
    // Record event
    cm.recordEvent(deviceID, "connect", metadata)
}

func (cm *ConnectionMonitor) OnDisconnect(deviceID string, reason string) {
    cm.mu.Lock()
    defer cm.mu.Unlock()
    
    if conn, exists := cm.activeConns[deviceID]; exists {
        // Update database
        _, err := cm.db.Exec(`
            UPDATE device_connections 
            SET disconnected_at = NOW()
            WHERE device_id = $1 AND disconnected_at IS NULL`,
            deviceID)
        
        delete(cm.activeConns, deviceID)
        cm.recordEvent(deviceID, "disconnect", map[string]interface{}{"reason": reason})
    }
}

func (cm *ConnectionMonitor) PingLoop() {
    ticker := time.NewTicker(30 * time.Second)
    for range ticker.C {
        cm.mu.RLock()
        for deviceID, conn := range cm.activeConns {
            if time.Since(conn.LastPing) > 2*time.Minute {
                cm.mu.RUnlock()
                cm.OnDisconnect(deviceID, "timeout")
                cm.mu.RLock()
            }
        }
        cm.mu.RUnlock()
    }
}
```

### Mobile Notifications System

#### Database Schema with LISTEN/NOTIFY
```sql
-- Mobile notifications table
CREATE TABLE mobile_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES clients(id),
    user_id UUID REFERENCES users(id),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'read', 'dismissed', 'failed')),
    error_message TEXT,
    retry_count INT DEFAULT 0,
    trace_id TEXT,
    INDEX idx_device_pending (device_id, status) WHERE status = 'pending',
    INDEX idx_user_notifications (user_id, created_at DESC)
);

-- Notification responses tracking
CREATE TABLE notification_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES mobile_notifications(id),
    device_id UUID REFERENCES clients(id),
    response_type TEXT NOT NULL, -- 'dismissed', 'clicked', 'button_click', 'text_reply'
    action_id TEXT, -- Which button was clicked
    action_data JSONB, -- Data from the action
    text_response TEXT, -- For quick reply responses
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    trace_id TEXT,
    INDEX idx_notification_responses (notification_id, timestamp)
);

-- Function to notify on new notifications
CREATE OR REPLACE FUNCTION notify_new_notification() RETURNS TRIGGER AS $$
DECLARE
    payload TEXT;
BEGIN
    -- Create notification payload
    payload := json_build_object(
        'id', NEW.id,
        'device_id', NEW.device_id,
        'user_id', NEW.user_id,
        'title', NEW.title,
        'body', NEW.body,
        'data', NEW.data,
        'priority', NEW.priority,
        'created_at', NEW.created_at
    )::text;
    
    -- Send notification to channel specific to device
    PERFORM pg_notify('notification_' || NEW.device_id::text, payload);
    
    -- Also send to user channel for multi-device support
    PERFORM pg_notify('notification_user_' || NEW.user_id::text, payload);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for LISTEN/NOTIFY
CREATE TRIGGER new_notification_trigger
    AFTER INSERT ON mobile_notifications
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_notification();
```

#### Notification Service Implementation
```python
import asyncio
import asyncpg
import json
from datetime import datetime
from typing import Dict, Any, Optional

class NotificationService:
    def __init__(self, db_url: str):
        self.db_url = db_url
        self.connections: Dict[str, asyncpg.Connection] = {}
        self.device_handlers = {}
        
    async def start_listening(self, device_id: str):
        """Start listening for notifications for a specific device"""
        conn = await asyncpg.connect(self.db_url)
        self.connections[device_id] = conn
        
        # Listen to device-specific channel
        await conn.add_listener(f'notification_{device_id}', 
                               lambda conn, pid, channel, payload: 
                               asyncio.create_task(self.handle_notification(device_id, payload)))
        
    async def handle_notification(self, device_id: str, payload: str):
        """Handle incoming notification and send to device"""
        notification = json.loads(payload)
        
        # Get device connection (WebSocket/gRPC stream)
        if device_id in self.device_handlers:
            handler = self.device_handlers[device_id]
            
            try:
                # Send notification to device
                await handler.send_notification(notification)
                
                # Update status to sent
                await self.update_notification_status(
                    notification['id'], 'sent', datetime.utcnow())
                    
            except Exception as e:
                # Mark as failed
                await self.update_notification_status(
                    notification['id'], 'failed', error=str(e))
    
    async def send_notification(self, device_id: str, title: str, body: str, 
                               data: Dict[str, Any], priority: str = 'normal'):
        """Create and send a notification"""
        async with asyncpg.create_pool(self.db_url) as pool:
            async with pool.acquire() as conn:
                # Insert notification (will trigger NOTIFY)
                notification_id = await conn.fetchval("""
                    INSERT INTO mobile_notifications 
                    (device_id, title, body, data, priority)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING id
                """, device_id, title, body, json.dumps(data), priority)
                
                return notification_id
    
    async def handle_notification_response(self, notification_id: str, 
                                          device_id: str,
                                          response_type: str,
                                          action_id: Optional[str] = None,
                                          action_data: Optional[Dict] = None,
                                          text_response: Optional[str] = None):
        """Record notification response from client"""
        async with asyncpg.create_pool(self.db_url) as pool:
            async with pool.acquire() as conn:
                # Record response
                await conn.execute("""
                    INSERT INTO notification_responses
                    (notification_id, device_id, response_type, action_id, 
                     action_data, text_response)
                    VALUES ($1, $2, $3, $4, $5, $6)
                """, notification_id, device_id, response_type, action_id,
                    json.dumps(action_data) if action_data else None,
                    text_response)
                
                # Update notification status based on response
                if response_type == 'dismissed':
                    await conn.execute("""
                        UPDATE mobile_notifications 
                        SET status = 'dismissed', dismissed_at = NOW()
                        WHERE id = $1
                    """, notification_id)
                elif response_type in ['clicked', 'button_click']:
                    await conn.execute("""
                        UPDATE mobile_notifications 
                        SET status = 'read', read_at = NOW()
                        WHERE id = $1
                    """, notification_id)
```

#### Example Notification Types

```python
# Meeting invitation with actions
meeting_notification = {
    "device_id": "22767454-7ae7-42e9-885e-8a3e8e735609",
    "title": "📅 Meeting Request: Product Review",
    "body": "Tomorrow at 2:00 PM - Can you make it?",
    "data": {
        "type": "calendar",
        "category": "meeting",
        "actions": [
            {
                "id": "accept",
                "title": "✓ Accept",
                "data": {
                    "meeting_id": "MEET-2024-0115-001",
                    "response": "accepted",
                    "meeting_time": "2024-01-16T14:00:00Z"
                },
                "resolved": True,
                "cancelNotification": True
            },
            {
                "id": "decline",
                "title": "✗ Decline",
                "data": {
                    "meeting_id": "MEET-2024-0115-001",
                    "response": "declined"
                },
                "resolved": True,
                "cancelNotification": True
            },
            {
                "id": "tentative",
                "title": "? Maybe",
                "data": {
                    "meeting_id": "MEET-2024-0115-001",
                    "response": "tentative"
                },
                "resolved": False,
                "cancelNotification": True
            }
        ],
        "metadata": {
            "organizer": "john.smith@company.com",
            "duration_minutes": 60,
            "location": "Conference Room B / Zoom",
            "zoom_link": "https://zoom.us/j/123456789",
            "attendees": ["john.smith", "jane.doe", "you"]
        }
    },
    "priority": "high"
}

# Quick reply notification (like Gmail)
email_notification = {
    "device_id": "device-uuid",
    "title": "📧 New Email from Sarah",
    "body": "Can you review the proposal by EOD?",
    "data": {
        "type": "email",
        "category": "work",
        "quick_reply": True,
        "suggested_replies": [
            "Will review it shortly",
            "On it now",
            "Can we discuss tomorrow?"
        ],
        "actions": [
            {
                "id": "reply",
                "title": "↩ Reply",
                "input": True,
                "placeholder": "Type your response..."
            },
            {
                "id": "archive",
                "title": "📁 Archive"
            }
        ]
    }
}

# Anomaly alert notification
anomaly_notification = {
    "device_id": "device-uuid",
    "title": "⚠️ Unusual Activity Detected",
    "body": "Heart rate spike detected without movement",
    "data": {
        "type": "health",
        "category": "anomaly",
        "severity": "medium",
        "anomaly_data": {
            "heart_rate": 145,
            "activity_level": "sedentary",
            "timestamp": "2024-01-15T14:30:00Z",
            "causal_explanation": "Possible stress response"
        },
        "actions": [
            {
                "id": "log_symptom",
                "title": "📝 Log Symptom"
            },
            {
                "id": "dismiss",
                "title": "✓ I'm OK"
            }
        ]
    },
    "priority": "high"
}
```

---

## Complete Data Types & Inputs Catalog

### Sensor Data Streams

#### Motion & Movement
1. **Accelerometer** (3-axis)
   - Format: `{x: float, y: float, z: float, timestamp: ms}`
   - Frequency: 10-100Hz
   - Source: Mobile, Watch, Wearables

2. **Gyroscope** (3-axis rotation)
   - Format: `{pitch: float, roll: float, yaw: float, timestamp: ms}`
   - Frequency: 10-100Hz
   - Source: Mobile, Watch

3. **Magnetometer** (compass)
   - Format: `{heading: float, x: float, y: float, z: float, timestamp: ms}`
   - Frequency: 10Hz
   - Source: Mobile, Watch

4. **Step Counter**
   - Format: `{steps: int, distance_m: float, timestamp: ms}`
   - Frequency: Event-based
   - Source: Mobile, Watch, Fitness trackers

5. **Activity Recognition**
   - Format: `{activity: enum, confidence: float, timestamp: ms}`
   - Activities: `walking, running, cycling, driving, stationary`
   - Source: Mobile, Watch

#### Location & Environment
6. **GPS**
   - Format: `{lat: float, lon: float, alt: float, accuracy_m: float, speed_mps: float, bearing: float, timestamp: ms}`
   - Frequency: 1Hz or on-change
   - Source: Mobile, Watch

7. **WiFi Scans**
   - Format: `{ssid: string, bssid: string, rssi: int, frequency: int, timestamp: ms}[]`
   - Frequency: Every 30s-5min
   - Source: Mobile

8. **Bluetooth Scans**
   - Format: `{device_id: string, name: string, rssi: int, device_type: string, timestamp: ms}[]`
   - Frequency: Every 30s-5min
   - Source: Mobile, Watch

9. **Barometer** (atmospheric pressure)
   - Format: `{pressure_hPa: float, altitude_m: float, timestamp: ms}`
   - Frequency: 1Hz
   - Source: Mobile, Watch

10. **Ambient Light**
    - Format: `{lux: float, timestamp: ms}`
    - Frequency: On-change
    - Source: Mobile, Watch

11. **Temperature Sensors**
    - Format: `{ambient_c: float, device_c: float, timestamp: ms}`
    - Frequency: Every minute
    - Source: Mobile, Watch, IoT devices

#### Biometric & Health
12. **Heart Rate**
    - Format: `{bpm: int, confidence: float, hrv: float, timestamp: ms}`
    - Frequency: Continuous or every 5s
    - Source: Watch, Chest strap, Fitness devices

13. **Blood Oxygen (SpO2)**
    - Format: `{spo2_percent: float, confidence: float, timestamp: ms}`
    - Frequency: On-demand or every hour
    - Source: Watch, Pulse oximeter

14. **ECG**
    - Format: `{samples: float[], sample_rate_hz: int, timestamp: ms}`
    - Frequency: 250-500Hz during recording
    - Source: Watch, Medical devices

15. **Sleep Data**
    - Format: `{stage: enum, duration_min: int, quality: float, timestamp: ms}`
    - Stages: `awake, rem, light, deep`
    - Source: Watch, Sleep trackers

16. **Stress Level**
    - Format: `{level: int(1-100), hrv_based: bool, timestamp: ms}`
    - Frequency: Every 5-30min
    - Source: Watch, Wearables

17. **Skin Temperature**
    - Format: `{temp_c: float, timestamp: ms}`
    - Frequency: Every minute
    - Source: Watch, Wearables

18. **Galvanic Skin Response (GSR)**
    - Format: `{conductance_uS: float, timestamp: ms}`
    - Frequency: 10Hz
    - Source: Specialized wearables

#### Audio & Speech
19. **Environmental Audio** (streaming)
    - Format: `{samples: int16[], sample_rate: int, duration_ms: int, timestamp: ms}`
    - Processing: VAD, STT, emotion, noise level
    - Source: Mobile, Watch, Smart speakers

20. **Speech Activity**
    - Format: `{is_speaking: bool, confidence: float, timestamp: ms}`
    - Frequency: 10Hz during audio capture
    - Source: Mobile, Watch

21. **Transcribed Text** (from STT)
    - Format: `{text: string, confidence: float, language: string, timestamp: ms}`
    - Source: Processed audio

22. **Voice Features**
    - Format: `{pitch_hz: float, energy_db: float, emotion: string, timestamp: ms}`
    - Source: Processed audio

##### Voice API Specific Inputs (Port 8257)

**Audio Processing Endpoints:**

23a. **Base64 Audio for Transcription** (`POST /process/base64`)
    - Input Format: 
      ```json
      {
        "audio_base64": "base64_encoded_wav_data",
        "language": "en",  // optional
        "options": {
          "include_speaker": true  // optional
        }
      }
      ```
    - Audio Requirements: 16kHz mono WAV recommended, 16-bit PCM
    - Max Size: ~10MB base64 (7.5MB raw audio)
    - Response: `{text, language, confidence, speaker, metadata}`

23b. **Audio File Upload** (`POST /process/audio`)
    - Input: Multipart form with audio file
    - Supported Formats: WAV, MP3, M4A, OGG, FLAC
    - Parameters: `include_speaker=true/false`, `language=en/es/fr/etc`
    - Response: Same as base64 endpoint

23c. **Text-to-Speech Generation** (`POST /tts/generate`)
    - Input Format:
      ```json
      {
        "text": "Text to synthesize",
        "voice": 1,  // Voice ID 0-109
        "speed": 1.0  // Speed multiplier 0.5-2.0
      }
      ```
    - Voice IDs: 
      - 0-21: US English voices
      - 22-27: British English voices
      - 28-36: Japanese voices
      - 37-41: French voices
      - 42-45: Portuguese voices
      - 46-50: Spanish voices
      - 51+: Chinese voices
    - Response: Base64 encoded audio, duration_ms, voice_used

23d. **Speaker Registration** (`POST /speakers/register`)
    - Input Format:
      ```json
      {
        "name": "Speaker Name",
        "embeddings": [float_array_256_or_512],  // optional
        "audio_base64": "base64_wav_for_extraction"  // optional
      }
      ```
    - Requirements: Either embeddings OR audio_base64 must be provided
    - Audio Requirements: Minimum 3 seconds, 16kHz mono WAV
    - Embedding Dimensions: 256 (NEMO) or 512 (3D-Speaker)

**WebSocket Streaming Endpoints:**

23e. **Real-time ASR** (`WS /ws/asr`)
    - Input: Binary audio chunks (16kHz, 16-bit PCM)
    - Chunk Size: 160-3200 samples (10-200ms)
    - Protocol: Binary frames with audio data
    - Response Stream: JSON with incremental transcriptions

23f. **Real-time TTS** (`WS /ws/tts`)
    - Input: JSON messages with text and voice parameters
    - Response: Binary audio chunks
    - Supports streaming synthesis

23g. **Real-time Speaker ID** (`WS /ws/speaker_id`)
    - Input: Binary audio chunks
    - Response: JSON with speaker identification results
    - Minimum Audio: 3 seconds for reliable identification

#### Visual & Screen
23. **Screenshots**
    - Format: `{image_base64: string, width: int, height: int, timestamp: ms}`
    - Frequency: Every 5-30min or on-change
    - Source: Mobile, Desktop

24. **Passive Photos** (IMU-triggered)
    - Format: `{image_base64: string, trigger_reason: string, timestamp: ms}`
    - Triggers: Motion detection, novelty, scheduled
    - Source: Mobile, Wearable camera

25. **Camera Photos/Videos** (user-initiated)
    - Format: `{file_path: string, metadata: object, timestamp: ms}`
    - Source: Mobile camera

26. **Screen Time**
    - Format: `{app_name: string, duration_s: int, category: string, timestamp: ms}`
    - Frequency: Every app switch
    - Source: Mobile, Desktop

27. **OCR Text** (from images/screenshots)
    - Format: `{text: string, bounding_boxes: object[], confidence: float, timestamp: ms}`
    - Source: Processed images

28. **Face Detection**
    - Format: `{faces: [{bbox: object, landmarks: object, id: string}], timestamp: ms}`
    - Source: Processed images

29. **Object Detection**
    - Format: `{objects: [{class: string, bbox: object, confidence: float}], timestamp: ms}`
    - Source: Processed images

#### Device & System
30. **Battery Status**
    - Format: `{level_percent: int, is_charging: bool, temperature_c: float, timestamp: ms}`
    - Frequency: Every 5min or on-change
    - Source: Mobile, Watch, Laptop

31. **Screen On/Off Events**
    - Format: `{state: enum(on/off), duration_s: int, timestamp: ms}`
    - Source: Mobile, Watch

32. **App Launch/Close Events**
    - Format: `{app_name: string, action: enum(launch/close), duration_s: int, timestamp: ms}`
    - Source: Mobile, Desktop

33. **App Crashes**
    - Format: `{app_name: string, error: string, stack_trace: string, timestamp: ms}`
    - Source: Mobile, Desktop

34. **Notifications Received**
    - Format: `{app_name: string, title: string, body: string, category: string, timestamp: ms}`
    - Source: Mobile, Watch

35. **Clipboard Events**
    - Format: `{text: string, source_app: string, timestamp: ms}`
    - Source: Mobile, Desktop

36. **Network Status**
    - Format: `{type: enum(wifi/cellular/none), ssid: string, signal_strength: int, timestamp: ms}`
    - Source: Mobile, Desktop

37. **CPU/Memory Usage**
    - Format: `{cpu_percent: float, memory_mb: int, disk_gb: float, timestamp: ms}`
    - Frequency: Every minute
    - Source: Mobile, Desktop

38. **Keyboard Events** (opt-in)
    - Format: `{key_count: int, words_per_min: float, app_context: string, timestamp: ms}`
    - Source: Desktop

#### External Services
39. **Calendar Events** (CalDAV)
    - Format: `{title: string, start: datetime, end: datetime, attendees: string[], timestamp: ms}`
    - Source: Google Calendar, Outlook, iCal

40. **Emails** (IMAP/SMTP)
    - Format: `{subject: string, from: string, to: string[], body_preview: string, timestamp: ms}`
    - Source: Email providers

41. **Contacts** (CardDAV)
    - Format: `{name: string, phone: string, email: string, last_interaction: datetime, timestamp: ms}`
    - Source: Contact providers

42. **Social Media Activity**
    - Twitter: `{likes: int, posts: int, mentions: int, timestamp: ms}`
    - GitHub: `{commits: int, prs: int, issues: int, timestamp: ms}`
    - YouTube: `{videos_watched: int, likes: int, comments: int, timestamp: ms}`

43. **Financial/Budget** (via APIs/Sheets)
    - Format: `{category: string, amount: float, merchant: string, timestamp: ms}`
    - Source: Banking APIs, Google Sheets

44. **Weather Data**
    - Format: `{temp_c: float, humidity: float, conditions: string, timestamp: ms}`
    - Source: Weather APIs

45. **News/RSS Feeds**
    - Format: `{title: string, source: string, category: string, sentiment: float, timestamp: ms}`
    - Source: RSS feeds, News APIs

#### Computed/Derived Data
46. **Embeddings** (text/image)
    - Format: `{vector: float[768], source_type: string, source_id: string, timestamp: ms}`
    - Source: Nomic Embed API

47. **Anomaly Scores**
    - Format: `{score: float, confidence: float, streams_affected: string[], explanation: object, timestamp: ms}`
    - Source: Anomaly Detection System

48. **Activity Summaries**
    - Format: `{period: string, metrics: object, insights: string[], timestamp: ms}`
    - Source: Analytics pipeline

49. **Habit Patterns**
    - Format: `{habit: string, frequency: string, streak_days: int, timestamp: ms}`
    - Source: Pattern mining

50. **Correlations**
    - Format: `{stream_a: string, stream_b: string, correlation: float, lag_ms: int, timestamp: ms}`
    - Source: Correlation analysis

### Data Input Methods

#### Direct Streaming
- **gRPC Bidirectional Stream**: Real-time sensor data
- **WebSocket**: Alternative for web clients
- **HTTP POST**: Batch uploads

#### File Uploads
- **Images**: JPEG, PNG, WebP
- **Audio**: WAV, MP3, M4A
- **Video**: MP4, MOV
- **Documents**: PDF, TXT

#### API Integrations
- **OAuth2**: Google, Twitter, GitHub
- **API Keys**: Weather, News, Financial
- **Webhooks**: Real-time updates from services

#### Message Queue Topics
```
user.{id}.sensor
user.{id}.audio
user.{id}.image
user.{id}.text
user.{id}.health
user.{id}.location
user.{id}.system
user.{id}.external
user.{id}.computed
```

### Data Processing Pipelines

#### Real-Time Processing
- Motion classification
- Voice activity detection
- Anomaly detection
- Event correlation

#### Batch Processing
- Daily summaries
- Habit mining
- Trend analysis
- Model retraining

#### ML Processing Services
- **STT**: NEMO Parakeet TDT, SenseVoice, Paraformer, FireRed ASR (via sherpa-onnx)
- **TTS**: Kokoro Multi-lang v1.0 (110 voices)
- **Speaker ID**: NEMO SpeakerNet, 3D-Speaker, WeSpeaker
- **OCR**: RapidOCR, MoonDream2
- **Embeddings**: Nomic Embed Vision v1.5
- **Face Detection**: YuNet
- **Object Detection**: YOLO
- **Emotion Recognition**: Custom models
- **Activity Recognition**: River ML

---

## TO BE SUPPORTED: Future Data Inputs

### Device Data Collection (Planned)

#### Audio/Video/Image
- **Raw microphone audio** - Continuous or VAD-triggered audio chunks
  - Format: `{device_id, timestamp, samples: int16[], sample_rate, duration_ms, codec}`
  
- **Screen recordings** - Keyframes or full video capture
  - Format: `{device_id, timestamp, frame_base64, width, height, fps, codec}`
  
- **Camera photos** - User-initiated and passive captures
  - Format: `{device_id, timestamp, image_base64, width, height, exif_data}`
  - Sources: Manual capture, motion-triggered, scheduled intervals
  
- **Food photos** - Meal documentation for nutrition tracking
  - Format: `{device_id, timestamp, image_base64, meal_type, location, tags[]}`
  - Sources: User-initiated, meal-time reminders

#### Extended Sensor Data
- **Proximity sensor** - Distance measurements
  - Format: `{device_id, timestamp, distance_cm, near_far_state}`

#### Health & Biometric Data
- **Heart rate** - Continuous heart rate monitoring
  - Format: `{device_id, timestamp, bpm, confidence, hrv_ms}`
  - Sources: Watch, chest strap, fitness bands
  
- **Blood oxygen (SpO2)** - Oxygen saturation levels
  - Format: `{device_id, timestamp, spo2_percent, pulse_rate, confidence}`
  
- **Blood pressure** - Systolic/diastolic readings
  - Format: `{device_id, timestamp, systolic, diastolic, pulse}`
  
- **EEG** - Brain electrical activity
  - Format: `{device_id, timestamp, channels[], sample_rate_hz, samples[][]}`
  - Sources: Consumer EEG headbands (Muse, Neurosity)
  
- **ECG** - Heart electrical activity
  - Format: `{device_id, timestamp, lead_data[], sample_rate_hz, duration_ms}`
  
- **Continuous glucose monitoring (CGM)** - Blood sugar tracking
  - Format: `{device_id, timestamp, glucose_mg_dl, trend_arrow, rate_of_change}`
  
- **Sleep stages** - Sleep phase detection
  - Format: `{device_id, timestamp, stage: enum, confidence, duration_min}`
  
- **Stress levels** - HRV-based stress detection
  - Format: `{device_id, timestamp, stress_level: 1-100, hrv_ms, recovery_time}`

#### System & Application Monitoring
- **Cross-platform app usage** - Application activity tracking
  - Windows: `{app_name, window_title, duration_s, keystrokes, clicks}`
  - macOS: `{app_name, window_title, duration_s, focus_time}`
  - Linux: `{process_name, window_class, cpu_percent, memory_mb}`
  - iOS/Android: `{bundle_id, app_name, category, duration_s}`

- **File system operations** - File access and modifications
  - Format: `{device_id, timestamp, operation, file_path, size_bytes, result}`

- **Hardware events** - USB devices, peripherals
  - Format: `{device_id, timestamp, device_type, device_name, action}`

#### Network & Connectivity
- **Cellular connection** - Mobile network data
  - Format: `{device_id, timestamp, carrier, signal_strength, network_type, cell_id}`
  
- **NFC interactions** - Near-field communication events
  - Format: `{device_id, timestamp, tag_id, tag_type, payload, action}`

#### Mobile App Data Collection
- **Bluetooth scans** - Nearby device discovery
  - Format: `{device_id, timestamp, discovered_devices[], rssi, device_type}`
  - Frequency: Periodic scans or on-demand
  
- **Screen text capture** - Accessibility-based text extraction
  - Format: `{device_id, timestamp, app_name, screen_text, ui_elements[]}`
  - Sources: Android AccessibilityService
  
- **App notifications** - System notification monitoring
  - Format: `{device_id, timestamp, app_name, title, body, category}`
  
- **Screen state events** - Display on/off tracking
  - Format: `{device_id, timestamp, state: on/off, duration_s}`
  
- **Battery status** - Power and charging state
  - Format: `{device_id, timestamp, level_percent, is_charging, temperature_c}`

#### Digital Activity
- **Browser history** - Web browsing activity
  - Format: `{device_id, timestamp, url, title, duration_s, referrer}`
  
- **Downloads tracking** - File download monitoring
  - Format: `{device_id, timestamp, file_name, file_size, source_url, file_type}`
  
- **Keylogging** - Complete keystroke capture
  - Format: `{device_id, timestamp, app_context, keys[], timing_ms[]}`

#### External Service Integration
- **Social media activity** - Cross-platform social data
  - Reddit: Saved posts, comments, upvotes
  - YouTube: Watch history, liked videos, subscriptions
  - Twitter/X: Liked tweets, bookmarks, lists
  - GitHub: Commits, issues, stars, activity
  
- **Music listening** - Spotify, Apple Music, etc.
  - Format: `{track_id, artist, album, played_at, duration_ms, context}`
  
- **Financial transactions** - Banking and payment data
  - Format: `{transaction_id, amount, merchant, category, date}`
  
- **Weather conditions** - Local environmental data
  - Format: `{timestamp, temp_c, humidity, pressure, conditions, wind_speed}`
  
- **News consumption** - Articles read/saved
  - Format: `{url, title, source, author, published_at, categories[]}`

### Processed & Derived Data (Planned)

#### Media Analysis
- **Speaker diarization** - Who spoke when in audio
- **Music vs speech classification** - Audio content type detection
- **Keyword spotting** - Wake word and keyword detection
- **Text summarization** - AI-generated summaries of content
- **Named entity recognition** - People, places, organizations
- **Sentiment analysis** - Emotional tone of text/speech
- **Scene understanding** - Indoor/outdoor/vehicle/activity detection
- **Food recognition** - Meal identification and nutrition estimation
- **Action recognition** - Detected activities in video

#### Behavioral Intelligence
- **Routine detection** - Daily/weekly patterns
- **Anomaly detection** - Unusual events with explanations
- **Correlation discovery** - Relationships between data streams
- **Predictive models** - Future behavior predictions
- **Personalized insights** - Tailored recommendations

#### Knowledge Representation
- **Entity graph** - People, places, things and their relationships
- **Event timeline** - Temporal events with context
- **Concept mapping** - Abstract topics and themes
- **Episodic memories** - Significant moments and experiences

#### Embeddings for Search & Similarity
- **Text embeddings** - Semantic search across all text
- **Image embeddings** - Visual similarity and search
- **Audio fingerprints** - Music/speech matching
- **Behavioral embeddings** - Pattern similarity detection

### Server-to-Device Commands (Planned)

Only the following commands can be initiated by the server to devices:

#### On-Demand Commands
- **Health check** - Verify client connectivity and responsiveness
  - Format: `{target_device_id, ping_id, timeout_ms}`
  - Response: Acknowledgment with client status and uptime
  
- **Capture photo** - Request camera photo capture
  - Format: `{target_device_id, camera_id, quality, flash, metadata_tags[]}`
  - Response: Photo data with EXIF information
  
- **Take screenshot** - Request screen capture
  - Format: `{target_device_id, display_id, region, include_cursor}`
  - Response: Screenshot image with window information
  
- **Send notification** - Push notification to device
  - Format: `{target_device_id, title, body, priority, actions[], expiry}`
  - Response: Delivery confirmation, user interaction

### Cross-Device Synchronization (Client-Initiated)

All other data flows are client-to-server initiated:

- **Universal clipboard** - Clipboard content sharing
  - Source: Client pushes clipboard changes
  - Distribution: Server broadcasts to authorized devices
  
- **File synchronization** - Selective file sync
  - Source: Client monitors and uploads changes
  - Distribution: Other clients pull updates
  
- **State synchronization** - App state and preferences
  - Source: Client pushes state changes
  - Distribution: Other clients subscribe to updates

### Data Storage & Retention (Planned)

#### Retention Policies
- **7 days**: Raw audio/video streams, high-frequency sensor data
- **30 days**: Location data, app usage, system events
- **90 days**: Processed analyses, behavioral patterns
- **1 year**: Health metrics, financial data, important documents
- **Indefinite**: Knowledge graph, memories, user-marked important data

#### Performance Optimizations
- **Time-series optimization**: Automatic compression of historical data
- **Pre-computed aggregates**: Hourly, daily, weekly summaries
- **Parallel processing**: Multi-worker ingestion pipeline
- **Smart indexing**: Optimized for time-range and similarity queries

---

## Anomaly Detection System

### Four-Tier Architecture

#### Tier 1: Individual Stream Analysis (River ML)
- **Purpose**: Detect temporal anomalies within individual streams
- **Models**: SNARIMAX, HoltWinters, QuantileFilter
- **Features**: Immediate learning from first data point
- **Performance**: ~30ms for 30+ streams

#### Tier 2: Cross-Stream Pattern Detection
- **Purpose**: Detect multivariate anomalies and gap patterns
- **Technology**: HalfSpaceTrees for streaming anomaly detection
- **Innovation**: Treats data availability as behavioral signals
- **Groups**: Motion, location, interaction, biometric

#### Tier 3: Ensemble & Meta-Learning
- **Purpose**: Combine signals with confidence weighting
- **Approach**: Health-aware weighted ensemble
- **Confidence**: Based on stream availability
- **Output**: Final anomaly score with confidence

#### Tier 4: Causal Explanation Layer
- **Purpose**: Explain WHY anomalies occur
- **Methods**:
  - Bayesian causal network
  - Event sequence matching
  - Temporal correlation analysis
- **Output**: Primary cause, confidence, evidence, alternatives

### Example Causal Explanation
```json
{
  "primary_cause": "exercise_onset",
  "confidence": 0.92,
  "causal_attribution": {
    "accelerometer_contribution": 0.6,
    "gps_movement_contribution": 0.3,
    "unexplained_variance": 0.1
  },
  "temporal_sequence": [
    "10:31 - accelerometer activity increased",
    "10:32 - GPS detected movement start",
    "10:33 - heart rate began climbing",
    "10:35 - heart rate reached peak (150 BPM)"
  ],
  "evidence": {
    "sequence_match": "exercise_pattern",
    "accelerometer_leads_heart_rate": "2 minutes"
  }
}
```

### Performance Requirements
- **Latency**: <35ms per timestamp, <85ms with causal explanation
- **Cold Start**: Works from first data point
- **Gap Tolerance**: Operates with 50% streams missing
- **Memory**: ~260MB for full system
- **CPU**: 2 cores for production

---

## Deployment & Operations

### Docker Compose Development
```yaml
version: '3.8'

services:
  # Core Infrastructure
  timescaledb:
    image: timescale/timescaledb:latest-pg14
    command: postgres -c shared_preload_libraries=timescaledb,vector
    environment:
      POSTGRES_DB: loomdb
      POSTGRES_USER: loom
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - timescale_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  nats:
    image: nats:latest
    command: ["-js", "-m=8222", "-sd=/data"]
    ports:
      - "4222:4222"
      - "8222:8222"
    volumes:
      - nats_data:/data

  minio:
    image: minio/minio:latest
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-minioadmin}
    command: server /data --console-address ":9001"

  # API Services
  grpc-api:
    build: ./api
    ports:
      - "50051:50051"
      - "8080:8080"
    environment:
      NATS_URL: nats://nats:4222
      DB_URL: postgresql://loom:${DB_PASSWORD}@timescaledb:5432/loomdb
      OTEL_EXPORTER_JAEGER_ENDPOINT: http://jaeger:14268/api/traces

  # ML Processing Services
  rapidocr:
    build: ./docker/rapidocr-raw-api
    ports:
      - "8001:8000"
    volumes:
      - ./models/rapidocr:/app/models:ro

  nomic-embed:
    build: ./docker/nomic-embed-api
    ports:
      - "8002:8000"

  yunet-face:
    build: ./docker/yunet-face-detection-raw-api
    ports:
      - "8003:8000"

  # Observability
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"
      - "14268:14268"

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml:ro

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
```

### Kubernetes Production
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grpc-api
  namespace: loom
spec:
  replicas: 3
  selector:
    matchLabels:
      app: grpc-api
  template:
    metadata:
      labels:
        app: grpc-api
    spec:
      containers:
      - name: grpc-api
        image: loom/grpc-api:latest
        ports:
        - containerPort: 50051
          name: grpc
        - containerPort: 8080
          name: metrics
        env:
        - name: NATS_URL
          value: nats://nats:4222
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

### Monitoring & Observability

#### OpenTelemetry Integration
Every service generates traces with:
- **trace_id**: Unique identifier following data through entire pipeline
- **span_id**: Individual operation identifier
- **parent_span_id**: Links operations in hierarchy

#### Key Metrics
- `loom_messages_received_total`: Messages by type and source
- `loom_processing_duration_seconds`: Processing time by service
- `loom_anomaly_detection_rate`: Anomalies detected per hour
- `loom_stream_availability_percentage`: Data stream health

#### Distributed Tracing Flow
```
[Mobile App] --span:upload--> [gRPC API]
                                   |
                              span:validate
                                   |
                              span:publish
                                   ↓
                            [NATS JetStream]
                                   |
                             span:consume
                                   ↓
                             [Data Router]
                                   |
                    +--------------+----------------+
                    |              |                |
              span:ocr      span:embedding    span:store
                    ↓              ↓                ↓
              [OCR Service]  [Nomic API]    [TimescaleDB]
```

### Testing Strategy

#### Integration Tests
Every service includes comprehensive `test.sh`:
```bash
#!/bin/bash
# Test health check
run_test "Health Check" \
    "curl -X GET $BASE_URL/health" \
    "200" \
    '"status":"healthy"'

# Test main endpoint
run_test "Process Data" \
    "curl -X POST -d @test/data.json $BASE_URL/process" \
    "200" \
    '"success":true'
```

#### CI/CD Pipeline
```yaml
name: Test Docker Container
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Container
        run: docker-compose build
      - name: Start Container
        run: docker-compose up -d
      - name: Run Tests
        run: ./test.sh
```

---

## Quick Start Guide

### Prerequisites
- Go 1.21+, Python 3.11+, Docker
- Optional: NVIDIA GPU for ML acceleration
- Optional: k3s/Kubernetes for production

### Development Setup
```bash
# Clone repository
git clone https://github.com/baocin/AM
cd AM

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Start core services
docker-compose up -d timescaledb nats minio

# Start ML processors
docker-compose up -d rapidocr nomic-embed yunet-face

# Run database migrations
make migrate

# Start API server
docker-compose up -d grpc-api

# Run tests
make test
./docker/test-all-services.sh
```

### Production Deployment
```bash
# Setup k3s cluster
./scripts/setup-local-dev.sh

# Deploy with Helm
helm install am ./helm/am --namespace loom

# Configure monitoring
kubectl apply -f ./k8s/monitoring/
```

---

## Roadmap

### Sprint 1 (Current)
- ✅ gRPC protocol definitions
- ✅ TimescaleDB setup with pgvector
- ✅ Docker container standards
- ✅ Basic ML processors (OCR, embeddings, face detection)

### Sprint 2
- Go API service with NATS JetStream
- OpenTelemetry integration
- Data router implementation
- Client gRPC migration

### Sprint 3
- Anomaly detection system (4-tier)
- Causal explanation layer
- Stream health tracking

### Sprint 4
- DSPy agent integration
- Notification system
- Advanced analytics

### Long-Term
- Multi-user support
- Digital twin features
- Consciousness augmentation

---

## Contact & Support

- **Email**: loom@steele.red
- **GitHub Issues**: https://github.com/baocin/AM/issues
- **Documentation**: This file and `/docs` directory
- **Commercial Licensing**: Contact for pricing

---

## Appendix: Key Innovations

### Trace ID System
Every operation is tracked with a unique trace_id that follows data through:
- Client → gRPC API → NATS → Processors → Database
- Enables debugging complex data flows
- Links all related operations across services

### Gap-Aware Anomaly Detection
- Treats missing data as behavioral signals
- Learns normal vs anomalous availability patterns
- Operates effectively with 50% data missing

### Hybrid Scaling Architecture
- Core services in k3s for orchestration
- ML processors as Docker containers anywhere
- API key authentication for secure fan-out
- Enables cloud/on-prem hybrid deployments

### Four-Tier Anomaly System
1. Individual stream analysis (River ML)
2. Cross-stream pattern detection
3. Health-aware ensemble
4. Causal explanation layer

This provides not just detection but understanding of WHY anomalies occur.

---

*Last Updated: 2025-01-10*
*Version: 1.0.0*