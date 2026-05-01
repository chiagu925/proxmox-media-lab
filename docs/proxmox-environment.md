# Proxmox VE Environment — Infrastructure Reference

This document covers the full hypervisor layer of the lab — how the physical hardware is configured, how virtual machines are provisioned and resourced, and how the storage and network layers are structured. This is the foundation everything else runs on.

---

## Why Proxmox VE

Proxmox VE is a Type-1 (bare metal) hypervisor — it runs directly on the hardware, not inside an operating system. This is the same category of technology as VMware vSphere and Microsoft Hyper-V used in enterprise data centers, and it maps directly to the underlying compute layer in cloud platforms like AWS EC2.

Running a home lab on a Type-1 hypervisor means the skills transfer directly:

| Proxmox Concept | AWS / Cloud Equivalent |
|-----------------|----------------------|
| Proxmox VE host | EC2 bare metal / physical host |
| KVM Virtual Machine | EC2 instance |
| vmbr0 bridge | VPC / virtual network interface |
| LVM thin pool | EBS volume pool |
| ZFS pool | EBS + S3 with snapshots |
| VM resource allocation | EC2 instance sizing |
| Proxmox backup | AMI snapshots |
| iGPU passthrough | EC2 G-series / P-series GPU instances |
| Ansible provisioning | CloudFormation / Terraform |

---

## Physical Hardware

| Component | Specification |
|-----------|--------------|
| Machine | Dell OptiPlex 7070 Micro |
| CPU | Intel Core i5-9500T (6 cores, 9MB cache) |
| RAM | 32GB DDR4 2666MHz SO-DIMM (dual channel) |
| Storage | 256GB SSD (NVMe) |
| iGPU | Intel UHD Graphics 630 (QuickSync capable) |
| Network | Intel I219-LM Gigabit Ethernet + Intel WiFi 6 |
| Form Factor | Micro PC — fanless capable, low power draw |

### RAM Upgrade Decision

The machine shipped with a single 16GB stick in DIMM1, leaving DIMM2 empty and running in single-channel mode. A matching 16GB stick was added to DIMM2 to achieve:

- **Dual-channel memory** — doubles memory bandwidth between CPU and RAM
- **iGPU performance** — integrated graphics shares system memory bandwidth, so dual-channel directly improves transcoding throughput
- **VM headroom** — 32GB allows running 3 VMs simultaneously with comfortable allocation

---

## Proxmox VE Installation

Proxmox VE is installed directly on the SSD as the primary OS. There is no host operating system underneath it — the hypervisor is the OS.

### Storage Layout Post-Install

```
/dev/sda (256GB SSD)
├── sda1    1007K    BIOS boot
├── sda2    1GB      /boot/efi
└── sda3    231GB    LVM Physical Volume
    ├── pve-swap     8GB     Swap
    ├── pve-root     68GB    Proxmox OS + config
    └── pve-data     136GB   VM disk image pool (thin provisioned)
```

### Why Thin Provisioning

The `pve-data` pool uses LVM thin provisioning — VM disks are allocated on paper but only consume real space as data is written. A VM with a 40GB disk that only uses 15GB only takes 15GB from the pool.

This is the same concept as AWS EBS volumes — you provision capacity and pay/use only what's written.

---

## Virtual Machine Architecture

### VM Inventory

| VM ID | Name | Purpose | vCPU | RAM | Disk | Status |
|-------|------|---------|------|-----|------|--------|
| 100 | ubuntu-server | General compute, Ansible target | 2 | 8GB | 40GB | Running |
| 101 | kali-attacker | Security lab / penetration testing | 2 | 4GB | 40GB | Stopped when not in use |
| 102 | media-server | Media automation stack | 2 | 14GB | 20GB OS + 20GB ZFS | Running |

### Resource Allocation Strategy

```
Total RAM:          32GB
─────────────────────────────────────
Proxmox host:        4GB  (reserved — never allocate all RAM to VMs)
ubuntu-server:       8GB
kali-attacker:       4GB
media-server:       14GB  (largest — runs full Docker stack + ZFS ARC cache)
─────────────────────────────────────
Total allocated:    30GB  (2GB buffer for host overhead)
```

The 2GB buffer is intentional. Proxmox needs headroom for its own processes, and overcommitting RAM on a hypervisor causes memory balloon pressure across all VMs simultaneously.

### VM Provisioning Commands

```bash
# Check all VM status and current allocation
qm list

# Get full config for a specific VM
qm config <VMID>

# Set RAM allocation (in MB)
qm set <VMID> --memory <MB>

# Resize a VM disk
qm resize <VMID> scsi0 +<SIZE>G

# Graceful reboot
qm reboot <VMID>

# Destroy VM and its disks
qm destroy <VMID> --destroy-unreferenced-disks 1
```

---

## Network Architecture

### Bridge Configuration

Proxmox uses a Linux bridge (`vmbr0`) as its virtual switch. Every VM's network interface connects to this bridge, which then connects to the physical NIC.

```
Physical NIC (nic0)
        │
      vmbr0  (Linux bridge — Proxmox virtual switch)
     /   |   \
  VM100 VM101 VM102   ← each VM gets a virtual NIC on the bridge
```

This is the same concept as a VPC with a virtual switch in AWS — VMs are isolated at the software layer but share the same physical network path to the gateway.

### /etc/network/interfaces Reference

```
auto lo
iface lo inet loopback

iface nic0 inet manual

auto vmbr0
iface vmbr0 inet static
  address <PROXMOX_HOST_IP>/24
  gateway <GATEWAY_IP>
  bridge-ports nic0
  bridge-stp off
  bridge-fd 0

source /etc/network/interfaces.d/*
```

**Key settings explained:**
- `bridge-stp off` — disables Spanning Tree Protocol (not needed in a single-switch home lab, adds unnecessary delay)
- `bridge-fd 0` — sets forward delay to 0 (instant packet forwarding)

---

## Storage Architecture

### Two-Tier Storage Model

The lab uses two distinct storage tiers, matching the separation of compute and data storage in cloud environments:

```
Tier 1 — OS Storage (LVM thin pool on Proxmox)
  └── VM system disks (Ubuntu OS, Docker binaries, app configs)
  └── Managed by Proxmox LVM
  └── AWS equivalent: Root EBS volume attached to EC2

Tier 2 — Data Storage (ZFS pool inside media-server VM)
  └── All media files, downloads, and application data
  └── Managed by ZFS inside the VM
  └── AWS equivalent: Secondary EBS data volume or EFS
```

### ZFS Pool Configuration

The media-server VM has a dedicated 20GB virtual disk formatted as a ZFS pool:

```bash
# Pool creation
zpool create -f -m /data mediapool /dev/sdb
zfs set compression=lz4 mediapool
```

**Why ZFS over ext4:**

| Feature | ext4 | ZFS |
|---------|------|-----|
| Checksumming | No | Yes — detects silent corruption |
| Compression | No | Yes — lz4, transparent |
| Snapshots | No | Yes — instant, space-efficient |
| Self-healing | No | Yes — corrects bit rot automatically |
| Copy-on-write | No | Yes — no corruption on crash |

**Why lz4 compression:**
lz4 is the fastest compression algorithm available in ZFS. For a media server it provides minimal compression on already-compressed video files but meaningful savings on config files, logs, and metadata — with essentially zero CPU overhead.

### ZFS Snapshot Strategy

```bash
# Before any risky operation — instant, no downtime
zfs snapshot mediapool@before-change

# List all snapshots
zfs list -t snapshot

# Roll back if something goes wrong
zfs rollback mediapool@before-change

# Delete snapshot when no longer needed
zfs destroy mediapool@before-change
```

---

## iGPU Passthrough

### What Passthrough Means

By default, Proxmox owns all physical hardware including the Intel UHD 630 iGPU. Passthrough remaps the GPU's PCIe device directly into a VM, giving that VM exclusive hardware access for GPU-accelerated workloads.

```
Without passthrough:          With passthrough:
─────────────────────         ─────────────────────
Proxmox owns /dev/dri         VM102 owns /dev/dri
VMs use CPU for video         VM102 uses GPU for video
High CPU during streams       Low CPU during streams
```

### Identifying the Device

```bash
# On Proxmox host
lspci | grep -i vga
# Output: 00:02.0 VGA compatible controller: Intel UHD Graphics 630

ls /dev/dri
# Output: card0  renderD128
```

### VM Config Addition

Added to `/etc/pve/qemu-server/<VMID>.conf`:

```
hostpci0: 00:02.0,pcie=1
```

### Performance Impact

| Workload | CPU Without GPU | CPU With GPU |
|----------|----------------|-------------|
| 1080p transcode x1 | 40-60% | 5-10% |
| 1080p transcode x3 | 90-100% | 15-25% |
| 4K transcode x1 | Lockup risk | 20-30% |

---

## Backup Strategy

### Current Implementation

Daily automated backups via cron with 7-day retention:

```bash
# Cron schedule — runs at 2AM daily
0 2 * * * tar -czf /backup/media-server-$(date +\%Y\%m\%d).tar.gz /data/config && \
          find /backup -name "*.tar.gz" -mtime +7 -delete
```

### ZFS Snapshot Backup (Per-Operation)

Before any infrastructure change, a ZFS snapshot is taken:

```bash
zfs snapshot mediapool@pre-<change-description>
```

This provides instant point-in-time recovery with zero downtime — equivalent to creating an AMI snapshot before modifying an EC2 instance.

### What Gets Backed Up

| Data | Method | Frequency |
|------|--------|-----------|
| App configs (/data/config) | tar + cron | Daily |
| Docker compose file | Git (this repo) | On change |
| Ansible playbooks | Git (this repo) | On change |
| Media files | Not backed up | Redownloadable |

Media files themselves are not backed up — they can be re-acquired. Config files are the irreplaceable data.

---

## Security Hardening at the Hypervisor Layer

| Control | Implementation |
|---------|---------------|
| Web UI access | HTTPS on port 8006, self-signed cert |
| Remote access | Tailscale only — no public ports open |
| VM isolation | Each VM on separate bridge namespace |
| Kali VM | Stopped when not in use — reduces attack surface |
| SSH to host | Key authentication only |

---

## Monitoring

```bash
# Real-time resource usage across all VMs
htop

# Check all VM status
qm list

# Check ZFS pool health
zpool status
zpool iostat

# Check storage usage across Proxmox
pvs && vgs && lvs
df -h

# Check running services on host
systemctl list-units --type=service --state=running

# Check what's listening on ports
ss -tulnp
```

---

## Cloud Architecture Mapping

This environment is deliberately structured to mirror how production cloud infrastructure works:

```
Home Lab                          AWS Equivalent
────────────────────────────────────────────────
Proxmox VE host              →   Physical host / EC2 bare metal
KVM Virtual Machines         →   EC2 instances
vmbr0 network bridge         →   VPC + virtual network interface
LVM thin pool                →   EBS volume pool
ZFS data pool                →   EBS data volume
VM snapshots                 →   AMI snapshots
iGPU passthrough             →   EC2 G4/P3 GPU instances
Tailscale zero-trust         →   AWS PrivateLink / VPN Gateway
Ansible provisioning         →   CloudFormation / Terraform
UFW firewall rules           →   Security Groups
Fail2Ban                     →   AWS WAF / Shield
mediaservice user/PUID       →   IAM roles + least privilege
ClamAV quarantine pipeline   →   S3 malware scanning / GuardDuty
Docker Compose stack         →   ECS task definitions
ZFS lz4 compression          →   S3 intelligent tiering
```

Every skill practiced in this lab has a direct, billable equivalent in cloud architecture roles.
