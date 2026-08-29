# mkvm

Creates a libvirt VM on Omarchy with defaults that actually work: q35 + UEFI,
virtio disk/net/gpu, 3D acceleration, and a USB tablet (no mouse lag).

Omits clipboard, USB redirection, audio and smartcard channels, and uses
usermode networking — so no `virbr0`, no IP forwarding, no host firewall rules.

## Prerequisites

Omarchy ships `gum`. The rest is one-time setup.

```bash
sudo pacman -S --needed virt-manager libvirt qemu-desktop edk2-ovmf
```

`virt-manager` gives you the GUI and the `virt-install` this script calls,
`libvirt` is the daemon that manages VMs, `qemu-desktop` is the emulator that
runs them, and `edk2-ovmf` is the UEFI firmware the guests boot from.

```bash
sudo systemctl enable --now libvirtd.socket
```

Turns on the system-wide libvirt. It is socket-activated: systemd holds the
socket and only starts the daemon when something connects, so nothing runs
while you are not using VMs.

```bash
sudo usermod -aG libvirt $USER    # then log out and back in
```

Lets you manage system VMs without root. **Do not drop the `-a`** — `-G` alone
replaces your groups, which would remove you from `wheel` and cost you `sudo`.
Group membership is applied at login, so a fresh login is required.

## Usage

**1. Put the ISO where the script looks** — `~/Documents` or `~/Downloads`.

**2. Preview first (optional).**

```bash
./mkvm.sh --dry-run
```

Prints the XML it would create and changes nothing.

**3. Create the VM.**

```bash
./mkvm.sh
```

**4. Answer the prompts** — ISO, name, OS variant, memory, vCPUs, disk size.
Memory, CPU and disk options are filtered to what this machine can back.

**5. Enter your password when asked.** The ISO is copied into
`/var/lib/libvirt/images`; expect a minute or two for a large one.

**6. Open the VM in `virt-manager`** and run the OS installer as normal.

**7. Reclaim the disk space** once the install finishes.

```bash
./mkvm.sh --clean
```

Deletes staged ISO copies. Skips any ISO a domain still references, so it is
safe to run at any time — an install in progress will not be touched, and your
original in `~/Documents` is never removed.

## Notes

- **The ISO gets copied to `/var/lib/libvirt/images`** (needs sudo). QEMU runs
  as an unprivileged account that can't read `$HOME`. Copying beats granting it
  access to your home directory. Clean it up afterwards with `--clean`; if the
  script fails or is interrupted mid-run, it removes the copy itself.
- **NVIDIA GPUs are skipped** when choosing a renderer. The proprietary driver
  has no usable EGL render node, so virgl fails with `EGL_NOT_INITIALIZED`.
  On a hybrid laptop this picks the iGPU, which is the right answer anyway.
- **No host/guest clipboard.** Deliberate.
- **Windows guests won't work** as-is — the installer can't see a virtio disk
  without drivers from the virtio-win ISO.

## Verifying it worked

Inside the guest:

```bash
lspci | grep -i vga           # Virtio 1.0 GPU, not QXL
glxinfo -B | grep renderer    # virgl, not llvmpipe
```

If it says `llvmpipe`, you're on software rendering and everything will stutter.
