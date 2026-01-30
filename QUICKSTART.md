# 🚀 Quick Start Guide - Oracle Cloud Keep-Alive v2.0

**For Gaming VPN Users** - Get up and running in 5 minutes!

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/oracle-alive.git
cd oracle-alive
```

---

## Step 2: (Optional) Edit Configuration

**Do this BEFORE installing if you want custom settings!**

```bash
nano config.env
```

**Recommended Gaming Settings (already default):**
- `STRESS_DURATION=45` - 45 seconds active
- `SLEEP_DURATION=480` - 8 minutes sleep  
- `NETWORK_STRESS_MODE="smart"` - Gaming-optimized
- `NETWORK_BANDWIDTH_LIMIT_KBS=100` - Won't saturate connection

Save and exit: `Ctrl+X`, `Y`, `Enter`

---

## Step 3: Install

```bash
sudo bash install.sh
```

You'll see a success message when complete!

---

## Step 4: Verify It's Working

```bash
# Watch the logs
sudo tail -f /var/log/oracle-keep-alive.log
```

You should see:
```
[INFO] Oracle Cloud Keep-Alive v2.0.0 Started
[INFO] System: 4 CPU cores, 24576MB RAM
[INFO] --- Cycle #1 ---
[INFO] CPU stress: 45s on 4 workers @ 95% target
[INFO] CPU stress completed (45s)
[INFO] Network stress (smart mode): bandwidth limit 100KB/s
[INFO] Sleeping for 480s... (next cycle in 8m)
```

Press `Ctrl+C` to stop watching logs.

---

## Step 5: Test Gaming Performance

### Before Keep-Alive (Baseline)
```bash
# Stop the service
sudo systemctl stop oracle-keep-alive

# Test your game, note the ping
# Example: For Valorant, check in-game ping
```

### After Keep-Alive
```bash
# Start the service
sudo systemctl start oracle-keep-alive

# Test the same game
# Compare ping - should be within 1-2ms
```

**If you notice lag:** Switch to minimal mode:
```bash
sudo nano /etc/default/oracle-keep-alive
# Change: NETWORK_STRESS_MODE="minimal"
sudo systemctl restart oracle-keep-alive
```

---

## Step 6: Monitor Oracle Cloud Metrics

1. Go to [Oracle Cloud Console](https://cloud.oracle.com)
2. **Compute** → **Instances** → **Your Instance**
3. Click **Metrics**
4. Check after 1 hour, then daily for first week

**Goal:** At least ONE metric above 15% average:
- ✅ CPU: Should show ~8-10% average, spikes to 95%
- ✅ Memory: Periodic spikes
- ✅ Network: Continuous activity

---

## Common Commands

```bash
# View status
sudo systemctl status oracle-keep-alive

# View logs
sudo tail -f /var/log/oracle-keep-alive.log

# Restart service
sudo systemctl restart oracle-keep-alive

# Edit configuration
sudo nano /etc/default/oracle-keep-alive
# (Remember to restart after editing!)

# Uninstall
sudo bash install.sh --uninstall
```

---

## Troubleshooting

### ❌ Metrics still below 15%?

**Option 1:** Reduce sleep time
```bash
sudo nano /etc/default/oracle-keep-alive
# Change: SLEEP_DURATION=300  # was 480
sudo systemctl restart oracle-keep-alive
```

**Option 2:** Wait for auto-adjustment
- Script has failsafe mode
- Will auto-increase intensity if metrics are low
- Check logs for "Activating failsafe mode"

### ❌ Gaming lag detected?

**Option 1:** Minimal network mode
```bash
sudo nano /etc/default/oracle-keep-alive
# Change: NETWORK_STRESS_MODE="minimal"
sudo systemctl restart oracle-keep-alive
```

**Option 2:** Lower bandwidth limit
```bash
sudo nano /etc/default/oracle-keep-alive
# Change: NETWORK_BANDWIDTH_LIMIT_KBS=50
sudo systemctl restart oracle-keep-alive
```

**Option 3:** Install traffic shaping
```bash
sudo apt install iproute2  # Ubuntu
sudo yum install iproute   # Oracle Linux
sudo systemctl restart oracle-keep-alive
```

### ❌ Service won't start?

```bash
# Check logs
sudo journalctl -u oracle-keep-alive -n 50

# Verify permissions
sudo chown -R root:root /opt/oracle-keep-alive
sudo chmod +x /opt/oracle-keep-alive/keep-alive.sh

# Restart
sudo systemctl restart oracle-keep-alive
```

---

## Success Checklist

- [x] Service is running: `sudo systemctl status oracle-keep-alive`
- [x] Logs show regular cycles: `sudo tail -f /var/log/oracle-keep-alive.log`
- [x] No gaming lag detected (test for 30 minutes)
- [x] Oracle Cloud metrics checked (after 24 hours)
- [x] At least ONE metric above 15%

---

## What Happens Next?

### First Week
- Script runs every ~8.5 minutes (45s stress + 480s sleep)
- Generates ~8% average CPU load
- Creates gentle network activity
- Memory spikes periodically

### Oracle Cloud Monitoring
- Oracle monitors your instance 24/7
- Checks CPU, memory, network every minute
- Calculates 95th percentile over 7 days
- Our periodic spikes ensure you stay above 15%

### Your Gaming
- VPN traffic is prioritized (Priority 0-4)
- Keep-alive traffic is lowest priority (Priority 7)
- Bandwidth-limited to prevent saturation
- Expected latency impact: <1ms

---

## Need Help?

1. Check the full [README.md](README.md)
2. Review [AUDIT.md](AUDIT.md) for detailed analysis
3. Check logs: `sudo tail -f /var/log/oracle-keep-alive.log`
4. Test each component individually
5. Open an issue on GitHub

---

## Tips for Success

✅ **DO:**
- Monitor Oracle metrics for first 2 weeks
- Test gaming performance after installation
- Keep default settings unless you have lag
- Check logs if something seems wrong
- Adjust configuration based on your needs

❌ **DON'T:**
- Set SLEEP_DURATION too high (>600s)
- Use aggressive network mode for gaming
- Disable all stress types at once
- Ignore Oracle Cloud metrics
- Panic if you see CPU spikes (that's normal!)

---

**You're all set! Your Oracle Cloud instance is now protected from reclamation while maintaining great gaming performance. 🎮**

**Questions?** Check README.md or open an issue!

---

**Pro Tip:** Set a calendar reminder to check Oracle Cloud metrics weekly for the first month, then monthly after that.
