# Agrama Enterprise Production Dockerfile
# Uses pre-built binaries for quick deployment testing

FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Create non-root user for security
RUN adduser -D -s /bin/sh agrama

# Copy pre-built executables
COPY zig-out/bin/agrama_v2 /usr/local/bin/agrama
COPY zig-out/bin/benchmark_suite /usr/local/bin/agrama-bench

# Create data directories with proper permissions
RUN mkdir -p /app/data /app/logs /app/config && \
    chown -R agrama:agrama /app

# Set working directory
WORKDIR /app
USER agrama

# Health check for enterprise monitoring
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD /usr/local/bin/agrama version || exit 1

# Expose MCP server port (if using WebSocket mode)
EXPOSE 8080

# Default command - MCP compliant server for enterprise integration
CMD ["/usr/local/bin/agrama", "mcp"]