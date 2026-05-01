# Runbook — Automated Enterprise Media Infrastructure

This is a living document. Every step that was done manually during the build is recorded here so the environment can be reproduced from scratch.

---

## Environment Reference

| Component | Value |
|-----------|-------|
| Hypervisor | Proxmox VE |
| Host Hardware | Dell OptiPlex 7070 Micro |
| CPU | Intel Core i5-9500T |
| RAM | 32GB DDR4 2666MHz (dual channel) |
| Storage | 256GB SSD (Proxmox + VMs) |
| iGPU | Intel UHD 630 (QuickSync capable) |
| Media VM OS | Ubuntu Server 24.04.4 LTS |
| Media VM RAM | 14GB |
| Media VM Disk 1 | 20GB (OS) |
| Media VM Disk 2 | 20GB (ZFS pool — mediapool) |

---

## Phase 1 — Storage Setup

### 1.1 Install ZFS

```bash
sudo apt install zfsutils-linux -y
```

### 1.2 Create ZFS Pool

```bash
# Replace /dev/sdb with your actual data disk device
sudo zpool create -f -m /data mediapool /dev/sdb
sudo zfs set compression=lz4 mediapool
```

Verify:
```bash
zpool status
zfs list
```

ZFS handles mounting automatically — no fstab entry required.

### 1.3 Create Directory Structure

```bash
sudo mkdir -p /data/compose
sudo mkdir -p /data/config
sudo mkdir -p /data/downloads/quarantine
sudo mkdir -p /data/downloads/cleared
sudo mkdir -p /data/media/movies
sudo mkdir -p /data/media/tv
sudo mkdir -p /data/scripts
```

### 1.4 Create Service User

```bash
sudo groupadd -g 1001 mediaservice
sudo useradd -u 1001 -g mediaservice -s /bin/false mediaservice
sudo chown -R mediaservice:mediaservice /data
sudo chmod -R 755 /data
```

Verify:
```bash
id mediaservice
# Expected: uid=1001(mediaservice) gid=1001(mediaservice)
```

---

## Phase 2 — VM Base Setup

### 2.1 Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### 2.2 Install Base Packages

```bash
sudo apt install -y curl wget git htop ufw fail2ban unattended-upgrades vainfo intel-media-va-driver-non-free
```

### 2.3 Configure UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
```

### 2.4 Configure Fail2Ban

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 2.5 Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

### 2.6 Disable IPv6 (prevents indexer SSL issues)

```bash
sudo nano /etc/sysctl.conf
```

Add:
```
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
```

Apply:
```bash
sudo sysctl -p
```

### 2.7 Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Verify:
```bash
docker ps
```

---

## Phase 3 — Docker Stack Deployment

### 3.1 Configure Docker DNS

```bash
sudo nano /etc/docker/daemon.json
```

Add:
```json
{
  "ipv6": false,
  "dns": ["1.1.1.1", "8.8.8.8"],
  "dns-opts": ["ndots:0"]
}
```

```bash
sudo systemctl restart docker
```

### 3.2 Deploy Stack

```bash
docker compose -f /data/compose/docker-compose.yml up -d
```

### 3.3 Verify All Containers Running

```bash
docker ps
```

Expected containers:
- jellyfin
- sonarr
- radarr
- prowlarr
- qbittorrent
- flaresolverr
- clamav

---

## Phase 4 — iGPU Passthrough

### 4.1 Verify iGPU on Proxmox Host

```bash
ls /dev/dri
lspci | grep -i vga
```

Expected:
```
card0  renderD128
Intel Corporation CoffeeLake-S GT2 [UHD Graphics 630]
```

### 4.2 Add Passthrough to VM Config

On Proxmox host:
```bash
nano /etc/pve/qemu-server/<VMID>.conf
```

Add:
```
hostpci0: 00:02.0,pcie=1
```

Reboot VM:
```bash
qm reboot <VMID>
```

### 4.3 Verify Inside VM

```bash
ls -la /dev/dri
vainfo
```

### 4.4 Enable in Jellyfin

Jellyfin → Dashboard → Playback → Hardware Acceleration → Intel QSV → Save

---

## Phase 5 — Security Hardening

### 5.1 ClamAV Quarantine Pipeline

ClamAV runs as a Docker container monitoring `/data/downloads/quarantine`.

```bash
docker compose -f /data/compose/docker-compose.yml up -d clamav
docker logs clamav --tail 20
```

Wait for: `clamd started`

### 5.2 Gatekeeper Script

See `scripts/gatekeeper.sh`

Schedule via cron:
```bash
sudo crontab -e
```

Add:
```
*/10 * * * * /data/scripts/gatekeeper.sh
```

### 5.3 Automated Updates

```bash
sudo dpkg-reconfigure unattended-upgrades
```

Select Yes.

---

## Phase 6 — Prowlarr / Arr Stack Configuration

### Indexer Setup

1. Prowlarr → Indexers → Add:
   - YTS (movies, no Cloudflare issues)
   - TorrentGalaxy (general)
   - 1337x (requires FlareSolverr)
   - EZTV (TV, requires FlareSolverr)

2. Prowlarr → Settings → Apps → Add Sonarr:
   - Server: `http://sonarr:8989`
   - API Key: from Sonarr → Settings → General

3. Prowlarr → Settings → Apps → Add Radarr:
   - Server: `http://radarr:7878`
   - API Key: from Radarr → Settings → General

### Download Path Configuration

- qBittorrent default save path: `/data/downloads/quarantine`
- Sonarr root folder: `/data/media/tv`
- Radarr root folder: `/data/media/movies`

### Jellyfin Libraries

- TV Shows → `/data/media/tv`
- Movies → `/data/media/movies`

---

## Troubleshooting

### ZFS ARC Cache Inflating RAM Usage

ZFS uses available RAM as a read cache. This is normal and not actual process consumption.

```bash
# Check real process usage vs cache
free -h
# Available column is the meaningful number
```

### Root Partition Full

```bash
# Check LVM free space
sudo vgdisplay

# Extend if free space available
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

### Docker Container DNS Failures

```bash
# Test from inside container
docker exec -it <container> curl -4 -I https://example.com

# If failing, check daemon.json DNS settings
cat /etc/docker/daemon.json
```

### FlareSolverr Cloudflare Timeout

Known issue with aggressive Cloudflare Turnstile challenges. Use indexers that don't require FlareSolverr (YTS, TorrentGalaxy) as primary sources.

---

## Key Lessons Learned

- ZFS ARC cache inflates apparent RAM usage — available column is what matters
- ZFS `-m` flag handles mount point on pool creation — no separate mount or fstab entry needed
- Docker containers use PUID/PGID to match host filesystem permissions — mismatches silently break imports
- IPv6 causes SSL errors with many torrent indexers — disable at OS level
- LVM often leaves significant unallocated space after Ubuntu install — extend before running out
- Hotel/shared networks intercept HTTPS — direct ethernet connection to hypervisor is more reliable
