# Change Management — CHG-M401-001

**Title:** Intel UHD 630 iGPU Passthrough to Media Server VM  
**Phase:** 4 — Hardware Acceleration  
**Risk Level:** Medium  
**Rollback Time:** < 10 minutes  

---

## Summary

This change passes the Intel UHD 630 integrated GPU from the Proxmox host through to the media-server VM, enabling Jellyfin to use Intel QuickSync for hardware-accelerated video transcoding.

---

## Why This Change Is Needed

Without GPU passthrough, all video transcoding falls on the CPU:

| Scenario | CPU (no GPU) | GPU (QuickSync) |
|----------|-------------|-----------------|
| 1080p x1 stream | 40-60% CPU | 5-10% CPU |
| 1080p x3 streams | 90-100% CPU | 15-25% CPU |
| 4K x1 stream | Likely lockup | 20-30% CPU |
| RAM per stream | +800MB - 4GB | +100-200MB |

This directly addresses the project charter risk: CPU lockup during 4K transcoding.

---

## Scope

**Changes to:**
- Proxmox VM config file (`/etc/pve/qemu-server/<VMID>.conf`)
- Intel media drivers inside media-server VM
- Jellyfin transcoding settings

**No changes to:**
- Any other VMs
- Proxmox host networking or storage
- Docker stack, ZFS pool, Tailscale, or ClamAV pipeline

---

## Implementation Steps

| # | Action | Command | Verification |
|---|--------|---------|--------------|
| 1 | Confirm iGPU on host | `ls /dev/dri` | card0, renderD128 present |
| 2 | Edit VM config | Add `hostpci0: 00:02.0,pcie=1` | File saved |
| 3 | Reboot VM | `qm reboot <VMID>` | VM online |
| 4 | Verify /dev/dri in VM | `ls -la /dev/dri` | renderD128 visible |
| 5 | Install drivers | `sudo apt install -y vainfo intel-media-va-driver-non-free` | vainfo shows QuickSync |
| 6 | Enable in Jellyfin | Dashboard → Playback → Intel QSV | Setting saved |
| 7 | Test 4K stream | Play 4K file, monitor htop | CPU stays below 40% |

---

## Rollback Plan

1. SSH into Proxmox host
2. `nano /etc/pve/qemu-server/<VMID>.conf`
3. Remove the `hostpci0` line
4. `qm reboot <VMID>`
5. Verify VM and Docker stack are back online

Result: Returns to CPU transcoding. No data loss, no impact to other services.

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| VM fails to boot | Low | Rollback plan above |
| /dev/dri not visible in VM | Low | Check Proxmox logs: `journalctl -xe` |
| Driver install fails | Low | Try `intel-media-va-driver` (non-free variant) |
| Other VMs impacted | None | Change isolated to single VM config |
| Proxmox loses display | None | Host is headless, no monitor attached |
