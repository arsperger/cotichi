.PHONY: build run stop test clean logs shell rebuild run-debug run-local

# Docker image name
IMAGE_NAME = cotichi
CONTAINER_NAME = cotichi-service

# Build the Docker image
build:
	docker-compose build

# Run the service
run:
	docker-compose up

# Run in detached mode
run-detached:
	docker-compose up -d

# Stop the service
stop:
	docker-compose down

# Run tests in container (override entrypoint)
test:
	docker-compose run --rm --entrypoint lua cotichi tests/run_config_test.lua
	docker-compose run --rm --entrypoint lua cotichi tests/run_deduplicator_test.lua
	docker-compose run --rm --entrypoint lua cotichi tests/run_image_queue.lua
	docker-compose run --rm --entrypoint lua cotichi tests/run_streaming_archive.lua
	docker-compose run --rm --entrypoint lua cotichi tests/run_streaming_fetcher.lua
	docker-compose run --rm --entrypoint lua cotichi tests/run_http_client_test.lua

# View logs
logs:
	docker-compose logs -f

# Open shell in container
shell:
	docker-compose run --rm cotichi /bin/sh

# Clean up
clean:
	docker-compose down --rmi local --volumes
	rm -rf output/*.zip output/stats_*.txt

# Rebuild from scratch
rebuild: clean build

# Run with debug API (no delay)
run-debug:
	docker-compose run --rm -e USE_DEBUG_API=true cotichi

# Run with local saving enabled
run-local:
	docker-compose run --rm -e USE_DEBUG_API=true -e SAVE_LOCAL=true cotichi
