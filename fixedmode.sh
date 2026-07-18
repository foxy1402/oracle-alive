#!/bin/bash
#
# Oracle Cloud Fixed-Mode Keep-Alive Script v1.0
# Maintains EXACT target percentages continuously with self-healing
#
# Features:
# - Manual target setting for CPU, RAM, Network
# - No sleep cycles - continuous monitoring and adjustment
# - Stable dashboard lines (no fluctuations)
# - Self-healing: auto-restarts failed stress processes
# - Single-CPU optimized: prevents overshoot to 100%
# - Works on Ubuntu, Oracle Linux (x86_64 and ARM)
#
# Version: 1.0.0
#

set -euo pipefail

VERSION="1.0.0"

# ============================================================================
# CONFIGURATION - SET YOUR TARGETS HERE
# ============================================================================

# CPU and RAM targets (percentage) — the only metrics users need to configure
# Oracle's minimum threshold is 20%; 25-30% gives a safe margin
TARGET_CPU_PERCENT="${TARGET_CPU_PERCENT:-25}"
TARGET_MEMORY_PERCENT="${TARGET_MEMORY_PERCENT:-30}"

# Control loop interval (seconds) — how often to check and adjust
CONTROL_INTERVAL="${CONTROL_INTERVAL:-3}"

# Network stress — disabled by default; set ENABLE_NETWORK=true in config to activate
ENABLE_NETWORK="${ENABLE_NETWORK:-false}"
TARGET_NETWORK_PERCENT="${TARGET_NETWORK_PERCENT:-30}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/oracle-fixed-mode.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
STATS_INTERVAL="${STATS_INTERVAL:-60}"

# Process priority
PROCESS_NICE_LEVEL="${PROCESS_NICE_LEVEL:-19}"
IO_SCHEDULING_CLASS="${IO_SCHEDULING_CLASS:-idle}"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

CPU_COUNT=1
TOTAL_MEMORY_MB=0
PRIMARY_INTERFACE=""

# Current stress levels (dynamically adjusted)
CURRENT_CPU_WORKERS=0
CURRENT_CPU_LOAD=0
CURRENT_MEMORY_MB=0
CURRENT_NETWORK_KBS=0

# PIDs of active stress processes
declare -a CPU_WORKER_PIDS=()
MEMORY_STRESS_PID=""
MEMORY_TEMP_FILE=""
declare -a NETWORK_STRESS_PIDS=()

# Statistics
STATS_LAST_LOG=0
TOTAL_ADJUSTMENTS=0
CPU_ADJUSTMENTS=0
MEMORY_ADJUSTMENTS=0
NETWORK_ADJUSTMENTS=0

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
    
    local os_name="Unknown"
    if [[ -f /etc/os-release ]]; then
        os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi
    
    # Detect primary network interface
    PRIMARY_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    
    if [[ -z "$PRIMARY_INTERFACE" ]] || [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        PRIMARY_INTERFACE=$(ip -o link show 2>/dev/null | awk -F': ' '!/lo:/ && /state UP/ {print $2; exit}')
    fi
    
    if [[ -z "$PRIMARY_INTERFACE" ]] || [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        PRIMARY_INTERFACE=$(ls /sys/class/net/ 2>/dev/null | grep -v '^lo$' | head -1)
    fi
    
    if [[ -z "$PRIMARY_INTERFACE" ]]; then
        PRIMARY_INTERFACE="eth0"
        log_warn "Could not detect network interface, defaulting to eth0"
    fi
    
    log_info "================================"
    log_info "Oracle Fixed-Mode Keep-Alive v${VERSION}"
    log_info "================================"
    log_info "System Information:"
    log_info "  • OS: ${os_name}"
    log_info "  • CPU cores: ${CPU_COUNT}"
    log_info "  • Total RAM: ${TOTAL_MEMORY_MB}MB"
    if [[ "$ENABLE_NETWORK" == "true" ]]; then
        log_info "  • Network interface: ${PRIMARY_INTERFACE}"
    fi
    log_info ""
    log_info "Target Utilization:"
    log_info "  • CPU: ${TARGET_CPU_PERCENT}%"
    log_info "  • Memory: ${TARGET_MEMORY_PERCENT}%"
    if [[ "$ENABLE_NETWORK" == "true" ]]; then
        log_info "  • Network: ${TARGET_NETWORK_PERCENT}%"
    else
        log_info "  • Network: disabled"
    fi
    log_info ""
    log_info "Control Parameters:"
    log_info "  • Check interval: ${CONTROL_INTERVAL}s"
    log_info "================================"
}

# ============================================================================
# METRIC MEASUREMENT FUNCTIONS
# ============================================================================

get_cpu_usage() {
    # Measure USER CPU usage (matches Oracle's monitoring)
    # Oracle only counts user+nice time, NOT system/kernel time
    
    if [[ ! -f /proc/stat ]]; then
        echo "0"
        return
    fi
    
    local cpu_line1
    cpu_line1=$(head -1 /proc/stat)
    local user1 nice1 system1 idle1 iowait1 irq1 softirq1
    set -- $cpu_line1
    user1=$2 nice1=$3 system1=$4 idle1=$5 iowait1=$6 irq1=$7 softirq1=$8
    
    sleep 1
    
    local cpu_line2
    cpu_line2=$(head -1 /proc/stat)
    local user2 nice2 system2 idle2 iowait2 irq2 softirq2
    set -- $cpu_line2
    user2=$2 nice2=$3 system2=$4 idle2=$5 iowait2=$6 irq2=$7 softirq2=$8
    
    local user_delta=$((user2 - user1))
    local nice_delta=$((nice2 - nice1))
    local system_delta=$((system2 - system1))
    local idle_delta=$((idle2 - idle1))
    local iowait_delta=$((iowait2 - iowait1))
    local irq_delta=$((irq2 - irq1))
    local softirq_delta=$((softirq2 - softirq1))
    
    local total_delta=$((user_delta + nice_delta + system_delta + idle_delta + iowait_delta + irq_delta + softirq_delta))
    local used_delta=$((user_delta + nice_delta))
    
    if [[ $total_delta -gt 0 ]]; then
        echo $((used_delta * 100 / total_delta))
    else
        echo "0"
    fi
}

get_memory_usage_percent() {
    # Measure application memory usage (matches Oracle's monitoring)
    # Oracle monitors (Total - Available) = actual app memory
    
    if ! command -v free &> /dev/null; then
        echo "0"
        return
    fi
    
    local free_output
    free_output=$(free 2>/dev/null)
    
    if [[ -z "$free_output" ]]; then
        echo "0"
        return
    fi
    
    local total
    local available
    
    total=$(echo "$free_output" | awk '/^Mem:/ {print $2}')
    local col_count
    col_count=$(echo "$free_output" | awk '/^Mem:/ {print NF}')
    
    if [[ "$col_count" -ge 7 ]]; then
        available=$(echo "$free_output" | awk '/^Mem:/ {print $7}')
    else
        local mem_free buffers cached
        mem_free=$(echo "$free_output" | awk '/^Mem:/ {print $4}')
        buffers=$(echo "$free_output" | awk '/^Mem:/ {print $6}')
        cached=$(echo "$free_output" | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "0")
        available=$((mem_free + buffers + cached))
    fi
    
    if [[ -z "$total" ]] || [[ "$total" -le 0 ]]; then
        echo "0"
        return
    fi
    
    if [[ -z "$available" ]]; then
        available=0
    fi
    
    local used=$((total - available))
    echo $((used * 100 / total))
}

get_network_usage_kbs() {
    # Measure current network bandwidth in KB/s
    
    if [[ ! -d "/sys/class/net/${PRIMARY_INTERFACE}" ]]; then
        echo "0"
        return
    fi
    
    local rx_file="/sys/class/net/${PRIMARY_INTERFACE}/statistics/rx_bytes"
    local tx_file="/sys/class/net/${PRIMARY_INTERFACE}/statistics/tx_bytes"
    
    if [[ ! -f "$rx_file" ]] || [[ ! -f "$tx_file" ]]; then
        echo "0"
        return
    fi
    
    local rx1 tx1
    rx1=$(cat "$rx_file" 2>/dev/null || echo "0")
    tx1=$(cat "$tx_file" 2>/dev/null || echo "0")
    
    sleep 1
    
    local rx2 tx2
    rx2=$(cat "$rx_file" 2>/dev/null || echo "0")
    tx2=$(cat "$tx_file" 2>/dev/null || echo "0")
    
    local rx_delta=$((rx2 - rx1))
    local tx_delta=$((tx2 - tx1))
    local total_bytes=$((rx_delta + tx_delta))
    
    echo $((total_bytes / 1024))
}

# ============================================================================
# CPU STRESS CONTROL
# ============================================================================

adjust_cpu_stress() {
    local current_usage=$1
    local target=$TARGET_CPU_PERCENT
    local diff=$((current_usage - target))
    
    log_debug "CPU: current=${current_usage}%, target=${target}%, diff=${diff}%"
    
    # Within tolerance - no adjustment needed
    if [[ $diff -ge -$CPU_TOLERANCE && $diff -le $CPU_TOLERANCE ]]; then
        log_debug "CPU within tolerance, no adjustment"
        return
    fi
    
    # Need to increase stress
    if [[ $diff -lt -$CPU_TOLERANCE ]]; then
        local increase=$CPU_ADJUSTMENT_STEP
        CURRENT_CPU_LOAD=$((CURRENT_CPU_LOAD + increase))
        
        # Cap at 95% to prevent total lockup on single-CPU systems
        if [[ $CURRENT_CPU_LOAD -gt 95 ]]; then
            CURRENT_CPU_LOAD=95
        fi
        
        log_info "CPU below target (${current_usage}% < ${target}%), increasing load to ${CURRENT_CPU_LOAD}%"
        restart_cpu_stress
        CPU_ADJUSTMENTS=$((CPU_ADJUSTMENTS + 1))
        
    # Need to decrease stress
    elif [[ $diff -gt $CPU_TOLERANCE ]]; then
        local decrease=$CPU_ADJUSTMENT_STEP
        CURRENT_CPU_LOAD=$((CURRENT_CPU_LOAD - decrease))
        
        # Don't go negative
        if [[ $CURRENT_CPU_LOAD -lt 0 ]]; then
            CURRENT_CPU_LOAD=0
        fi
        
        log_info "CPU above target (${current_usage}% > ${target}%), decreasing load to ${CURRENT_CPU_LOAD}%"
        
        if [[ $CURRENT_CPU_LOAD -eq 0 ]]; then
            stop_cpu_stress
        else
            restart_cpu_stress
        fi
        CPU_ADJUSTMENTS=$((CPU_ADJUSTMENTS + 1))
    fi
}

start_cpu_stress() {
    if [[ $CURRENT_CPU_LOAD -le 0 ]]; then
        return
    fi
    
    # Use stress-ng if available, otherwise fallback to basic method
    if command -v stress-ng &> /dev/null; then
        for ((i=0; i<CPU_COUNT; i++)); do
            # Run stress-ng in background
            # Use very long timeout (1 year = 31536000 seconds) for continuous operation
            nohup nice -n $PROCESS_NICE_LEVEL stress-ng --cpu 1 --cpu-load $CURRENT_CPU_LOAD -t 31536000 --quiet &>/dev/null &
            CPU_WORKER_PIDS+=($!)
            # Give it a moment to start
            sleep 0.1
        done
        log_debug "Started ${CPU_COUNT} stress-ng workers at ${CURRENT_CPU_LOAD}% load (PIDs: ${CPU_WORKER_PIDS[*]})"
    else
        # Fallback: Simple yes loop with CPU limit via timeout
        # This is more reliable than complex timing loops
        for ((i=0; i<CPU_COUNT; i++)); do
            (
                # Simple CPU burner - runs continuously
                while true; do
                    # Busy loop for work period (ms)
                    local work_cycles=$((CURRENT_CPU_LOAD * 1000))
                    local sleep_cycles=$(( (100 - CURRENT_CPU_LOAD) * 1000 ))
                    
                    # Work phase - simple counter loop
                    local counter=0
                    while [[ $counter -lt $work_cycles ]]; do
                        counter=$((counter + 1))
                    done
                    
                    # Sleep phase
                    if [[ $sleep_cycles -gt 0 ]]; then
                        local sleep_sec=$(echo "scale=3; $sleep_cycles / 1000000" | bc 2>/dev/null || echo "0.001")
                        sleep "$sleep_sec" 2>/dev/null || sleep 0.001
                    fi
                done
            ) &
            CPU_WORKER_PIDS+=($!)
        done
        log_debug "Started ${CPU_COUNT} CPU workers (fallback mode) at ${CURRENT_CPU_LOAD}% load"
    fi
    
    # Set lowest priority
    for pid in "${CPU_WORKER_PIDS[@]}"; do
        renice -n $PROCESS_NICE_LEVEL -p $pid &> /dev/null || true
        ionice -c 3 -p $pid &> /dev/null || true
    done
}

stop_cpu_stress() {
    if [[ ${#CPU_WORKER_PIDS[@]} -gt 0 ]]; then
        for pid in "${CPU_WORKER_PIDS[@]}"; do
            kill -9 $pid 2>/dev/null || true
        done
        CPU_WORKER_PIDS=()
        log_debug "Stopped all CPU workers"
    fi
}

restart_cpu_stress() {
    stop_cpu_stress
    start_cpu_stress
}

# ============================================================================
# MEMORY STRESS CONTROL
# ============================================================================

adjust_memory_stress() {
    local current_usage=$1
    local target=$TARGET_MEMORY_PERCENT
    local diff=$((current_usage - target))
    
    log_debug "Memory: current=${current_usage}%, target=${target}%, diff=${diff}%"
    
    if [[ $diff -ge -$MEMORY_TOLERANCE && $diff -le $MEMORY_TOLERANCE ]]; then
        log_debug "Memory within tolerance, no adjustment"
        return
    fi
    
    if [[ $diff -lt -$MEMORY_TOLERANCE ]]; then
        CURRENT_MEMORY_MB=$((CURRENT_MEMORY_MB + MEMORY_ADJUSTMENT_MB))
        
        # Cap at 90% of total to prevent OOM
        local max_mb=$((TOTAL_MEMORY_MB * 90 / 100))
        if [[ $CURRENT_MEMORY_MB -gt $max_mb ]]; then
            CURRENT_MEMORY_MB=$max_mb
        fi
        
        log_info "Memory below target (${current_usage}% < ${target}%), increasing to ${CURRENT_MEMORY_MB}MB"
        restart_memory_stress
        MEMORY_ADJUSTMENTS=$((MEMORY_ADJUSTMENTS + 1))
        
    elif [[ $diff -gt $MEMORY_TOLERANCE ]]; then
        CURRENT_MEMORY_MB=$((CURRENT_MEMORY_MB - MEMORY_ADJUSTMENT_MB))
        
        if [[ $CURRENT_MEMORY_MB -lt 0 ]]; then
            CURRENT_MEMORY_MB=0
        fi
        
        log_info "Memory above target (${current_usage}% > ${target}%), decreasing to ${CURRENT_MEMORY_MB}MB"
        
        if [[ $CURRENT_MEMORY_MB -eq 0 ]]; then
            stop_memory_stress
        else
            restart_memory_stress
        fi
        MEMORY_ADJUSTMENTS=$((MEMORY_ADJUSTMENTS + 1))
    fi
}

start_memory_stress() {
    if [[ $CURRENT_MEMORY_MB -le 0 ]]; then
        return
    fi
    
    MEMORY_TEMP_FILE="/dev/shm/oracle-fixed-mode-mem-$$"
    
    (
        nice -n $PROCESS_NICE_LEVEL dd if=/dev/zero of="$MEMORY_TEMP_FILE" bs=1M count=$CURRENT_MEMORY_MB &> /dev/null
        # Hold the file open to keep memory allocated
        tail -f /dev/null
    ) &
    MEMORY_STRESS_PID=$!
    
    renice -n $PROCESS_NICE_LEVEL -p $MEMORY_STRESS_PID &> /dev/null || true
    ionice -c 3 -p $MEMORY_STRESS_PID &> /dev/null || true
    
    log_debug "Allocated ${CURRENT_MEMORY_MB}MB in /dev/shm"
}

stop_memory_stress() {
    if [[ -n "$MEMORY_STRESS_PID" ]]; then
        kill -9 $MEMORY_STRESS_PID 2>/dev/null || true
        MEMORY_STRESS_PID=""
    fi
    
    if [[ -n "$MEMORY_TEMP_FILE" ]] && [[ -f "$MEMORY_TEMP_FILE" ]]; then
        rm -f "$MEMORY_TEMP_FILE" 2>/dev/null || true
        MEMORY_TEMP_FILE=""
    fi
    
    log_debug "Released memory allocation"
}

restart_memory_stress() {
    stop_memory_stress
    start_memory_stress
}

# ============================================================================
# NETWORK STRESS CONTROL
# ============================================================================

adjust_network_stress() {
    local current_kbs=$1
    local target_mb=$((TOTAL_MEMORY_MB * TARGET_NETWORK_PERCENT / 100))
    local target_kbs=$((target_mb * 10))  # Rough estimate
    
    # Cap target at configured limit
    if [[ $target_kbs -gt $NETWORK_BANDWIDTH_LIMIT_KBS ]]; then
        target_kbs=$NETWORK_BANDWIDTH_LIMIT_KBS
    fi
    
    local diff=$((current_kbs - target_kbs))
    local tolerance=$((target_kbs * NETWORK_TOLERANCE / 100))
    
    log_debug "Network: current=${current_kbs}KB/s, target=${target_kbs}KB/s, diff=${diff}KB/s"
    
    if [[ $diff -ge -$tolerance && $diff -le $tolerance ]]; then
        log_debug "Network within tolerance, no adjustment"
        return
    fi
    
    if [[ $diff -lt -$tolerance ]]; then
        CURRENT_NETWORK_KBS=$((CURRENT_NETWORK_KBS + NETWORK_ADJUSTMENT_KBS))
        
        if [[ $CURRENT_NETWORK_KBS -gt $NETWORK_BANDWIDTH_LIMIT_KBS ]]; then
            CURRENT_NETWORK_KBS=$NETWORK_BANDWIDTH_LIMIT_KBS
        fi
        
        log_info "Network below target (${current_kbs} < ${target_kbs}KB/s), increasing to ${CURRENT_NETWORK_KBS}KB/s"
        restart_network_stress
        NETWORK_ADJUSTMENTS=$((NETWORK_ADJUSTMENTS + 1))
        
    elif [[ $diff -gt $tolerance ]]; then
        CURRENT_NETWORK_KBS=$((CURRENT_NETWORK_KBS - NETWORK_ADJUSTMENT_KBS))
        
        if [[ $CURRENT_NETWORK_KBS -lt 0 ]]; then
            CURRENT_NETWORK_KBS=0
        fi
        
        log_info "Network above target (${current_kbs} > ${target_kbs}KB/s), decreasing to ${CURRENT_NETWORK_KBS}KB/s"
        
        if [[ $CURRENT_NETWORK_KBS -eq 0 ]]; then
            stop_network_stress
        else
            restart_network_stress
        fi
        NETWORK_ADJUSTMENTS=$((NETWORK_ADJUSTMENTS + 1))
    fi
}

start_network_stress() {
    if [[ $CURRENT_NETWORK_KBS -le 0 ]]; then
        return
    fi
    
    # Calculate packets per second needed (assuming 1KB packets)
    local pps=$CURRENT_NETWORK_KBS
    local interval_ms=$((1000 / pps))
    
    # Ensure minimum interval
    if [[ $interval_ms -lt 1 ]]; then
        interval_ms=1
    fi
    
    # Start ping floods to multiple targets (distributed load)
    local target_array=($NETWORK_TARGETS)
    for target in "${target_array[@]}"; do
        (
            while true; do
                ping -c 1 -s 1024 -W 1 "$target" &> /dev/null || true
                sleep 0.$(printf "%03d" $interval_ms) 2>/dev/null || sleep 0.001
            done
        ) &
        NETWORK_STRESS_PIDS+=($!)
    done
    
    # Set lowest priority
    for pid in "${NETWORK_STRESS_PIDS[@]}"; do
        renice -n $PROCESS_NICE_LEVEL -p $pid &> /dev/null || true
        ionice -c 3 -p $pid &> /dev/null || true
    done
    
    log_debug "Started ${#target_array[@]} network workers targeting ${CURRENT_NETWORK_KBS}KB/s"
}

stop_network_stress() {
    if [[ ${#NETWORK_STRESS_PIDS[@]} -gt 0 ]]; then
        for pid in "${NETWORK_STRESS_PIDS[@]}"; do
            kill -9 $pid 2>/dev/null || true
        done
        NETWORK_STRESS_PIDS=()
        log_debug "Stopped all network workers"
    fi
}

restart_network_stress() {
    stop_network_stress
    start_network_stress
}

# ============================================================================
# SELF-HEALING / WATCHDOG
# ============================================================================

check_and_heal() {
    # Check if stress processes are still running and restart if needed
    
    # Check CPU workers
    if [[ $CURRENT_CPU_LOAD -gt 0 ]]; then
        local alive=0
        for pid in "${CPU_WORKER_PIDS[@]}"; do
            if kill -0 $pid 2>/dev/null; then
                alive=$((alive + 1))
            fi
        done
        
        if [[ $alive -eq 0 ]]; then
            log_warn "All CPU workers died, restarting..."
            restart_cpu_stress
        fi
    fi
    
    # Check memory stress
    if [[ $CURRENT_MEMORY_MB -gt 0 ]] && [[ -n "$MEMORY_STRESS_PID" ]]; then
        if ! kill -0 $MEMORY_STRESS_PID 2>/dev/null; then
            log_warn "Memory stress process died, restarting..."
            restart_memory_stress
        fi
    fi
    
    # Check network workers
    if [[ $CURRENT_NETWORK_KBS -gt 0 ]]; then
        local alive=0
        for pid in "${NETWORK_STRESS_PIDS[@]}"; do
            if kill -0 $pid 2>/dev/null; then
                alive=$((alive + 1))
            fi
        done
        
        if [[ $alive -eq 0 ]]; then
            log_warn "All network workers died, restarting..."
            restart_network_stress
        fi
    fi
}

# ============================================================================
# STATISTICS AND MONITORING
# ============================================================================

log_statistics() {
    local now
    now=$(date +%s)
    
    if [[ $((now - STATS_LAST_LOG)) -ge $STATS_INTERVAL ]]; then
        local cpu
        local mem
        cpu=$(get_cpu_usage)
        mem=$(get_memory_usage_percent)
        
        log_info "--- Status Report ---"
        if [[ "$ENABLE_NETWORK" == "true" ]]; then
            local net
            net=$(get_network_usage_kbs)
            log_info "Current: CPU=${cpu}% (target=${TARGET_CPU_PERCENT}%), Memory=${mem}% (target=${TARGET_MEMORY_PERCENT}%), Network=${net}KB/s"
            log_info "Active stress: CPU=${CURRENT_CPU_LOAD}%, Memory=${CURRENT_MEMORY_MB}MB, Network=${CURRENT_NETWORK_KBS}KB/s"
            log_info "Total adjustments: ${TOTAL_ADJUSTMENTS} (CPU=${CPU_ADJUSTMENTS}, Mem=${MEMORY_ADJUSTMENTS}, Net=${NETWORK_ADJUSTMENTS})"
        else
            log_info "Current: CPU=${cpu}% (target=${TARGET_CPU_PERCENT}%), Memory=${mem}% (target=${TARGET_MEMORY_PERCENT}%)"
            log_info "Active stress: CPU=${CURRENT_CPU_LOAD}%, Memory=${CURRENT_MEMORY_MB}MB"
            log_info "Total adjustments: ${TOTAL_ADJUSTMENTS} (CPU=${CPU_ADJUSTMENTS}, Mem=${MEMORY_ADJUSTMENTS})"
        fi
        log_info "--------------------"
        
        STATS_LAST_LOG=$now
    fi
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    log_info "Shutting down gracefully..."
    stop_cpu_stress
    stop_memory_stress
    stop_network_stress
    log_info "Cleanup complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ============================================================================
# MAIN CONTROL LOOP
# ============================================================================

main() {
    detect_system
    
    # Initialize stress levels to match targets
    CURRENT_CPU_LOAD=$TARGET_CPU_PERCENT
    CURRENT_MEMORY_MB=$((TOTAL_MEMORY_MB * TARGET_MEMORY_PERCENT / 100))
    
    if [[ "$ENABLE_NETWORK" == "true" ]]; then
        local target_net_mb=$((TOTAL_MEMORY_MB * TARGET_NETWORK_PERCENT / 100))
        CURRENT_NETWORK_KBS=$((target_net_mb * 10))
        if [[ $CURRENT_NETWORK_KBS -gt $NETWORK_BANDWIDTH_LIMIT_KBS ]]; then
            CURRENT_NETWORK_KBS=$NETWORK_BANDWIDTH_LIMIT_KBS
        fi
    fi
    
    log_info "Starting initial stress processes..."
    start_cpu_stress
    start_memory_stress
    if [[ "$ENABLE_NETWORK" == "true" ]]; then
        start_network_stress
    fi
    
    log_info "Entering continuous monitoring mode (${CONTROL_INTERVAL}s interval)"
    log_info "This will run 24/7 until stopped. Press Ctrl+C to exit."
    
    STATS_LAST_LOG=$(date +%s)
    
    while true; do
        # Measure current metrics (get_cpu_usage always takes ~1s)
        local cpu
        local mem
        cpu=$(get_cpu_usage)
        mem=$(get_memory_usage_percent)
        
        # Adjust stress based on measurements
        adjust_cpu_stress $cpu
        adjust_memory_stress $mem
        
        if [[ "$ENABLE_NETWORK" == "true" ]]; then
            local net
            net=$(get_network_usage_kbs)  # takes ~1s
            adjust_network_stress $net
        fi
        
        # Self-healing check
        check_and_heal
        
        # Log statistics periodically
        log_statistics
        
        # Wait for the remainder of the control interval
        # get_cpu_usage ~1s; get_network_usage_kbs adds another ~1s when enabled
        local measurement_secs=1
        [[ "$ENABLE_NETWORK" == "true" ]] && measurement_secs=2
        local remaining=$((CONTROL_INTERVAL - measurement_secs))
        if [[ $remaining -gt 0 ]]; then
            sleep $remaining
        fi
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (required for stress operations)"
    echo "Please run: sudo $0"
    exit 1
fi

# Load config if exists
if [[ -f /etc/default/oracle-fixed-mode ]]; then
    # shellcheck source=/dev/null
    source /etc/default/oracle-fixed-mode
    log_info "Loaded configuration from /etc/default/oracle-fixed-mode"
fi

# Warn if the config file sets TARGET_NETWORK_PERCENT but ENABLE_NETWORK is not true
# (catches users upgrading from an older config that had network targets configured)
if [[ "$ENABLE_NETWORK" != "true" ]] && \
   [[ -f /etc/default/oracle-fixed-mode ]] && \
   grep -q "^TARGET_NETWORK_PERCENT=" /etc/default/oracle-fixed-mode 2>/dev/null; then
    log_warn "TARGET_NETWORK_PERCENT is set in config but ENABLE_NETWORK is not 'true' — network stress is disabled"
    log_warn "Add ENABLE_NETWORK=true to /etc/default/oracle-fixed-mode to activate network stress"
fi

# Internal control parameters — set after config load so they cannot be overridden
CPU_ADJUSTMENT_STEP=5
MEMORY_ADJUSTMENT_MB=100
NETWORK_ADJUSTMENT_KBS=50
CPU_TOLERANCE=2
MEMORY_TOLERANCE=2
NETWORK_TOLERANCE=3
NETWORK_BANDWIDTH_LIMIT_KBS=500
NETWORK_TARGETS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"

main
