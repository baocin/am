.PHONY: help build run stop clean logs shell download-models check-models clean-models

# Default target
help:
	@echo "Available commands:"
	@echo "  make build          - Build the CPU Docker image"
	@echo "  make run            - Run the container (downloads models if needed)"
	@echo "  make stop           - Stop the container"
	@echo "  make clean          - Stop and remove containers"
	@echo "  make logs           - View container logs"
	@echo "  make shell          - Open shell in running container"
	@echo "  make download-models - Download ASR/TTS models to Docker volume"
	@echo "  make check-models   - Check models in Docker volume"
	@echo "  make clean-models   - Remove all models from Docker volume"
	@echo "  make setup-speaker-id - Download and setup speaker ID models"

# Build the Docker image
build:
	docker compose build

# Run the container (downloads models to volume if needed)
run:
	# Check if models exist in the Docker Compose volume
	@docker run --rm -v voiceapi_voiceapi-models:/models alpine sh -c '\
		if [ ! -f "/models/silero_vad/silero_vad.onnx" ] || \
		   [ ! -d "/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16" ] || \
		   [ ! -d "/models/kokoro-multi-lang-v1_0" ] || \
		   [ ! -f "/models/nemo-speakernet/nemo_en_speakerverification_speakernet.onnx" ]; then \
			exit 1; \
		fi' > /dev/null 2>&1 || make download-models
	docker compose up -d

# Stop the container
stop:
	docker compose stop

# Clean up
clean:
	docker compose down -v

# View logs
logs:
	docker compose logs -f

# Shell into container
shell:
	docker compose exec voiceapi bash

# Download models to Docker volume
download-models:
	@echo "Creating Docker volume if not exists..."
	@docker volume create voiceapi_voiceapi-models
	
	@echo "Checking and downloading models to Docker volume..."
	@docker run --rm -v voiceapi_voiceapi-models:/models alpine sh -c '\
		apk add --no-cache curl bzip2 && \
		mkdir -p /models/silero_vad && \
		if [ ! -f "/models/silero_vad/silero_vad.onnx" ]; then \
			echo "Downloading Silero VAD..." && \
			curl -SL -o /models/silero_vad/silero_vad.onnx \
				https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx || \
				{ echo "Failed to download Silero VAD"; exit 1; }; \
		else \
			echo "Silero VAD already exists, skipping..."; \
		fi && \
		cd /models && \
		if [ ! -d "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16" ] || [ ! -f "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16/tokens.txt" ]; then \
			echo "Downloading Parakeet ASR model..." && \
			rm -rf sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16* && \
			curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16.tar.bz2 || \
				{ echo "Failed to download Parakeet ASR model"; exit 1; } && \
			tar xvf sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16.tar.bz2 || \
				{ echo "Failed to extract Parakeet ASR model"; exit 1; } && \
			rm sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16.tar.bz2; \
		else \
			echo "Parakeet ASR model already exists, skipping..."; \
		fi && \
		if [ ! -d "kokoro-multi-lang-v1_0" ] || [ ! -f "kokoro-multi-lang-v1_0/model.onnx" ]; then \
			echo "Downloading Kokoro TTS model..." && \
			rm -rf kokoro-multi-lang-v1_0* && \
			curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2 || \
				{ echo "Failed to download Kokoro TTS model"; exit 1; } && \
			tar xvf kokoro-multi-lang-v1_0.tar.bz2 || \
				{ echo "Failed to extract Kokoro TTS model"; exit 1; } && \
			rm kokoro-multi-lang-v1_0.tar.bz2; \
		else \
			echo "Kokoro TTS model already exists, skipping..."; \
		fi && \
		mkdir -p /models/nemo-speakernet && \
		if [ ! -f "/models/nemo-speakernet/nemo_en_speakerverification_speakernet.onnx" ]; then \
			echo "Downloading NeMo SpeakerNet model..." && \
			curl -SL -o /models/nemo-speakernet/nemo_en_speakerverification_speakernet.onnx \
				https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_speakerverification_speakernet.onnx || \
				{ echo "Failed to download NeMo SpeakerNet model"; exit 1; }; \
		else \
			echo "NeMo SpeakerNet model already exists, skipping..."; \
		fi && \
		echo "Model check complete!"'

# Check models in volume
check-models:
	@echo "Checking models in Docker volume..."
	@docker run --rm -v voiceapi_voiceapi-models:/models alpine sh -c '\
		echo "=== Model Status ===" && \
		if [ -f "/models/silero_vad/silero_vad.onnx" ]; then \
			echo "✓ Silero VAD: Found"; \
		else \
			echo "✗ Silero VAD: Missing"; \
		fi && \
		if [ -d "/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16" ] && [ -f "/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-fp16/tokens.txt" ]; then \
			echo "✓ Parakeet ASR: Found"; \
		else \
			echo "✗ Parakeet ASR: Missing or incomplete"; \
		fi && \
		if [ -d "/models/kokoro-multi-lang-v1_0" ] && [ -f "/models/kokoro-multi-lang-v1_0/model.onnx" ]; then \
			echo "✓ Kokoro TTS: Found"; \
		else \
			echo "✗ Kokoro TTS: Missing or incomplete"; \
		fi && \
		if [ -d "/models/sherpa-onnx-wespeaker-voxceleb-resnet34" ] && [ -f "/models/sherpa-onnx-wespeaker-voxceleb-resnet34/model.onnx" ]; then \
			echo "✓ WeSpeaker VoxCeleb: Found"; \
		else \
			echo "✗ WeSpeaker VoxCeleb: Missing"; \
		fi && \
		if [ -f "/models/nemo-speakernet/nemo_en_speakerverification_speakernet.onnx" ] || [ -f "/models/nemo_en_speakerverification_speakernet.onnx" ]; then \
			echo "✓ NeMo SpeakerNet: Found"; \
		else \
			echo "✗ NeMo SpeakerNet: Missing"; \
		fi && \
		echo "" && \
		echo "=== Directory Contents ===" && \
		ls -la /models/'

# Clean models from volume
clean-models:
	@echo "Removing all models from Docker volume..."
	@docker volume inspect voiceapi_voiceapi-models > /dev/null 2>&1 && \
		docker run --rm -v voiceapi_voiceapi-models:/models alpine rm -rf /models/* && \
		echo "Models removed successfully" || \
		echo "Volume does not exist"

# Download speaker identification models
download-speaker-models:
	@echo "Downloading speaker identification models..."
	@./download_speaker_models.sh

# Download NeMo SpeakerNet model
download-nemo-speaker:
	@echo "Downloading NeMo SpeakerNet model..."
	@./download_nemo_speaker_model.sh

# Copy speaker models to Docker volume
copy-speaker-models:
	@echo "Copying speaker models to Docker volume..."
	@docker volume create voiceapi_voiceapi-models 2>/dev/null || true
	@if [ -d "models/sherpa-onnx-wespeaker-voxceleb-resnet34" ]; then \
		docker run --rm -v $(PWD)/models:/source -v voiceapi_voiceapi-models:/dest alpine cp -r /source/sherpa-onnx-wespeaker-voxceleb-resnet34 /dest/ && \
		echo "✓ Speaker models copied to Docker volume"; \
	else \
		echo "✗ Speaker models not found. Run 'make download-speaker-models' first"; \
		exit 1; \
	fi

# Setup speaker identification (download and copy to volume)
setup-speaker-id: download-speaker-models copy-speaker-models
	@echo "Speaker identification setup complete!"

# Copy NeMo speaker model to Docker volume
copy-nemo-speaker:
	@echo "Copying NeMo SpeakerNet model to Docker volume..."
	@docker volume create voiceapi_voiceapi-models 2>/dev/null || true
	@if [ -d "models/nemo-speakernet" ]; then \
		docker run --rm -v $(PWD)/models:/source -v voiceapi_voiceapi-models:/dest alpine cp -r /source/nemo-speakernet /dest/ && \
		echo "✓ NeMo SpeakerNet model copied to Docker volume"; \
	else \
		echo "✗ NeMo SpeakerNet model not found. Run 'make download-nemo-speaker' first"; \
		exit 1; \
	fi

# Setup NeMo speaker identification
setup-nemo-speaker: download-nemo-speaker copy-nemo-speaker
	@echo "NeMo SpeakerNet setup complete!"