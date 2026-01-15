#!/bin/bash
#
# Oracle Cloud Keep-Alive Script
# Prevents free tier ARM instances from being reclaimed due to inactivity
#
# This script generates minimal CPU, Memory, and Network activity to keep
# at least one metric above Oracle's 15% threshold.
#
# Usage: ./keep-alive.sh [--status|--version]
#
# Version: 1.0.0
#

set -euo pipefail

VERSION="1.0.0"

# ============================================================================
# CONFIGURATION (can be overridden via environment variables)
# ============================================================================

# How long to run stress operations (seconds)
STRESS_DURATION="${STRESS_DURATION:-30}"

# How long to sleep between stress cycles (seconds)  
SLEEP_DURATION="${SLEEP_DURATION:-60}"

# Target CPU percentage (will be adjusted based on core count)
TARGET_CPU_PERCENT="${TARGET_CPU_PERCENT:-20}"

# Memory to allocate during stress (in MB)
MEMORY_STRESS_MB="${MEMORY_STRESS_MB:-100}"

# Enable/disable specific stress types (1=enabled, 0=disabled)
STRESS_CPU="${STRESS_CPU:-1}"
STRESS_MEMORY="${STRESS_MEMORY:-1}"
STRESS_NETWORK="${STRESS_NETWORK:-1}"

# Log file location
LOG_FILE="${LOG_FILE:-/var/log/oracle-keep-alive.log}"

# Network stress targets (ping these servers)
NETWORK_TARGETS="${NETWORK_TARGETS:-8.8.8.8 1.1.1.1}"

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$timestamp] [$level] $message"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ============================================================================
# SYSTEM DETECTION
# ============================================================================

detect_system() {
    CPU_COUNT=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "1048576")
    TOTAL_MEMORY_MB=$((TOTAL_MEMORY_KB / 1024))
    
    log_info "System detected: ${CPU_COUNT} CPU(s), ${TOTAL_MEMORY_MB}MB RAM"
    
    # Calculate appropriate stress levels based on system resources
    # For ARM instances, we want to hit ~20% CPU usage
    # With STRESS_DURATION=30s and SLEEP_DURATION=60s, we're active 33% of time
    # So we need to hit ~60% during active period to average ~20%
    
    log_info "Configuration: stress=${STRESS_DURATION}s, sleep=${SLEEP_DURATION}s, target=${TARGET_CPU_PERCENT}%"
}

# ============================================================================
# CPU STRESS
# ============================================================================

stress_cpu() {
    if [[ "$STRESS_CPU" != "1" ]]; then
        return
    fi
    
    log_info "Starting CPU stress for ${STRESS_DURATION}s on ${CPU_COUNT} core(s)..."
    
    local end_time=$((SECONDS + STRESS_DURATION))
    local pids=()
    
    # Start CPU stress workers (one per core for consistent load)
    for ((i = 0; i < CPU_COUNT; i++)); do
        (
            while [[ $SECONDS -lt $end_time ]]; do
                # Generate CPU load with computation
                for ((j = 0; j < 10000; j++)); do
                    : $((j * j * j))
                done
                # Small sleep to control CPU percentage (not 100% load)
                sleep 0.01
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all workers to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    log_info "CPU stress completed"
}

# ============================================================================
# MEMORY STRESS
# ============================================================================

stress_memory() {
    if [[ "$STRESS_MEMORY" != "1" ]]; then
        return
    fi
    
    log_info "Starting memory stress (${MEMORY_STRESS_MB}MB)..."
    
    # Allocate memory using dd to /dev/shm (tmpfs - RAM disk)
    # This creates actual memory pressure
    local temp_file="/dev/shm/oracle-keep-alive-$$"
    
    # Create a file in RAM
    if dd if=/dev/urandom of="$temp_file" bs=1M count="$MEMORY_STRESS_MB" 2>/dev/null; then
        # Read it back to ensure it's in memory
        cat "$temp_file" > /dev/null 2>&1 || true
        # Hold it for a moment
        sleep 5
        # Clean up
        rm -f "$temp_file" 2>/dev/null || true
        log_info "Memory stress completed"
    else
        log_warn "Memory stress failed (permission denied or /dev/shm unavailable)"
    fi
}

# ============================================================================
# NETWORK STRESS
# ============================================================================

stress_network() {
    if [[ "$STRESS_NETWORK" != "1" ]]; then
        return
    fi
    
    log_info "Starting network stress..."
    
    for target in $NETWORK_TARGETS; do
        # Send a few pings to generate network activity
        if ping -c 5 -i 0.5 "$target" > /dev/null 2>&1; then
            log_info "Pinged $target successfully"
        else
            log_warn "Failed to ping $target"
        fi
    done
    
    # Also do a small HTTP request if curl is available
    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" "https://www.google.com" > /dev/null 2>&1; then
            log_info "HTTP request completed"
        fi
    fi
    
    log_info "Network stress completed"
}

# ============================================================================
# MONITORING
# ============================================================================

show_stats() {
    log_info "=== Current System Stats ==="
    
    # CPU usage - works on both Ubuntu and Oracle Linux
    local cpu_usage="N/A"
    if [[ -f /proc/stat ]]; then
        # Read CPU stats from /proc/stat (more reliable than top)
        local cpu_line
        cpu_line=$(head -1 /proc/stat)
        local user nice system idle iowait irq softirq
        read -r _ user nice system idle iowait irq softirq _ <<< "$cpu_line"
        local total=$((user + nice + system + idle + iowait + irq + softirq))
        local used=$((user + nice + system + irq + softirq))
        if [[ $total -gt 0 ]]; then
            cpu_usage=$((used * 100 / total))
            log_info "CPU Usage: ~${cpu_usage}% (instantaneous)"
        fi
    fi
    
    # Memory usage
    if command -v free &> /dev/null; then
        local mem_info
        mem_info=$(free -m | grep Mem | awk '{printf "Used: %sMB / %sMB (%.1f%%)", $3, $2, ($3/$2)*100}')
        log_info "Memory: $mem_info"
    fi
    
    # Uptime
    log_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
}

# ============================================================================
# MAIN LOOP
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    # Kill any child processes
    pkill -P $$ 2>/dev/null || true
    rm -f /dev/shm/oracle-keep-alive-* 2>/dev/null || true
    log_info "Cleanup complete, exiting"
    exit 0
}

main() {
    # Handle signals
    trap cleanup SIGTERM SIGINT SIGHUP
    
    log_info "============================================"
    log_info "Oracle Cloud Keep-Alive Script Started"
    log_info "============================================"
    
    detect_system
    
    local cycle=0
    while true; do
        cycle=$((cycle + 1))
        log_info "--- Cycle #${cycle} ---"
        
        # Run stress operations
        stress_cpu
        stress_memory
        stress_network
        
        # Show current stats
        show_stats
        
        log_info "Sleeping for ${SLEEP_DURATION}s..."
        sleep "$SLEEP_DURATION"
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

main "$@"
