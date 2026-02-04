# Oracle Cloud Keep-Alive

**Keep your free Oracle Cloud server running forever - prevents automatic deletion due to low usage.**

Works on Oracle Linux and Ubuntu (both x86_64 and ARM instances).

---

## ⚡ What's New in v2.2.1

**PARALLEL STRESS EDITION** - Fully optimized to match Oracle's monitoring methodology:

- 🚀 **Parallel Execution**: CPU, memory, and network stress run simultaneously (not sequentially)
- 📊 **High Duty Cycles**: 67% CPU, 94% memory/network (matches Oracle's 60s sampling)
- 🎯 **Exact Methodology Match**: Measures only what Oracle monitors (USER CPU, app memory, interface traffic)
- 🔄 **Dynamic Recalibration**: Auto-adjusts every 12 cycles (~20 minutes)
- ⏱️ **Predictable Timing**: 96-second cycles (64s CPU + 90s memory/network overlap)
- 🎮 **Gaming-Friendly**: Consistent patterns, no surprise spikes
- 🛡️ **Baseline Protection**: Runs light 30% stress during baseline scans to prevent metric drops
- 🔧 **v2.2.1 Fixes**: Critical bug fixes for memory cleanup, improved reliability

---

## What Does This Do?

Oracle deletes free-tier instances if CPU, memory, and network usage are **all below 20%** for 7 consecutive days.

This script:
- ✅ Monitors your actual usage (**exactly** what Oracle monitors - USER CPU, app memory, network traffic)
- ✅ Runs all three stresses **in parallel** for maximum efficiency
- ✅ Keeps **all 3 metrics above 40%** (double the requirement) with 94% duty cycles
- ✅ Runs automatically 24/7 in the background
- ✅ Won't interfere with your apps (lowest priority, nice level 19)
- ✅ Self-optimizes every 20 minutes based on actual measurements

**Result: Your instance will never be deleted.**

---

## Installation

### Step 1: Download

**Oracle Linux:**
```bash
sudo yum install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
```

**Ubuntu:**
```bash
sudo apt update && sudo apt install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
```

### Step 2: Install

```bash
sudo bash install.sh
```

That's it! The script is now running.

### Step 3: Verify

```bash
sudo tail -f /var/log/oracle-keep-alive.log
```

You should see:
```
[INFO] System detected: Ubuntu 22.04 (or Oracle Linux 8.x)
[INFO] Target metrics (with 5% safety margin): CPU: 45%, Memory: 45%, Network: 45%
[INFO] Starting parallel stress cycles...
[INFO] CPU: 50% for 64s
[INFO] Memory/Network: Hold for 90s (parallel with CPU)
[INFO] Total cycle: ~96s (90s stress + 6s cleanup)
[INFO] === Cycle #1 ===
[INFO] Memory stress: Allocating XXXmb, holding for 90s (parallel)
[INFO] Network stress: Continuous XXX KB/s for 90s (parallel)
[INFO] CPU Cycle #1: 50% for 64s, sleep 0s (expect 33% avg)
[INFO] ✓ All three metrics meeting targets - instance is SAFE
```

Press `Ctrl+C` to exit.

---

## Supported Systems

| Operating System | x86_64 | ARM (aarch64) |
|------------------|--------|---------------|
| Oracle Linux 8/9 | ✅ | ✅ |
| Ubuntu 20.04 LTS | ✅ | ✅ |
| Ubuntu 22.04 LTS | ✅ | ✅ |
| Ubuntu Minimal   | ✅ | ✅ |

---

## Common Commands

```bash
# Check status
sudo systemctl status oracle-keep-alive

# View logs
sudo tail -f /var/log/oracle-keep-alive.log

# Stop/start
sudo systemctl stop oracle-keep-alive
sudo systemctl start oracle-keep-alive

# Restart (after config changes)
sudo systemctl restart oracle-keep-alive

# Uninstall
sudo bash install.sh --uninstall
```

---

## Configuration (Optional)

Default settings work for 99% of users. To customize:

```bash
sudo nano /etc/default/oracle-keep-alive
```

**Key settings:**
- `TARGET_CPU_PERCENT=40` - Target CPU usage (default: 40%, double Oracle's minimum)
- `TARGET_MEMORY_PERCENT=40` - Target memory usage (default: 40%)
- `TARGET_NETWORK_PERCENT=40` - Target network usage (default: 40%)
- `CPU_STRESS_DURATION=64` - CPU stress duration in seconds (default: 64s)
- `MEMORY_NETWORK_DURATION=90` - Memory/network hold duration (default: 90s)
- `CPU_RECALIBRATION_CYCLES=12` - Recalibrate every N cycles (default: 12 = ~20min)

After changing settings:
```bash
sudo systemctl restart oracle-keep-alive
```

---

## How It Works (v2.2 - Parallel Stress Edition)

### Oracle's Policy

Oracle monitors 3 metrics using **periodic sampling** (approximately every 60 seconds):
1. **CPU** - USER + NICE time only (NOT system/kernel/irq)
2. **Memory** - Application memory only (NOT buffers/cache)  
3. **Network** - Total interface traffic

If **ALL THREE** stay below 20% for 7 days → instance deleted.

### Our Optimized Strategy

**96-Second Parallel Cycle:**

```
t=0s:   START all three simultaneously
        ├─ CPU stress:     64s at 50-68% (user-space only)
        ├─ Memory:         Allocate and HOLD for 90s
        └─ Network:        Continuous traffic for 90s

t=64s:  CPU completes (memory/network continue for 26s)
t=90s:  Memory released, network stopped
t=96s:  Next cycle begins
```

**Why This Works Perfectly:**

1. **Parallel Execution** - All metrics elevated simultaneously
2. **High Duty Cycles** - CPU: 67%, Memory/Network: 94%
3. **Oracle's Samples** - Every 60s sample catches elevated metrics
4. **Exact Matching** - Measures only what Oracle monitors:
   - CPU: USER + NICE (excludes system/kernel)
   - Memory: Application memory (excludes buffers/cache)
   - Network: Total interface traffic
5. **Dynamic Recalibration** - Adjusts CPU intensity every ~20 minutes
6. **Lowest Priority** - Nice level 19, won't slow your apps

**Result: 40%+ average on all metrics = Double Oracle's requirement = Safe forever**

---

## Verification

### Check Logs (Immediate)

```bash
sudo tail -100 /var/log/oracle-keep-alive.log
```

Look for:
- ✅ "Starting parallel stress cycles..."
- ✅ "CPU: 50% for 64s"
- ✅ "Memory/Network: Hold for 90s (parallel with CPU)"
- ✅ CPU Cycle messages with intensity and expected average
- ✅ After cycle 12: "CPU Recalibration" with new intensity
- ✅ "All three metrics meeting targets - instance is SAFE"

### Check Oracle Cloud Console (After 1 Hour)

1. Login to [Oracle Cloud Console](https://cloud.oracle.com)
2. Go to: **Compute** → **Instances** → **Your Instance** → **Metrics**
3. Verify all 3 graphs show activity:
   - **CPU**: ~40-45% average with 96-second cycle pattern
   - **Memory**: ~42% average, held continuously (94% duty cycle)
   - **Network**: Sustained activity throughout (94% duty cycle)

---

## Troubleshooting

### Problem: Metrics still below 40%

**Check logs:**
```bash
sudo tail -100 /var/log/oracle-keep-alive.log
```

**Ensure all stress types enabled:**
```bash
sudo nano /etc/default/oracle-keep-alive
```

Verify these are set to `1`:
```bash
STRESS_CPU=1
STRESS_MEMORY=1
STRESS_NETWORK=1
```

**Restart:**
```bash
sudo systemctl restart oracle-keep-alive
```

### Problem: Service won't start

```bash
# Check for errors
sudo journalctl -u oracle-keep-alive -n 50

# Verify files exist
ls -la /opt/oracle-keep-alive/keep-alive.sh
ls -la /etc/systemd/system/oracle-keep-alive.service

# Reinstall
cd oracle-alive
sudo bash install.sh
```

### Problem: Baseline shows 0% for CPU or Network

This was a bug in older versions. Update to latest:
```bash
cd oracle-alive
git pull
sudo systemctl stop oracle-keep-alive
sudo bash install.sh
sudo systemctl start oracle-keep-alive
```

---

## FAQ

**Q: Will this use my free tier limits?**  
A: No. It only uses CPU/RAM/Network on your existing instance. No additional resources consumed.

**Q: Will it slow down my applications?**  
A: No. Runs at lowest priority (nice level 19). Your apps always get resources first.

**Q: How long until it protects my instance?**  
A: Immediately. Oracle's metrics update within 1 hour.

**Q: Do I need to do anything after installation?**  
A: No. It runs automatically 24/7. Check logs occasionally to confirm it's working.

**Q: What if I already got a warning from Oracle?**  
A: Install immediately. The script will raise your metrics within 1 hour.

**Q: Can I use this with other software (VPN, web server, etc.)?**  
A: Yes. It works alongside anything. Won't interfere.

**Q: Is this against Oracle's terms of service?**  
A: No. The script creates normal system activity. Oracle only prohibits resource mining/abuse.

---

## Uninstall

```bash
cd oracle-alive
sudo bash install.sh --uninstall
```

This removes:
- Service files
- Installation directory
- (Keeps logs and config for reference)

---

## Technical Details

### Parallel Architecture (v2.2)

**Cycle Structure (96 seconds):**
- **t=0-64s**: CPU stress at 50-68% (user-space processes only)
- **t=0-90s**: Memory allocated and held (application memory)
- **t=0-90s**: Network continuous traffic (rate-limited bandwidth)
- **t=90-96s**: Cleanup and prep for next cycle

**Measurements (matches Oracle's methodology exactly):**
- **CPU**: Delta-based measurement of `user + nice` time from `/proc/stat`
  - ✓ Counts: User-space application CPU
  - ✗ Excludes: system, kernel, irq, softirq, steal, iowait
- **Memory**: Actual application memory (total - available) from `free`
  - ✓ Counts: Application-allocated memory
  - ✗ Excludes: Buffers, cache, kernel memory
- **Network**: Interface traffic from `/sys/class/net/` statistics
  - ✓ Counts: Total TX+RX bytes on primary interface

**Stress Methods:**
- **CPU**: Parallel worker processes at nice level 19 (lowest priority)
- **Memory**: Allocation in `/dev/shm`, held for 90s (94% duty cycle)
- **Network**: Continuous distributed pings + HTTP requests + rate-limited downloads

**Intelligent Operation:**
- Runs all three stresses **in parallel** for maximum efficiency
- CPU auto-recalibrates every 12 cycles (~20 minutes)
- Memory/network adjust every 5 minutes based on baseline
- High duty cycles ensure Oracle's 60s samples always catch activity
- Automatically detects network interface
- Portable across Oracle Linux and Ubuntu (pure POSIX bash)

---

## Support

**Check logs first:**
```bash
sudo tail -200 /var/log/oracle-keep-alive.log
```

**Still have issues?** Open a GitHub issue with:
- Your OS version (`cat /etc/os-release`)
- Architecture (`uname -m`)
- Recent logs (last 50 lines)

---

## License

MIT License - Free to use, modify, and share.

## Credits

Created to help the community keep their free Oracle Cloud instances alive.

**If this saved your instance, please ⭐ star this repo!**

---

**Version:** 2.2.1 (Parallel Stress Edition)  
**Compatibility:** Oracle Linux 8/9, Ubuntu 20.04/22.04, Ubuntu Minimal (x86_64 and ARM)
