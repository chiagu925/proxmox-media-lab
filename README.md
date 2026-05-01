# Proxmox Home Lab — Automated Enterprise Media Infrastructure

A self-hosted, production-grade media platform built on bare metal using a Type-1 hypervisor. This project was designed and deployed end-to-end as a hands-on exercise in cloud architecture, infrastructure automation, and security engineering.

---

## What This Is

This isn't a tutorial follow-along. It's a real infrastructure project — planned with a formal project charter, tracked with a task breakdown, deployed iteratively, and documented like a production system.

The end result is a fully automated media acquisition and streaming platform that:
- Runs entirely on self-hosted hardware with no cloud dependency
- Automatically finds, downloads, scans for malware, and organizes media
- Streams to any device from anywhere via a zero-trust VPN
- Uses hardware-accelerated GPU transcoding to handle 4K without breaking a sweat

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Dell OptiPlex (Bare Metal)              │
│                  Proxmox VE Hypervisor                   │
│                                                         │
│  ┌─────────────────────┐   ┌────────────────────────┐  │
│  │   media-server VM   │   │   ubuntu-server VM     │  │
│  │   Ubuntu 24.04 LTS  │   │   Ubuntu 24.04 LTS     │  │
│  │                     │   │                        │  │
│  │  ┌───────────────┐  │   │  General purpose       │  │
│  │  │ Docker Stack  │  │   │  compute node          │  │
│  │  │               │  │   └────────────────────────┘  │
│  │  │ Jellyfin      │  │                               │
│  │  │ Sonarr        │  │   ┌────────────────────────┐  │
│  │  │ Radarr        │  │   │   kali-attacker VM     │  │
│  │  │ Prowlarr      │  │   │   Security lab /       │  │
│  │  │ qBittorrent   │  │   │   penetration testing  │  │
│  │  │ FlareSolverr  │  │   └────────────────────────┘  │
│  │  │ ClamAV        │  │                               │
│  │  └───────────────┘  │                               │
│  │                     │                               │
│  │  ZFS Pool (mediapool)│                              │
│  │  iGPU Passthrough   │                               │
│  └─────────────────────┘                               │
└─────────────────────────────────────────────────────────┘
                          │
                    Tailscale VPN
                    (Zero-trust access)
                          │
              ┌───────────┴───────────┐
              │                       │
         MacBook                 Mobile / Remote
         (Admin)                 (Streaming)
```

---

## Media Pipeline

```
Prowlarr (indexer aggregation)
    │
    ├── Sonarr (TV automation)
    └── Radarr (Movie automation)
              │
              ▼
        qBittorrent
              │
              ▼
    /data/downloads/quarantine
              │
        ClamAV scan (every 10 min)
              │
        ┌─────┴─────┐
      Clean       Infected
        │               │
        ▼               ▼
  /data/downloads/   Deleted +
     cleared         Logged
        │
        ▼
  Sonarr/Radarr imports
  renames + organizes
        │
        ▼
  /data/media/tv
  /data/media/movies
        │
        ▼
     Jellyfin
  (hardware transcoding
   via Intel QuickSync)
```

---

## Storage Layout

```
/data  (ZFS pool — mediapool)
├── compose/          ← docker-compose.yml lives here
├── config/           ← app configs (Jellyfin, Sonarr, Radarr, etc.)
├── downloads/
│   ├── quarantine/   ← all downloads land here first
│   └── cleared/      ← ClamAV-approved files only
├── media/
│   ├── movies/       ← Radarr-managed library
│   └── tv/           ← Sonarr-managed library
└── scripts/          ← automation scripts
```

---

## Security Architecture

| Layer | Implementation |
|-------|---------------|
| Network | UFW firewall, default deny |
| Auth | SSH key-only, password auth disabled |
| Intrusion | Fail2Ban active on SSH |
| Remote Access | Tailscale zero-trust VPN — no open ports |
| File Security | ClamAV quarantine pipeline for all downloads |
| Updates | Unattended-upgrades for automated security patches |
| Backups | Cron-scheduled daily backups with 7-day retention |

---

## Tech Stack

| Category | Technology |
|----------|-----------|
| Hypervisor | Proxmox VE |
| OS | Ubuntu Server 24.04 LTS |
| Storage | ZFS (pool: mediapool), lz4 compression |
| Containers | Docker, Docker Compose |
| Media Server | Jellyfin |
| Automation | Sonarr, Radarr, Prowlarr |
| Downloader | qBittorrent |
| Antivirus | ClamAV |
| VPN | Tailscale |
| IaC | Ansible |
| GPU Transcoding | Intel UHD 630 via QuickSync (PCIe passthrough) |

---

## Skills Demonstrated

- **Type-1 Hypervisor Management** — Proxmox VE VM provisioning, resource allocation, hardware passthrough
- **Linux System Administration** — Ubuntu Server, ZFS, LVM, systemd, networking
- **Containerization** — Docker Compose multi-service orchestration, volume management, networking
- **Infrastructure as Code** — Ansible playbooks, inventory management, role-based automation
- **Network Security** — UFW, Fail2Ban, zero-trust access, firewall rules
- **Storage Engineering** — ZFS pool creation, compression, snapshot strategy
- **Security Architecture** — DMZ-style quarantine pipeline, ClamAV integration, automated threat response
- **Hardware Optimization** — iGPU passthrough, Intel QuickSync, hardware-accelerated transcoding

---

## Repository Structure

```
proxmox-media-lab/
├── README.md
├── docs/
│   ├── proxmox-environment.md        ← full hypervisor layer reference
│   ├── project-charter.md
│   ├── runbook.md
│   └── change-management/
│       └── CHG-M401-001-gpu-passthrough.md
├── ansible/
│   ├── inventory/
│   │   └── hosts.yml
│   └── playbooks/
│       ├── ubuntu-base.yml
│       ├── media-server.yml
│       └── docker-stack.yml
├── docker/
│   └── media-stack/
│       └── docker-compose.yml
├── scripts/
│   └── gatekeeper.sh
└── infrastructure/
    └── proxmox/
        └── vm-config-reference.md
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
| [Proxmox Environment](docs/proxmox-environment.md) | Full hypervisor layer — hardware, VM architecture, storage, networking, cloud mapping |
| [Project Charter](docs/project-charter.md) | Scope, objectives, risks, and success criteria |
| [Runbook](docs/runbook.md) | Step-by-step deployment guide, lessons learned |
| [CHG-M401-001](docs/change-management/CHG-M401-001-gpu-passthrough.md) | iGPU passthrough change management doc |

---

## Project Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Storage Provisioning & Directory Structure | ✅ Complete |
| Phase 2 | VM Provisioning & Docker Installation | ✅ Complete |
| Phase 3 | Core Services Deployment | ✅ Complete |
| Phase 4 | GPU Passthrough & Hardware Acceleration | 🔄 In Progress |
| Phase 5 | Remote Playback & Final Hardening | ⏳ Pending |
| Phase 6 | UAT, Load Testing & Runbook Finalization | ⏳ Pending |

---

## Author

**Chibuzo Agu**  
Infrastructure & Cloud Architecture  
CompTIA A+ | CompTIA Security+  

> Built this to get reps in on the tools cloud architects actually use — not just to say I know them.
