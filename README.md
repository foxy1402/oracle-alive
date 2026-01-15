# Oracle Cloud Free Tier Keep-Alive 🔄

Prevent your Oracle Cloud Always Free ARM instances from being reclaimed due to inactivity.

## Why Do You Need This?

Oracle Cloud reclaims **Always Free** compute instances if they are **idle for 7 days**.

An instance is considered **idle** when **ALL** of these are true:
- CPU utilization (95th percentile) < 15%
- Network utilization < 15%
- Memory utilization < 15% *(ARM instances only)*

> 💡 **Good news:** You only need to keep **ONE** metric above 15% to stay safe!

This script generates minimal CPU, memory, and network activity to keep your instance alive.

---

## 🚀 Quick Start (One Command!)

SSH into your Oracle Cloud instance and run:

```bash
# Download and install
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
sudo bash install.sh
```

**That's it!** The service is now running and will auto-start on reboot.

---

## 📋 Step-by-Step Guide

### Prerequisites
- Oracle Cloud Always Free ARM instance (VM.Standard.A1.Flex)
- SSH access to your instance
- Root/sudo privileges

### Step 1: Connect to Your Instance

```bash
ssh -i your-key.pem ubuntu@YOUR_INSTANCE_IP
```

Or use:
```bash
ssh -i your-key.pem opc@YOUR_INSTANCE_IP  # Oracle Linux
```

### Step 2: Download the Scripts

**Option A: Using Git**
```bash
git clone https://github.com/foxy1402/oracle-alive.git
cd oracle-alive
```

**Option B: Manual Download**
```bash
mkdir oracle-alive && cd oracle-alive

# Download files
wget https://raw.githubusercontent.com/foxy1402/oracle-alive/main/keep-alive.sh
wget https://raw.githubusercontent.com/foxy1402/oracle-alive/main/oracle-keep-alive.service
wget https://raw.githubusercontent.com/foxy1402/oracle-alive/main/install.sh
```

**Option C: Upload via SCP**
```bash
# From your local machine:
scp -i your-key.pem -r oracle-alive/ ubuntu@YOUR_INSTANCE_IP:~/
```

### Step 3: Run the Installer

```bash
sudo bash install.sh
```

You should see:
```
╔══════════════════════════════════════════════════════════════╗
║           Oracle Cloud Keep-Alive Installer                  ║
╚══════════════════════════════════════════════════════════════╝

✓ Created /opt/oracle-keep-alive
✓ Installed keep-alive.sh
✓ Installed service file
✓ Created config at /etc/default/oracle-keep-alive
✓ Systemd reloaded
✓ Service enabled
✓ Service started

✓ Installation complete!
```

### Step 4: Verify It's Working

```bash
# Check service status
sudo systemctl status oracle-keep-alive

# Watch the logs in real-time
sudo tail -f /var/log/oracle-keep-alive.log
```

Expected log output:
```
[2024-01-15 10:30:00] [INFO] Oracle Cloud Keep-Alive Script Started
[2024-01-15 10:30:00] [INFO] System detected: 4 CPU(s), 24576MB RAM
[2024-01-15 10:30:00] [INFO] --- Cycle #1 ---
[2024-01-15 10:30:00] [INFO] Starting CPU stress for 30s on 4 core(s)...
[2024-01-15 10:30:30] [INFO] CPU stress completed
[2024-01-15 10:30:30] [INFO] Starting memory stress (100MB)...
[2024-01-15 10:30:35] [INFO] Memory stress completed
[2024-01-15 10:30:35] [INFO] Starting network stress...
[2024-01-15 10:30:37] [INFO] Pinged 8.8.8.8 successfully
```

---

## ⚙️ Configuration

Edit the config file to customize behavior:

```bash
sudo nano /etc/default/oracle-keep-alive
```

Available options:

| Variable | Default | Description |
|----------|---------|-------------|
| `STRESS_DURATION` | 30 | Seconds to run stress operations |
| `SLEEP_DURATION` | 60 | Seconds to sleep between cycles |
| `TARGET_CPU_PERCENT` | 20 | Target CPU percentage |
| `MEMORY_STRESS_MB` | 100 | Memory to allocate (MB) |
| `STRESS_CPU` | 1 | Enable CPU stress (1=yes, 0=no) |
| `STRESS_MEMORY` | 1 | Enable memory stress |
| `STRESS_NETWORK` | 1 | Enable network stress |
| `LOG_FILE` | /var/log/oracle-keep-alive.log | Log file path |

After editing, restart the service:
```bash
sudo systemctl restart oracle-keep-alive
```

---

## 🔧 Useful Commands

| Command | Description |
|---------|-------------|
| `sudo systemctl status oracle-keep-alive` | Check service status |
| `sudo systemctl stop oracle-keep-alive` | Stop the service |
| `sudo systemctl start oracle-keep-alive` | Start the service |
| `sudo systemctl restart oracle-keep-alive` | Restart the service |
| `sudo tail -f /var/log/oracle-keep-alive.log` | View logs in real-time |
| `sudo journalctl -u oracle-keep-alive -f` | View systemd logs |

---

## 🗑️ Uninstallation

```bash
sudo bash install.sh --uninstall
```

This will:
- Stop and disable the service
- Remove all installed files
- Keep logs (remove manually if needed)

---

## 🔍 How It Works

The script runs in a continuous loop:

1. **CPU Stress** (30s default)
   - Spawns worker processes for each CPU core
   - Runs computational loops
   - Auto-adjusts based on CPU count

2. **Memory Stress** (5s)
   - Allocates 100MB in RAM (/dev/shm)
   - Reads it back to ensure memory pressure
   - Cleans up immediately

3. **Network Stress**
   - Pings Google DNS (8.8.8.8) and Cloudflare (1.1.1.1)
   - Makes an HTTPS request if curl is available

4. **Sleep** (60s default)
   - Rests before next cycle

**Result:** ~20% average CPU usage, enough to stay above Oracle's 15% threshold.

---

## ❓ FAQ

### Will this slow down my instance?
Minimal impact. The script runs at lowest priority (`nice=19`) and uses idle I/O scheduling.

### How much resources does it use?
- CPU: ~20% averaged over time (30s stress, 60s sleep)
- Memory: 100MB temporarily during stress
- Network: A few KB per cycle

### Can I run this on x86 instances?
Yes! But x86 instances don't check memory utilization, so you could disable memory stress.

### What if I'm already running services?
Perfect! Your services probably generate enough activity. Install this as a safety net anyway.

### Does this work with Oracle Linux?
Yes! Works with Ubuntu, Oracle Linux, and most Linux distributions.

---

## 📊 Monitoring Your Instance

Check your instance metrics in Oracle Cloud Console:
1. Go to **Compute** → **Instances** → **Your Instance**
2. Click **Metrics**
3. Look at CPU, Memory, and Network graphs
4. Ensure at least one is averaging above 15%

---

## 📄 License

MIT License - Use freely!

---

## 🤝 Contributing

Found a bug or have an improvement? Open an issue or PR!
