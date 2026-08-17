# Dockerfile for adtn_tracker
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

# Copy the application code
COPY src/ ./src/
COPY scripts/ ./scripts/
COPY notebooks/ ./notebooks/
COPY docs/ ./docs/

# Create data and output directories
RUN mkdir -p data output

# Set environment variables
ENV PYTHONPATH=/app/src
ENV PYTHONUNBUFFERED=1

# Default command
ENTRYPOINT ["python", "-m", "adtn_tracker.cli"]
CMD ["--help"]