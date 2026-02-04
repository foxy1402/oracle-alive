# Fixed-Mode Keep-Alive for Oracle Cloud

## 🎯 Perfect for Single-CPU Instances

The **Fixed-Mode** script is designed for instances with limited resources (especially single-CPU systems) where you need **precise control** over utilization to prevent Oracle from reclaiming your instance due to inactivity.

### Why Fixed-Mode?

- ✅ **Manual target setting** - You set exact percentages (e.g., CPU 25%, RAM 30%, Network 30%)
- ✅ **No overshoot** - Intelligent control prevents hitting 100% on single-CPU systems
- ✅ **Stable dashboard lines** - No fluctuations, creates perfect horizontal lines in Oracle Console
- ✅ **No sleep cycles** - Runs 24/7 with continuous 3-second monitoring loops
- ✅ **Self-healing** - Automatically restarts any stress processes that die
- ✅ **Oracle-safe** - Guaranteed to keep you above the 20% minimum threshold

### vs. Regular Keep-Alive Script

| Feature | Fixed-Mode | Regular Keep-Alive |
|---------|-----------|-------------------|
| Target Setting | Manual (you choose) | Intelligent (auto-adjusts) |
| CPU Control | Capped at 95% | May hit 100% on 1-CPU |
| Sleep Cycles | None (continuous) | Yes (cycles every ~90s) |
| Dashboard Lines | Perfectly stable | Some fluctuation |
| Best For | Single-CPU, precise needs | Multi-core, set-and-forget |

> **Not sure which mode is right for you?** [See detailed comparison →](COMPARISON.md)

---

## 🚀 Quick Start

### Installation (Ubuntu/Oracle Linux)

```bash
# 1. Clone repository
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive

# 2. Install Fixed-Mode
sudo bash install-fixed.sh

# 3. (Optional) Customize targets
sudo nano /etc/default/oracle-fixed-mode

# 4. Restart to apply changes
sudo systemctl restart oracle-fixed-mode
```

### Set Your Targets

Edit `/etc/default/oracle-fixed-mode`:

```bash
# Set your desired utilization (percentage)
TARGET_CPU_PERCENT=25      # 25% CPU usage
TARGET_MEMORY_PERCENT=30   # 30% RAM usage
TARGET_NETWORK_PERCENT=30  # 30% Network usage
```

**Recommended targets for Oracle's 20% minimum:**
- **Conservative:** CPU 25%, Memory 30%, Network 30% (25-50% above minimum)
- **Moderate:** CPU 30%, Memory 35%, Network 35% (50-75% above minimum)
- **Aggressive:** CPU 35%, Memory 40%, Network 40% (75-100% above minimum)

---

## 📊 How It Works

### Continuous Monitoring Loop

```
Every 3 seconds:
1. Measure current CPU, Memory, Network usage
2. Compare to your targets
3. Adjust stress up or down (±5% CPU, ±100MB RAM, ±50KB/s Network)
4. Self-heal: check if stress processes are alive
5. Repeat
```

### Intelligent Control System

- **Proportional adjustment:** Small changes prevent wild swings
- **Tolerance zones:** ±2-3% to avoid constant micro-adjustments
- **Safety caps:** CPU max 95%, Memory max 90% to prevent system lockup
- **Priority:** All stress runs at nice level 19 (lowest priority)

### Example Timeline (Target: 25% CPU)

```
00:00 - Start: CPU at 10% → Increase stress to 20%
00:03 - Check: CPU at 15% → Increase stress to 25%
00:06 - Check: CPU at 23% → Within tolerance, no change
00:09 - Check: CPU at 26% → Within tolerance, no change
00:12 - Check: CPU at 28% → Decrease stress to 23%
... continues 24/7 ...
```

---

## 📈 Verify in Oracle Console

1. **Navigate to:** Oracle Cloud Console → Compute → Instances → [Your Instance] → Metrics
2. **Wait:** 60 minutes for initial data
3. **Expect:** Three stable horizontal lines at your target percentages

### Perfect Dashboard Example:
```
CPU Usage (%)      ████████████████────────────── 25% (stable line)
Memory Usage (%)   ████████████████████──────── 30% (stable line)
Network (KB/s)     ████████████████████──────── 30% (stable line)
```

---

## 🛠️ Service Management

### Check Status
```bash
sudo systemctl status oracle-fixed-mode
```

### View Live Logs
```bash
sudo tail -f /var/log/oracle-fixed-mode.log
```

### Stop/Start/Restart
```bash
sudo systemctl stop oracle-fixed-mode
sudo systemctl start oracle-fixed-mode
sudo systemctl restart oracle-fixed-mode
```

### Change Targets
```bash
# 1. Edit config
sudo nano /etc/default/oracle-fixed-mode

# 2. Change TARGET_CPU_PERCENT, TARGET_MEMORY_PERCENT, etc.

# 3. Save (Ctrl+O, Enter, Ctrl+X)

# 4. Restart service
sudo systemctl restart oracle-fixed-mode

# 5. Watch logs to confirm
sudo tail -f /var/log/oracle-fixed-mode.log
```

---

## 🔧 Advanced Configuration

### Control Loop Tuning

```bash
# /etc/default/oracle-fixed-mode

# How often to check and adjust (seconds)
CONTROL_INTERVAL=3           # Default: 3s (fast response)
                             # Increase to 5s if you see high overhead

# Adjustment step sizes (how much to change per cycle)
CPU_ADJUSTMENT_STEP=5        # ±5% per cycle
MEMORY_ADJUSTMENT_MB=100     # ±100MB per cycle
NETWORK_ADJUSTMENT_KBS=50    # ±50KB/s per cycle

# Tolerance (prevents thrashing)
CPU_TOLERANCE=2              # ±2% is acceptable
MEMORY_TOLERANCE=2           # ±2% is acceptable
NETWORK_TOLERANCE=3          # ±3% is acceptable
```

### Network Limits

```bash
# Maximum bandwidth to use (safety cap)
NETWORK_BANDWIDTH_LIMIT_KBS=500    # 500 KB/s max

# DNS targets for distributed traffic
NETWORK_TARGETS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"
```

### Logging

```bash
# Log verbosity
LOG_LEVEL=INFO               # DEBUG, INFO, WARN, ERROR

# Status report frequency
STATS_INTERVAL=60            # Log stats every 60 seconds
```

---

## 🐛 Troubleshooting

### CPU Not Reaching Target

**Problem:** CPU stays at 15% but target is 25%

**Solutions:**
1. Check if stress-ng is installed: `sudo apt install stress-ng -y` (Ubuntu) or `sudo yum install stress-ng -y` (Oracle Linux)
2. Increase adjustment step: `CPU_ADJUSTMENT_STEP=10`
3. Check logs: `sudo tail -50 /var/log/oracle-fixed-mode.log`

### CPU Overshooting (Single-CPU)

**Problem:** CPU hits 100% when target is 25%

**Solutions:**
1. Script automatically caps at 95% - check if it's working: `grep "CPU_LOAD" /etc/default/oracle-fixed-mode`
2. Reduce adjustment step: `CPU_ADJUSTMENT_STEP=3`
3. Increase tolerance: `CPU_TOLERANCE=5`

### Memory Not Holding

**Problem:** Memory drops below target

**Solutions:**
1. Check /dev/shm has space: `df -h /dev/shm`
2. Increase adjustment: `MEMORY_ADJUSTMENT_MB=200`
3. Check for OOM killer: `dmesg | grep -i oom`

### Service Keeps Restarting

**Problem:** `systemctl status` shows frequent restarts

**Solutions:**
1. Check for errors: `sudo journalctl -u oracle-fixed-mode -n 100`
2. Verify dependencies: `bash install-fixed.sh` (re-run installer)
3. Check resource limits: `systemctl show oracle-fixed-mode | grep -i limit`

---

## 🔐 Security Notes

- **Runs as root:** Required for memory allocation and network operations
- **Low priority:** All stress runs at nice 19 (won't interfere with user apps)
- **Resource limits:** systemd limits prevent runaway processes
- **Read-only system:** ProtectSystem=strict in service file

---

## 🗑️ Uninstall

```bash
cd oracle-alive
sudo bash install-fixed.sh --uninstall

# Optional: Remove logs
sudo rm /var/log/oracle-fixed-mode.log*

# Optional: Remove config
sudo rm /etc/default/oracle-fixed-mode
```

---

## 📝 FAQ

### Q: Can I run both scripts (fixed-mode and regular)?
**A:** No. Choose one. Stop the other: `sudo systemctl stop oracle-keep-alive`

### Q: How often does Oracle check my metrics?
**A:** Oracle samples every 60 seconds and calculates rolling averages over 7 days.

### Q: What if I need different targets per metric?
**A:** Yes! Set different values for `TARGET_CPU_PERCENT`, `TARGET_MEMORY_PERCENT`, `TARGET_NETWORK_PERCENT`.

### Q: Will this work on ARM instances?
**A:** Yes! Tested on both x86_64 and aarch64 (ARM).

### Q: Does this impact my VPN/gaming?
**A:** Minimal. All stress runs at lowest priority (nice 19). Your apps get CPU first.

### Q: Can I set targets below 20%?
**A:** Technically yes, but NOT recommended. Oracle reclaims if < 20%. Stay at 25% minimum for safety.

---

## 📚 Related Files

- **Script:** `/opt/oracle-keep-alive/fixedmode.sh`
- **Service:** `/etc/systemd/system/oracle-fixed-mode.service`
- **Config:** `/etc/default/oracle-fixed-mode`
- **Logs:** `/var/log/oracle-fixed-mode.log`

---

## 💡 Tips for Success

1. **Start conservative:** Begin with CPU 25%, Memory 30%, Network 30%
2. **Monitor for 24 hours:** Check Oracle Console metrics the next day
3. **Adjust gradually:** Change targets by 5% at a time
4. **Check weekly:** First month, verify metrics weekly in Oracle Console
5. **Set alerts:** (Optional) Use Oracle's built-in metric alerts for < 20%

---

## 🎉 Success Criteria

You've configured it correctly when:
- ✅ Oracle Console shows stable horizontal lines at your targets
- ✅ Metrics stay above targets ±5% consistently
- ✅ Service runs 24/7 without restarts
- ✅ Your applications still perform normally

---

## 📖 Additional Resources

- **Main README:** [README.md](README.md)
- **Regular Keep-Alive:** For multi-core instances with intelligent auto-adjustment
- **GitHub Issues:** Report bugs or request features
- **Oracle Docs:** [Compute Instance Lifecycle](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managinginstances.htm)

---

**Need help?** Open an issue on GitHub or check the main README.md for more troubleshooting tips.
