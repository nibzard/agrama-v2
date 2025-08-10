#!/bin/bash

# MCP Server Health Monitor & Auto-Restart Script
# Monitors Agrama MCP server health and automatically restarts on failures

set -euo pipefail

# Configuration
MCP_SERVER_BINARY="./zig-out/bin/agrama_v2"
MCP_SERVER_ARGS="mcp"
LOG_FILE="mcp_server.log"
HEALTH_CHECK_INTERVAL=30
MAX_RESTART_ATTEMPTS=5
RESTART_COOLDOWN=5

# State tracking
RESTART_COUNT=0
LAST_RESTART_TIME=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

# Health check function
check_mcp_server_health() {
    local test_message='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}},"id":1}'
    
    # Use timeout to prevent hanging
    if timeout 10 bash -c "echo '$test_message' | $MCP_SERVER_BINARY $MCP_SERVER_ARGS" >/dev/null 2>&1; then
        return 0  # Healthy
    else
        return 1  # Unhealthy
    fi
}

# Start MCP server with monitoring
start_mcp_server() {
    log "Starting Agrama MCP server..."
    
    # Build the server first
    if ! zig build; then
        log_error "Failed to build MCP server"
        return 1
    fi
    
    # Start server in background with proper I/O redirection
    {
        $MCP_SERVER_BINARY $MCP_SERVER_ARGS 2>> "$LOG_FILE"
    } &
    
    MCP_PID=$!
    echo $MCP_PID > mcp_server.pid
    
    # Give server time to start
    sleep 2
    
    # Verify it's running
    if ps -p $MCP_PID > /dev/null; then
        log_success "MCP server started successfully (PID: $MCP_PID)"
        return 0
    else
        log_error "MCP server failed to start"
        return 1
    fi
}

# Stop MCP server gracefully
stop_mcp_server() {
    if [[ -f "mcp_server.pid" ]]; then
        local pid=$(cat mcp_server.pid)
        if ps -p $pid > /dev/null; then
            log "Stopping MCP server (PID: $pid)..."
            kill -TERM $pid 2>/dev/null || true
            
            # Wait for graceful shutdown
            local count=0
            while ps -p $pid > /dev/null && [ $count -lt 10 ]; do
                sleep 1
                ((count++))
            done
            
            # Force kill if still running
            if ps -p $pid > /dev/null; then
                log_warning "Force killing MCP server"
                kill -KILL $pid 2>/dev/null || true
            fi
        fi
        rm -f mcp_server.pid
    fi
}

# Restart with backoff
restart_mcp_server() {
    local current_time=$(date +%s)
    
    # Check restart rate limiting
    if [[ $RESTART_COUNT -ge $MAX_RESTART_ATTEMPTS ]]; then
        if [[ $((current_time - LAST_RESTART_TIME)) -lt 300 ]]; then  # 5 minutes
            log_error "Too many restart attempts ($RESTART_COUNT). Waiting for cooldown period."
            return 1
        else
            # Reset counter after cooldown
            RESTART_COUNT=0
        fi
    fi
    
    log_warning "Attempting to restart MCP server (attempt $((RESTART_COUNT + 1))/$MAX_RESTART_ATTEMPTS)"
    
    stop_mcp_server
    sleep $RESTART_COOLDOWN
    
    if start_mcp_server; then
        log_success "MCP server restarted successfully"
        RESTART_COUNT=0
        return 0
    else
        ((RESTART_COUNT++))
        LAST_RESTART_TIME=$current_time
        log_error "MCP server restart failed"
        return 1
    fi
}

# Cleanup on exit
cleanup() {
    log "Shutting down MCP health monitor..."
    stop_mcp_server
    exit 0
}

# Signal handlers
trap cleanup SIGTERM SIGINT

# Main monitoring loop
main() {
    log "🏥 Starting MCP Server Health Monitor"
    log "Configuration: check_interval=${HEALTH_CHECK_INTERVAL}s, max_restarts=${MAX_RESTART_ATTEMPTS}"
    
    # Initial server start
    if ! start_mcp_server; then
        log_error "Failed to start MCP server initially"
        exit 1
    fi
    
    # Health monitoring loop
    while true; do
        sleep $HEALTH_CHECK_INTERVAL
        
        # Check if process is still running
        if [[ -f "mcp_server.pid" ]]; then
            local pid=$(cat mcp_server.pid)
            if ! ps -p $pid > /dev/null; then
                log_error "MCP server process died unexpectedly"
                if ! restart_mcp_server; then
                    log_error "Failed to restart MCP server, exiting"
                    exit 1
                fi
                continue
            fi
        else
            log_error "MCP server PID file missing"
            if ! restart_mcp_server; then
                log_error "Failed to restart MCP server, exiting"
                exit 1
            fi
            continue
        fi
        
        # Health check via protocol test
        if ! check_mcp_server_health; then
            log_warning "MCP server health check failed"
            if ! restart_mcp_server; then
                log_error "Failed to restart unhealthy MCP server, exiting"
                exit 1
            fi
        else
            # Periodic success message (every 10 health checks)
            if [[ $(($(date +%s) / $HEALTH_CHECK_INTERVAL % 10)) -eq 0 ]]; then
                log_success "MCP server health check passed"
            fi
        fi
    done
}

# Usage information
usage() {
    echo "Usage: $0 [start|stop|restart|status|health]"
    echo ""
    echo "Commands:"
    echo "  start   - Start MCP server with health monitoring"
    echo "  stop    - Stop MCP server and health monitor"
    echo "  restart - Restart MCP server"
    echo "  status  - Show server status"
    echo "  health  - Perform health check"
    echo ""
    echo "The health monitor will automatically restart the server on failures."
    echo "Logs are written to: $LOG_FILE"
}

# Command handling
case "${1:-start}" in
    "start")
        main
        ;;
    "stop")
        stop_mcp_server
        log "MCP server stopped"
        ;;
    "restart")
        restart_mcp_server
        ;;
    "status")
        if [[ -f "mcp_server.pid" ]] && ps -p $(cat mcp_server.pid) > /dev/null; then
            echo -e "${GREEN}MCP server is running (PID: $(cat mcp_server.pid))${NC}"
            exit 0
        else
            echo -e "${RED}MCP server is not running${NC}"
            exit 1
        fi
        ;;
    "health")
        if check_mcp_server_health; then
            echo -e "${GREEN}MCP server health check passed${NC}"
            exit 0
        else
            echo -e "${RED}MCP server health check failed${NC}"
            exit 1
        fi
        ;;
    *)
        usage
        exit 1
        ;;
esac