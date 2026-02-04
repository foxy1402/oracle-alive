# Quick Comparison: Which Mode Should I Use?

## TL;DR

- **1 CPU core?** → Use Fixed-Mode
- **2+ CPU cores?** → Use Intelligent Mode (default)
- **Need exact control?** → Use Fixed-Mode
- **Want set-and-forget?** → Use Intelligent Mode

---

## Side-by-Side Comparison

| Feature | Intelligent Mode | Fixed-Mode |
|---------|------------------|------------|
| **Installation** | `sudo bash install.sh` | `sudo bash install-fixed.sh` |
| **Target Setting** | Auto (targets 40% all) | Manual (you choose) |
| **CPU Behavior (1 CPU)** | May hit 100% | Capped at 95% ✅ |
| **CPU Behavior (2+ CPUs)** | Efficient 40-45% | Works but less optimal |
| **Dashboard Lines** | Minor fluctuations | Perfectly stable ✅ |
| **Sleep Cycles** | Yes (96s cycles) | No (continuous) ✅ |
| **Responsiveness** | Adjusts every 5 min | Adjusts every 3 sec ✅ |
| **Overhead** | Very low | Low (slightly higher) |
| **Configuration Complexity** | Simple (one setting) | More options (per-metric) |
| **Self-Healing** | Yes | Yes ✅ |
| **Gaming/VPN Impact** | Minimal | Minimal |
| **Oracle Reclaim Prevention** | ✅ Guaranteed | ✅ Guaranteed |

---

## When to Choose Intelligent Mode

✅ **You have 2 or more CPU cores**
- Efficiently uses all cores without hitting limits
- Better performance on multi-core systems

✅ **You want zero maintenance**
- Install once, forget about it
- Auto-adjusts to system changes

✅ **You don't care about minor fluctuations**
- Metrics vary between 35-50%
- Still way above Oracle's 20% minimum

✅ **You trust automatic optimization**
- Script measures baseline and adjusts
- Recalibrates every 20 minutes

### Installation
```bash
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install.sh
```

### Configuration
```bash
# Optional: Edit targets (default 40% is great)
sudo nano /etc/default/oracle-keep-alive
sudo systemctl restart oracle-keep-alive
```

---

## When to Choose Fixed-Mode

✅ **You have a single CPU core**
- Prevents hitting 100% and locking up your instance
- Intelligent proportional control

✅ **You need exact percentages**
- Set CPU to exactly 25%, RAM to 30%, Network to 30%
- Perfect control over resource usage

✅ **You want perfectly stable metrics**
- Oracle Console shows flat horizontal lines
- No ups and downs, just steady state

✅ **You're running critical apps**
- Predictable resource usage
- No surprise spikes (even small ones)

✅ **You enjoy fine-tuning**
- Many knobs to adjust
- Tolerance, step sizes, intervals

### Installation
```bash
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install-fixed.sh
```

### Configuration
```bash
# Set your exact targets
sudo nano /etc/default/oracle-fixed-mode

# Change these lines:
TARGET_CPU_PERCENT=25      # Your desired CPU %
TARGET_MEMORY_PERCENT=30   # Your desired RAM %
TARGET_NETWORK_PERCENT=30  # Your desired Network %

# Save and restart
sudo systemctl restart oracle-fixed-mode
```

---

## Real-World Examples

### Example 1: Free-Tier ARM Instance (4 cores, 24GB RAM)
**Recommendation:** Intelligent Mode
- Plenty of resources, no risk of hitting limits
- Set-and-forget operation
- Auto-adjusts if you add apps later

### Example 2: Free-Tier x86 Instance (1 core, 1GB RAM)
**Recommendation:** Fixed-Mode with conservative targets
- Single core needs careful control
- Set CPU to 25%, RAM to 30% to avoid lockup
- Stable performance for lightweight apps

### Example 3: Gaming VPN Server (2 cores, 12GB RAM)
**Recommendation:** Intelligent Mode
- Efficient multi-core usage
- Gaming-optimized settings built-in
- Minimal latency impact

### Example 4: Development Server (1 core, 2GB RAM, running databases)
**Recommendation:** Fixed-Mode with low targets
- CPU to 20%, RAM to 25% (leave room for dev work)
- Predictable overhead
- Won't interfere with compile jobs

---

## Migration Between Modes

### From Intelligent → Fixed-Mode
```bash
# 1. Stop current service
sudo systemctl stop oracle-keep-alive
sudo systemctl disable oracle-keep-alive

# 2. Install fixed-mode
sudo bash install-fixed.sh

# 3. Set your targets
sudo nano /etc/default/oracle-fixed-mode

# 4. Done! Fixed-mode is now running
```

### From Fixed-Mode → Intelligent
```bash
# 1. Stop current service
sudo systemctl stop oracle-fixed-mode
sudo systemctl disable oracle-fixed-mode

# 2. Install intelligent mode
sudo bash install.sh

# 3. Done! Intelligent mode is now running
```

---

## Still Not Sure?

### Try This Decision Tree

1. **How many CPU cores do you have?**
   - 1 core → **Fixed-Mode**
   - 2+ cores → Go to #2

2. **Do you run resource-intensive apps?**
   - Yes (databases, compiling, etc.) → **Fixed-Mode** (set low targets)
   - No → Go to #3

3. **Do you want to customize targets?**
   - Yes, I want exact control → **Fixed-Mode**
   - No, defaults are fine → **Intelligent Mode**

### Still can't decide? Use Intelligent Mode
It works for 90% of users and you can always switch later.

---

## Performance Impact

### Intelligent Mode
- **CPU:** ~1-2% overhead (recalculation every 5 min)
- **Memory:** ~100MB working set
- **Network:** Minimal (burst patterns)
- **Best for:** General use

### Fixed-Mode
- **CPU:** ~2-3% overhead (continuous 3s monitoring)
- **Memory:** ~50MB working set
- **Network:** Minimal (continuous low traffic)
- **Best for:** Precision control

Both are designed to run at **nice level 19** (lowest priority) so your apps always get resources first.

---

## FAQ

### Q: Can I run both scripts at the same time?
**A:** No! Choose one. Running both will cause conflicts and waste resources.

### Q: Which mode is more reliable?
**A:** Both are equally reliable. Both prevent Oracle reclaim. Choose based on your CPU count and preference.

### Q: Which uses less resources?
**A:** Intelligent Mode has slightly lower overhead (~1-2% vs 2-3% CPU).

### Q: Can I change modes later?
**A:** Yes! See [Migration Between Modes](#migration-between-modes) above.

### Q: Does Oracle care which mode I use?
**A:** No. Oracle only checks if metrics are above 20%. Both modes guarantee that.

---

## Support

- **Intelligent Mode Issues:** Open issue with `[Intelligent]` tag
- **Fixed-Mode Issues:** Open issue with `[Fixed]` tag
- **General Questions:** Check main [README.md](README.md) or [README-FIXED.md](README-FIXED.md)

---

**Ready to install?**
- [Intelligent Mode Installation →](README.md#installation)
- [Fixed-Mode Installation →](README-FIXED.md#-quick-start)
