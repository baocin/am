.PHONY: install dev run test format lint type-check docker docker-run

# Python environment
PYTHON := python3.11
VENV := venv
PIP := $(VENV)/bin/pip
PYTHON_BIN := $(VENV)/bin/python

# Docker settings
DOCKER_IMAGE := loomv2-gps-geocoding-consumer
DOCKER_TAG := latest

# Create virtual environment
$(VENV):
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip

# Install dependencies
install: $(VENV)
	$(PIP) install -r requirements.txt
	$(PIP) install -r requirements-dev.txt || true

# Run development server
dev:
	LOOM_LOG_LEVEL=DEBUG \
	LOOM_KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
	LOOM_DATABASE_URL=postgresql://loom:loom@localhost:5432/loom \
	$(PYTHON_BIN) -m app.main

# Run production server
run:
	$(PYTHON_BIN) -m app.main

# Run tests
test:
	$(PYTHON_BIN) -m pytest tests/ -v

# Format code
format:
	$(PYTHON_BIN) -m black app/ tests/
	$(PYTHON_BIN) -m isort app/ tests/

# Lint code
lint:
	$(PYTHON_BIN) -m flake8 app/ tests/
	$(PYTHON_BIN) -m pylint app/

# Type checking
type-check:
	$(PYTHON_BIN) -m mypy app/

# Build Docker image
docker:
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

# Run Docker container
docker-run:
	docker run --rm -it \
		-e LOOM_KAFKA_BOOTSTRAP_SERVERS=host.docker.internal:9092 \
		-e LOOM_DATABASE_URL=postgresql://loom:loom@host.docker.internal:5432/loom \
		-e LOOM_LOG_LEVEL=DEBUG \
		-p 8000:8000 \
		$(DOCKER_IMAGE):$(DOCKER_TAG)

# Clean up
clean:
	rm -rf $(VENV)
	find . -type f -name '*.pyc' -delete
	find . -type d -name '__pycache__' -delete