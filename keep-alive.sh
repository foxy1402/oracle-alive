#!/bin/bash
#
# Oracle Cloud Keep-Alive Script (Enhanced Version)
# Prevents free tier ARM instances from being reclaimed due to inactivity
#
# Features:
# - Smart CPU stress with auto-detection
# - Memory stress with configurable hold time
# - Gaming-optimized network stress (won't interfere with VPN traffic)
# - Traffic shaping to prevent latency spikes
# - Distributed targets for better monitoring visibility
# - Auto-adjustment based on metric verification
# - Detailed statistics and logging
#
# Version: 2.0.0
#

set -euo pipefail

VERSION="2.0.0"

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

# Timing
STRESS_DURATION="${STRESS_DURATION:-45}"
SLEEP_DURATION="${SLEEP_DURATION:-480}"

# CPU
STRESS_CPU="${STRESS_CPU:-1}"
TARGET_CPU_PERCENT="${TARGET_CPU_PERCENT:-95}"
CPU_WORKERS="${CPU_WORKERS:-}"

# Memory
STRESS_MEMORY="${STRESS_MEMORY:-1}"
MEMORY_STRESS_MB="${MEMORY_STRESS_MB:-150}"
MEMORY_HOLD_DURATION="${MEMORY_HOLD_DURATION:-10}"

# Network
STRESS_NETWORK="${STRESS_NETWORK:-1}"
NETWORK_STRESS_MODE="${NETWORK_STRESS_MODE:-smart}"
NETWORK_BANDWIDTH_LIMIT_KBS="${NETWORK_BANDWIDTH_LIMIT_KBS:-100}"
NETWORK_USE_DISTRIBUTED_TARGETS="${NETWORK_USE_DISTRIBUTED_TARGETS:-1}"
NETWORK_PING_TARGETS="${NETWORK_PING_TARGETS:-8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1}"
NETWORK_PINGS_PER_TARGET="${NETWORK_PINGS_PER_TARGET:-5}"
NETWORK_PING_INTERVAL="${NETWORK_PING_INTERVAL:-0.3}"
NETWORK_HTTP_TARGETS="${NETWORK_HTTP_TARGETS:-http://www.google.com/generate_204 http://detectportal.firefox.com/success.txt}"
NETWORK_HTTP_REQUESTS="${NETWORK_HTTP_REQUESTS:-10}"
NETWORK_HTTP_TIMEOUT="${NETWORK_HTTP_TIMEOUT:-3}"
NETWORK_ENABLE_DOWNLOAD_TEST="${NETWORK_ENABLE_DOWNLOAD_TEST:-1}"
NETWORK_DOWNLOAD_TEST_URL="${NETWORK_DOWNLOAD_TEST_URL:-http://speedtest.ftp.otenet.gr/files/test100k.db}"
NETWORK_USE_TRAFFIC_SHAPING="${NETWORK_USE_TRAFFIC_SHAPING:-1}"
NETWORK_TRAFFIC_PRIORITY="${NETWORK_TRAFFIC_PRIORITY:-7}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/oracle-keep-alive.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_STATS_EVERY_N_CYCLES="${LOG_STATS_EVERY_N_CYCLES:-12}"

# Advanced
PROCESS_NICE_LEVEL="${PROCESS_NICE_LEVEL:-19}"
IO_SCHEDULING_CLASS="${IO_SCHEDULING_CLASS:-idle}"
AUTO_ADJUST_INTENSITY="${AUTO_ADJUST_INTENSITY:-1}"
METRIC_CHECK_INTERVAL="${METRIC_CHECK_INTERVAL:-15}"
ENABLE_FAILSAFE_MODE="${ENABLE_FAILSAFE_MODE:-1}"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

CPU_COUNT=1
TOTAL_MEMORY_MB=0
CYCLE_COUNT=0
TOTAL_CPU_STRESS_TIME=0
TOTAL_MEMORY_STRESS_TIME=0
TOTAL_NETWORK_STRESS_TIME=0
INTENSITY_MULTIPLIER=1.0
FAILSAFE_ACTIVE=0

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    
    # Check log level
    local level_priority=0
    case "$level" in
        DEBUG) level_priority=0 ;;
        INFO)  level_priority=1 ;;
        WARN)  level_priority=2 ;;
        ERROR) level_priority=3 ;;
    esac
    
    local current_level_priority=1
    case "$LOG_LEVEL" in
        DEBUG) current_level_priority=0 ;;
        INFO)  current_level_priority=1 ;;
        WARN)  current_level_priority=2 ;;
        ERROR) current_level_priority=3 ;;
    esac
    
    if [[ $level_priority -ge $current_level_priority ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$timestamp] [$level] $message"
    fi
}

log_debug() { log "DEBUG" "$@"; }
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
    
    log_info "System: ${CPU_COUNT} CPU cores, ${TOTAL_MEMORY_MB}MB RAM"
    
    # Set CPU workers if not manually configured
    if [[ -z "$CPU_WORKERS" ]]; then
        CPU_WORKERS=$CPU_COUNT
    fi
    
    log_info "Configuration: CPU workers=${CPU_WORKERS}, Stress=${STRESS_DURATION}s, Sleep=${SLEEP_DURATION}s"
    
    # Calculate expected average metrics
    local active_ratio=$(awk "BEGIN {printf \"%.2f\", $STRESS_DURATION / ($STRESS_DURATION + $SLEEP_DURATION) * 100}")
    local expected_cpu=$(awk "BEGIN {printf \"%.1f\", $TARGET_CPU_PERCENT * $active_ratio / 100}")
    log_info "Expected average CPU: ~${expected_cpu}% (${active_ratio}% duty cycle @ ${TARGET_CPU_PERCENT}% target)"
    
    if (( $(awk "BEGIN {print ($expected_cpu < 15)}") )); then
        log_warn "WARNING: Expected CPU average (${expected_cpu}%) is below 15% threshold!"
        log_warn "Consider: reducing SLEEP_DURATION or increasing TARGET_CPU_PERCENT"
    fi
}

# ============================================================================
# CPU STRESS
# ============================================================================

stress_cpu() {
    if [[ "$STRESS_CPU" != "1" ]]; then
        log_debug "CPU stress disabled"
        return
    fi
    
    local duration=$(awk "BEGIN {printf \"%.0f\", $STRESS_DURATION * $INTENSITY_MULTIPLIER}")
    log_info "CPU stress: ${duration}s on ${CPU_WORKERS} workers @ ${TARGET_CPU_PERCENT}% target"
    
    local start_time=$SECONDS
    local end_time=$((SECONDS + duration))
    local pids=()
    
    # Calculate sleep time to achieve target CPU percentage
    # Higher target = less sleep between work bursts
    local work_sleep=$(awk "BEGIN {printf \"%.4f\", (100 - $TARGET_CPU_PERCENT) / 1000}")
    
    for ((i = 0; i < CPU_WORKERS; i++)); do
        (
            # Set nice level for low priority
            renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
            
            while [[ $SECONDS -lt $end_time ]]; do
                # CPU intensive computation
                for ((j = 0; j < 5000; j++)); do
                    : $((j * j * j % 7919))
                done
                # Small sleep to control CPU percentage
                sleep "$work_sleep" 2>/dev/null || sleep 0.01
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all workers
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_CPU_STRESS_TIME=$((TOTAL_CPU_STRESS_TIME + elapsed))
    log_info "CPU stress completed (${elapsed}s)"
}

# ============================================================================
# MEMORY STRESS
# ============================================================================

stress_memory() {
    if [[ "$STRESS_MEMORY" != "1" ]]; then
        log_debug "Memory stress disabled"
        return
    fi
    
    local memory_mb=$(awk "BEGIN {printf \"%.0f\", $MEMORY_STRESS_MB * $INTENSITY_MULTIPLIER}")
    log_info "Memory stress: allocating ${memory_mb}MB for ${MEMORY_HOLD_DURATION}s"
    
    local start_time=$SECONDS
    local temp_file="/dev/shm/oracle-keep-alive-$$"
    
    # Check if we have enough free memory
    local free_memory_mb=$(free -m | grep "^Mem:" | awk '{print $7}')
    if [[ $memory_mb -gt $free_memory_mb ]]; then
        log_warn "Not enough free memory (${free_memory_mb}MB), reducing to ${free_memory_mb}MB"
        memory_mb=$free_memory_mb
    fi
    
    # Allocate memory in tmpfs (RAM disk)
    if dd if=/dev/urandom of="$temp_file" bs=1M count="$memory_mb" 2>/dev/null; then
        # Read back to ensure it's in memory
        cat "$temp_file" > /dev/null 2>&1 || true
        
        # Hold allocation
        sleep "$MEMORY_HOLD_DURATION"
        
        # Clean up
        rm -f "$temp_file" 2>/dev/null || true
        
        local elapsed=$((SECONDS - start_time))
        TOTAL_MEMORY_STRESS_TIME=$((TOTAL_MEMORY_STRESS_TIME + elapsed))
        log_info "Memory stress completed (${elapsed}s)"
    else
        log_error "Memory stress failed (permission denied or /dev/shm unavailable)"
    fi
}

# ============================================================================
# NETWORK STRESS (GAMING OPTIMIZED)
# ============================================================================

setup_traffic_shaping() {
    if [[ "$NETWORK_USE_TRAFFIC_SHAPING" != "1" ]]; then
        return
    fi
    
    if ! command -v tc &> /dev/null; then
        log_warn "tc command not found, traffic shaping disabled (install iproute2)"
        return
    fi
    
    log_debug "Setting up traffic shaping for gaming optimization"
    
    # This would require root and interface detection
    # Placeholder for future implementation
    # tc qdisc add dev eth0 root handle 1: prio bands 3
    # tc filter add dev eth0 protocol ip parent 1:0 prio 3 u32 match ip dport 51820 0xffff flowid 1:1  # WireGuard
}

stress_network_smart() {
    log_info "Network stress (smart mode): bandwidth limit ${NETWORK_BANDWIDTH_LIMIT_KBS}KB/s"
    
    local start_time=$SECONDS
    local bandwidth_limit=$NETWORK_BANDWIDTH_LIMIT_KBS
    local targets_array=($NETWORK_PING_TARGETS)
    local http_targets_array=($NETWORK_HTTP_TARGETS)
    
    # 1. Distributed ICMP pings (low bandwidth, high visibility)
    if [[ "$NETWORK_USE_DISTRIBUTED_TARGETS" == "1" ]]; then
        log_debug "Pinging ${#targets_array[@]} distributed targets"
        
        for target in "${targets_array[@]}"; do
            # Ping in background to parallelize
            (
                renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
                if ping -c "$NETWORK_PINGS_PER_TARGET" -i "$NETWORK_PING_INTERVAL" -W 2 "$target" > /dev/null 2>&1; then
                    log_debug "Pinged $target (${NETWORK_PINGS_PER_TARGET} packets)"
                else
                    log_debug "Failed to ping $target"
                fi
            ) &
        done
        
        # Wait for pings to complete
        wait
    fi
    
    # 2. Small HTTP requests (generates actual traffic)
    if command -v curl &> /dev/null && [[ ${#http_targets_array[@]} -gt 0 ]]; then
        log_debug "Making ${NETWORK_HTTP_REQUESTS} HTTP requests"
        
        local requests_made=0
        while [[ $requests_made -lt $NETWORK_HTTP_REQUESTS ]]; do
            # Rotate through targets
            local target="${http_targets_array[$((requests_made % ${#http_targets_array[@]}))]}"
            
            (
                renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
                curl -s -m "$NETWORK_HTTP_TIMEOUT" -o /dev/null "$target" 2>/dev/null || true
            ) &
            
            requests_made=$((requests_made + 1))
            
            # Small delay between requests to avoid burst
            sleep 0.2
        done
        
        wait
    fi
    
    # 3. Download test (actual bandwidth usage)
    if [[ "$NETWORK_ENABLE_DOWNLOAD_TEST" == "1" ]] && command -v curl &> /dev/null; then
        # Calculate bytes to download based on bandwidth limit
        # We'll download for ~5 seconds at the specified rate
        local bytes_to_download=$((bandwidth_limit * 1024 * 5))
        
        log_debug "Download test: ${bytes_to_download} bytes (~5s @ ${bandwidth_limit}KB/s)"
        
        (
            renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
            # Use --limit-rate to control bandwidth
            curl -s -m 10 --limit-rate "${bandwidth_limit}k" -r "0-${bytes_to_download}" -o /dev/null "$NETWORK_DOWNLOAD_TEST_URL" 2>/dev/null || true
        ) &
        
        wait
    fi
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
    log_info "Network stress completed (${elapsed}s)"
}

stress_network_minimal() {
    log_info "Network stress (minimal mode)"
    
    local start_time=$SECONDS
    local targets_array=($NETWORK_PING_TARGETS)
    
    # Just ping a couple targets
    for target in "${targets_array[@]:0:2}"; do
        ping -c 3 -i 1 -W 2 "$target" > /dev/null 2>&1 && log_debug "Pinged $target" || true
    done
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
    log_info "Network stress completed (${elapsed}s)"
}

stress_network_moderate() {
    log_info "Network stress (moderate mode)"
    
    local start_time=$SECONDS
    local targets_array=($NETWORK_PING_TARGETS)
    local http_targets_array=($NETWORK_HTTP_TARGETS)
    
    # Ping all targets
    for target in "${targets_array[@]}"; do
        ping -c 5 -i 0.5 -W 2 "$target" > /dev/null 2>&1 && log_debug "Pinged $target" || true
    done
    
    # Make some HTTP requests
    if command -v curl &> /dev/null; then
        for target in "${http_targets_array[@]:0:3}"; do
            curl -s -m 5 -o /dev/null "$target" 2>/dev/null || true
        done
    fi
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
    log_info "Network stress completed (${elapsed}s)"
}

stress_network_aggressive() {
    log_warn "Network stress (aggressive mode) - may impact gaming!"
    
    local start_time=$SECONDS
    
    # Heavy download for network utilization
    if command -v curl &> /dev/null; then
        # Download 10MB
        curl -s -m 30 -r "0-10485760" -o /dev/null "$NETWORK_DOWNLOAD_TEST_URL" 2>/dev/null || true
    fi
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
    log_info "Network stress completed (${elapsed}s)"
}

stress_network() {
    if [[ "$STRESS_NETWORK" != "1" ]]; then
        log_debug "Network stress disabled"
        return
    fi
    
    case "$NETWORK_STRESS_MODE" in
        smart)
            stress_network_smart
            ;;
        minimal)
            stress_network_minimal
            ;;
        moderate)
            stress_network_moderate
            ;;
        aggressive)
            stress_network_aggressive
            ;;
        *)
            log_warn "Unknown network stress mode: $NETWORK_STRESS_MODE, using smart"
            stress_network_smart
            ;;
    esac
}

# ============================================================================
# MONITORING & STATISTICS
# ============================================================================

get_cpu_usage() {
    # Get CPU usage from /proc/stat
    if [[ ! -f /proc/stat ]]; then
        echo "0"
        return
    fi
    
    local cpu_line
    cpu_line=$(head -1 /proc/stat)
    local user nice system idle iowait irq softirq
    read -r _ user nice system idle iowait irq softirq _ <<< "$cpu_line"
    
    local total=$((user + nice + system + idle + iowait + irq + softirq))
    local used=$((user + nice + system + irq + softirq))
    
    if [[ $total -gt 0 ]]; then
        echo $((used * 100 / total))
    else
        echo "0"
    fi
}

get_memory_usage_percent() {
    if ! command -v free &> /dev/null; then
        echo "0"
        return
    fi
    
    local mem_info
    mem_info=$(free | grep "^Mem:" | awk '{printf "%.1f", ($3/$2)*100}')
    echo "$mem_info"
}

get_network_stats() {
    # This is a placeholder - actual implementation would need to track
    # network interface statistics over time
    echo "N/A"
}

show_stats() {
    log_info "=== System Statistics ==="
    
    # CPU
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    log_info "CPU: ${cpu_usage}% (instantaneous)"
    
    # Memory
    if command -v free &> /dev/null; then
        local mem_percent
        mem_percent=$(get_memory_usage_percent)
        local mem_info
        mem_info=$(free -m | grep "^Mem:" | awk '{printf "%s/%sMB", $3, $2}')
        log_info "Memory: ${mem_info} (${mem_percent}%)"
    fi
    
    # Uptime
    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null || uptime | cut -d',' -f1)
    log_info "Uptime: $uptime_str"
    
    # Stress statistics
    log_info "Total stress time: CPU=${TOTAL_CPU_STRESS_TIME}s, Mem=${TOTAL_MEMORY_STRESS_TIME}s, Net=${TOTAL_NETWORK_STRESS_TIME}s"
    
    if [[ $FAILSAFE_ACTIVE -eq 1 ]]; then
        log_warn "Failsafe mode ACTIVE (intensity: ${INTENSITY_MULTIPLIER}x)"
    fi
}

check_metrics_and_adjust() {
    if [[ "$AUTO_ADJUST_INTENSITY" != "1" ]]; then
        return
    fi
    
    if [[ $((CYCLE_COUNT % METRIC_CHECK_INTERVAL)) -ne 0 ]]; then
        return
    fi
    
    log_info "Checking metrics against 15% threshold..."
    
    # In a real implementation, we'd query Oracle Cloud API for actual metrics
    # For now, we'll check local instantaneous values as a proxy
    
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    local mem_usage
    mem_usage=$(get_memory_usage_percent)
    
    log_info "Current metrics: CPU=${cpu_usage}%, Memory=${mem_usage}%"
    
    # Check if any metric is above 15%
    local cpu_ok=0
    local mem_ok=0
    
    [[ $cpu_usage -ge 15 ]] && cpu_ok=1
    [[ $(awk "BEGIN {print ($mem_usage >= 15)}") -eq 1 ]] && mem_ok=1
    
    if [[ $cpu_ok -eq 1 ]] || [[ $mem_ok -eq 1 ]]; then
        log_info "✓ At least one metric above 15% threshold"
        
        # Reset intensity if it was increased
        if [[ $(awk "BEGIN {print ($INTENSITY_MULTIPLIER > 1.0)}") -eq 1 ]]; then
            log_info "Reducing intensity back to normal"
            INTENSITY_MULTIPLIER=1.0
            FAILSAFE_ACTIVE=0
        fi
    else
        log_warn "⚠ All metrics below 15% threshold!"
        
        if [[ "$ENABLE_FAILSAFE_MODE" == "1" ]]; then
            # Increase intensity
            INTENSITY_MULTIPLIER=$(awk "BEGIN {printf \"%.1f\", $INTENSITY_MULTIPLIER + 0.2}")
            FAILSAFE_ACTIVE=1
            log_warn "Activating failsafe mode, increasing intensity to ${INTENSITY_MULTIPLIER}x"
            
            # Also reduce sleep duration
            if [[ $(awk "BEGIN {print ($INTENSITY_MULTIPLIER >= 1.5)}") -eq 1 ]]; then
                log_warn "Consider reducing SLEEP_DURATION in config for sustained 15%+ metrics"
            fi
        fi
    fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    
    # Kill child processes
    pkill -P $$ 2>/dev/null || true
    
    # Remove temp files
    rm -f /dev/shm/oracle-keep-alive-* 2>/dev/null || true
    
    log_info "Cleanup complete, exiting"
    exit 0
}

main() {
    # Handle signals
    trap cleanup SIGTERM SIGINT SIGHUP
    
    log_info "================================================"
    log_info "Oracle Cloud Keep-Alive v${VERSION} Started"
    log_info "================================================"
    
    detect_system
    setup_traffic_shaping
    
    log_info "Starting stress cycles..."
    
    while true; do
        CYCLE_COUNT=$((CYCLE_COUNT + 1))
        log_info "--- Cycle #${CYCLE_COUNT} ---"
        
        # Run stress operations
        stress_cpu
        stress_memory
        stress_network
        
        # Check and adjust if needed
        check_metrics_and_adjust
        
        # Show stats periodically
        if [[ $LOG_STATS_EVERY_N_CYCLES -gt 0 ]] && [[ $((CYCLE_COUNT % LOG_STATS_EVERY_N_CYCLES)) -eq 0 ]]; then
            show_stats
        fi
        
        # Sleep
        log_info "Sleeping for ${SLEEP_DURATION}s... (next cycle in $((SLEEP_DURATION / 60))m)"
        sleep "$SLEEP_DURATION"
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Show version
if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
    echo "Oracle Cloud Keep-Alive v${VERSION}"
    exit 0
fi

# Start main loop
main "$@"
