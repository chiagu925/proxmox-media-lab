# Project Charter — Automated Enterprise Media Infrastructure

**Version:** 1.0  
**Date:** March 23, 2026  
**Lead Engineer:** Chibuzo Agu  

---

## 1. Purpose

The goal of this project is to design, deploy, and document a self-hosted, automated media acquisition and streaming platform on bare metal infrastructure.

This is not just a media server project. It's a structured exercise in building production-grade infrastructure using the same tools and patterns found in enterprise environments and cloud architecture roles — Type-1 hypervisors, containerized microservices, infrastructure as code, hardware passthrough, and zero-trust networking.

---

## 2. Success Criteria

The project is complete when:

1. **Hardware-accelerated streaming** — Jellyfin is deployed and uses the integrated GPU for transcoding via Intel QuickSync, handling 4K content without CPU bottleneck.

2. **Full automation stack** — Sonarr, Radarr, Prowlarr, and qBittorrent are deployed via a single `docker-compose.yml` and communicate correctly end-to-end.

3. **Secure remote access** — All services are accessible from outside the local network via Tailscale, with zero public-facing ports open.

4. **Resilient, permission-correct storage** — ZFS pool configured with correct PUID/PGID across all containers, quarantine pipeline active.

---

## 3. Scope

### In Scope
- VM provisioning on Proxmox VE
- ZFS storage pool configuration
- Docker and Docker Compose deployment
- Full media stack (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent)
- ClamAV quarantine security pipeline
- Intel iGPU passthrough for hardware transcoding
- Tailscale VPN integration
- Ansible automation layer

### Out of Scope
- VLAN segmentation or custom routing
- Public-facing reverse proxy or custom SSL domains
- High-availability Proxmox clustering

---

## 4. Key Deliverables

| Deliverable | Description |
|-------------|-------------|
| Compute Foundation | Proxmox VM dedicated to media services |
| Docker Compose | Production-ready multi-service compose file |
| Security Pipeline | ClamAV quarantine with automated gatekeeper script |
| Ansible Playbooks | Automated provisioning for base VM setup |
| Runbook | Full deployment documentation |
| Change Management | Formal change docs for infrastructure modifications |

---

## 5. Milestones

| Phase | Description |
|-------|-------------|
| Phase 1 | Storage provisioning, ZFS pool, directory structure |
| Phase 2 | VM provisioning, Docker installation |
| Phase 3 | Core services deployment via Docker Compose |
| Phase 4 | iGPU passthrough, Intel QuickSync validation |
| Phase 5 | Tailscale integration, remote playback testing |
| Phase 6 | UAT, load testing, runbook finalization |

---

## 6. Risks

| Risk | Mitigation |
|------|-----------|
| Permissions mismatch between Docker containers and host filesystem | Explicitly define PUID/PGID in all containers, match to host mediaservice user |
| CPU overload during 4K transcoding before GPU passthrough | Prioritize Phase 4 before loading full media library |
| Infected files entering media library | ClamAV quarantine pipeline — all downloads scanned before Sonarr/Radarr can import |
| Insufficient storage for media library | ZFS pool on dedicated virtual disk, expandable via Proxmox |
