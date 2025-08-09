The next installment of the ever lingering side project. Originally [pino](https://github.com/baocin/pino), then [loom](https://github.com/baocin/loom), then [loomv2](https://github.com/baocin/loomv2), breifly [loomv3](https://github.com/baocin/loomv3) but now finally {totally} settling on the forever repo - 

# *AM*
### As in, "I, AM" and short for "Allied Mastercomputer"

*AM* is a custodian of all digital timeseries dataset an individual has access to. Typical sensors like gps, heart rate, ocred screen text, environmental audio, speech, motion, android app launch/close events, any manual screenshots taken, copied text, etc. Anything and everything. Including data not on your phone - but your watch, laptop, calendars, email, and some (hopefully more) social media sites. A time-synced feed of as much context an LLM background agent could ask for. Then we crunch it. OCR on all photos, STT on all audio, LLM analysis of all text, all of it embedded - searchable. Then a DSPY agent is let loose to analyze, find patterns, track habits, keep a log of *memories*, aspects inferred from your true behavior. And then makes suggestions - nudges, over real time custom notifications - where the LLM decides what is helpful to ask you, mention to you, proactively reminding you of events, memories, facts relevant to your immediate task. An LLM that doesn't need your explicit prompt to be useful - it knows what is happening. It can help. 


----------------------------------
Old description:

Loom v2 Project Description
This document provides a comprehensive overview of the Loom v2 project, a scalable, event-driven system designed to ingest, process, and analyze high-throughput multimodal data streams for a multi-user paid service. It details the technology stack, architecture, supported data streams, key considerations, and requirements to ensure a successful handoff to a new development team. The system is containerized using k3s for a monolith-like deployment experience, with support for GPU acceleration and CPU fallback, and is optimized for robustness, scalability, and maintainability.

1. Project Overview
Purpose: Loom v2 is a privacy-first platform that collects, processes, and derives insights from diverse data streams (e.g., audio, images, videos, EEG, sensors) to provide personalized notifications and actions via a Flutter mobile app and Android native watch app. It supports multi-user scalability as a paid service, with local processing capabilities to minimize cloud dependency.
Core Features:

Data Ingestion: Accepts real-time and batched data via REST, WebSocket, and gRPC.
AI Processing: Uses MoonDream2 (OCR, gaze detection), MediaPipe (pose detection), and Phi-4 (speech-to-text, reasoning) for multimodal analysis.
Event-Driven Architecture: Processes data asynchronously using NATS JetStream.
Storage: Persists time-series data in TimescaleDB and large files locally.
Notifications: Delivers insights via WebSocket to Flutter and Android apps.
Tracing: Implements OpenTelemetry for end-to-end trace IDs.
Deployment: Runs as a k3s-bound container set, with GPU support and CPU fallback.

Goals:

Support high-throughput data streams with sub-second latency for critical tasks.
Ensure scalability for multiple users with data isolation.
Maintain simplicity for development and deployment.
Enable local processing for privacy compliance (e.g., GDPR, HIPAA).
Allow testing on diverse hardware (GPU and CPU-only systems).


2. Technology Stack
The technology stack is chosen for performance, scalability, and developer productivity, with a focus on containerization and modularity.
Backend

Language: Go (v1.21+)

Reason: High performance, concurrency with goroutines, and robust ecosystem for microservices.


Framework: None (standard library + Gorilla Mux for HTTP, gRPC for RPC)

Reason: Minimal dependencies for maintainability.


Message Queue: NATS JetStream (v2.10+)

Reason: Lightweight, high-throughput event streaming with durable subscriptions NATS.io.


Database: TimescaleDB (v2.11+, PostgreSQL 15)

Reason: Optimized for time-series data (e.g., EEG, sensor data) with hypertable compression TimescaleDB.


Containerization: Docker (v24+)

Reason: Standard for packaging services and dependencies.


Orchestration: k3s (v1.28.3+k3s1)

Reason: Lightweight Kubernetes for single-node deployments, suitable for servers and testing k3s Documentation.


GPU Support: NVIDIA Container Toolkit (v1.14+), CUDA (12.2)

Reason: Accelerates AI tasks (e.g., Phi-4, MoonDream2) NVIDIA Container Toolkit.


Tracing: OpenTelemetry (v1.20+)

Reason: Provides trace IDs for debugging across microservices OpenTelemetry.


Monitoring: Prometheus (v2.47+), Grafana (v10+)

Reason: Metrics collection and visualization for performance and health.



AI Models

MoonDream2: OCR and gaze detection for images and videos.

Source: Hugging Face.
Reason: Lightweight, suitable for edge and server deployment.


MediaPipe: Pose detection for videos and real-time streams.

Source: MediaPipe.
Reason: Optimized for real-time processing, low resource usage.


Phi-4 Multimodal Instruct: Speech-to-text (STT) and DSPy reasoning for audio and insights.

Source: Hugging Face.
Reason: Multimodal capabilities, GPU/CPU support.



Frontend

Mobile App: Flutter (v3.16+)

Reason: Cross-platform (iOS, Android, desktop) with native performance Flutter.


Watch App: Android Native (Kotlin, Android Wear OS 4.0+)

Reason: Optimized for low-power wearables Android Wear OS.



Development Tools

Build System: Make (GNU Make 4.3+)

Reason: Simplifies development and deployment workflows.


CI/CD: GitHub Actions (optional for automated testing)

Reason: Streamlines testing and deployment pipelines.


Helm: v3.12+

Reason: Manages k3s deployments with templated manifests Helm.




3. Architecture
Loom v2 uses an event-driven microservices architecture, orchestrated by k3s, to process high-throughput data streams. The system is designed for modularity, scalability, and maintainability, with a monolith-like deployment experience.
Components

Ingestion Service (Go)

Accepts data via REST, WebSocket, and gRPC.
Publishes metadata to NATS (e.g., user.<user_id>.data.raw).
Stores large files (images, videos) locally, with metadata in NATS.


Storage Service (Go)

Subscribes to NATS raw data events.
Persists metadata and time-series data (e.g., EEG, sensors) in TimescaleDB.


Processing Services (Go)

STT Processor: Uses Phi-4 for audio transcription.
OCR Processor: Uses MoonDream2 for image/video analysis.
Pose Processor: Uses MediaPipe for pose detection.
EEG Processor: Processes high-frequency EEG data with artifact removal.
Subscribes to NATS stored data events (e.g., user.<user_id>.data.stored).


DSPy Service (Go)

Uses Phi-4 for reasoning and action generation (e.g., notifications).
Subscribes to processed data events (e.g., user.<user_id>.audio.transcribed).


Embedding Service (Go)

Generates embeddings for text, images, and audio.
Subscribes to processed data events.


Correlation & Causation Service (Go)

Analyzes time-series data for patterns.
Runs as a background process, subscribing to processed events.


NATS JetStream

Handles event-driven communication with durable streams.
Uses subject hierarchies for user isolation (e.g., user.<user_id>.*).


TimescaleDB

Stores time-series data with hypertables for EEG, sensors, and health data.
Supports compression for efficient storage.


Flutter Mobile App

Collects sensor data, sends to ingestion service via gRPC/WebSocket.
Displays insights and notifications via WebSocket.


Android Watch App (Kotlin)

Collects wearable data (e.g., heart rate, EEG).
Syncs with backend or mobile app via WebSocket.



Data Flow

Ingestion: Client (mobile/watch) sends data (e.g., audio, EEG) to ingestion service.
Event Publishing: Ingestion service stores large files locally and publishes metadata to NATS (e.g., user.<user_id>.audio.raw).
Storage: Storage service subscribes to raw events, persists metadata to TimescaleDB, and publishes stored events (e.g., user.<user_id>.audio.stored).
Processing: Processing services (STT, OCR, EEG) subscribe to stored events, process data using AI models, and publish results (e.g., user.<user_id>.audio.transcribed).
Reasoning: DSPy service subscribes to processed events, generates insights, and sends notifications via WebSocket.
Client Update: Mobile/watch apps receive notifications and display insights.

Deployment

k3s: Orchestrates all services as containers in a single-node cluster.
Helm: Manages deployments with dynamic GPU/CPU configuration.
GPU Support: Enabled via NVIDIA Container Toolkit, with CPU fallback for testing.
Monolith-Like Experience: Single make dev-up command starts k3s and deploys services.


4. Supported Data Streams
The system supports diverse data streams from detailed_project.md, each with specific processing and storage requirements.

Audio

Formats: WAV, WebM, Opus, MP3
Sources: Mobile/watch microphones, multiple concurrent streams
Processing: Phi-4 STT for transcription, embedding generation
Storage: Local file system (raw), TimescaleDB (metadata, transcripts)
Requirements: Sub-second latency for real-time transcription, noise filtering


Images

Formats: JPEG, PNG
Sources: Photos, screenshots
Processing: MoonDream2 for OCR, gaze detection, embedding
Storage: Local file system (raw), TimescaleDB (metadata, results)
Requirements: High-resolution processing, batch processing support


Videos

Formats: MP4, WebM
Sources: Screen recordings, camera feeds
Processing: MoonDream2 (OCR, gaze), MediaPipe (pose), embedding
Storage: Local file system (raw), TimescaleDB (metadata, results)
Requirements: Chunked streaming, GPU acceleration for real-time analysis


EEG

Format: High-frequency time-series (up to 1000 Hz)
Sources: Wearable EEG devices
Processing: Artifact removal (e.g., ICA), feature extraction, embedding
Storage: TimescaleDB hypertables (raw, processed)
Requirements: Real-time processing, noise robustness Electroencephalography Signal Processing


Sensors

Types: GPS, accelerometer, gyroscope
Sources: Mobile/watch sensors
Processing: Time-series analysis, embedding
Storage: TimescaleDB hypertables
Requirements: Low-power collection, high-frequency sampling


Health Data

Types: Steps, sleep, heart rate
Sources: Wearables, mobile apps
Processing: Aggregation, correlation analysis
Storage: TimescaleDB
Requirements: Privacy compliance, data export


OS Events

Types: Screen on/off, app lifecycle
Sources: Mobile/watch OS
Processing: Event correlation
Storage: TimescaleDB
Requirements: Low overhead, event deduplication


System Monitoring

Types: App usage, memory, CPU
Sources: Mobile/watch OS
Processing: Anomaly detection
Storage: TimescaleDB
Requirements: Minimal performance impact


External Data

Types: Email (IMAP), calendar (CalDAV), social media
Sources: Third-party APIs
Processing: Text extraction, embedding
Storage: TimescaleDB (metadata), local cache
Requirements: Robust error handling, rate limit management




5. Key Considerations
Scalability

Challenge: High-throughput data (e.g., EEG at 1000 Hz, multiple audio streams) requires efficient resource allocation for multi-user support.
Solution:

NATS JetStream scales horizontally with additional nodes.
k3s supports single-node clusters but can extend to multi-node for production.
TimescaleDB hypertables optimize storage and query performance.


Requirement: Test with simulated multi-user workloads (e.g., 100 users sending EEG data).

Performance

Challenge: AI tasks (e.g., Phi-4 STT, MoonDream2 OCR) are computationally intensive, requiring GPU acceleration for sub-second latency.
Solution:

NVIDIA Container Toolkit enables GPU support in k3s.
CPU fallback for testing on low-end hardware.
Batch processing for non-real-time tasks (e.g., video analysis).


Requirement: Measure latency for critical streams (e.g., EEG, audio) in GPU and CPU modes.

Privacy and Security

Challenge: Sensitive data (EEG, health, emails) requires GDPR/HIPAA compliance.
Solution:

Encrypt data at rest (AES-256) and in transit (TLS).
Use NATS subject prefixes (user.<user_id>.*) for data isolation.
Support local processing to minimize cloud exposure.
Provide data export/delete tools.


Requirement: Implement RBAC and audit logging for user data access.

Maintainability

Challenge: Over 30 microservices increase operational complexity.
Solution:

Use Helm for standardized deployments.
Centralize logging with Prometheus/Grafana.
Implement OpenTelemetry for tracing.


Requirement: Document service interactions and dependencies.

Portability

Challenge: GPU configurations vary across environments, and CPU-only deployments must be supported.
Solution:

Programmatic GPU detection (check_gpu.sh) enables dynamic configuration.
Standardized Docker images with CUDA/CPU support.


Requirement: Test deployments on diverse hardware (e.g., NVIDIA RTX, CPU-only servers).

Data Consistency

Challenge: High-throughput event-driven systems risk data loss or duplicates.
Solution:

Configure NATS JetStream for exactly-once delivery.
Use trace IDs for idempotent storage in TimescaleDB.


Requirement: Implement retry mechanisms and dead-letter queues.


6. Requirements for Handoff
Documentation

Architecture Diagram: Visualize service interactions, data flows, and NATS subjects.
Service Catalog: Document each service’s purpose, inputs, outputs, and dependencies.
Setup Guide: Detail k3s, NATS, TimescaleDB, and GPU setup steps.
Development Workflow: Explain Makefile commands (setup, dev-up, test-cpu, test-gpu).
API Reference: Document REST, gRPC, and WebSocket endpoints.
Data Schemas: Define NATS event schemas and TimescaleDB tables.
Testing Plan: Outline unit, integration, and stress tests.

Code Artifacts

Backend Services: Go source code for ingestion, storage, processing, DSPy, embedding, correlation services.
Dockerfiles: For each service, with GPU/CPU support (e.g., stt_processor/Dockerfile).
Helm Charts: For k3s deployments (helm/loom/).
Frontend Apps: Flutter mobile app (main.dart), Android watch app (MainActivity.kt).
Scripts: GPU detection (check_gpu.sh), build automation (Makefile).
Tests: Unit tests (go test), integration tests (tests/integration.yaml).

Setup Instructions

Install Dependencies:

Go, Docker, k3s, Helm, Flutter, Kotlin SDK.
NVIDIA drivers and Container Toolkit (if GPU available).


Run Setup:
bashmake setup
Installs k3s, Helm, and builds Docker images, with GPU detection.
Start Development:
bashmake dev-up
Starts k3s and deploys services with dynamic GPU/CPU configuration.
Test Modes:
bashmake test-cpu
make test-gpu
Tests CPU and GPU performance limits.
Monitor:

Access Prometheus at http://localhost:9090.
View traces in Grafana or OpenTelemetry collector.



Team Skills

Go: For backend service development and maintenance.
Kubernetes/k3s: For container orchestration and deployment.
NATS: For event-driven architecture and message queue management.
TimescaleDB/PostgreSQL: For database schema design and optimization.
Flutter/Kotlin: For mobile and watch app development.
AI/ML: Familiarity with MoonDream2, MediaPipe, Phi-4 for model integration.
DevOps: Experience with Docker, Helm, Prometheus, and OpenTelemetry.

Testing Requirements

Unit Tests: Cover all Go services (90%+ coverage).
Integration Tests: Verify NATS, TimescaleDB, and service interactions.
Stress Tests: Simulate 100 users with EEG, audio, and video streams.
Performance Tests: Measure latency for GPU vs. CPU modes.
Security Tests: Validate encryption, RBAC, and data isolation.

Deployment Requirements

Single-Node Deployment: k3s on a server with 16GB RAM, modern CPU, optional NVIDIA GPU.
Multi-Node (Future): Extend k3s to multi-node Kubernetes for production.
Installer: Package k3s, images, and Helm charts into a single script or binary.
Monitoring: Deploy Prometheus/Grafana for production monitoring.


