# Fixed-Mode Quick Start (Single-CPU Instances)

## 🚀 Get Your 1-CPU Instance Protected in 2 Minutes

### Why Fixed-Mode for 1 CPU?

Oracle's free-tier x86 instances have just **1 CPU core**. The regular script may push it to 100%, making your instance unresponsive. Fixed-Mode **caps at 95%** and gives you exact control.

---

## Step 1: Install (60 seconds)

```bash
# Ubuntu
sudo apt update && sudo apt install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install-fixed.sh
```

```bash
# Oracle Linux
sudo yum install git -y
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install-fixed.sh
```

**Done!** Script is running with defaults: CPU 25%, Memory 30% (network stress disabled)

---

## Step 2: Verify (30 seconds)

```bash
# Watch logs to confirm it's working
sudo tail -20 /var/log/oracle-fixed-mode.log
```

You should see:
```
[INFO] Oracle Fixed-Mode Keep-Alive v1.0.0
[INFO] Target Utilization:
[INFO]   • CPU: 25%
[INFO]   • Memory: 30%
[INFO]   • Network: disabled
[INFO] Starting initial stress processes...
[INFO] Entering continuous monitoring mode (3s interval)
[INFO] CPU below target (10% < 25%), increasing load to 20%
[INFO] Memory below target (15% < 30%), increasing to 500MB
```

Press `Ctrl+C` to exit log view.

---

## Step 3: Customize (Optional)

### Want Different Percentages?

```bash
# Edit config
sudo nano /etc/default/oracle-fixed-mode
```

**Change these lines:**
```bash
TARGET_CPU_PERCENT=25      # ← Your desired CPU %
TARGET_MEMORY_PERCENT=30   # ← Your desired RAM %
```

**Save:** `Ctrl+O`, `Enter`, `Ctrl+X`

**Apply changes:**
```bash
sudo systemctl restart oracle-fixed-mode
```

### Recommended Targets for 1-CPU Instances

| Use Case | CPU | RAM | Why |
|----------|-----|-----|-----|
| **Minimal overhead** | 22% | 25% | Just above Oracle's 20% minimum |
| **Safe default** ✅ | 25% | 30% | 25-50% above minimum, good balance |
| **Extra safety** | 30% | 35% | 50-75% above minimum, more headroom |
| **Maximum safety** | 35% | 40% | 75-100% above minimum, overkill but safe |

---

## Step 4: Check Oracle Console (1 hour later)

1. Go to: **Oracle Cloud Console → Compute → Instances → [Your Instance] → Metrics**
2. Wait: **60 minutes** for data to populate
3. Expect: **Two flat horizontal lines** at your target percentages

### Perfect Results:
```
CPU Usage:    ▬▬▬▬▬▬▬▬▬▬▬▬▬ 25% (stable)
Memory Usage: ▬▬▬▬▬▬▬▬▬▬▬▬▬▬ 30% (stable)
```

✅ **Your instance is safe from Oracle's 7-day reclaim policy!**

---

## Common Commands

```bash
# Check if running
sudo systemctl status oracle-fixed-mode

# View live logs
sudo tail -f /var/log/oracle-fixed-mode.log

# Stop service
sudo systemctl stop oracle-fixed-mode

# Start service
sudo systemctl start oracle-fixed-mode

# Restart (after config changes)
sudo systemctl restart oracle-fixed-mode
```

---

## Troubleshooting

### Problem: CPU Not Reaching 25%

**Check logs:**
```bash
sudo tail -50 /var/log/oracle-fixed-mode.log | grep CPU
```

**Solution:**
```bash
# Install stress-ng for better control
sudo apt install stress-ng -y        # Ubuntu
sudo yum install stress-ng -y        # Oracle Linux

# Restart service
sudo systemctl restart oracle-fixed-mode
```

### Problem: Service Won't Start

**Check what failed:**
```bash
sudo journalctl -u oracle-fixed-mode -n 50
```

**Re-run installer:**
```bash
cd oracle-alive
sudo bash install-fixed.sh
```

### Problem: CPU Hitting 100% (Should be capped at 95%)

**Check current load:**
```bash
sudo grep "CURRENT_CPU_LOAD" /var/log/oracle-fixed-mode.log | tail -5
```

**Reduce target if needed:**
```bash
sudo nano /etc/default/oracle-fixed-mode
# Change: TARGET_CPU_PERCENT=20
sudo systemctl restart oracle-fixed-mode
```

---

## What Happens Next?

### First 24 Hours
- Script continuously adjusts stress every 3 seconds
- Metrics stabilize at your targets within 10-15 minutes
- Oracle Console updates every 5 minutes

### First Week
- Check Oracle Console daily to verify stable lines
- Adjust targets if needed (see Step 3)
- Script self-heals if processes die

### After First Week
- **Completely hands-off** - no maintenance needed
- Script runs 24/7/365 automatically
- Check metrics monthly just to be sure

---

## FAQ for Single-CPU Users

### Q: Will this make my instance slow?
**A:** No! All stress runs at **nice level 19** (lowest priority). Your apps get CPU first. The script only uses what's left over.

### Q: What if I'm running a web server?
**A:** Set lower targets: CPU 20%, RAM 25%, Network 25%. This leaves plenty of room for your web traffic.

### Q: Can I enable network stress too?
**A:** Yes. Add `ENABLE_NETWORK=true` and `TARGET_NETWORK_PERCENT=30` to `/etc/default/oracle-fixed-mode`, then restart.

### Q: How do I know it's working?
**A:** Check Oracle Console metrics after 1 hour. You'll see stable horizontal lines at your targets.

### Q: Does this cost money?
**A:** No! CPU and memory stress generate no outbound traffic. If you enable network stress, Oracle gives 10TB/month free outbound.

### Q: What if Oracle changes their policy?
**A:** Script can be adjusted. Just update targets in `/etc/default/oracle-fixed-mode` and restart.

---

## Next Steps

- ✅ **You're done!** Script is protecting your instance 24/7
- 📊 Check Oracle Console in 1 hour to verify metrics
- 🔧 Customize targets if needed (see Step 3)
- 📚 Read full docs: [README.md](README.md)

---

## Support

- **Issues?** Check [README.md Troubleshooting](README.md#-troubleshooting)
- **Questions?** Open a GitHub issue

---

**Your free Oracle instance is now protected! 🎉**

The script will keep all metrics above 20% forever, preventing Oracle from reclaiming your instance.
