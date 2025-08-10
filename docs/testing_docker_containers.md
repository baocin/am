# Testing Docker Containers

This guide explains how to test Docker containers that follow the [API Docker Contract](../api-docker-contract.md) standards.

## Overview

Every Docker container that implements the API contract must include a `test.sh` script that validates all endpoints and functionality. This ensures consistent behavior and easy verification across all services.

## Quick Start

### 1. Build and Run the Container

```bash
# Using docker-compose (recommended)
docker-compose up -d --build

# Or specify a custom port
PORT=8080 docker-compose up -d --build
```

### 2. Run the Test Suite

```bash
# Run tests with default settings (localhost:8000)
./test.sh

# Run tests on a different port
BASE_URL=http://localhost:8080 ./test.sh

# Run tests with verbose output
VERBOSE=true ./test.sh
```

### 3. Interpret Results

The test script provides color-coded output:
- 🟢 **GREEN**: Test passed
- 🔴 **RED**: Test failed
- 🟡 **YELLOW**: Test skipped (missing optional dependencies)

Example output:
```
===================================
Service API Tests
Base URL: http://localhost:8000
===================================

Testing Health Check... PASSED
Testing Root Info... PASSED
Testing Primary Endpoint... PASSED
...

===================================
Results: 12 passed, 0 failed
===================================
```

## Test Script Standards

### Required Structure

Every `test.sh` must include:

1. **Configuration Variables**
```bash
BASE_URL="${BASE_URL:-http://localhost:8000}"
VERBOSE="${VERBOSE:-false}"
TEST_DIR="test"
```

2. **Test Helper Function**
```bash
run_test() {
    local test_name="$1"
    local curl_cmd="$2"
    local expected_status="$3"
    local expected_contains="$4"
    # Test execution logic
}
```

3. **Test Counters**
```bash
TESTS_PASSED=0
TESTS_FAILED=0
```

### Required Tests

All containers must test these standard endpoints:

1. **Health Checks**
```bash
# Standard health check
run_test "Health Check" \
    "curl -X GET $BASE_URL/health" \
    "200" \
    '"status":"healthy"'

# Kubernetes-style health check
run_test "Health Check (K8s)" \
    "curl -X GET $BASE_URL/healthz" \
    "200" \
    '"status":"healthy"'
```

2. **Root Endpoint**
```bash
run_test "Root Info" \
    "curl -X GET $BASE_URL/" \
    "200" \
    '"service":"Service Name"'
```

3. **Service-Specific Endpoints**
```bash
# Example for an embedding service
run_test "Text Embedding" \
    "curl -X POST -H 'Content-Type: application/json' -d '$JSON_DATA' $BASE_URL/embed" \
    "200" \
    '"success":true'
```

### Test Directory Structure

```
docker/service-name/
├── test.sh              # Test script
├── test/                # Test resources
│   ├── sample.jpg       # Sample images
│   ├── sample.txt       # Sample text
│   └── test-base64.txt  # Base64 encoded data
├── .env.example         # Environment configuration
└── docker-compose.yml   # Container definition
```

## Writing Effective Tests

### 1. Test Different Scenarios

```bash
# Success case
run_test "Valid Request" \
    "curl -X POST ... valid data ..." \
    "200" \
    '"success":true'

# Error handling
run_test "Invalid Request" \
    "curl -X POST ... invalid data ..." \
    "400" \
    '"error":'

# Edge cases
run_test "Empty Request" \
    "curl -X POST -d '{}' ..." \
    "422" \
    ""
```

### 2. Display Actual Responses

Show curl output for important endpoints to help with debugging:

```bash
echo ""
echo "Testing Primary Endpoint..."
curl -s "$BASE_URL/process" | jq '.' 2>/dev/null || curl -s "$BASE_URL/process"
```

### 3. Handle Optional Dependencies

```bash
if [ -f "$TEST_DIR/optional-file.txt" ]; then
    run_test "Optional Feature" ...
else
    echo -e "${YELLOW}SKIPPED${NC} Optional Feature (file not found)"
fi
```

## Environment Configuration

### Using .env.example

Each container should provide an `.env.example` file:

```bash
# Service Configuration
PORT=8000
LOG_LEVEL=INFO
DEBUG=false

# Performance
MAX_WORKERS=4
TIMEOUT=300

# Service-specific settings
MODEL_PATH=/app/models
CACHE_SIZE=100
```

### Testing with Different Configurations

```bash
# Test with custom settings
PORT=8080 LOG_LEVEL=DEBUG ./test.sh

# Test with production-like settings
cp .env.example .env
# Edit .env as needed
docker-compose up -d
./test.sh
```

## Continuous Integration

### GitHub Actions Example

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
        
      - name: Wait for Service
        run: |
          for i in {1..30}; do
            curl -f http://localhost:8000/health && break
            echo "Waiting for service..."
            sleep 2
          done
          
      - name: Run Tests
        run: ./test.sh
        
      - name: Show Logs on Failure
        if: failure()
        run: docker-compose logs
```

### Local CI Testing

```bash
# Run the same tests CI will run
docker-compose down
docker-compose build --no-cache
docker-compose up -d
sleep 5  # Wait for service to start
./test.sh
EXIT_CODE=$?
docker-compose logs
docker-compose down
exit $EXIT_CODE
```

## Debugging Failed Tests

### 1. Check Container Logs

```bash
# View recent logs
docker-compose logs --tail=50

# Follow logs in real-time
docker-compose logs -f

# Check specific container
docker logs container-name
```

### 2. Test Individual Endpoints

```bash
# Test with curl directly
curl -v http://localhost:8000/health

# Test with detailed output
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' \
  -w "\nHTTP Status: %{http_code}\n" \
  http://localhost:8000/endpoint
```

### 3. Verify Container is Running

```bash
# Check container status
docker-compose ps

# Check port bindings
docker port container-name

# Check network
docker network ls
docker network inspect bridge
```

### 4. Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Port already in use | Use `PORT=8081 docker-compose up -d` |
| Container exits immediately | Check `docker-compose logs` for errors |
| Tests timeout | Increase timeout in health check or wait longer |
| 404 errors | Verify BASE_URL matches container port |
| Connection refused | Ensure container is running and healthy |

## Best Practices

1. **Always test both success and failure cases**
   - Valid inputs should succeed
   - Invalid inputs should fail gracefully

2. **Use meaningful test names**
   - Good: "Text Embedding - Single Input"
   - Bad: "Test 1"

3. **Provide helpful error messages**
   ```bash
   echo -e "${RED}FAILED${NC} (Status: $status_code, Expected: $expected_status)"
   [ "$VERBOSE" == "true" ] && echo "Response: $body"
   ```

4. **Test incrementally**
   - Start with health checks
   - Test basic functionality
   - Add complex scenarios
   - Test error handling

5. **Keep tests fast**
   - Use small test files
   - Avoid unnecessary delays
   - Run tests in parallel when possible

6. **Document special requirements**
   ```bash
   # Note: This test requires GPU support
   # Note: This endpoint may take 10-15 seconds on first run
   ```

## Example Test Scripts

For complete examples, see:
- [YuNet Face Detection Test](../docker/yunet-face-detection/test.sh)
- [Nomic Embed API Test](../docker/nomic-embed-api/test.sh)
- [RapidOCR API Test](../docker/rapidocr-api/test.sh)

These examples demonstrate testing for different types of services:
- Image processing (YuNet)
- Embedding generation (Nomic)
- OCR processing (RapidOCR)

## Validation Checklist

Before considering a container "tested", ensure:

- [ ] All standard endpoints tested (/health, /healthz, /)
- [ ] Service-specific endpoints tested
- [ ] Error cases handled gracefully
- [ ] Test script exits with proper code (0 for success, 1 for failure)
- [ ] Test output is clear and informative
- [ ] Tests work with default settings
- [ ] Tests can be configured via environment variables
- [ ] Documentation includes example test output
- [ ] Container can be tested in CI/CD pipeline