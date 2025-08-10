Architecture Flow
mermaidgraph TD
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

    subgraph "Configuration"
        WorkerRegistry[Worker Registry Table]
        WorkerRegistry -->|Config| AudioConsumer
        WorkerRegistry -->|Config| SensorConsumer
        WorkerRegistry -->|Config| ImageConsumer
    end
Key Corrections & Enhancements
1. User/Client Management Tables
sql-- Users table (account level)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    tier TEXT NOT NULL DEFAULT 'free', -- free, pro, enterprise
    max_clients INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Invite codes (for client linking)
CREATE TABLE invite_codes (
    code TEXT PRIMARY KEY DEFAULT encode(gen_random_bytes(12), 'hex'),
    user_id UUID REFERENCES users(id),
    client_name TEXT,
    used BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '7 days',
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

-- Worker registry
CREATE TABLE worker_types (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL, -- 'audio_stt', 'image_ocr', etc
    endpoint_url TEXT NOT NULL,
    destination_table TEXT NOT NULL,
    input_schema JSONB,
    output_schema JSONB,
    enabled BOOLEAN DEFAULT TRUE,
    api_key TEXT -- For worker auth
);
2. MinIO Setup (docker-compose.yml)
yamlservices:
  minio:
    image: minio/minio:latest
    container_name: am-minio
    ports:
      - "9000:9000"
      - "9001:9001" # Console
    volumes:
      - ./data/minio:/data
      - ./data/minio-config:/root/.minio
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-minioadmin}
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
3. WebSocket Server Enhancement (Go)
gotype IncomingData struct {
    ClientID  string          `json:"client_id"`
    UserID    string          `json:"user_id"`
    Type      string          `json:"type"` // audio, image, sensor
    Timestamp time.Time       `json:"timestamp"`
    Data      json.RawMessage `json:"data"`
    Size      int64           `json:"size,omitempty"`
}

func (s *Server) handleData(data IncomingData) error {
    // Large files go to MinIO first
    if data.Type == "audio" || data.Type == "image" || data.Type == "video" {
        objectKey := fmt.Sprintf("%s/%s/%s-%s", 
            data.UserID, data.Type, data.Timestamp.Format("20060102"), uuid.New())
        
        // Upload to MinIO
        info, err := s.minioClient.PutObject(ctx, "am-data", objectKey, ...)
        
        // Update message with S3 reference
        data.Data = json.RawMessage(fmt.Sprintf(`{"s3_url": "s3://am-data/%s", "size": %d}`, 
            objectKey, info.Size))
    }
    
    // Publish to user-specific NATS topic
    topic := fmt.Sprintf("user.%s.%s", data.UserID, data.Type)
    return s.natsConn.Publish(topic, data)
}
4. NATS Consumer Pattern (Python)
pythonclass WorkerConsumer:
    def __init__(self, worker_type: str):
        self.worker_type = worker_type
        self.worker_config = self.load_worker_config(worker_type)
        self.db = TimescaleDBClient()
        self.http_client = httpx.AsyncClient(timeout=30.0)
        
    def load_worker_config(self, worker_type: str):
        # Load from worker_types table
        query = "SELECT * FROM worker_types WHERE name = %s AND enabled = true"
        return db.fetch_one(query, (worker_type,))
    
    async def process_message(self, msg):
        data = json.loads(msg.data)
        
        # Download from S3 if needed
        if "s3_url" in data.get("data", {}):
            file_data = await self.download_from_s3(data["data"]["s3_url"])
            data["data"]["content"] = file_data
        
        # Call worker API
        headers = {"X-API-Key": self.worker_config["api_key"]}
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
                result=result
            )
5. Worker API Pattern (Stateless)
python# Simple worker that ONLY processes, doesn't save
@app.post("/process")
async def process_audio(request: AudioRequest):
    # Validate API key
    # Process audio (STT, etc)
    # Return result
    return {
        "transcript": transcript,
        "confidence": confidence,
        "duration_ms": duration
    }
Implementation Order for MVP

Week 1: Core Infrastructure

Set up MinIO
Create DB tables (users, clients, workers)
Basic WebSocket server


Week 2: Data Flow

NATS consumer framework
Worker registry loading
S3 upload/download logic


Week 3: Auth & Scaling

Invite code generation/validation
API key auth for workers
Docker container setup for workers



Key Benefits of This Design

Separation of Concerns: Workers only process, consumers handle DB writes
Easy Scaling: Workers can run anywhere (cloud, on-prem) with just API keys
Tier Enforcement: Check client limits at WebSocket level
Flexible Storage: Large files in S3, metadata in TimescaleDB
Worker Registry: Dynamic configuration without code changes

This architecture gives you maximum flexibility for your hybrid scaling approach!
