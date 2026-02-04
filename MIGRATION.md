# Migration: Intelligent Mode → Fixed-Mode

## Quick Migration Steps

Run these commands on your Oracle instance (via SSH):

```bash
# Step 1: Stop the current service
sudo systemctl stop oracle-keep-alive

# Step 2: Disable it (prevent auto-start on reboot)
sudo systemctl disable oracle-keep-alive

# Step 3: Pull latest code (with fixed-mode)
cd oracle-alive
git pull origin main

# Step 4: Install fixed-mode
sudo bash install-fixed.sh

# Step 5: Verify it's running
sudo systemctl status oracle-fixed-mode
```

That's it! Fixed-mode is now running.

---

## Verify It's Working

```bash
# Watch logs for 1-2 minutes
sudo tail -f /var/log/oracle-fixed-mode.log
```

You should see:
```
[INFO] Oracle Fixed-Mode Keep-Alive v1.0.0
[INFO] Target Utilization:
[INFO]   • CPU: 25%
[INFO]   • Memory: 30%
[INFO]   • Network: 30%
[INFO] Starting initial stress processes...
[INFO] CPU below target (10% < 25%), increasing load to 20%
[INFO] Memory below target (15% < 30%), increasing to 500MB
```

Press `Ctrl+C` when you see it adjusting.

---

## Check Both Services Status

```bash
# Old service should be stopped/disabled
sudo systemctl status oracle-keep-alive

# New service should be active/running
sudo systemctl status oracle-fixed-mode
```

---

## Customize Targets (Optional)

If you want different percentages:

```bash
# Edit config
sudo nano /etc/default/oracle-fixed-mode

# Change these lines:
TARGET_CPU_PERCENT=25      # Your desired %
TARGET_MEMORY_PERCENT=30
TARGET_NETWORK_PERCENT=30

# Save: Ctrl+O, Enter, Ctrl+X

# Apply changes
sudo systemctl restart oracle-fixed-mode
```

---

## Rollback (If Needed)

If you want to go back to intelligent mode:

```bash
# Stop fixed-mode
sudo systemctl stop oracle-fixed-mode
sudo systemctl disable oracle-fixed-mode

# Start intelligent mode again
sudo systemctl enable oracle-keep-alive
sudo systemctl start oracle-keep-alive
```

---

## What Changed?

| Before (Intelligent) | After (Fixed-Mode) |
|---------------------|-------------------|
| Auto-adjusts to 40% | You set exact % (default 25/30/30) |
| 96s cycles with sleep | Continuous 3s monitoring |
| May hit 100% on 1-CPU | Capped at 95% ✅ |
| Some fluctuation | Perfectly stable lines ✅ |

---

## Next: Check Oracle Console

Wait **1 hour**, then check:
- Oracle Cloud Console → Compute → Instances → [Your Instance] → Metrics
- You should see **flat horizontal lines** at your targets

✅ Done! Your instance is now protected with precise control.
