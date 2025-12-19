# Cotichi

Async cat archive service in Lua. Fetches cat images, deduplicates, packs into ZIP and uploads.

## Quick Start

```bash
docker-compose up --build
```

## Features

- Async HTTP with Copas
- Parallel fetching (12 workers)
- MD5 deduplication
- ZIP archives
- Graceful shutdown (SIGINT/SIGTERM)

## Configuration

All settings can be configured via environment variables:

### API Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `CAT_API_URL` | `http://algisothal.ru:8889` | Production API URL |
| `CAT_API_DEBUG_URL` | `http://algisothal.ru:8890` | Debug API URL (no delay) |
| `USE_DEBUG_API` | `false` | Use debug endpoint (`true`/`1` to enable) |
| `UPLOAD_ENABLED` | `true` | Upload archive to server (`false` to disable) |
| `UPLOAD_ENDPOINT` | `/cat` | Upload endpoint path |

### Async/Concurrency Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NUM_WORKERS` | `12` | Number of parallel fetch workers |
| `TIMEOUT` | `20` | HTTP request timeout (seconds) |
| `FETCH_TIMEOUT` | `60` | Total fetch batch timeout (seconds) |
| `RETRY_COUNT` | `3` | HTTP retry attempts |
| `RETRY_DELAY` | `1` | Initial retry delay (seconds, exponential backoff) |

### Archive Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_COUNT` | `12` | Number of cats per archive |
| `FILENAME_PATTERN` | `cat_%02d.jpg` | Filename pattern in ZIP |
| `OUTPUT_DIR` | `/app/output` | Output directory for local saves |
| `SAVE_LOCAL` | `false` | Save archive locally (`true`/`1` to enable) |

### Service Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Log level: `DEBUG`, `INFO`, `WARN`, `ERROR` |

## Commands

```bash
make build       # Build image
make run         # Run service
make run-debug   # Debug mode (no delay)
make test        # Run tests
```

## License

VIBE
