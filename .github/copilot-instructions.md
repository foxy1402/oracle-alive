# Oracle Cloud Keep-Alive

## Project Overview

A bash-based systemd service that prevents Oracle Cloud free-tier instances from being reclaimed due to inactivity. The script intelligently monitors CPU, memory, and network utilization, then applies targeted stress to maintain all three metrics above Oracle's 20% minimum threshold.

**Target:** 40% utilization on all metrics (double Oracle's minimum) with a 5% safety margin.

**Supported OS:** Oracle Linux 8, Ubuntu 20.04/22.04, Ubuntu Minimal (x86_64 and aarch64/ARM)

## Architecture

### Core Components

1. **keep-alive.sh** - Main script (~700 lines)
   - Baseline measurement: Observes system load for 60s to understand normal usage
   - Gap calculation: Determines additional stress needed to reach 45% (40% target + 5% margin) on each metric
   - Intelligent stress application: Only adds what's needed, not wasteful fixed amounts
   - Dynamic sleep scheduling: Adjusts cycle timing based on stress requirements
   - Continuous monitoring: Re-measures and adjusts every 5 minutes

2. **install.sh** - Installation script
   - System compatibility checks
   - Installs to `/opt/oracle-keep-alive/`
   - Creates systemd service
   - Generates default config at `/etc/default/oracle-keep-alive`
   - Sets up logrotate

3. **config.env** - Configuration template
   - Defines target percentages for CPU, memory, network
   - Controls stress parameters (duration, intensity, bandwidth limits)
   - Gaming VPN optimized defaults (low-priority traffic shaping)

4. **oracle-keep-alive.service** - systemd unit
   - Runs as root (required for memory stress and traffic control)
   - Nice level 19 (lowest CPU priority)
   - IO scheduling class: idle
   - Memory limits as safety guards

### How the Intelligent System Works

**Traditional approach** (v1.x): Apply fixed stress (e.g., 95% CPU for 45s, sleep 8m) regardless of actual need.

**Intelligent approach** (v2.1): 
1. Measure baseline (what system + apps already use)
2. Calculate gap (how much more needed to reach 45% on each metric)
3. Apply only the required additional stress
4. Dynamically adjust sleep duration (more stress needed = shorter sleep)
5. Re-measure every 5 minutes and recalculate

**Example:**
- Baseline: CPU 5%, Memory 10%, Network 150 KB/s
- Targets: CPU 45%, Memory 45%, Network ~5,625 KB/s
- Applied stress: CPU +40%, Memory +35% (~8.4GB), Network +500 KB/s (capped)
- Sleep: Dynamically calculated based on stress level (~150-300s)

## Build, Test, and Deploy

### Installation

**Ubuntu/Ubuntu Minimal:**
```bash
sudo apt update && sudo apt install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install.sh
```

**Oracle Linux:**
```bash
sudo yum install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install.sh
```

The installer automatically:
- Detects OS (Ubuntu, Oracle Linux, etc.)
- Installs missing dependencies (curl, iproute2/iproute, procps, etc.)
- Sets up systemd service
- Starts the service

### Configuration

Edit `/etc/default/oracle-keep-alive` then restart:

```bash
sudo systemctl restart oracle-keep-alive
```

### Service Management

```bash
# Check status
sudo systemctl status oracle-keep-alive

# View logs (live)
sudo tail -f /var/log/oracle-keep-alive.log

# Stop/start/restart
sudo systemctl stop oracle-keep-alive
sudo systemctl start oracle-keep-alive
sudo systemctl restart oracle-keep-alive
```

### Uninstall

```bash
sudo bash install.sh --uninstall
```

### Monitoring

**Local logs:**
```bash
# Recent logs
sudo tail -100 /var/log/oracle-keep-alive.log

# Full systemd journal
sudo journalctl -u oracle-keep-alive -n 100
```

**Oracle Cloud Console:**
- Compute → Instances → [Your Instance] → Metrics
- Check after 1 hour for initial results
- All three metrics (CPU, Memory, Network) should show sustained activity above 40%

## Key Conventions

### Configuration Variables

- **All variables use UPPERCASE_SNAKE_CASE** with descriptive prefixes:
  - `TARGET_*` - Target utilization percentages
  - `STRESS_*` - Stress operation parameters
  - `NETWORK_*` - Network-specific settings
  - `LOG_*` - Logging configuration
  - `BASELINE_*` - Baseline measurement variables (script internals)
  - `REQUIRED_*` - Calculated stress requirements (script internals)

### Logging

The script uses a custom logging system with 4 levels:
- `log_debug()` - Verbose diagnostic information
- `log_info()` - Normal operation (default)
- `log_warn()` - Warnings about metrics below target
- `log_error()` - Critical failures

Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`

Set `LOG_LEVEL` in config to control verbosity.

### Metric Measurement

**CRITICAL: Oracle only monitors USER workload, not system processes**

**CPU:** Measured using delta between two `/proc/stat` readings (1 second apart)
- **Only counts:** `user + nice` time (user-space applications)
- **Excludes:** `system + irq + softirq` (kernel/system time that Oracle ignores)
- Formula: `(user_delta + nice_delta) * 100 / total_delta`

**Memory:** Using `free` command with available column
- **Only counts:** Actual application memory (`total - available`)
- **Excludes:** Kernel buffers, disk cache (Oracle ignores these)
- Fallback for older systems without "available" column

**Network:** Measured via `/sys/class/net/${PRIMARY_INTERFACE}/statistics/` as KB/s over 1-second intervals
- Total interface traffic (all applications)
- Interface detected with portable `awk` parsing (not `grep -oP` which fails on Oracle Linux 8)

**Important:** All metric functions must use delta measurements, never cumulative values since boot.

### Stress Functions

Each stress function follows the pattern:
1. Check if stress is needed (`REQUIRED_*_STRESS` > 0)
2. Log what will be done
3. Apply stress (CPU: parallel workers, Memory: /dev/shm allocation, Network: distributed pings/downloads)
4. Track total time in global counters
5. Log completion

All stress processes run at nice level 19 and lowest IO priority.

### Gaming VPN Optimization

The script is designed to coexist with gaming VPN traffic:
- **Traffic shaping:** Keep-alive network traffic tagged at priority 7 (lowest)
- **CPU priority:** Nice level 19 ensures user apps get CPU first
- **Bandwidth limits:** `NETWORK_BANDWIDTH_LIMIT_KBS` caps maximum bandwidth used
- **Smart mode:** Distributed targets (multiple DNS servers) to avoid single-server saturation

## File Structure

```
oracle-alive/
├── .github/
│   └── copilot-instructions.md    # This file
├── keep-alive.sh                   # Main script (intelligent multi-metric)
├── install.sh                      # Installer with dependency checks
├── config.env                      # Configuration template
├── oracle-keep-alive.service       # systemd unit file
├── oracle-keep-alive.logrotate     # Log rotation config
├── README.md                       # User-facing documentation
├── QUICKSTART.md                   # Gaming VPN quick start guide
└── LICENSE

Installed locations:
├── /opt/oracle-keep-alive/
│   └── keep-alive.sh
├── /etc/systemd/system/oracle-keep-alive.service
├── /etc/default/oracle-keep-alive
├── /etc/logrotate.d/oracle-keep-alive
└── /var/log/oracle-keep-alive.log
```

## Common Tasks

### Adding a New Stress Type

1. Add configuration variables in `config.env` with prefix (e.g., `DISK_*`)
2. Create measurement function `get_disk_usage()` in keep-alive.sh
3. Add baseline calculation in `measure_baseline()`
4. Add gap calculation in `calculate_required_stress()`
5. Implement stress function `stress_disk_intelligent()`
6. Call from main loop
7. Update monitoring in `monitor_and_adjust()`

### Changing Target Percentages

Edit `/etc/default/oracle-keep-alive`:
```bash
TARGET_CPU_PERCENT=50      # Increase to 50%
TARGET_MEMORY_PERCENT=50
TARGET_NETWORK_PERCENT=50
SAFETY_MARGIN=10           # Increase safety margin to 10%
```

Total target becomes 60% (50% + 10%).

### Debugging Low Metrics

1. Set `LOG_LEVEL=DEBUG` in config
2. Check baseline measurements in logs - are they accurate?
3. Check required stress calculations - are they reasonable?
4. Verify stress functions are actually running (check timestamps)
5. Increase `STRESS_DURATION` or decrease `MAX_SLEEP_DURATION`

### Reducing Gaming Impact

```bash
# In /etc/default/oracle-keep-alive:
NETWORK_BANDWIDTH_LIMIT_KBS=200    # Reduce from 500
NETWORK_TRAFFIC_PRIORITY=7          # Ensure lowest priority
NETWORK_STRESS_MODE="smart"         # Use smart mode

# Ensure iproute2 is installed for traffic shaping:
sudo apt install iproute2           # Ubuntu/Debian
sudo yum install iproute            # Oracle Linux
```

## Version History

- **v2.1** (Current) - Intelligent multi-metric with baseline detection and gap calculation
- **v2.0** - Gaming VPN optimized with traffic shaping
- **v1.x** - Basic fixed-interval stress testing

## Oracle's Reclaim Policy

Instances are reclaimed after 7 days if **ALL** of these are below 20%:
- CPU utilization (95th percentile) - **USER + NICE time only** (not system/kernel time)
- Network utilization
- Memory utilization (ARM instances only) - **Application memory only** (not buffers/cache)

**CRITICAL:** Oracle monitors USER workload only, NOT system processes. The script's measurement functions exactly match Oracle's monitoring methodology:
- CPU: Only `user + nice` time from `/proc/stat`
- Memory: Only application memory (`total - available`), excludes buffers/cache
- Network: All interface traffic

**This script targets 40% on all three metrics to provide double the safety margin.**
