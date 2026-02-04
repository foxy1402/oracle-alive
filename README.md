# Oracle Cloud Keep-Alive

**Keep your free Oracle Cloud server running forever - prevents automatic deletion due to low usage.**

Works on Oracle Linux and Ubuntu (both x86_64 and ARM instances).

---

## What Does This Do?

Oracle deletes free-tier instances if CPU, memory, and network usage are **all below 20%** for 7 consecutive days.

This script:
- ✅ Monitors your actual usage (only what Oracle monitors)
- ✅ Adds just enough activity to keep **all 3 metrics above 40%** (double the requirement)
- ✅ Runs automatically 24/7 in the background
- ✅ Won't interfere with your apps (lowest priority)

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
[INFO] Detected OS: Ubuntu 22.04.3 LTS  (or Oracle Linux Server 8.x)
[INFO] Baseline metrics established (USER workload only):
[INFO]   • CPU: 5-15% (user+nice time only)
[INFO]   • Memory: 10-20% (excluding buffers/cache)
[INFO]   • Network: 50-500 KB/s
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
- `TARGET_CPU_PERCENT=40` - Target CPU usage (default: 40%)
- `TARGET_MEMORY_PERCENT=40` - Target memory usage (default: 40%)
- `TARGET_NETWORK_PERCENT=40` - Target network usage (default: 40%)

After changing settings:
```bash
sudo systemctl restart oracle-keep-alive
```

---

## How It Works

### Oracle's Policy

Oracle monitors 3 metrics:
1. **CPU** (user+nice time only - NOT system/kernel)
2. **Memory** (application memory - NOT buffers/cache)  
3. **Network** (total traffic)

If **ALL THREE** stay below 20% for 7 days → instance deleted.

### Our Strategy

1. **Measure baseline** - What your apps currently use
2. **Calculate gap** - How much more needed to reach 40% on each metric
3. **Add smart stress** - Only what's needed, nothing wasted
4. **Monitor continuously** - Adjusts every 5 minutes
5. **Runs at lowest priority** - Won't slow down your apps

**Target: 40% on all metrics = Double Oracle's requirement = Safe forever**

---

## Verification

### Check Logs (Immediate)

```bash
sudo tail -100 /var/log/oracle-keep-alive.log
```

Look for:
- ✅ Baseline CPU: 5-15% (not 0%)
- ✅ Baseline Memory: 10-30%
- ✅ Baseline Network: 50-500 KB/s (not 0)
- ✅ "All three metrics meeting targets - instance is SAFE"

### Check Oracle Cloud Console (After 1 Hour)

1. Login to [Oracle Cloud Console](https://cloud.oracle.com)
2. Go to: **Compute** → **Instances** → **Your Instance** → **Metrics**
3. Verify all 3 graphs show activity above 40%

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

**Measurements (matches Oracle's methodology exactly):**
- CPU: Delta-based measurement of `user + nice` time from `/proc/stat`
- Memory: Actual application memory (total - available) from `free`
- Network: Interface traffic from `/sys/class/net/` statistics

**Stress Methods:**
- CPU: Parallel worker processes at nice level 19
- Memory: Temporary allocation in `/dev/shm`
- Network: Distributed pings + HTTP requests (bandwidth-limited)

**Intelligent Operation:**
- Measures baseline every 5 minutes
- Only adds stress where needed
- Adjusts sleep duration based on requirements
- Automatically detects network interface
- Portable across Oracle Linux and Ubuntu

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

**Version:** 2.1.0  
**Compatibility:** Oracle Linux 8/9, Ubuntu 20.04/22.04, Ubuntu Minimal (x86_64 and ARM)
