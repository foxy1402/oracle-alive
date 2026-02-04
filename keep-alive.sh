#!/bin/bash
#
# Oracle Cloud Keep-Alive Script v2.2 (Parallel Stress Edition)
# Prevents free tier ARM instances from being reclaimed due to inactivity
#
# NEW in v2.2:
# - PARALLEL execution: CPU, memory, network run simultaneously
# - CPU: 64s stress at 50-68% (USER+NICE only, matches Oracle)
# - Memory: 90s hold (application memory only, matches Oracle)
# - Network: 90s continuous traffic (sustained bandwidth, matches Oracle)
# - Total cycle: 96s with high duty cycles (67-94%)
# - Optimized to match Oracle's 60s periodic sampling methodology
# - Recalibration every 12 cycles (~20 minutes)
# - Baseline protection: Light 30% stress during baseline scans (prevents metric drops)
#
# Version: 2.2.1
#

set -euo pipefail

VERSION="2.2.1"

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

# CPU Stress Cycle Configuration (New Strategy)
# Fixed stress/sleep pattern with periodic recalibration
# 
# OPTIMIZED PARALLEL STRATEGY:
# ============================
# All three metrics (CPU, Memory, Network) run IN PARALLEL for maximum efficiency
# and to match Oracle's monitoring methodology.
#
# Cycle Structure (96 seconds total):
#   t=0s:   START - CPU stress begins (64s duration)
#           START - Memory allocated and held (90s duration)  
#           START - Network continuous traffic (90s duration)
#   t=64s:  CPU stress ends (sleep 0s)
#           Memory continues holding (26s remaining)
#           Network continues traffic (26s remaining)
#   t=90s:  Memory released
#           Network stopped
#   t=90s:  Cleanup and prep for next cycle (6s)
#   t=96s:  Next cycle begins
#
# Oracle Monitoring Alignment:
# ============================
# CPU:     Samples user+nice time only (we stress user-space = matches)
#          64s active / 96s cycle = 67% duty × 68% intensity = 45% avg ✓
#
# Memory:  Samples application memory (total - available, excludes buffers)
#          90s allocated / 96s cycle = 94% duty × 45% target = 42% avg ✓
#
# Network: Samples total interface traffic (all applications)
#          90s traffic / 96s cycle = 94% duty × bandwidth = sustained ✓
#
CPU_STRESS_PERCENT="${CPU_STRESS_PERCENT:-50}"      # Initial stress intensity (will auto-adjust to ~68%)
CPU_STRESS_DURATION="${CPU_STRESS_DURATION:-64}"    # Stress phase duration (seconds)
CPU_SLEEP_DURATION="${CPU_SLEEP_DURATION:-0}"       # Sleep phase (0 = overlap with memory/network)
CPU_RECALIBRATION_CYCLES="${CPU_RECALIBRATION_CYCLES:-12}"  # Recalibrate every N cycles
CPU_STRESS_FLOOR="${CPU_STRESS_FLOOR:-40}"          # Minimum stress percentage (safety floor)

# Memory/Network parallel stress duration
# How long to hold memory and run network traffic (in parallel with CPU + additional time)
MEMORY_NETWORK_DURATION="${MEMORY_NETWORK_DURATION:-90}"  # Hold for 90s out of 96s cycle

# Monitoring interval - how often to check and adjust (seconds)
MONITORING_INTERVAL="${MONITORING_INTERVAL:-300}"  # 5 minutes

# Baseline measurement duration (seconds)
# Script will observe system for this long to understand normal load
BASELINE_DURATION="${BASELINE_DURATION:-60}"

# ============================================================================
# DEFAULT CONFIGURATION (LEGACY - kept for compatibility)
# ============================================================================

# CPU
STRESS_CPU="${STRESS_CPU:-1}"
CPU_WORKERS="${CPU_WORKERS:-}"

# Memory
STRESS_MEMORY="${STRESS_MEMORY:-1}"
MEMORY_STRESS_MB="${MEMORY_STRESS_MB:-150}"

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
CPU_CYCLE_COUNT=0  # Track CPU stress cycles for recalibration

# Baseline metrics (what system normally uses without our stress)
BASELINE_CPU=0
BASELINE_MEMORY=0
BASELINE_NETWORK_KB=0

# Light stress contribution (for subtraction from baseline)
LIGHT_STRESS_MEMORY_MB=0

# Current metrics
CURRENT_CPU=0
CURRENT_MEMORY=0
CURRENT_NETWORK_KB=0

# Required additional stress
REQUIRED_CPU_STRESS=0
REQUIRED_MEMORY_STRESS_MB=0
REQUIRED_NETWORK_STRESS_KBS=0

# Dynamic CPU stress intensity (initialized from config, recalibrated periodically)
CURRENT_CPU_STRESS_PERCENT="${CPU_STRESS_PERCENT}"

# Network interface for monitoring
PRIMARY_INTERFACE=""

# Statistics
TOTAL_CPU_STRESS_TIME=0
TOTAL_MEMORY_STRESS_TIME=0
TOTAL_NETWORK_STRESS_TIME=0

# Background stress process PIDs
MEMORY_STRESS_PID=""
MEMORY_STRESS_TEMP_FILE=""
NETWORK_STRESS_PID=""

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
    
    # Detect OS for logging
    local os_name="Unknown"
    if [[ -f /etc/os-release ]]; then
        os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi
    
    # Detect primary network interface (exclude lo)
    # Use portable method that works on Oracle Linux 8 and Ubuntu
    PRIMARY_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    
    # Fallback: find first non-loopback interface that is UP
    if [[ -z "$PRIMARY_INTERFACE" ]] || [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        PRIMARY_INTERFACE=$(ip -o link show 2>/dev/null | awk -F': ' '!/lo:/ && /state UP/ {print $2; exit}')
    fi
    
    # Final fallback: find any non-loopback interface
    if [[ -z "$PRIMARY_INTERFACE" ]] || [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        PRIMARY_INTERFACE=$(ls /sys/class/net/ 2>/dev/null | grep -v '^lo$' | head -1)
    fi
    
    # Ultimate fallback
    if [[ -z "$PRIMARY_INTERFACE" ]]; then
        PRIMARY_INTERFACE="eth0"
        log_warn "Could not detect network interface, defaulting to eth0"
    fi
    
    log_info "System detected:"
    log_info "  • OS: ${os_name}"
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
    # Get USER CPU usage by measuring delta between two /proc/stat readings
    # 
    # CRITICAL: Oracle only counts USER + NICE time, NOT system/kernel time
    # This matches Oracle's monitoring methodology EXACTLY
    # 
    # What we measure (matches Oracle):
    #   ✓ user   - Normal user-space processes
    #   ✓ nice   - Niced user-space processes
    # 
    # What we EXCLUDE (Oracle also excludes these):
    #   ✗ system - Kernel/system time
    #   ✗ irq    - Hardware interrupt time
    #   ✗ softirq - Software interrupt time
    #   ✗ steal  - Time stolen by hypervisor
    #   ✗ iowait - Waiting for I/O
    # 
    # This ensures our measurements match what Oracle sees and uses
    # for reclaim decisions. System processes DON'T count!
    
    if [[ ! -f /proc/stat ]]; then
        echo "0"
        return
    fi
    
    # First reading
    local cpu_line1
    cpu_line1=$(head -1 /proc/stat)
    local user1 nice1 system1 idle1 iowait1 irq1 softirq1
    set -- $cpu_line1
    user1=$2 nice1=$3 system1=$4 idle1=$5 iowait1=$6 irq1=$7 softirq1=$8
    
    # Wait 1 second
    sleep 1
    
    # Second reading
    local cpu_line2
    cpu_line2=$(head -1 /proc/stat)
    local user2 nice2 system2 idle2 iowait2 irq2 softirq2
    set -- $cpu_line2
    user2=$2 nice2=$3 system2=$4 idle2=$5 iowait2=$6 irq2=$7 softirq2=$8
    
    # Calculate deltas
    local user_delta=$((user2 - user1))
    local nice_delta=$((nice2 - nice1))
    local system_delta=$((system2 - system1))
    local idle_delta=$((idle2 - idle1))
    local iowait_delta=$((iowait2 - iowait1))
    local irq_delta=$((irq2 - irq1))
    local softirq_delta=$((softirq2 - softirq1))
    
    # Total delta includes everything (for percentage calculation)
    local total_delta=$((user_delta + nice_delta + system_delta + idle_delta + iowait_delta + irq_delta + softirq_delta))
    
    # IMPORTANT: Only count USER + NICE (user space workload)
    # DO NOT count system, irq, softirq - Oracle doesn't monitor these
    local used_delta=$((user_delta + nice_delta))
    
    if [[ $total_delta -gt 0 ]]; then
        echo $((used_delta * 100 / total_delta))
    else
        echo "0"
    fi
}

get_cpu_usage_average() {
    # Get average CPU usage over a period
    # Note: Each get_cpu_usage() call takes ~1 second internally
    local duration=${1:-10}
    local samples
    
    # Adjust samples based on duration (each sample takes ~1s due to delta measurement)
    if [[ $duration -lt 5 ]]; then
        samples=3
    elif [[ $duration -lt 15 ]]; then
        samples=5
    else
        samples=10
    fi
    
    local total=0
    
    for ((i=0; i<samples; i++)); do
        local usage=$(get_cpu_usage)
        total=$((total + usage))
    done
    
    echo $((total / samples))
}

get_memory_usage_percent() {
    if ! command -v free &> /dev/null; then
        echo "0"
        return
    fi
    
    # IMPORTANT: Oracle monitors actual used memory (excluding buffers/cache)
    # The "available" memory calculation in modern free command handles this
    # Formula: (Total - Available) / Total = actual application usage
    
    # Parse free output - works on both old and new versions
    local free_output
    free_output=$(free 2>/dev/null)
    
    if [[ -z "$free_output" ]]; then
        echo "0"
        return
    fi
    
    local total
    local available
    
    # Try to get total and available from free output
    total=$(echo "$free_output" | awk '/^Mem:/ {print $2}')
    
    # Check if column 7 exists (available) - modern free has it
    local col_count
    col_count=$(echo "$free_output" | awk '/^Mem:/ {print NF}')
    
    if [[ "$col_count" -ge 7 ]]; then
        # Modern free with 'available' column
        available=$(echo "$free_output" | awk '/^Mem:/ {print $7}')
    else
        # Old free format: calculate available = free + buffers + cached
        local mem_free
        local buffers
        local cached
        mem_free=$(echo "$free_output" | awk '/^Mem:/ {print $4}')
        buffers=$(echo "$free_output" | awk '/^Mem:/ {print $6}')
        cached=$(echo "$free_output" | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "0")
        
        # Handle case where cached might be in a different row
        if [[ -z "$cached" ]] || [[ "$cached" == "0" ]]; then
            cached=$(echo "$free_output" | awk '/^-\/\+ buffers/ {print $4}' 2>/dev/null || echo "0")
        fi
        
        available=$((mem_free + buffers + cached))
    fi
    
    # Validate values
    if [[ -z "$total" ]] || [[ "$total" -le 0 ]]; then
        echo "0"
        return
    fi
    
    if [[ -z "$available" ]]; then
        available=0
    fi
    
    local used_real=$((total - available))
    if [[ $used_real -lt 0 ]]; then
        used_real=0
    fi
    
    echo $(( (used_real * 100) / total ))
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

# ============================================================================
# LIGHT STRESS FOR BASELINE PROTECTION
# ============================================================================

# Global PIDs for light stress processes
LIGHT_STRESS_CPU_PIDS=()
LIGHT_STRESS_MEMORY_PID=""
LIGHT_STRESS_MEMORY_TEMP_FILE=""
LIGHT_STRESS_NETWORK_PID=""

# Known light stress contributions (for subtraction from baseline)
LIGHT_STRESS_CPU_PERCENT=30
LIGHT_STRESS_NETWORK_KBS=200

start_light_stress_for_baseline() {
    # Start light background stress (30% all metrics) during baseline measurement
    # This ensures Oracle never sees drops below 20% during the 60s baseline scan
    # IMPORTANT: We know exact contributions and will SUBTRACT them from baseline readings
    
    # 1. Light CPU stress (30%)
    local light_cpu_workers=2
    local light_iterations=1500  # Lower iterations = lighter load
    local light_cpu_pids=()
    
    for ((i = 0; i < light_cpu_workers; i++)); do
        (
            renice -n 19 $$ >/dev/null 2>&1 || true
            local end_time=$((SECONDS + BASELINE_DURATION + 5))  # +5s buffer
            
            while [[ $SECONDS -lt $end_time ]]; do
                # Light CPU work
                for ((j = 0; j < light_iterations; j++)); do
                    : $((j * j % 997))
                done
                # Longer yield for lower CPU usage
                sleep 0.05
            done
        ) &
        LIGHT_STRESS_CPU_PIDS+=($!)
    done
    
    # 2. Light Memory stress (30%)
    local total_memory_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "1024")
    local light_memory_mb=$((total_memory_mb * 30 / 100))
    
    # Store for later subtraction from baseline
    LIGHT_STRESS_MEMORY_MB=$light_memory_mb
    
    # Cap at reasonable size
    if [[ $light_memory_mb -gt 4096 ]]; then
        light_memory_mb=4096
        LIGHT_STRESS_MEMORY_MB=4096
    fi
    if [[ $light_memory_mb -lt 100 ]]; then
        light_memory_mb=100
        LIGHT_STRESS_MEMORY_MB=100
    fi
    
    # CRITICAL: Generate temp file path BEFORE backgrounding
    local light_temp_file="/dev/shm/oracle-keep-alive-light-mem-$$-$(date +%s)"
    LIGHT_STRESS_MEMORY_TEMP_FILE="$light_temp_file"
    
    (
        if dd if=/dev/urandom of="$light_temp_file" bs=1M count="$light_memory_mb" 2>/dev/null; then
            local end_time=$((SECONDS + BASELINE_DURATION + 5))
            while [[ -f "$light_temp_file" ]] && [[ $SECONDS -lt $end_time ]]; do
                cat "$light_temp_file" > /dev/null 2>&1 || true
                sleep 5
            done
            rm -f "$light_temp_file" 2>/dev/null || true
        fi
    ) &
    LIGHT_STRESS_MEMORY_PID=$!
    
    # 3. Light Network stress (30% = ~3750 KB/s for 100Mbps, capped at 200 KB/s)
    local light_network_kbs=200
    
    (
        renice -n 19 $$ >/dev/null 2>&1 || true
        local end_time=$((SECONDS + BASELINE_DURATION + 5))
        local targets_array=($NETWORK_PING_TARGETS)
        
        while [[ $SECONDS -lt $end_time ]]; do
            # Quick pings
            if command -v ping &> /dev/null; then
                for target in "${targets_array[@]}"; do
                    ping -c 1 -W 1 "$target" > /dev/null 2>&1 &
                done
            fi
            
            # Light HTTP traffic
            if command -v curl &> /dev/null; then
                curl -s -m 3 --limit-rate "${light_network_kbs}k" -o /dev/null "$NETWORK_DOWNLOAD_TEST_URL" 2>/dev/null &
            fi
            
            sleep 5
        done
    ) &
    LIGHT_STRESS_NETWORK_PID=$!
    
    # Give light stress 2 seconds to ramp up before baseline measurement
    sleep 2
    
    log_debug "Light stress started: ${#LIGHT_STRESS_CPU_PIDS[@]} CPU workers, ${light_memory_mb}MB memory, ${light_network_kbs}KB/s network"
}

stop_light_stress_for_baseline() {
    # Stop all light stress processes
    
    # Stop CPU workers
    for pid in "${LIGHT_STRESS_CPU_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${LIGHT_STRESS_CPU_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    LIGHT_STRESS_CPU_PIDS=()
    
    # Stop memory stress
    if [[ -n "$LIGHT_STRESS_MEMORY_PID" ]]; then
        if [[ -n "${LIGHT_STRESS_MEMORY_TEMP_FILE:-}" ]]; then
            rm -f "$LIGHT_STRESS_MEMORY_TEMP_FILE" 2>/dev/null || true
        fi
        rm -f /dev/shm/oracle-keep-alive-light-mem-$$-* 2>/dev/null || true
        kill -TERM "$LIGHT_STRESS_MEMORY_PID" 2>/dev/null || true
        wait "$LIGHT_STRESS_MEMORY_PID" 2>/dev/null || true
        LIGHT_STRESS_MEMORY_PID=""
        LIGHT_STRESS_MEMORY_TEMP_FILE=""
    fi
    
    # Stop network stress
    if [[ -n "$LIGHT_STRESS_NETWORK_PID" ]]; then
        kill -TERM "$LIGHT_STRESS_NETWORK_PID" 2>/dev/null || true
        wait "$LIGHT_STRESS_NETWORK_PID" 2>/dev/null || true
        LIGHT_STRESS_NETWORK_PID=""
    fi
    
    # Clean up any remaining temp files
    rm -f /dev/shm/oracle-keep-alive-light-* 2>/dev/null || true
    
    # Give system 2 seconds to stabilize after stopping light stress
    sleep 2
    
    log_debug "Light stress stopped and cleaned up"
}

# ============================================================================
# BASELINE MEASUREMENT
# ============================================================================

measure_baseline() {
    log_info "================================================"
    log_info "Measuring baseline system utilization..."
    log_info "IMPORTANT: Only measuring USER applications (Oracle's monitoring methodology)"
    log_info "Excluding: System processes, kernel time, buffers/cache"
    log_info "Observing for ${BASELINE_DURATION}s to understand normal load"
    log_info ""
    log_info "BASELINE PROTECTION STRATEGY:"
    log_info "  1. Run light 30% stress during scan (protects against Oracle sampling)"
    log_info "  2. Measure system (includes light stress + user apps)"
    log_info "  3. Subtract known light stress contribution"
    log_info "  4. Result = TRUE baseline of user applications only"
    log_info "================================================"
    
    # CRITICAL: Ensure no stress processes are running from previous cycles
    # This baseline must reflect ONLY user applications (what Oracle monitors)
    pkill -P $$ 2>/dev/null || true
    sleep 2  # Let any remaining processes fully exit
    
    # START LIGHT BACKGROUND STRESS (30% all metrics)
    # This prevents Oracle from seeing low usage during baseline measurement
    log_info "Starting light protective stress: 30% CPU/Memory/Network for ${BASELINE_DURATION}s..."
    start_light_stress_for_baseline
    
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
    
    # Calculate raw averages (includes light stress)
    local raw_cpu=$((cpu_total / samples))
    local raw_memory=$((mem_total / samples))
    local raw_network=$((net_total / samples))
    
    log_info "================================================"
    log_info "Raw measurements (includes light stress):"
    log_info "  • CPU: ${raw_cpu}%"
    log_info "  • Memory: ${raw_memory}%"
    log_info "  • Network: ${raw_network} KB/s"
    log_info ""
    
    # SUBTRACT light stress contributions to get TRUE baseline (user apps only)
    log_info "Subtracting light stress contributions..."
    log_info "  • CPU: ${raw_cpu}% - ${LIGHT_STRESS_CPU_PERCENT}% = $((raw_cpu - LIGHT_STRESS_CPU_PERCENT))%"
    
    # Memory: Convert MB to percentage for subtraction (guard against division by zero)
    local light_memory_percent=0
    if [[ $TOTAL_MEMORY_MB -gt 0 ]]; then
        light_memory_percent=$((LIGHT_STRESS_MEMORY_MB * 100 / TOTAL_MEMORY_MB))
    fi
    log_info "  • Memory: ${raw_memory}% - ${light_memory_percent}% (${LIGHT_STRESS_MEMORY_MB}MB) = $((raw_memory - light_memory_percent))%"
    log_info "  • Network: ${raw_network} KB/s - ${LIGHT_STRESS_NETWORK_KBS} KB/s = $((raw_network - LIGHT_STRESS_NETWORK_KBS)) KB/s"
    
    # Apply subtractions (with floor at 0 to prevent negative values)
    BASELINE_CPU=$((raw_cpu - LIGHT_STRESS_CPU_PERCENT))
    if [[ $BASELINE_CPU -lt 0 ]]; then BASELINE_CPU=0; fi
    
    BASELINE_MEMORY=$((raw_memory - light_memory_percent))
    if [[ $BASELINE_MEMORY -lt 0 ]]; then BASELINE_MEMORY=0; fi
    
    BASELINE_NETWORK_KB=$((raw_network - LIGHT_STRESS_NETWORK_KBS))
    if [[ $BASELINE_NETWORK_KB -lt 0 ]]; then BASELINE_NETWORK_KB=0; fi
    
    log_info "================================================"
    log_info "TRUE Baseline (USER applications only, light stress subtracted):"
    log_info "  • CPU: ${BASELINE_CPU}% (user+nice time only)"
    log_info "  • Memory: ${BASELINE_MEMORY}% (excluding buffers/cache)"
    log_info "  • Network: ${BASELINE_NETWORK_KB} KB/s"
    log_info "================================================"
    
    # STOP LIGHT STRESS
    log_info "Stopping light background stress..."
    stop_light_stress_for_baseline
    
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
    
    # CPU calculation (no longer used in v2.2 parallel - kept for baseline reference)
    if [[ $BASELINE_CPU -ge $target_cpu ]]; then
        REQUIRED_CPU_STRESS=0
        log_info "  • CPU: Already at ${BASELINE_CPU}% (target: ${target_cpu}%) - NO STRESS NEEDED ✓"
    else
        REQUIRED_CPU_STRESS=$((target_cpu - BASELINE_CPU))
        log_info "  • CPU: Adding ${REQUIRED_CPU_STRESS}% stress (baseline: ${BASELINE_CPU}%, target: ${target_cpu}%)"
    fi
    
    # Memory calculation
    if [[ $BASELINE_MEMORY -ge $target_memory ]]; then
        REQUIRED_MEMORY_STRESS_MB=0
        log_info "  • Memory: Already at ${BASELINE_MEMORY}% (target: ${target_memory}%) - NO STRESS NEEDED ✓"
    else
        local additional_percent=$((target_memory - BASELINE_MEMORY))
        # Use pure bash arithmetic instead of awk for portability
        REQUIRED_MEMORY_STRESS_MB=$((TOTAL_MEMORY_MB * additional_percent / 100))
        
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
    # Use pure bash arithmetic
    local target_network_kbs=$((max_network_kbs * target_network / 100))
    
    if [[ $BASELINE_NETWORK_KB -ge $target_network_kbs ]]; then
        REQUIRED_NETWORK_STRESS_KBS=0
        log_info "  • Network: Already at ${BASELINE_NETWORK_KB} KB/s (target: ${target_network_kbs} KB/s) - NO STRESS NEEDED ✓"
    else
        REQUIRED_NETWORK_STRESS_KBS=$((target_network_kbs - BASELINE_NETWORK_KB))
        log_info "  • Network: Need additional ${REQUIRED_NETWORK_STRESS_KBS} KB/s (baseline: ${BASELINE_NETWORK_KB} KB/s, target: ${target_network_kbs} KB/s)"
    fi
}

# ============================================================================
# INTELLIGENT STRESS FUNCTIONS
# ============================================================================

stress_cpu_cycle() {
    # New fixed-cycle CPU stress strategy
    # Stress phase: CURRENT_CPU_STRESS_PERCENT% for CPU_STRESS_DURATION seconds
    # Sleep phase: 0% for CPU_SLEEP_DURATION seconds
    # Total cycle: CPU_STRESS_DURATION + CPU_SLEEP_DURATION seconds
    
    if [[ $STRESS_CPU -ne 1 ]]; then
        log_debug "CPU stress disabled"
        return
    fi
    
    # Increment cycle counter
    CPU_CYCLE_COUNT=$((CPU_CYCLE_COUNT + 1))
    
    # Check if recalibration is needed (every 12 cycles)
    if [[ $((CPU_CYCLE_COUNT % CPU_RECALIBRATION_CYCLES)) -eq 0 ]]; then
        recalibrate_cpu_stress
    fi
    
    local total_cycle_duration=$((CPU_STRESS_DURATION + CPU_SLEEP_DURATION))
    local expected_avg=$((CURRENT_CPU_STRESS_PERCENT * CPU_STRESS_DURATION / total_cycle_duration))
    
    log_info "CPU Cycle #${CPU_CYCLE_COUNT}: ${CURRENT_CPU_STRESS_PERCENT}% for ${CPU_STRESS_DURATION}s, sleep ${CPU_SLEEP_DURATION}s (expect ${expected_avg}% avg)"
    
    # === STRESS PHASE ===
    log_info "CPU stress phase: Running at ${CURRENT_CPU_STRESS_PERCENT}% for ${CPU_STRESS_DURATION}s"
    
    local start_time=$SECONDS
    local end_time=$((SECONDS + CPU_STRESS_DURATION))
    local pids=()
    
    # Calculate iterations to achieve target CPU percentage
    # Higher percentage = more iterations (more work, less sleep)
    local iterations=$((CURRENT_CPU_STRESS_PERCENT * 50))
    if [[ $iterations -lt 100 ]]; then
        iterations=100
    fi
    if [[ $iterations -gt 5000 ]]; then
        iterations=5000
    fi
    
    for ((i = 0; i < CPU_WORKERS; i++)); do
        (
            renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
            
            while [[ $SECONDS -lt $end_time ]]; do
                # CPU-bound work
                for ((j = 0; j < iterations; j++)); do
                    : $((j * j * j % 7919))
                done
                # Brief yield to allow other processes
                read -t 0.01 -N 0 2>/dev/null || true
            done
        ) &
        pids+=($!)
    done
    
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    local elapsed=$((SECONDS - start_time))
    TOTAL_CPU_STRESS_TIME=$((TOTAL_CPU_STRESS_TIME + elapsed))
    log_info "CPU stress phase completed (${elapsed}s)"
    
    # === SLEEP PHASE (only if duration > 0) ===
    if [[ $CPU_SLEEP_DURATION -gt 0 ]]; then
        log_info "CPU sleep phase: ${CPU_SLEEP_DURATION}s"
        sleep "$CPU_SLEEP_DURATION"
    fi
}

recalibrate_cpu_stress() {
    # Scan actual system-wide CPU usage and recalculate target stress intensity
    # Called every CPU_RECALIBRATION_CYCLES cycles (default: 12)
    
    log_info "=== CPU Recalibration (after ${CPU_RECALIBRATION_CYCLES} cycles) ==="
    
    # Measure current system-wide CPU usage
    log_info "Scanning actual system CPU usage..."
    local actual_cpu=$(get_cpu_usage_average 10)
    
    log_info "Current actual CPU usage: ${actual_cpu}%"
    log_info "Target (with buffer): $((TARGET_CPU_PERCENT + SAFETY_MARGIN))%"
    
    # Calculate new stress intensity based on formula: target% + buffer%
    local target_with_buffer=$((TARGET_CPU_PERCENT + SAFETY_MARGIN))
    
    # Calculate the required stress percentage to achieve target
    # We need to account for the duty cycle: stress_duration / total_cycle_duration
    local total_cycle_duration=$((CPU_STRESS_DURATION + CPU_SLEEP_DURATION))
    local duty_cycle_percent=$((CPU_STRESS_DURATION * 100 / total_cycle_duration))
    
    # If actual < target, we need more stress
    # stress_intensity = (target - baseline) * 100 / duty_cycle_percent
    local baseline_cpu=$actual_cpu
    
    if [[ $baseline_cpu -ge $target_with_buffer ]]; then
        # Already at or above target
        CURRENT_CPU_STRESS_PERCENT=$CPU_STRESS_FLOOR
        log_info "Already at target, setting stress to floor: ${CURRENT_CPU_STRESS_PERCENT}%"
    else
        # Calculate required stress intensity
        local gap=$((target_with_buffer - baseline_cpu))
        # Recalculate: what stress % during stress phase will give us the gap we need?
        # gap = stress_intensity * duty_cycle_percent / 100
        # stress_intensity = gap * 100 / duty_cycle_percent
        CURRENT_CPU_STRESS_PERCENT=$((gap * 100 / duty_cycle_percent))
        
        log_info "Gap to target: ${gap}% (baseline: ${baseline_cpu}%, target: ${target_with_buffer}%)"
        log_info "Duty cycle: ${duty_cycle_percent}% (${CPU_STRESS_DURATION}s/${total_cycle_duration}s)"
        log_info "Calculated stress intensity: ${CURRENT_CPU_STRESS_PERCENT}%"
    fi
    
    # Apply floor constraint
    if [[ $CURRENT_CPU_STRESS_PERCENT -lt $CPU_STRESS_FLOOR ]]; then
        log_info "Applying floor constraint: ${CURRENT_CPU_STRESS_PERCENT}% → ${CPU_STRESS_FLOOR}%"
        CURRENT_CPU_STRESS_PERCENT=$CPU_STRESS_FLOOR
    fi
    
    # Cap at 100%
    if [[ $CURRENT_CPU_STRESS_PERCENT -gt 100 ]]; then
        log_info "Capping at maximum: ${CURRENT_CPU_STRESS_PERCENT}% → 100%"
        CURRENT_CPU_STRESS_PERCENT=100
    fi
    
    log_info "New CPU stress intensity: ${CURRENT_CPU_STRESS_PERCENT}%"
    log_info "=== Recalibration Complete ==="
}

stress_memory_parallel() {
    # Parallel memory stress - allocates and holds for MEMORY_NETWORK_DURATION
    # Runs in background, returns immediately
    # Call cleanup_memory_stress() to stop and release
    
    if [[ $STRESS_MEMORY -ne 1 ]] || [[ $REQUIRED_MEMORY_STRESS_MB -le 0 ]]; then
        log_debug "Memory stress not needed (disabled or baseline sufficient)"
        return
    fi
    
    log_info "Memory stress: Allocating ${REQUIRED_MEMORY_STRESS_MB}MB, holding for ${MEMORY_NETWORK_DURATION}s (parallel)"
    
    # Safety check - get available memory
    local free_memory_mb
    local col_count
    col_count=$(free -m 2>/dev/null | awk '/^Mem:/ {print NF}')
    
    if [[ "$col_count" -ge 7 ]]; then
        free_memory_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')
    else
        free_memory_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $4 + $6}')
    fi
    
    if [[ -z "$free_memory_mb" ]] || [[ "$free_memory_mb" -le 0 ]]; then
        free_memory_mb=100
    fi
    
    local memory_mb=$REQUIRED_MEMORY_STRESS_MB
    
    if [[ $memory_mb -gt $free_memory_mb ]]; then
        log_warn "Not enough free memory (${free_memory_mb}MB), reducing to ${free_memory_mb}MB"
        memory_mb=$free_memory_mb
    fi
    
    if [[ $memory_mb -le 0 ]]; then
        log_warn "No memory available for stress test"
        return
    fi
    
    # CRITICAL: Generate temp file path BEFORE backgrounding
    # Using parent $$ ensures cleanup can find the file
    local temp_file="/dev/shm/oracle-keep-alive-mem-$$-$(date +%s)"
    
    # Store temp file path for cleanup
    MEMORY_STRESS_TEMP_FILE="$temp_file"
    
    # Allocate in background and hold
    (
        local start_time=$SECONDS
        
        if dd if=/dev/urandom of="$temp_file" bs=1M count="$memory_mb" 2>/dev/null; then
            log_debug "Memory allocated: ${memory_mb}MB at $temp_file, holding for ${MEMORY_NETWORK_DURATION}s"
            
            # Hold memory by keeping it in cache
            while [[ -f "$temp_file" ]] && [[ $((SECONDS - start_time)) -lt $MEMORY_NETWORK_DURATION ]]; do
                cat "$temp_file" > /dev/null 2>&1 || true
                sleep 5
            done
            
            rm -f "$temp_file" 2>/dev/null || true
            
            local elapsed=$((SECONDS - start_time))
            log_info "Memory stress completed (held for ${elapsed}s)"
        else
            log_error "Memory allocation failed"
            rm -f "$temp_file" 2>/dev/null || true
        fi
    ) &
    
    # Store PID for cleanup
    MEMORY_STRESS_PID=$!
}

cleanup_memory_stress() {
    # Stop memory stress and release
    if [[ -n "${MEMORY_STRESS_PID:-}" ]]; then
        # Remove temp file using stored path (signals subprocess to exit)
        if [[ -n "${MEMORY_STRESS_TEMP_FILE:-}" ]]; then
            rm -f "$MEMORY_STRESS_TEMP_FILE" 2>/dev/null || true
        fi
        
        # Also clean up any orphaned temp files from this process
        rm -f /dev/shm/oracle-keep-alive-mem-$$-* 2>/dev/null || true
        
        # Kill the background process
        kill -TERM "$MEMORY_STRESS_PID" 2>/dev/null || true
        wait "$MEMORY_STRESS_PID" 2>/dev/null || true
        
        MEMORY_STRESS_PID=""
        MEMORY_STRESS_TEMP_FILE=""
    fi
}

stress_network_parallel() {
    # Parallel network stress - continuous traffic for MEMORY_NETWORK_DURATION
    # Runs in background, returns immediately
    # Call cleanup_network_stress() to stop
    
    if [[ $STRESS_NETWORK -ne 1 ]] || [[ $REQUIRED_NETWORK_STRESS_KBS -le 0 ]]; then
        log_debug "Network stress not needed (disabled or baseline sufficient)"
        return
    fi
    
    # Cap at configured bandwidth limit
    local target_kbs=$REQUIRED_NETWORK_STRESS_KBS
    if [[ $target_kbs -gt $NETWORK_BANDWIDTH_LIMIT_KBS ]]; then
        target_kbs=$NETWORK_BANDWIDTH_LIMIT_KBS
    fi
    
    log_info "Network stress: Continuous ${target_kbs} KB/s for ${MEMORY_NETWORK_DURATION}s (parallel)"
    
    # Start continuous network traffic in background
    (
        local start_time=$SECONDS
        local targets_array=($NETWORK_PING_TARGETS)
        local http_targets_array=($NETWORK_HTTP_TARGETS)
        
        renice -n "$PROCESS_NICE_LEVEL" $$ >/dev/null 2>&1 || true
        
        # Continuous loop until duration expires
        while [[ $((SECONDS - start_time)) -lt $MEMORY_NETWORK_DURATION ]]; do
            
            # 1. Quick pings to multiple targets (parallel, fast)
            if [[ "$NETWORK_USE_DISTRIBUTED_TARGETS" == "1" ]] && command -v ping &> /dev/null; then
                for target in "${targets_array[@]}"; do
                    ping -c 2 -i 1 -W 1 "$target" > /dev/null 2>&1 &
                done
            fi
            
            # 2. HTTP requests (lightweight, distributed)
            if command -v curl &> /dev/null; then
                for target in "${http_targets_array[@]}"; do
                    curl -s -m 2 -o /dev/null "$target" 2>/dev/null &
                done
            fi
            
            # 3. Continuous download with rate limiting (main bandwidth generator)
            if [[ "$NETWORK_ENABLE_DOWNLOAD_TEST" == "1" ]] && command -v curl &> /dev/null; then
                # Download for 8 seconds at target rate, then loop
                curl -s -m 10 --limit-rate "${target_kbs}k" -o /dev/null "$NETWORK_DOWNLOAD_TEST_URL" 2>/dev/null &
            fi
            
            # Wait a bit before next iteration (8s download + 2s gap = ~10s per loop)
            sleep 8
            
            # Cleanup background jobs to avoid accumulation (portable way)
            # Kill all background jobs in this subshell
            for pid in $(jobs -p 2>/dev/null); do
                kill "$pid" 2>/dev/null || true
            done
        done
        
        # Final cleanup - kill all remaining background jobs
        for pid in $(jobs -p 2>/dev/null); do
            kill "$pid" 2>/dev/null || true
        done
        
        local elapsed=$((SECONDS - start_time))
        TOTAL_NETWORK_STRESS_TIME=$((TOTAL_NETWORK_STRESS_TIME + elapsed))
        log_info "Network stress completed (ran for ${elapsed}s)"
    ) &
    
    # Store PID for cleanup
    NETWORK_STRESS_PID=$!
}

cleanup_network_stress() {
    # Stop network stress
    if [[ -n "${NETWORK_STRESS_PID:-}" ]]; then
        # Kill the main process and all its children
        pkill -P "$NETWORK_STRESS_PID" 2>/dev/null || true
        kill -TERM "$NETWORK_STRESS_PID" 2>/dev/null || true
        wait "$NETWORK_STRESS_PID" 2>/dev/null || true
        NETWORK_STRESS_PID=""
    fi
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
    
    # Use pure bash arithmetic
    local target_network_kbs=$((12500 * target_network / 100))
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
    local mem_info
    mem_info=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%s/%sMB", $3, $2}' || echo "N/A")
    local net=$(get_network_usage_kbs)
    
    log_info "Current instantaneous metrics:"
    log_info "  • CPU: ${cpu}%"
    log_info "  • Memory: ${mem_info} (${mem}%)"
    log_info "  • Network: ${net} KB/s"
    log_info ""
    
    # Baseline vs Target
    local target_net_kbs=$((12500 * (TARGET_NETWORK_PERCENT + SAFETY_MARGIN) / 100))
    log_info "Baseline → Current → Target:"
    log_info "  • CPU: ${BASELINE_CPU}% → ${CURRENT_CPU}% → $((TARGET_CPU_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Memory: ${BASELINE_MEMORY}% → ${CURRENT_MEMORY}% → $((TARGET_MEMORY_PERCENT + SAFETY_MARGIN))%"
    log_info "  • Network: ${BASELINE_NETWORK_KB} KB/s → ${CURRENT_NETWORK_KB} KB/s → ${target_net_kbs} KB/s"
    log_info ""
    
    # Stress statistics
    log_info "Total stress applied:"
    log_info "  • CPU stress time: ${TOTAL_CPU_STRESS_TIME}s"
    log_info "  • Memory stress time: ${TOTAL_MEMORY_STRESS_TIME}s"
    log_info "  • Network stress time: ${TOTAL_NETWORK_STRESS_TIME}s"
    log_info ""
    
    # System info - uptime -p not available on Oracle Linux 8
    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null) || uptime_str=$(uptime | sed 's/.*up /up /' | cut -d',' -f1-2)
    log_info "System uptime: $uptime_str"
    log_info "Total cycle duration: ~$((MEMORY_NETWORK_DURATION + 6))s (${MEMORY_NETWORK_DURATION}s stress + 6s cleanup)"
    log_info "================================================"
}

# ============================================================================
# MAIN LOOP
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    
    # Stop background memory and network stress
    cleanup_memory_stress
    cleanup_network_stress
    
    # Kill any remaining child processes
    pkill -P $$ 2>/dev/null || true
    
    # Remove temp files
    rm -f /dev/shm/oracle-keep-alive-* 2>/dev/null || true
    
    log_info "Cleanup complete, exiting"
    exit 0
}

main() {
    trap cleanup SIGTERM SIGINT SIGHUP
    
    log_info "================================================"
    log_info "Oracle Cloud Keep-Alive v${VERSION} Started"
    log_info "PARALLEL STRESS EDITION"
    log_info "================================================"
    
    detect_system
    
    # Initial baseline measurement
    measure_baseline
    
    log_info ""
    log_info "Starting parallel stress cycles..."
    log_info "CPU: ${CPU_STRESS_PERCENT}% for ${CPU_STRESS_DURATION}s"
    log_info "Memory/Network: Hold for ${MEMORY_NETWORK_DURATION}s (parallel with CPU)"
    log_info "Total cycle: ~$((MEMORY_NETWORK_DURATION + 6))s (90s stress + 6s cleanup)"
    log_info "CPU recalibration: Every ${CPU_RECALIBRATION_CYCLES} cycles"
    log_info ""
    
    while true; do
        CYCLE_COUNT=$((CYCLE_COUNT + 1))
        log_info "=== Cycle #${CYCLE_COUNT} ==="
        
        local cycle_start=$SECONDS
        
        # START ALL THREE STRESSES IN PARALLEL
        # Memory and network start immediately and run in background
        stress_memory_parallel
        stress_network_parallel
        
        # CPU stress runs in foreground (blocks for CPU_STRESS_DURATION)
        stress_cpu_cycle
        
        # CPU is done at t=64s, but memory/network continue until t=90s
        local cpu_done=$((SECONDS - cycle_start))
        local remaining=$((MEMORY_NETWORK_DURATION - cpu_done))
        
        if [[ $remaining -gt 0 ]]; then
            log_info "CPU done (${cpu_done}s), waiting ${remaining}s for memory/network to complete..."
            sleep "$remaining"
        fi
        
        # Stop memory and network stress
        cleanup_memory_stress
        cleanup_network_stress
        
        # Show comprehensive stats periodically
        if [[ $LOG_STATS_EVERY_N_CYCLES -gt 0 ]] && [[ $((CYCLE_COUNT % LOG_STATS_EVERY_N_CYCLES)) -eq 0 ]]; then
            show_comprehensive_stats
        fi
        
        # Short cleanup/prep time before next cycle
        log_info "Cleanup and prep (6s)..."
        sleep 6
        
        local cycle_total=$((SECONDS - cycle_start))
        log_info "Cycle completed in ${cycle_total}s"
        
        # Monitor and adjust memory/network requirements periodically
        # CPU self-calibrates every 12 cycles
        local cycles_per_monitor=$((MONITORING_INTERVAL / (MEMORY_NETWORK_DURATION + 6)))
        if [[ $cycles_per_monitor -lt 1 ]]; then
            cycles_per_monitor=1
        fi
        
        if [[ $((CYCLE_COUNT % cycles_per_monitor)) -eq 0 ]]; then
            monitor_and_adjust
        fi
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

show_help() {
    echo "Oracle Cloud Keep-Alive v${VERSION}"
    echo "Parallel Stress Edition"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h       Show this help message"
    echo "  --version, -v    Show version information"
    echo
    echo "Description:"
    echo "  Prevents Oracle Cloud free-tier instances from being reclaimed"
    echo "  by maintaining CPU, memory, and network utilization above 40%."
    echo
    echo "Configuration:"
    echo "  /etc/default/oracle-keep-alive"
    echo
    echo "Logs:"
    echo "  /var/log/oracle-keep-alive.log"
    echo
    echo "Service management:"
    echo "  sudo systemctl status oracle-keep-alive"
    echo "  sudo systemctl restart oracle-keep-alive"
    echo "  sudo systemctl stop oracle-keep-alive"
    echo
}

if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
    echo "Oracle Cloud Keep-Alive v${VERSION}"
    echo "Parallel Stress Edition"
    exit 0
fi

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

main "$@"
