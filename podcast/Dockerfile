# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o /podcast .

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    ffmpeg \
    python3 \
    py3-pip \
    && pip3 install --break-system-packages yt-dlp \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /podcast /app/podcast

# Create data directory
RUN mkdir -p /app/data
RUN mkdir -p /app/secrets

# Expose port
EXPOSE 8080

# Set default environment variables
ENV PORT=8080 \
    STORAGE_TYPE=local \
    LOCAL_STORAGE_PATH=/app/data \
    AUDIO_FORMAT=aac \
    AUDIO_QUALITY=64

# Run the application
CMD ["/app/podcast"]
