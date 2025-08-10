# AM: Allied Mastercomputer

[![Build Status](https://img.shields.io/badge/build-passing-green)](https://github.com/baocin/AM/actions) [![Python](https://img.shields.io/badge/python-3.11+-blue)](https://python.org) [![Docker](https://img.shields.io/badge/docker-supported-blue)](https://docker.com) [![Kubernetes](https://img.shields.io/badge/kubernetes-optional-blue)](https://kubernetes.io) [![License](https://img.shields.io/badge/license-AGPL--3.0%20%2B%20Commercial-orange)](https://www.gnu.org/licenses/agpl-3.0.en.html)

**AM** is your ultimate personal digital custodian—a privacy-first, local-first system that aggregates, processes, and analyzes *all* available timeseries data from your devices and digital life. Evolving from prototypes like [Pino](https://github.com/baocin/pino), [Loom](https://github.com/baocin/loom), [Loom v2](https://github.com/baocin/loomv2), and [Loom v3](https://github.com/baocin/loomv3), AM unifies everything into a cohesive platform. It collects raw data streams (e.g., GPS, audio, sensors), applies AI/ML processing (e.g., STT, OCR, embeddings), extracts meaningful abstractions (e.g., habits, memories), and deploys an intelligent agent for proactive insights and notifications.

Think of AM as a "second brain" that:
- Records your life's context passively.
- Derives high-level insights like "Your heart rate spiked during that meeting—likely stress from the conversation topic."
- Nudges you with timely suggestions: "Based on your GPS and calendar, you're near the gym—time for your workout?"
- Evolves into a DSPy-powered LLM agent that queries your data, detects anomalies, and acts autonomously (e.g., sending reminders or logging inferred events).

**Key Principles**:
- **Local-First**: No cloud dependencies; all processing on-device or self-hosted.
- **Privacy-Centric**: Encrypted storage, user-configurable data retention, no tracking.
- **Extensible**: Plug in new ML models (e.g., commercially viable open source models) for custom analysis.
- **Ambitious but Phased**: Start with data ingestion, build to full agent intelligence.

**Disclaimer**: This is a work-in-progress prototype. Features are experimental. Always follow local laws on data recording (e.g., audio consent). You are responsible for your usage.

## Goal & Vision

AM aims to create a comprehensive "life log" by fusing raw data into increasingly abstract layers of meaning:
1. **Raw Data Layer**: Collect everything (sensors, apps, external services).
2. **Processed Data Layer**: Apply ML for features like STT, OCR, embeddings.
3. **Insight Layer**: Detect patterns, anomalies, correlations (e.g., heart rate + GPS = exercise detection).
4. **Agent Layer**: DSPy/LLM agent analyzes abstractions, logs "memories," tracks habits, and sends proactive notifications.
5. **Ultimate Dream**: A digital twin for simulation, longevity coaching, and consciousness augmentation (long-term).

Real-world applications:
- **Health**: Correlate heart rate spikes with events (e.g., stress from emails).
- **Productivity**: Track app usage + context for focus insights.
- **Memory**: Searchable embeddings of transcribed audio, OCRed screens, and photos.
- **Legal/Safety**: Timestamped logs for disputes or emergencies.
- **Personal Growth**: Habit tracking with nudges (e.g., "You've skipped breaks—take one now").

## Features

### Data Sources (Ingestion)
- **Mobile/Wearable (Android/iOS/Watch)**: GPS, accelerometer, gyroscope, magnetometer, heart rate, steps, sleep, battery, temperature, barometer, WiFi/Bluetooth scans.
- **OS Events**: Screen on/off, app launches/closes/crashes, notifications, copied text.
- **Media**: Environmental audio (streaming), passive photos (triggered by motion/novelty), screenshots, camera photos/videos.
- **Health/External**: Steps, sleep, calendars (CalDAV for events integration), emails (IMAP/SMTP for inbox/sent monitoring), contacts (CardDAV), social media (Twitter likes/posts, GitHub activity, YouTube history/posts), budgets (Google Sheets).
- **Laptop/Desktop**: System stats (CPU/GPU/memory), browser history, keystrokes (opt-in), screen OCR.
- **Custom**: Any timeseries via generic endpoints (e.g., EEG from wearables).

### Processing Pipelines
- **Real-Time Ingestion**: WebSocket/REST/gRPC for streaming/batch; validation with JSON schemas.
- **Audio/Video**: STT (Whisper/Phi-4), voice activity detection, emotion recognition, noise filtering.
- **Images**: OCR (MoonDream2), face detection/recognition, object detection (YOLO), gaze/pose estimation (MediaPipe), license plate recognition.
- **Sensors**: Motion classification (walking/driving), geocoding (Nominatim), speed estimation.
- **Text/Analysis**: Embeddings (Nomic Embed Vision v1.5 for open commercial usage), NLP for sentiment/summarization, LLM reasoning (Phi-4 or other open source models).
- **Anomaly Detection**: Multi-tier system (River ML for streaming, Prophet for forecasting) handling 30+ streams, gap-aware, causal explanations (e.g., "Heart rate anomaly due to GPS movement").
- **Passive Photo System**: IMU-triggered low-res verification → full-res capture on novelty; off-device stitching for "journey maps."
- **Abstractions**: Time-synced feed → embeddings → searchable index → pattern mining (habits, correlations) → "memories" (inferred events like "Conversation with X about Y").

### Insights & Agent
- **Notifications**: Gotify/WebSocket for nudges (e.g., "Break time based on screen usage").
- **DSPy/LLM Agent**: Analyzes data for patterns/habits/memories; proactive (e.g., "Remind of past event relevant to current GPS").
- **Analytics**: Causal inference (e.g., "App usage caused fatigue"), multi-modal fusion (audio + sensors = activity detection).
- **Storage**: TimescaleDB for timeseries (hypertables, compression); local files for media; DuckDB for edge queries.

### Monitoring & Extensibility
- Prometheus/Grafana for metrics/logs.
- OpenTelemetry for tracing.
- Plug-and-play ML: GPU/CPU support (NVIDIA Toolkit); models like Florence2 for vision, SGLang for LLM serving.

## Architecture

AM uses a microservices design for modularity, deployable as Docker Compose (dev/small-scale) or k3s/Kubernetes (production/multi-user).

```mermaid
graph TD
    subgraph "Data Sources"
        Mobile[Mobile/Watch Apps]
        Laptop[Laptop/Desktop]
        External[APIs: Email/Calendar/Social]
    end

    subgraph "Ingestion Layer"
        API[FastAPI/gRPC/WebSocket]
        Validators[Schema Validation]
    end

    subgraph "Storage & Queue"
        DB[(TimescaleDB: Timeseries/Metadata)]
        Files[Local Files: Media]
        Queue[NATS JetStream/Kafka: Events]
    end

    subgraph "Processing Services"
        Audio[STT/Emotion]
        Vision[OCR/Object Detection]
        Sensors[Motion/Geocoding]
        Anomaly[Multi-Tier Detection]
        Embed[Embeddings/NLP]
    end

    subgraph "Agent & Insights"
        LLM[DSPy/LLM Agent]
        Notify[Notifications/Actions]
        Analytics[Causal Inference/Patterns]
    end

    subgraph "Clients"
        App[Flutter Mobile App]
        Watch[Android Watch App]
        Desktop[Rust/Tauri Desktop]
    end

    Mobile --> API
    Laptop --> API
    External --> API
    API --> Validators --> Queue --> DB
    API --> Files
    Queue --> Audio --> Embed --> LLM
    Queue --> Vision --> Embed --> LLM
    Queue --> Sensors --> Analytics --> LLM
    Queue --> Anomaly --> Analytics --> LLM
    LLM --> Notify --> App
    Notify --> Watch
    Notify --> Desktop
```

- **Event-Driven**: NATS/Kafka for async processing.
- **Scalability**: Horizontal scaling per service; user isolation via namespaces.
- **Edge Support**: Subset runs on-device (e.g., DuckDB + lightweight ML).

## Identified Problems & Mitigations

AM's ambition introduces challenges. Here's a breakdown with solutions:

| Problem | Description | Mitigation |
|---------|-------------|------------|
| **Privacy/Security** | Collecting sensitive data (audio, photos, emails) risks breaches/leaks. | - Encrypt at-rest/in-transit (AES-256/TLS).<br>- User controls: Opt-in per source, retention policies, data export/delete.<br>- Local-only mode; audit logs; GDPR/HIPAA-ready features. |
| **Battery/Power Drain** | Continuous sensors/audio drain mobile battery. | - Interrupt-driven (IMU triggers); low-res previews for photos.<br>- Adaptive sampling (e.g., reduce during sleep).<br>- Targets: <1mW baseline, 2-3 days battery. |
| **Data Volume/Storage** | TBs from audio/video/sensors overwhelm storage. | - Compression (TimescaleDB hypertables); selective capture (novelty triggers).<br>- Rolling retention (e.g., 30 days raw, permanent abstractions).<br>- Offload to external drives. |
| **Processing Overhead** | ML models (STT, LLM) require GPU/compute. | - CPU/GPU fallback; quantized models (e.g., open source models).<br>- Batch/offline processing; edge-first for real-time needs.<br>- Monitor via Prometheus; scale with k3s. |
| **Integration Reliability** | External APIs (email/social) can fail/rate-limit. | - Retry queues; caching; error handling.<br>- Polling with backoff; user alerts for auth issues. |
| **Accuracy/False Positives** | ML errors (e.g., bad STT) or noisy anomalies/notifications annoy users. | - Confidence thresholds; user feedback loops for retraining.<br>- Ensemble models; causal explanations for context.<br>- Rate-limit notifications. |
| **Legal/Ethical** | Audio recording, face detection violate laws/consent. | - User-configurable consent prompts; geo-based rules.<br>- Disclaimers; anonymization options.<br>- No sharing without explicit opt-in. |
| **Complexity/Scope Creep** | 30+ streams + ML pipelines = hard to maintain. | - Phased rollout (ingestion first, agent last).<br>- Modular services; comprehensive tests (71+ from v2).<br>- Open-source for community help. |
| **Scalability/Multi-User** | From personal to paid service. | - User namespaces in DB/Queue.<br>- Kubernetes for horizontal scaling.<br>- Start single-user; add RBAC later. |
| **Cold Start/Adaptation** | Needs data to learn; slow initial value. | - River ML for immediate streaming learning.<br>- Pre-seeded models; quick wins like basic alerts. |

## Setup & Installation

### Prerequisites
- Python 3.11+, Docker, k3s (optional), NVIDIA GPU (recommended for ML).
- Libraries: FastAPI, River, Prophet, HuggingFace (Whisper, MoonDream2, etc.).

### Quick Start (Docker Compose)
```bash
git clone https://github.com/baocin/AM
cd AM
cp .env.example .env  # Edit secrets
make setup  # Install deps, pre-commit
make dev-up  # Start services (ingestion, DB, processors)
make topics-create  # Kafka/NATS topics
make test  # Run tests
```

- Access: API at http://localhost:8000/docs; DB at postgres://loom:loom@localhost:5432/loom.
- Mobile App: Flutter setup in `/android-app` or `/flutter-app`.
- Models: Download Whisper/Phi-4 manually to `/models`.

### Production (k3s)
```bash
./scripts/setup-local-dev.sh  # Builds images, deploys cluster
```

## Contribution

Welcome! See issues for tasks. Use conventional commits; run `make lint`/`make test`. Focus: Ingestion stability, ML integrations, anomaly detection.

## Licensing

AM is dual-licensed:

- **Individual Use**: AGPL-3.0 License (free)
  - Personal use on your own devices
  - Modifications must be open sourced
  - Cannot be used in commercial products/services

- **Commercial Use**: Commercial License Required
  - For companies, organizations, or commercial products
  - For SaaS offerings or embedded use
  - Contact loom@steele.red for pricing

## Roadmap

- **Sprint 1**: Unified ingestion + basic storage.
- **Sprint 2**: Core ML pipelines (STT/OCR/anomalies).
- **Sprint 3**: Passive photo + embeddings/search.
- **Sprint 4**: DSPy agent + notifications.
- **Long-Term**: Multi-user, digital twin features.

Contact: loom@steele.red or issues. Let's build the future of personal AI!