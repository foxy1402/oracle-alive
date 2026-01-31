#!/bin/bash
#
# Oracle Cloud Keep-Alive Script v2.1 (Intelligent Multi-Metric Edition)
# Prevents free tier ARM instances from being reclaimed due to inactivity
#
# NEW in v2.1:
# - Real-time monitoring of CPU, Memory, and Network utilization
# - Intelligent calculation of additional stress needed
# - Dynamic adjustment to reach 40% (double minimum) on ALL three metrics
# - Baseline detection to understand current system load
# - Smart stress only adds what's needed to reach targets
#
# Version: 2.1.0
#

set -euo pipefail

VERSION="2.1.0"

# ============================================================================
# TARGET CONFIGURATION
# ============================================================================

# Target utilization levels (percentage)
# Oracle's minimum is 20%, we target double (40%) for safety margin
TARGET_CPU_PERCENT="${TARGET_CPU_PERCENT:-40}"
TARGET_MEMORY_PERCENT="${TARGET_MEMORY_PERCENT:-40}"
TARGET_NETWORK_PERCENT="${TARGET_NETWORK_PERCENT:-40}"

# Safety margin - how much above target to aim for (in percentage points)
# Example: If target is 40%, margin of 5 means we aim for 45%
SAFETY_MARGIN="${SAFETY_MARGIN:-5}"

# Monitoring interval - how often to check and adjust (seconds)
MONITORING_INTERVAL="${MONITORING_INTERVAL:-300}"  # 5 minutes

# Baseline measurement duration (seconds)
# Script will observe system for this long to understand normal load
BASELINE_DURATION="${BASELINE_DURATION:-60}"

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

# Timing
STRESS_DURATION="${STRESS_DURATION:-45}"
MIN_SLEEP_DURATION="${MIN_SLEEP_DURATION:-60}"
MAX_SLEEP_DURATION="${MAX_SLEEP_DURATION:-600}"

# CPU
STRESS_CPU="${STRESS_CPU:-1}"
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
NETWORK_PING_TARGETS="${NETWORK_PING_TARGETS:-8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 208.67.222.222 208.67.220.220}"
NETWORK_PINGS_PER_TARGET="${NETWORK_PINGS_PER_TARGET:-5}"
NETWORK_PING_INTERVAL="${NETWORK_PING_INTERVAL:-0.3}"
NETWORK_HTTP_TARGETS="${NETWORK_HTTP_TARGETS:-http://www.google.com/generate_204 http://detectportal.firefox.com/success.txt http://captive.apple.com/hotspot-detect.html https://www.cloudflare.com/cdn-cgi/trace}"
NETWORK_HTTP_REQUESTS="${NETWORK_HTTP_REQUESTS:-10}"
NETWORK_HTTP_TIMEOUT="${NETWORK_HTTP_TIMEOUT:-3}"
NETWORK_ENABLE_DOWNLOAD_TEST="${NETWORK_ENABLE_DOWNLOAD_TEST:-1}"
NETWORK_DOWNLOAD_TEST_URL="${NETWORK_DOWNLOAD_TEST_URL:-http://speedtest.ftp.otenet.gr/files/test100k.db}"
NETWORK_USE_TRAFFIC_SHAPING="${NETWORK_USE_TRAFFIC_SHAPING:-1}"
NETWORK_TRAFFIC_PRIORITY="${NETWORK_TRAFFIC_PRIORITY:-7}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/oracle-keep-alive.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_STATS_EVERY_N_CYCLES="${LOG_STATS_EVERY_N_CYCLES:-6}"

# Advanced
PROCESS_NICE_LEVEL="${PROCESS_NICE_LEVEL:-19}"
IO_SCHEDULING_CLASS="${IO_SCHEDULING_CLASS:-idle}"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

CPU_COUNT=1
TOTAL_MEMORY_MB=0
CYCLE_COUNT=0

# Baseline metrics (what system normally uses without our stress)
BASELINE_CPU=0
BASELINE_MEMORY=0
BASELINE_NETWORK_KB=0

# Current metrics
CURRENT_CPU=0
CURRENT_MEMORY=0
CURRENT_NETWORK_KB=0

# Required additional stress
REQUIRED_CPU_STRESS=0
REQUIRED_MEMORY_STRESS_MB=0
REQUIRED_NETWORK_STRESS_KBS=0

# Dynamic sleep duration
CURRENT_SLEEP_DURATION=300

# Network interface for monitoring
PRIMARY_INTERFACE=""

# Statistics
TOTAL_CPU_STRESS_TIME=0
TOTAL_MEMORY_STRESS_TIME=0
TOTAL_NETWORK_STRESS_TIME=0

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    
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
    
    # Detect primary network interface (exclude lo)
    PRIMARY_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' || echo "eth0")
    
    log_info "System detected:"
    log_info "  • CPU cores: ${CPU_COUNT}"
    log_info "  • Total RAM: ${TOTAL_MEMORY_MB}MB"
    log_info "  • Primary network interface: ${PRIMARY_INTERFACE}"
    
    # Set CPU workers if not configured
    if [[ -z "$CPU_WORKERS" ]]; then
        CPU_WORKERS=$CPU_COUNT
    fi
    
    log_info "Target metrics (with ${SAFETY_MARGIN}% safety margin):"
    log_info "  • CPU: ${TARGET_CPU_PERCENT}% + ${SAFETY_MARGIN}% = $((TARGET_CPU_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Memory: ${TARGET_MEMORY_PERCENT}% + ${SAFETY_MARGIN}% = $((TARGET_MEMORY_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Network: ${TARGET_NETWORK_PERCENT}% + ${SAFETY_MARGIN}% = $((TARGET_NETWORK_PERCENT + SAFETY_MARGIN))%"
}

# ============================================================================
# METRIC MEASUREMENT FUNCTIONS
# ============================================================================

get_cpu_usage() {
    # Get instantaneous CPU usage from /proc/stat
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

get_cpu_usage_average() {
    # Get average CPU usage over a period
    local duration=${1:-10}
    local samples=10
    local total=0
    
    for ((i=0; i<samples; i++)); do
        local usage=$(get_cpu_usage)
        total=$((total + usage))
        sleep $(awk "BEGIN {printf \"%.2f\", $duration / $samples}")
    done
    
    echo $((total / samples))
}

get_memory_usage_percent() {
    if ! command -v free &> /dev/null; then
        echo "0"
        return
    fi
    
    local mem_info
    mem_info=$(free | grep "^Mem:" | awk '{printf "%.0f", ($3/$2)*100}')
    echo "$mem_info"
}

get_network_usage_kbs() {
    # Get network usage in KB/s
    if [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        echo "0"
        return
    fi
    
    local rx1=$(cat /sys/class/net/${PRIMARY_INTERFACE}/statistics/rx_bytes 2>/dev/null || echo "0")
    local tx1=$(cat /sys/class/net/${PRIMARY_INTERFACE}/statistics/tx_bytes 2>/dev/null || echo "0")
    
    sleep 1
    
    local rx2=$(cat /sys/class/net/${PRIMARY_INTERFACE}/statistics/rx_bytes 2>/dev/null || echo "0")
    local tx2=$(cat /sys/class/net/${PRIMARY_INTERFACE}/statistics/tx_bytes 2>/dev/null || echo "0")
    
    local rx_kbs=$(( (rx2 - rx1) / 1024 ))
    local tx_kbs=$(( (tx2 - tx1) / 1024 ))
    local total_kbs=$((rx_kbs + tx_kbs))
    
    echo "$total_kbs"
}

get_network_usage_percent() {
    # Get network usage as percentage of 100 Mbps (typical for cloud instances)
    # 100 Mbps = 12,500 KB/s
    local max_kbs=12500
    local current_kbs=$(get_network_usage_kbs)
    local percent=$(awk "BEGIN {printf \"%.0f\", ($current_kbs / $max_kbs) * 100}")
    
    # Cap at 100%
    if [[ $percent -gt 100 ]]; then
        percent=100
    fi
    
    echo "$percent"
}

# ============================================================================
# BASELINE MEASUREMENT
# ============================================================================

measure_baseline() {
    log_info "================================================"
    log_info "Measuring baseline system utilization..."
    log_info "Observing for ${BASELINE_DURATION}s to understand normal load"
    log_info "================================================"
    
    local samples=6
    local sample_interval=$((BASELINE_DURATION / samples))
    
    local cpu_total=0
    local mem_total=0
    local net_total=0
    
    for ((i=1; i<=samples; i++)); do
        log_info "Baseline sample $i/$samples..."
        
        local cpu=$(get_cpu_usage_average 5)
        local mem=$(get_memory_usage_percent)
        local net=$(get_network_usage_kbs)
        
        cpu_total=$((cpu_total + cpu))
        mem_total=$((mem_total + mem))
        net_total=$((net_total + net))
        
        log_debug "  Sample $i: CPU=${cpu}%, Memory=${mem}%, Network=${net}KB/s"
        
        if [[ $i -lt $samples ]]; then
            sleep "$sample_interval"
        fi
    done
    
    BASELINE_CPU=$((cpu_total / samples))
    BASELINE_MEMORY=$((mem_total / samples))
    BASELINE_NETWORK_KB=$((net_total / samples))
    
    log_info "================================================"
    log_info "Baseline metrics established:"
    log_info "  • CPU: ${BASELINE_CPU}%"
    log_info "  • Memory: ${BASELINE_MEMORY}%"
    log_info "  • Network: ${BASELINE_NETWORK_KB} KB/s"
    log_info "================================================"
    
    # Calculate required additional stress
    calculate_required_stress
}

# ============================================================================
# INTELLIGENT STRESS CALCULATION
# ============================================================================

calculate_required_stress() {
    local target_cpu=$((TARGET_CPU_PERCENT + SAFETY_MARGIN))
    local target_memory=$((TARGET_MEMORY_PERCENT + SAFETY_MARGIN))
    local target_network=$((TARGET_NETWORK_PERCENT + SAFETY_MARGIN))
    
    log_info "Calculating required additional stress..."
    
    # CPU calculation
    if [[ $BASELINE_CPU -ge $target_cpu ]]; then
        REQUIRED_CPU_STRESS=0
        log_info "  • CPU: Already at ${BASELINE_CPU}% (target: ${target_cpu}%) - NO STRESS NEEDED ✓"
    else
        REQUIRED_CPU_STRESS=$((target_cpu - BASELINE_CPU))
        log_info "  • CPU: Need additional ${REQUIRED_CPU_STRESS}% (baseline: ${BASELINE_CPU}%, target: ${target_cpu}%)"
    fi
    
    # Memory calculation
    if [[ $BASELINE_MEMORY -ge $target_memory ]]; then
        REQUIRED_MEMORY_STRESS_MB=0
        log_info "  • Memory: Already at ${BASELINE_MEMORY}% (target: ${target_memory}%) - NO STRESS NEEDED ✓"
    else
        local additional_percent=$((target_memory - BASELINE_MEMORY))
        REQUIRED_MEMORY_STRESS_MB=$(awk "BEGIN {printf \"%.0f\", ($TOTAL_MEMORY_MB * $additional_percent) / 100}")
        
        # Cap at reasonable maximum (50% of total RAM)
        local max_stress_mb=$((TOTAL_MEMORY_MB / 2))
        if [[ $REQUIRED_MEMORY_STRESS_MB -gt $max_stress_mb ]]; then
            REQUIRED_MEMORY_STRESS_MB=$max_stress_mb
        fi
        
        log_info "  • Memory: Need additional ${additional_percent}% = ${REQUIRED_MEMORY_STRESS_MB}MB (baseline: ${BASELINE_MEMORY}%, target: ${target_memory}%)"
    fi
    
    # Network calculation
    # For network, we calculate KB/s needed to reach target percentage
    # Assuming 100 Mbps (12,500 KB/s) as baseline network capacity
    local max_network_kbs=12500
    local target_network_kbs=$(awk "BEGIN {printf \"%.0f\", ($max_network_kbs * $target_network) / 100}")
    
    if [[ $BASELINE_NETWORK_KB -ge $target_network_kbs ]]; then
        REQUIRED_NETWORK_STRESS_KBS=0
        log_info "  • Network: Already at ${BASELINE_NETWORK_KB} KB/s (target: ${target_network_kbs} KB/s) - NO STRESS NEEDED ✓"
    else
        REQUIRED_NETWORK_STRESS_KBS=$((target_network_kbs - BASELINE_NETWORK_KB))
        log_info "  • Network: Need additional ${REQUIRED_NETWORK_STRESS_KBS} KB/s (baseline: ${BASELINE_NETWORK_KB} KB/s, target: ${target_network_kbs} KB/s)"
    fi
    
    # Adjust sleep duration based on how much stress we need
    calculate_sleep_duration
}

calculate_sleep_duration() {
    # If we need a lot of stress, reduce sleep time
    # If we need little stress, increase sleep time
    
    local stress_level=0
    
    # Calculate overall stress level (0-100)
    if [[ $REQUIRED_CPU_STRESS -gt 0 ]]; then
        stress_level=$((stress_level + (REQUIRED_CPU_STRESS * 100 / TARGET_CPU_PERCENT)))
    fi
    
    if [[ $REQUIRED_MEMORY_STRESS_MB -gt 0 ]]; then
        local mem_percent=$(awk "BEGIN {printf \"%.0f\", ($REQUIRED_MEMORY_STRESS_MB * 100) / $TOTAL_MEMORY_MB}")
        stress_level=$((stress_level + (mem_percent * 100 / TARGET_MEMORY_PERCENT)))
    fi
    
    if [[ $REQUIRED_NETWORK_STRESS_KBS -gt 0 ]]; then
        local net_percent=$(awk "BEGIN {printf \"%.0f\", ($REQUIRED_NETWORK_STRESS_KBS * 100) / 12500}")
        stress_level=$((stress_level + (net_percent * 100 / TARGET_NETWORK_PERCENT)))
    fi
    
    stress_level=$((stress_level / 3))  # Average of three metrics
    
    # Inverse relationship: more stress needed = less sleep
    # stress_level 0-100 maps to MAX_SLEEP_DURATION down to MIN_SLEEP_DURATION
    CURRENT_SLEEP_DURATION=$(awk "BEGIN {printf \"%.0f\", $MAX_SLEEP_DURATION - (($MAX_SLEEP_DURATION - $MIN_SLEEP_DURATION) * $stress_level / 100)}")
    
    log_info "Calculated stress level: ${stress_level}% → Sleep duration: ${CURRENT_SLEEP_DURATION}s"
}

# ============================================================================
# INTELLIGENT STRESS FUNCTIONS
# ============================================================================

stress_cpu_intelligent() {
    if [[ $REQUIRED_CPU_STRESS -le 0 ]]; then
        log_debug "CPU stress not needed (baseline already sufficient)"
        return
    fi
    
    log_info "CPU stress: Adding ${REQUIRED_CPU_STRESS}% for ${STRESS_DURATION}s"
    
    local start_time=$SECONDS
    local end_time=$((SECONDS + STRESS_DURATION))
    local pids=()
    
    # Calculate work/sleep ratio for target CPU percentage
    local work_sleep=$(awk "BEGIN {printf \"%.4f\", (100 - $REQUIRED_CPU_STRESS) / 1000}")
    
    for ((i = 0; i < CPU_WORKERS; i++)); do
        (
            renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
            
            while [[ $SECONDS -lt $end_time ]]; do
                for ((j = 0; j < 5000; j++)); do
                    : $((j * j * j % 7919))
                done
                sleep "$work_sleep" 2>/dev/null || sleep 0.01
            done
        ) &
        pids+=($!)
    done
    
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_CPU_STRESS_TIME=$((TOTAL_CPU_STRESS_TIME + elapsed))
    log_info "CPU stress completed (${elapsed}s)"
}

stress_memory_intelligent() {
    if [[ $REQUIRED_MEMORY_STRESS_MB -le 0 ]]; then
        log_debug "Memory stress not needed (baseline already sufficient)"
        return
    fi
    
    log_info "Memory stress: Allocating ${REQUIRED_MEMORY_STRESS_MB}MB for ${MEMORY_HOLD_DURATION}s"
    
    local start_time=$SECONDS
    local temp_file="/dev/shm/oracle-keep-alive-$$"
    
    # Safety check
    local free_memory_mb=$(free -m | grep "^Mem:" | awk '{print $7}')
    local memory_mb=$REQUIRED_MEMORY_STRESS_MB
    
    if [[ $memory_mb -gt $free_memory_mb ]]; then
        log_warn "Not enough free memory (${free_memory_mb}MB), reducing to ${free_memory_mb}MB"
        memory_mb=$free_memory_mb
    fi
    
    if dd if=/dev/urandom of="$temp_file" bs=1M count="$memory_mb" 2>/dev/null; then
        cat "$temp_file" > /dev/null 2>&1 || true
        sleep "$MEMORY_HOLD_DURATION"
        rm -f "$temp_file" 2>/dev/null || true
        
        local elapsed=$((SECONDS - start_time))
        TOTAL_MEMORY_STRESS_TIME=$((TOTAL_MEMORY_STRESS_TIME + elapsed))
        log_info "Memory stress completed (${elapsed}s)"
    else
        log_error "Memory stress failed"
    fi
}

stress_network_intelligent() {
    if [[ $REQUIRED_NETWORK_STRESS_KBS -le 0 ]]; then
        log_debug "Network stress not needed (baseline already sufficient)"
        return
    fi
    
    log_info "Network stress: Generating ${REQUIRED_NETWORK_STRESS_KBS} KB/s"
    
    local start_time=$SECONDS
    local targets_array=($NETWORK_PING_TARGETS)
    local http_targets_array=($NETWORK_HTTP_TARGETS)
    
    # 1. Distributed pings (parallel for efficiency)
    if [[ "$NETWORK_USE_DISTRIBUTED_TARGETS" == "1" ]]; then
        for target in "${targets_array[@]}"; do
            (
                renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
                ping -c "$NETWORK_PINGS_PER_TARGET" -i "$NETWORK_PING_INTERVAL" -W 2 "$target" > /dev/null 2>&1 || true
            ) &
        done
        wait
    fi
    
    # 2. HTTP requests
    if command -v curl &> /dev/null; then
        for ((i=0; i<NETWORK_HTTP_REQUESTS; i++)); do
            local target="${http_targets_array[$((i % ${#http_targets_array[@]}))]}"
            (
                renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
                curl -s -m "$NETWORK_HTTP_TIMEOUT" -o /dev/null "$target" 2>/dev/null || true
            ) &
            sleep 0.2
        done
        wait
    fi
    
    # 3. Bandwidth test - download enough data to generate required KB/s
    if [[ "$NETWORK_ENABLE_DOWNLOAD_TEST" == "1" ]] && command -v curl &> /dev/null; then
        # Download for 5 seconds at required rate
        local bytes_to_download=$((REQUIRED_NETWORK_STRESS_KBS * 1024 * 5))
        
        (
            renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
            curl -s -m 10 --limit-rate "${REQUIRED_NETWORK_STRESS_KBS}k" -r "0-${bytes_to_download}" -o /dev/null "$NETWORK_DOWNLOAD_TEST_URL" 2>/dev/null || true
        ) &
        wait
    fi
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
    log_info "Network stress completed (${elapsed}s)"
}

# ============================================================================
# MONITORING & ADJUSTMENT
# ============================================================================

monitor_and_adjust() {
    log_info "=== Monitoring Current Metrics ==="
    
    # Measure current utilization
    CURRENT_CPU=$(get_cpu_usage_average 10)
    CURRENT_MEMORY=$(get_memory_usage_percent)
    CURRENT_NETWORK_KB=$(get_network_usage_kbs)
    
    local target_cpu=$((TARGET_CPU_PERCENT + SAFETY_MARGIN))
    local target_memory=$((TARGET_MEMORY_PERCENT + SAFETY_MARGIN))
    local target_network=$((TARGET_NETWORK_PERCENT + SAFETY_MARGIN))
    
    log_info "Current metrics:"
    log_info "  • CPU: ${CURRENT_CPU}% (target: ${target_cpu}%)"
    log_info "  • Memory: ${CURRENT_MEMORY}% (target: ${target_memory}%)"
    log_info "  • Network: ${CURRENT_NETWORK_KB} KB/s"
    
    # Check if all metrics are meeting targets
    local all_targets_met=1
    
    if [[ $CURRENT_CPU -lt $target_cpu ]]; then
        log_warn "  ⚠ CPU below target"
        all_targets_met=0
    else
        log_info "  ✓ CPU target met"
    fi
    
    if [[ $CURRENT_MEMORY -lt $target_memory ]]; then
        log_warn "  ⚠ Memory below target"
        all_targets_met=0
    else
        log_info "  ✓ Memory target met"
    fi
    
    local target_network_kbs=$(awk "BEGIN {printf \"%.0f\", (12500 * $target_network) / 100}")
    if [[ $CURRENT_NETWORK_KB -lt $target_network_kbs ]]; then
        log_warn "  ⚠ Network below target"
        all_targets_met=0
    else
        log_info "  ✓ Network target met"
    fi
    
    if [[ $all_targets_met -eq 0 ]]; then
        log_warn "Not all targets met - recalculating required stress"
        # Re-measure baseline and recalculate
        measure_baseline
    else
        log_info "✓ All three metrics meeting targets - instance is SAFE"
    fi
}

# ============================================================================
# STATISTICS
# ============================================================================

show_comprehensive_stats() {
    log_info "================================================"
    log_info "=== Comprehensive System Statistics ==="
    log_info "================================================"
    
    # Current metrics
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage_percent)
    local mem_info=$(free -m | grep "^Mem:" | awk '{printf "%s/%sMB", $3, $2}')
    local net=$(get_network_usage_kbs)
    
    log_info "Current instantaneous metrics:"
    log_info "  • CPU: ${cpu}%"
    log_info "  • Memory: ${mem_info} (${mem}%)"
    log_info "  • Network: ${net} KB/s"
    log_info ""
    
    # Baseline vs Target
    log_info "Baseline → Current → Target:"
    log_info "  • CPU: ${BASELINE_CPU}% → ${CURRENT_CPU}% → $((TARGET_CPU_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Memory: ${BASELINE_MEMORY}% → ${CURRENT_MEMORY}% → $((TARGET_MEMORY_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Network: ${BASELINE_NETWORK_KB} KB/s → ${CURRENT_NETWORK_KB} KB/s → $(awk "BEGIN {printf \"%.0f\", (12500 * (TARGET_NETWORK_PERCENT + SAFETY_MARGIN)) / 100}") KB/s"
    log_info ""
    
    # Stress statistics
    log_info "Total stress applied:"
    log_info "  • CPU stress time: ${TOTAL_CPU_STRESS_TIME}s"
    log_info "  • Memory stress time: ${TOTAL_MEMORY_STRESS_TIME}s"
    log_info "  • Network stress time: ${TOTAL_NETWORK_STRESS_TIME}s"
    log_info ""
    
    # System info
    local uptime_str=$(uptime -p 2>/dev/null || uptime | cut -d',' -f1)
    log_info "System uptime: $uptime_str"
    log_info "Current sleep duration: ${CURRENT_SLEEP_DURATION}s"
    log_info "================================================"
}

# ============================================================================
# MAIN LOOP
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    pkill -P $$ 2>/dev/null || true
    rm -f /dev/shm/oracle-keep-alive-* 2>/dev/null || true
    log_info "Cleanup complete, exiting"
    exit 0
}

main() {
    trap cleanup SIGTERM SIGINT SIGHUP
    
    log_info "================================================"
    log_info "Oracle Cloud Keep-Alive v${VERSION} Started"
    log_info "INTELLIGENT MULTI-METRIC EDITION"
    log_info "================================================"
    
    detect_system
    
    # Initial baseline measurement
    measure_baseline
    
    log_info ""
    log_info "Starting intelligent stress cycles..."
    log_info "Will monitor and adjust every ${MONITORING_INTERVAL}s"
    log_info ""
    
    while true; do
        CYCLE_COUNT=$((CYCLE_COUNT + 1))
        log_info "--- Cycle #${CYCLE_COUNT} ---"
        
        # Apply intelligent stress based on calculated requirements
        stress_cpu_intelligent
        stress_memory_intelligent
        stress_network_intelligent
        
        # Show comprehensive stats periodically
        if [[ $LOG_STATS_EVERY_N_CYCLES -gt 0 ]] && [[ $((CYCLE_COUNT % LOG_STATS_EVERY_N_CYCLES)) -eq 0 ]]; then
            show_comprehensive_stats
        fi
        
        # Sleep
        log_info "Sleeping for ${CURRENT_SLEEP_DURATION}s... (next cycle in $((CURRENT_SLEEP_DURATION / 60))m)"
        sleep "$CURRENT_SLEEP_DURATION"
        
        # Monitor and adjust if needed
        if [[ $((CYCLE_COUNT % (MONITORING_INTERVAL / CURRENT_SLEEP_DURATION))) -eq 0 ]]; then
            monitor_and_adjust
        fi
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
    echo "Oracle Cloud Keep-Alive v${VERSION}"
    echo "Intelligent Multi-Metric Edition"
    exit 0
fi

main "$@"
