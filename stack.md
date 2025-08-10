# AM Technical Stack Documentation

## Table of Contents
1. [Overview](#overview)
2. [Data Flow Architecture](#data-flow-architecture)
3. [Protocol Layer (gRPC)](#protocol-layer-grpc)
4. [Message Queue (NATS JetStream)](#message-queue-nats-jetstream)
5. [Storage Layer (TimescaleDB + pgvector)](#storage-layer-timescaledb--pgvector)
6. [Processing Pipeline](#processing-pipeline)
7. [Observability](#observability)
8. [Client Implementation](#client-implementation)
9. [Deployment Architecture](#deployment-architecture)

## Overview

AM employs a distributed, event-driven architecture designed for high-throughput data ingestion, real-time processing, and scalable analytics. The system processes 10,000+ messages/second while maintaining sub-100ms latency for real-time operations.

### Core Technologies
- **Protocol**: gRPC with Protocol Buffers v3
- **Languages**: Go (services), Python (ML), Kotlin/Dart (clients)
- **Message Queue**: NATS JetStream
- **Database**: TimescaleDB with pgvector
- **Observability**: OpenTelemetry + Prometheus + Jaeger
- **Container**: Docker + Kubernetes/k3s

## Data Flow Architecture

```
[Client Device] → [gRPC] → [Go API Server] → [NATS JetStream] → [Data Router]
                                ↓                                      ↓
                        [OpenTelemetry]                    [Processing Services]
                                ↓                                      ↓
                            [Jaeger]                          [TimescaleDB]
                                                                      ↓
                                                              [Analytics/Agent]
```

### Flow Stages

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
   - OpenTelemetry span creation
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

## Protocol Layer (gRPC)

### Protocol Buffer Structure

```protobuf
// proto/v1/common/types.proto
syntax = "proto3";
package loom.common.v1;

import "google/protobuf/timestamp.proto";

message SensorReading {
  string device_id = 1;
  string reading_id = 2;
  google.protobuf.Timestamp recorded_at = 3;
  map<string, string> metadata = 4;
  
  oneof data {
    HeartRateData heart_rate = 10;
    GPSData gps = 11;
    AccelerometerData accelerometer = 12;
    AudioChunk audio = 13;
    ImageData image = 14;
  }
}

message HeartRateData {
  int32 bpm = 1;
  float confidence = 2;
  HeartRateZone zone = 3;
  string source = 4;  // "watch", "chest_strap", etc.
  
  enum HeartRateZone {
    ZONE_UNSPECIFIED = 0;
    ZONE_RESTING = 1;
    ZONE_FAT_BURN = 2;
    ZONE_CARDIO = 3;
    ZONE_PEAK = 4;
  }
}
```

### Service Definition

```protobuf
// proto/v1/gateway/data_ingestion.proto
service DataIngestionService {
  // Bidirectional streaming for real-time data
  rpc StreamData(stream SensorReading) returns (stream DataResponse);
  
  // Unary for batch uploads
  rpc BatchUpload(BatchRequest) returns (BatchResponse);
  
  // Device registration
  rpc RegisterDevice(DeviceInfo) returns (RegistrationResponse);
  
  // Health check
  rpc HealthCheck(HealthRequest) returns (HealthResponse);
}
```

### gRPC Benefits
- **Performance**: Binary protocol, HTTP/2 multiplexing
- **Type Safety**: Generated code eliminates serialization errors
- **Streaming**: Native bidirectional streaming support
- **Language Support**: Clients in any language
- **Compression**: Built-in gzip/snappy support

## Message Queue (NATS JetStream)

### Stream Configuration

```yaml
# NATS JetStream Configuration
streams:
  - name: sensor-data
    subjects: 
      - "sensor.>"          # All sensor data
      - "wearable.>"       # Wearable-specific
      - "mobile.>"         # Mobile app data
    retention: limits
    max_age: 7d            # 7 days retention
    max_bytes: 100GB
    max_msg_size: 1MB
    replicas: 3            # For HA
    
  - name: ml-processing
    subjects:
      - "ml.ocr"
      - "ml.stt"
      - "ml.embeddings"
    retention: work_queue  # Delete after processing
    max_age: 1h
    ack_wait: 5m          # Processing timeout
    max_deliver: 3        # Retry count
```

### Consumer Groups

```go
// Go consumer implementation
type Consumer struct {
    js      nats.JetStreamContext
    subject string
}

func (c *Consumer) Start(ctx context.Context) error {
    // Durable consumer for at-least-once delivery
    sub, err := c.js.PullSubscribe(
        c.subject,
        "data-router-group",  // Consumer group name
        nats.Durable("processor"),
        nats.AckExplicit(),
        nats.MaxDeliver(3),
        nats.AckWait(30*time.Second),
    )
    
    for {
        msgs, err := sub.Fetch(100, nats.MaxWait(time.Second))
        for _, msg := range msgs {
            go c.processMessage(msg)  // Parallel processing
        }
    }
}
```

### Message Patterns

1. **Pub/Sub**: Real-time notifications
2. **Queue Groups**: Load balancing across consumers
3. **Request/Reply**: Synchronous operations
4. **Key/Value Store**: Configuration and state

## Storage Layer (TimescaleDB + pgvector)

### Schema Design

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS vector;

-- Main sensor data table
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

-- Create indexes for common queries
CREATE INDEX idx_sensor_type_time 
    ON sensor_readings (reading_type, recorded_at DESC);
CREATE INDEX idx_sensor_metadata 
    ON sensor_readings USING GIN (metadata);

-- Compression policy for old data
ALTER TABLE sensor_readings SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id,reading_type',
    timescaledb.compress_orderby = 'recorded_at DESC'
);

SELECT add_compression_policy('sensor_readings', INTERVAL '7 days');
```

### Vector Storage for ML

```sql
-- Embeddings table for semantic search
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id TEXT NOT NULL,  -- Reference to original data
    source_type TEXT NOT NULL,  -- 'audio', 'image', 'text'
    embedding vector(768),  -- Nomic embed dimension
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- HNSW index for fast similarity search
CREATE INDEX ON embeddings 
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Function for semantic search
CREATE FUNCTION search_similar(
    query_embedding vector(768),
    limit_count INT DEFAULT 10
) RETURNS TABLE (
    id UUID,
    source_id TEXT,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id,
        e.source_id,
        1 - (e.embedding <=> query_embedding) as similarity
    FROM embeddings e
    ORDER BY e.embedding <=> query_embedding
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;
```

### Continuous Aggregates

```sql
-- Real-time heart rate statistics
CREATE MATERIALIZED VIEW heart_rate_stats
WITH (timescaledb.continuous) AS
SELECT 
    device_id,
    time_bucket('5 minutes', recorded_at) AS bucket,
    AVG((data->>'bpm')::INT) as avg_bpm,
    MIN((data->>'bpm')::INT) as min_bpm,
    MAX((data->>'bpm')::INT) as max_bpm,
    COUNT(*) as reading_count
FROM sensor_readings
WHERE reading_type = 'heart_rate'
GROUP BY device_id, bucket
WITH NO DATA;

-- Refresh policy
SELECT add_continuous_aggregate_policy(
    'heart_rate_stats',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes'
);
```

## Processing Pipeline

### Data Router Architecture

```go
// internal/router/engine.go
type RoutingEngine struct {
    rules    []RoutingRule
    clients  map[string]ServiceClient
    db       *TimescaleDB
    metrics  *Metrics
}

type RoutingRule struct {
    Name       string
    Conditions []Condition
    Target     ServiceTarget
    Transform  TransformFunc
}

func (e *RoutingEngine) Route(msg *Message) error {
    span := e.startSpan("route_message")
    defer span.End()
    
    // Find matching rules
    for _, rule := range e.rules {
        if rule.Matches(msg) {
            // Apply transformation
            transformed := rule.Transform(msg)
            
            // Get service client with circuit breaker
            client := e.clients[rule.Target.Service]
            
            // Send to processing service
            result, err := client.Process(transformed)
            if err != nil {
                return e.handleError(msg, err)
            }
            
            // Store results
            return e.db.StoreResult(msg.ID, result)
        }
    }
    
    // No matching rule - store raw
    return e.db.StoreRaw(msg)
}
```

### Processing Service Integration

```yaml
# Routing configuration
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
      transform:
        type: "base64_encode"
        
    - name: "face_detection"
      conditions:
        - field: "data_type"
          operator: "equals"
          value: "image"
        - field: "metadata.detect_faces"
          operator: "equals"
          value: "true"
      target:
        service: "yunet"
        endpoint: "/api/v1/detect"
        timeout: 15s
        
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

### Circuit Breaker Pattern

```go
// Circuit breaker for service calls
breaker := gobreaker.NewCircuitBreaker(gobreaker.Settings{
    Name:        "OCR-Service",
    MaxRequests: 100,
    Interval:    10 * time.Second,
    Timeout:     30 * time.Second,
    ReadyToTrip: func(counts gobreaker.Counts) bool {
        failureRatio := float64(counts.TotalFailures) / float64(counts.Requests)
        return counts.Requests >= 10 && failureRatio >= 0.5
    },
    OnStateChange: func(name string, from, to gobreaker.State) {
        log.Printf("Circuit breaker %s: %s -> %s", name, from, to)
    },
})

// Use circuit breaker
result, err := breaker.Execute(func() (interface{}, error) {
    return client.CallService(request)
})
```

## Observability

### OpenTelemetry Setup

```go
// Tracer initialization
func InitTracer() (*trace.TracerProvider, error) {
    exporter, err := jaeger.New(
        jaeger.WithCollectorEndpoint(
            jaeger.WithEndpoint("http://jaeger:14268/api/traces"),
        ),
    )
    
    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(resource.NewWithAttributes(
            semconv.ServiceNameKey.String("loom-api"),
            semconv.ServiceVersionKey.String("1.0.0"),
        )),
        trace.WithSampler(trace.AlwaysSample()),
    )
    
    otel.SetTracerProvider(tp)
    return tp, nil
}

// Instrument gRPC server
func NewGRPCServer() *grpc.Server {
    return grpc.NewServer(
        grpc.UnaryInterceptor(
            otelgrpc.UnaryServerInterceptor(),
        ),
        grpc.StreamInterceptor(
            otelgrpc.StreamServerInterceptor(),
        ),
    )
}
```

### Metrics Collection

```go
// Prometheus metrics
var (
    messagesReceived = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "loom_messages_received_total",
            Help: "Total messages received by type",
        },
        []string{"type", "source"},
    )
    
    processingDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "loom_processing_duration_seconds",
            Help:    "Processing duration by service",
            Buckets: prometheus.DefBuckets,
        },
        []string{"service", "status"},
    )
)
```

### Distributed Tracing Example

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

## Client Implementation

### Android/Kotlin gRPC Client

```kotlin
// GrpcDataService.kt
class GrpcDataService(
    private val config: ClientConfig
) {
    private lateinit var channel: ManagedChannel
    private lateinit var stub: DataIngestionServiceGrpc.DataIngestionServiceStub
    private lateinit var streamObserver: StreamObserver<SensorReading>
    
    fun connect() {
        channel = ManagedChannelBuilder
            .forAddress(config.host, config.port)
            .keepAliveTime(30, TimeUnit.SECONDS)
            .keepAliveTimeout(15, TimeUnit.SECONDS)
            .maxInboundMessageSize(4 * 1024 * 1024)  // 4MB
            .intercept(AuthInterceptor(config.apiKey))
            .build()
            
        stub = DataIngestionServiceGrpc.newStub(channel)
        startBidirectionalStream()
    }
    
    private fun startBidirectionalStream() {
        val responseObserver = object : StreamObserver<DataResponse> {
            override fun onNext(response: DataResponse) {
                handleServerResponse(response)
            }
            
            override fun onError(t: Throwable) {
                Log.e(TAG, "Stream error", t)
                reconnectWithBackoff()
            }
            
            override fun onCompleted() {
                Log.d(TAG, "Stream completed")
            }
        }
        
        streamObserver = stub.streamData(responseObserver)
    }
    
    fun sendHeartRate(bpm: Int, confidence: Float) {
        val reading = SensorReading.newBuilder()
            .setDeviceId(deviceId)
            .setReadingId(UUID.randomUUID().toString())
            .setRecordedAt(Timestamps.now())
            .setHeartRate(
                HeartRateData.newBuilder()
                    .setBpm(bpm)
                    .setConfidence(confidence)
                    .setZone(calculateZone(bpm))
                    .setSource("watch")
            )
            .build()
            
        try {
            streamObserver.onNext(reading)
        } catch (e: Exception) {
            offlineQueue.add(reading)
        }
    }
}
```

### Flutter/Dart gRPC Client

```dart
// grpc_data_service.dart
class GrpcDataService {
  late ClientChannel _channel;
  late DataIngestionServiceClient _client;
  StreamController<SensorReading>? _controller;
  final Queue<SensorReading> _offlineQueue = Queue();
  
  Future<void> connect() async {
    _channel = ClientChannel(
      config.host,
      port: config.port,
      options: ChannelOptions(
        credentials: config.useTls 
            ? ChannelCredentials.secure()
            : ChannelCredentials.insecure(),
        keepAlive: ClientKeepAliveOptions(
          pingInterval: Duration(seconds: 30),
        ),
      ),
    );
    
    _client = DataIngestionServiceClient(_channel);
    await _startStream();
  }
  
  Future<void> _startStream() async {
    _controller = StreamController<SensorReading>();
    
    final responseStream = _client.streamData(_controller!.stream);
    
    responseStream.listen(
      _handleResponse,
      onError: _handleError,
      onDone: _handleDone,
    );
    
    // Process offline queue
    while (_offlineQueue.isNotEmpty) {
      _controller!.add(_offlineQueue.removeFirst());
    }
  }
  
  Future<void> sendSensorData(Map<String, dynamic> data) async {
    final reading = SensorReading()
      ..deviceId = _deviceId
      ..readingId = Uuid().v4()
      ..recordedAt = Timestamp.fromDateTime(DateTime.now())
      ..metadata.addAll(data['metadata'] ?? {});
      
    // Set data based on type
    switch (data['type']) {
      case 'heart_rate':
        reading.heartRate = _buildHeartRateData(data);
        break;
      case 'gps':
        reading.gps = _buildGpsData(data);
        break;
      // ... other types
    }
    
    if (_controller != null && !_controller!.isClosed) {
      _controller!.add(reading);
    } else {
      _offlineQueue.add(reading);
    }
  }
}
```

## Deployment Architecture

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
      - ./migrations:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U loom"]
      interval: 10s
      timeout: 5s
      retries: 5

  nats:
    image: nats:latest
    command: 
      - "-js"                # Enable JetStream
      - "-m=8222"            # Monitoring port
      - "-sd=/data"          # Storage directory
    ports:
      - "4222:4222"          # Client port
      - "8222:8222"          # Monitoring port
    volumes:
      - nats_data:/data
    healthcheck:
      test: ["CMD", "nats", "account", "info"]
      interval: 10s
      timeout: 5s
      retries: 5

  # API Services
  grpc-api:
    build: ./api
    ports:
      - "50051:50051"       # gRPC port
      - "8080:8080"         # Health/metrics
    environment:
      NATS_URL: nats://nats:4222
      DB_URL: postgresql://loom:${DB_PASSWORD}@timescaledb:5432/loomdb
      OTEL_EXPORTER_JAEGER_ENDPOINT: http://jaeger:14268/api/traces
    depends_on:
      - nats
      - timescaledb
      - jaeger
    healthcheck:
      test: ["CMD", "grpcurl", "-plaintext", "localhost:50051", "grpc.health.v1.Health/Check"]
      interval: 30s
      timeout: 10s
      retries: 3

  data-router:
    build: ./docker/nats-data-router
    environment:
      NATS_URL: nats://nats:4222
      DB_URL: postgresql://loom:${DB_PASSWORD}@timescaledb:5432/loomdb
      ROUTING_CONFIG: /app/configs/routing-rules.yaml
    volumes:
      - ./configs:/app/configs:ro
    depends_on:
      - nats
      - timescaledb
    restart: unless-stopped

  # ML Processing Services
  rapidocr:
    build: ./docker/rapidocr-raw-api
    ports:
      - "8001:8000"
    volumes:
      - ./models/rapidocr:/app/models:ro
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

  nomic-embed:
    build: ./docker/nomic-embed-api
    ports:
      - "8002:8000"
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 2G

  yunet-face:
    build: ./docker/yunet-face-detection
    ports:
      - "8003:8000"
    volumes:
      - ./models/yunet:/app/models:ro

  # Observability
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"       # Jaeger UI
      - "14268:14268"       # Collector HTTP
    environment:
      COLLECTOR_ZIPKIN_HOST_PORT: :9411

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./configs/grafana:/etc/grafana/provisioning:ro

volumes:
  timescale_data:
  nats_data:
  prometheus_data:
  grafana_data:

networks:
  default:
    name: loom-network
```

### Kubernetes Production

```yaml
# k8s/grpc-api-deployment.yaml
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
        livenessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 10
        readinessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: grpc-api
  namespace: loom
spec:
  type: LoadBalancer
  ports:
  - port: 50051
    targetPort: 50051
    name: grpc
  - port: 8080
    targetPort: 8080
    name: metrics
  selector:
    app: grpc-api
```

### Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: grpc-api-hpa
  namespace: loom
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: grpc-api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: grpc_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"
```

## Performance Characteristics

### Throughput
- **Ingestion**: 10,000+ messages/second per API instance
- **Processing**: 100-1,000 messages/second depending on ML model
- **Storage**: 50,000+ writes/second to TimescaleDB
- **Query**: Sub-100ms for time-range queries with indexes

### Latency
- **gRPC Round-trip**: 10-50ms (LAN), 50-200ms (WAN)
- **NATS Publishing**: <1ms
- **Database Write**: 5-20ms (batched)
- **ML Processing**: 100ms-30s depending on model

### Resource Usage
- **API Server**: 256MB RAM, 0.25 CPU cores baseline
- **Data Router**: 512MB RAM, 0.5 CPU cores
- **TimescaleDB**: 4GB+ RAM recommended
- **NATS**: 256MB RAM, minimal CPU
- **ML Services**: 1-4GB RAM per service

### Scalability
- **Horizontal**: All services stateless except database
- **Vertical**: Database benefits from more RAM/CPU
- **Sharding**: TimescaleDB supports distributed hypertables
- **Multi-tenant**: Device ID partitioning for isolation

## Security Considerations

### Authentication & Authorization
- JWT tokens with 1-hour expiry
- API key rotation every 90 days
- mTLS for service-to-service communication
- Row-level security in TimescaleDB

### Encryption
- TLS 1.3 for all network traffic
- AES-256 for data at rest
- Certificate pinning for mobile clients
- Secrets management via Kubernetes secrets

### Privacy
- PII anonymization options
- GDPR-compliant data deletion
- Audit logging for all access
- Configurable retention policies

## Conclusion

This architecture provides a robust, scalable foundation for AM's ambitious goals. The combination of gRPC for efficient data transmission, NATS JetStream for reliable messaging, TimescaleDB for time-series storage, and comprehensive observability ensures the system can handle the demands of continuous, multi-modal data collection and processing while maintaining privacy and performance.