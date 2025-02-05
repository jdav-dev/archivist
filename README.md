# Archivist

Organize PDFs with AI.

Personally, I scan documents I'd like to keep to a network drive, where the archivist processes
and organizes the PDFs for me.

## Installation

[Ollama](https://ollama.com/) is needed for the archivist's capabilities.  Install Ollama
somewhere accessible to the archivist.

The archivist is intended to run via Docker:

```sh
$ docker run \
  --net=host \
  -v ~/Documents:/archive \
  -v ~/Downloads/inbox:/inbox \
  -e ARCHIVIST_ARCHIVE_DIR="/archive" \
  -e ARCHIVIST_INBOX_DIR="/inbox" \
  ghcr.io/jdav-dev/archivist
```

`ARCHIVIST_INBOX_DIR` and `ARCHIVIST_ARCHIVE_DIR` are required environment variables, specifying
the respective source and destination directories for PDFs.  Optional environment variables
include `ARCHIVIST_OLLAMA_BASE_URL` to override the URL for Ollama's API (defaults to
"http://localhost:11434/api") and `ARCHIVIST_OLLAMA_TIMEOUT_SECONDS` to override how long to wait
on responses from Ollama (defaults to "60").

## Development

The archivist uses [development containers](https://containers.dev/) for local development.  After
cloning the repository and before opening the project in its development container, a file must
be created at `.devcontainer/docker-compose.extend.yml`.  This file customizes the Docker Compose
development stack for your local machine.  For example:

```yaml
services:
  archivist:
    volumes:
      - ~/Documents:/archive
      - ~/Downloads:/inbox
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [ gpu ]
```

This will mount `~/Documents` to `/archive` and `~/Downloads` to `~/inbox` in your development
environment.  It will also give the Ollama container access to a Nvidia GPU.  Change the
directories as needed for your machine, and change or remove the Ollama section if you do not have
an Nvidia GPU available.
