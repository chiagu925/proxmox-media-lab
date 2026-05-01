# Proxmox VM Configuration Reference

This document describes the configuration applied to the media-server VM on the Proxmox host. Sensitive values are replaced with placeholders.

---

## VM Specification

| Setting | Value |
|---------|-------|
| VM ID | `<VMID>` |
| Name | media-server |
| OS | Ubuntu Server 24.04.4 LTS |
| CPU | 2 cores |
| RAM | 14GB |
| Disk 1 | 20GB (OS — LVM) |
| Disk 2 | 20GB (Data — ZFS pool: mediapool) |
| Network | VirtIO bridge |

---

## iGPU Passthrough Config

Add to `/etc/pve/qemu-server/<VMID>.conf` on the Proxmox host:

```
hostpci0: 00:02.0,pcie=1
```

> **Note:** `00:02.0` is the PCIe address of the Intel UHD 630 on the Dell OptiPlex 7070 Micro. Verify your address with `lspci | grep -i vga` before applying.

---

## RAM Allocation Reference

```bash
# Set VM RAM from Proxmox host
qm set <VMID> --memory <MB>

# Example: 14GB
qm set <VMID> --memory 14336
```

---

## Disk Expansion Reference

If the OS root partition needs expanding after Ubuntu install:

```bash
# Check available LVM space
sudo vgdisplay

# Extend logical volume
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

# Resize filesystem
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

---

## Proxmox Storage Check

```bash
# Check physical disk layout
lsblk

# Check LVM volume groups
pvs && vgs && lvs

# Check ZFS pools
zpool list
zfs list
```
