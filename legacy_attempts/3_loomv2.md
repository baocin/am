# Loom v2

> Personal informatics data pipeline with real-time ingestion, event streaming, and Kubernetes-native deployment.

[![Tests](https://img.shields.io/badge/tests-71%20passing-green)](services/ingestion-api/tests)
[![Python](https://img.shields.io/badge/python-3.11+-blue)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-green)](https://fastapi.tiangolo.com)
[![Kubernetes](https://img.shields.io/badge/kubernetes-native-blue)](https://kubernetes.io)

Loom v2 is a modern data pipeline designed to ingest, process, and store personal informatics data from various devices including audio sensors, accelerometers, GPS, and health monitors. Built with a microservices architecture using FastAPI, Kafka, and PostgreSQL.

## 🚀 Quick Start

Get the complete Loom v2 stack running in one command:

```bash
# Clone the repository
git clone <repository-url>
cd loomv2

# One-command setup (installs dependencies, builds images, deploys k3s)
./scripts/setup-local-dev.sh
```

This script will automatically:
- ✅ Check and install dependencies (k3d, kubectl, uv)
- ✅ Build Docker images for all services
- ✅ Create k3s cluster with port mappings
- ✅ Deploy TimescaleDB with hypertables and compression
- ✅ Deploy Kafka with topics and UI
- ✅ Deploy Ingestion API with health checks
- ✅ Run database migrations
- ✅ Test the entire deployment

**Manual Setup** (if you prefer step-by-step):

```bash
# 1. Build images
./scripts/build-images.sh

# 2. Deploy to k3s
./scripts/deploy-k3s.sh

# 3. Test deployment
./scripts/test-deployment.sh
```

## 📋 Prerequisites

### Required
- **Docker** - [Get Docker](https://docs.docker.com/get-docker/) (must be running)
- **Python 3.11+** - [Download](https://python.org/downloads/)

### Auto-installed by setup script
- **k3d** - Lightweight Kubernetes distribution
- **kubectl** - Kubernetes CLI
- **uv** - Fast Python package manager

### System Requirements
- **Memory**: 4GB+ RAM (8GB recommended for AI services)
- **Storage**: 5GB+ free space
- **Network**: Internet connection for downloads
- **Ports**: 30000, 30081, 30092, 30432 (auto-configured)

## 🛠️ Architecture Overview

### 1. Environment Setup

```bash
# Install development dependencies and pre-commit hooks
make setup
```

This command will:
- Install `uv` if not present
- Install `pre-commit` hooks
- Set up the development environment

### 2. Start Development Environment

```bash
# Start all services (Kafka, PostgreSQL, Ingestion API)
make dev-up
```

This will:
- Start Docker Compose services
- Deploy Kafka, PostgreSQL, and the Ingestion API
- Set up port forwarding for local access
- Enable hot-reload for development

### 3. Verify Installation

```bash
# Check service status
make status

# View logs
make logs

# Test the API
curl http://localhost:8000/healthz
curl http://localhost:8000/metrics
```

## 🏃‍♂️ Running the Application

### Development Mode

The recommended way to run Loom v2 for development:

```bash
# Start the full development stack
make dev-up

# In another terminal, create Kafka topics
make topics-create

# Run tests to verify everything is working
make test
```

### Service Endpoints

Once running, the following services are available:

| Service | URL | Description |
|---------|-----|-------------|
| **Ingestion API** | http://localhost:8000 | Main data ingestion service |
| **API Documentation** | http://localhost:8000/docs | Interactive API docs (Swagger) |
| **Health Check** | http://localhost:8000/healthz | Service health status |
| **Metrics** | http://localhost:8000/metrics | Prometheus metrics |
| **Kafka UI** | http://localhost:8081 | Web-based Kafka monitoring and management |
| **PostgreSQL** | localhost:5432 | Database (loom/loom/loom) |
| **Kafka** | localhost:9092 | Message broker |

### Stopping Services

```bash
# Stop all services and clean up
make dev-down

# Clean up build artifacts
make clean
```

## 📡 API Usage Examples

### Health Check
```bash
curl http://localhost:8000/healthz
# Response: {"status": "healthy"}
```

### Upload Audio Data
```bash
curl -X POST http://localhost:8000/audio/upload \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "phone-001",
    "timestamp": "2024-01-01T12:00:00Z",
    "data": "SGVsbG8gV29ybGQ=",
    "format": "wav",
    "sample_rate": 44100
  }'
```

### Send GPS Data
```bash
curl -X POST http://localhost:8000/sensor/gps \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "phone-001",
    "timestamp": "2024-01-01T12:00:00Z",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 5.0,
    "speed": 2.5
  }'
```

### WebSocket Streaming (Audio)
```javascript
const ws = new WebSocket('ws://localhost:8000/audio/stream/phone-001');
ws.onopen = () => {
  ws.send(JSON.stringify({
    timestamp: new Date().toISOString(),
    data: "SGVsbG8gV29ybGQ=",
    format: "wav",
    sample_rate: 44100
  }));
};
```

## 🧪 Testing

### Run All Tests
```bash
# Run the full test suite (71 tests)
make test

# Run with coverage report
make test-coverage

# Run integration tests
make test-integration
```

### Run Specific Tests
```bash
# Test individual service
cd services/ingestion-api && make test

# Run specific test file
pytest services/ingestion-api/tests/unit/test_health.py -v

# Run tests in watch mode (development)
cd services/ingestion-api && make test-watch

# AI Service Testing Script
# First install script dependencies
uv pip install -r requirements-scripts.txt

# Test all AI services
uv run python scripts/test_ai_services.py

# Test specific service
uv run python scripts/test_ai_services.py --service nomic-embed

# Generate JSON report
uv run python scripts/test_ai_services.py --output test_results.json

# Performance testing with multiple iterations
uv run python scripts/test_ai_services.py --performance --iterations 3
```

### Test Categories
- **Unit Tests**: Individual component testing
- **Integration Tests**: End-to-end service testing
- **Health Tests**: Kubernetes probe validation
- **WebSocket Tests**: Real-time streaming functionality
- **Schema Tests**: Data validation and compatibility

## 🔧 Development Workflow

### Code Quality
```bash
# Run linting and formatting
make lint

# Format code
make format

# Run security scans
make security-scan
```

### Database Operations
```bash
# Connect to local database
make db-connect

# Create database migrations (when implemented)
alembic revision -m "add new table"
alembic upgrade head
```

### Kafka Operations
```bash
# Create topics
make topics-create

# List topics
make topics-list

# Monitor messages via CLI
kubectl exec -n loom-dev -it deployment/kafka -- \
  kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic device.audio.raw

# Monitor via Web UI (recommended)
# Open http://localhost:8081 in your browser
```

### Docker Operations
```bash
# Build Docker images
make docker

# Run service directly in Docker
cd services/ingestion-api && make docker-run
```

## 📊 Monitoring & Observability

### Kafka Monitoring with Web UI

Access the **Kafka UI** at http://localhost:8081 for comprehensive Kafka monitoring:

#### **Key Features:**
- **Real-time topic monitoring** - View messages, partitions, and configurations
- **Consumer group tracking** - Monitor lag and consumption rates
- **Message browsing** - Search and inspect individual messages
- **Cluster health** - Broker status and performance metrics
- **Topic management** - Create, configure, and delete topics via web interface

#### **Common Tasks:**
```bash
# View all topics and their message counts
# Navigate to Topics tab in Kafka UI

# Monitor consumer lag
# Go to Consumer Groups → Select group → View lag per partition

# Browse messages in a topic
# Topics → Select topic → Messages tab → Browse/Search

# Create new topics
# Topics → Create Topic → Configure partitions and replication
```

### Application Logs
```bash
# View all service logs
make logs

# View specific service logs
kubectl logs -n loom-dev -l app=ingestion-api -f
```

### Metrics
```bash
# View Prometheus metrics
curl http://localhost:8000/metrics

# Key metrics available:
# - http_requests_total
# - http_request_duration_seconds
# - websocket_connections_total
# - kafka_messages_sent_total
```

### Health Checks
```bash
# Liveness probe
curl http://localhost:8000/healthz

# Readiness probe
curl http://localhost:8000/readyz
```

## 📚 Documentation

### Core Documentation
- **[CLAUDE.md](CLAUDE.md)** - Claude Code configuration and project instructions
- **[Data Processing Flows](docs/data-processing-flows.md)** - Comprehensive guide to all 11 data pipelines
- **[Flow Specifications](docs/flows/)** - Detailed YAML specifications for each processing pipeline
- **[Storage Architecture](docs/storage.md)** - Database design patterns and TimescaleDB configuration

### Key Processing Pipelines
1. **Audio Processing** - VAD → Speech-to-Text → Environment Classification
2. **Vision Processing** - Object Detection → Face/Pose/Gaze Analysis → 3D Mapping
3. **Location Enrichment** - GPS → Geocoding → Business Identification
4. **Motion Classification** - Accelerometer → Activity Detection (walking/driving)
5. **External Data** - Email/Calendar/HackerNews → Embeddings → Search

See [docs/data-processing-flows.md](docs/data-processing-flows.md) for complete pipeline documentation.

## 🏗️ Architecture

### System Components

```mermaid
flowchart TB
    subgraph "Data Sources"
        Audio[📱 Audio Devices]
        GPS[📍 GPS Sensors]
        Accel[📊 Accelerometers]
        Heart[❤️ Heart Rate Monitors]
        Power[🔋 Power Sensors]
    end

    subgraph "Ingestion Layer"
        API[Ingestion API<br/>FastAPI:8000]
        WS[WebSocket<br/>Real-time Streaming]
        REST[REST API<br/>Batch Upload]
    end

    subgraph "Message Streaming"
        Kafka[Apache Kafka<br/>:9092]
        KafkaUI[Kafka UI<br/>:8081]

        subgraph "Topics"
            AudioTopic[device.audio.raw]
            GPSTopic[device.sensor.gps.raw]
            AccelTopic[device.sensor.accelerometer.raw]
            HeartTopic[device.health.heartrate.raw]
            PowerTopic[device.sensor.power.raw]
        end
    end

    subgraph "Storage Layer"
        PG[(PostgreSQL<br/>:5432)]
    end

    subgraph "Monitoring"
        Metrics[Prometheus Metrics<br/>/metrics]
        Health[Health Checks<br/>/healthz, /readyz]
        Logs[Structured Logging<br/>JSON Format]
    end

    subgraph "Development Tools"
        Compose[Docker Compose<br/>Local Environment]
        Make[Makefile Commands<br/>Dev Orchestration]
    end

    %% Data Flow
    Audio --> REST
    GPS --> REST
    Accel --> REST
    Heart --> REST
    Power --> REST
    Audio -.->|real-time| WS

    REST --> API
    WS --> API

    API --> AudioTopic
    API --> GPSTopic
    API --> AccelTopic
    API --> HeartTopic
    API --> PowerTopic

    AudioTopic --> Kafka
    GPSTopic --> Kafka
    AccelTopic --> Kafka
    HeartTopic --> Kafka
    PowerTopic --> Kafka

    Kafka --> PG
    Kafka -.-> KafkaUI

    API --> Metrics
    API --> Health
    API --> Logs

    Compose --> API
    Compose --> Kafka
    Compose --> PG
    Make --> Compose

    classDef service fill:#4CAF50,stroke:#333,stroke-width:2px,color:#fff
    classDef storage fill:#2196F3,stroke:#333,stroke-width:2px,color:#fff
    classDef monitor fill:#FF9800,stroke:#333,stroke-width:2px,color:#fff
    classDef topic fill:#9C27B0,stroke:#333,stroke-width:2px,color:#fff
    classDef device fill:#F44336,stroke:#333,stroke-width:2px,color:#fff
    classDef tool fill:#607D8B,stroke:#333,stroke-width:2px,color:#fff

    class API,WS,REST service
    class Kafka,PG storage
    class Metrics,Health,Logs,KafkaUI monitor
    class AudioTopic,GPSTopic,AccelTopic,HeartTopic,PowerTopic topic
    class Audio,GPS,Accel,Heart,Power device
    class Compose,Make tool
```

### Data Flow
1. **Devices** send data via REST API or WebSocket to the **Ingestion API**
2. **Ingestion API** validates data using JSON schemas and publishes to **Kafka Topics**
3. **Kafka** provides durable message streaming with topic-based routing
4. **PostgreSQL** stores processed data for long-term persistence (future implementation)
5. **Monitoring** tools track system health, metrics, and logs

### Key Technologies
- **FastAPI**: High-performance async web framework
- **Kafka**: Event streaming and message queuing
- **PostgreSQL**: Reliable relational database (with TimescaleDB for time-series data)
- **Kubernetes**: Container orchestration
- **Docker Compose**: Alternative development environment

## 🔧 Configuration

### Environment Variables

All configuration uses the `LOOM_` prefix:

```bash
# Database
export LOOM_DATABASE_URL="postgresql://loom:loom@localhost:5432/loom"

# Kafka
export LOOM_KAFKA_BOOTSTRAP_SERVERS="localhost:9092"

# API Server
export LOOM_HOST="0.0.0.0"
export LOOM_PORT=8000
export LOOM_LOG_LEVEL="INFO"

# Development
export LOOM_ENVIRONMENT="development"
export LOOM_DEBUG=true
```

### Configuration Files
- **Makefile**: Development commands and orchestration
- **Tiltfile**: Local Kubernetes development setup
- **pyproject.toml**: Python dependencies and tool configuration
- **deploy/**: Kubernetes manifests and Helm charts

## 🐛 Troubleshooting

### Common Issues

#### Development environment won't start
```bash
# Check Docker Compose services
docker-compose -f docker-compose.local.yml ps

# Check Docker daemon status
docker info

# Restart services if needed
make dev-down
make dev-up
```

#### Service crashes
```bash
# Check container status
docker-compose -f docker-compose.local.yml ps

# View detailed container info
docker inspect <container-name>

# Check logs
docker-compose -f docker-compose.local.yml logs <service-name>
```

#### Database connection issues
```bash
# Test direct connection
make db-connect

# Check database credentials
kubectl get secrets -n loom-dev postgres-secret -o yaml
```

#### Kafka issues
```bash
# Verify topics exist
make topics-list

# Check Kafka logs
kubectl logs -n loom-dev deployment/kafka
```

### Debug Mode

```bash
# Enable debug logging
export LOOM_LOG_LEVEL=DEBUG

# Run service directly (outside Kubernetes)
cd services/ingestion-api
uv run uvicorn app.main:app --reload --log-level debug
```

### Getting Help

1. Check the [troubleshooting section](#troubleshooting)
2. Review service logs: `make logs`
3. Verify service status: `make status`
4. Check the API docs: http://localhost:8000/docs
5. Examine the test suite for usage examples

## 🤝 Contributing

### Development Setup
```bash
# Fork the repository and clone
git clone <your-fork-url>
cd loomv2

# Set up development environment
make setup
make dev-up

# Create a feature branch
git checkout -b feature/your-feature

# Make changes and test
make test
make lint

# Commit and push
git commit -m "feat: add your feature"
git push origin feature/your-feature
```

### Code Standards
- **Python**: Black formatting, Ruff linting, mypy type checking
- **Tests**: Comprehensive test coverage required
- **Documentation**: Update README and API docs
- **Commits**: Use conventional commit messages

### Pull Request Process
1. Ensure all tests pass: `make test`
2. Run code quality checks: `make lint`
3. Update documentation if needed
4. Create PR with clear description
5. All checks must pass for merge

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏷️ Project Status

- **Sprint 0**: ✅ Complete - Infrastructure, pre-commit hooks, k3d environment
- **Sprint 1**: ✅ Complete - Comprehensive test suite (71 tests), CI/CD
- **Sprint 2**: ✅ Complete - Core infrastructure, schema validation
- **Sprint 3**: ✅ Complete - Storage abstraction layer, migrations
- **Sprint 4**: ✅ Complete - Kafka optimization, service architecture
- **Sprint 5**: ✅ Complete - OS event tracking, mobile app integration
- **Sprint 6**: 🚧 In Progress - AI model integration, documentation cleanup

---

**Quick Reference**: `make setup && make dev-up` → http://localhost:8000

