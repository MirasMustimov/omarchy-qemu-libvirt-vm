# mkvm

Creates a libvirt VM on Omarchy with defaults that actually work: q35 + UEFI,
virtio disk/net/gpu, 3D acceleration, and a USB tablet (no mouse lag).

Omits clipboard, USB redirection, audio and smartcard channels, and uses
usermode networking — so no `virbr0`, no IP forwarding, no host firewall rules.

## Prerequisites

Omarchy ships `gum`. The rest is one-time setup:

```bash
sudo pacman -S --needed virt-manager libvirt qemu-desktop edk2-ovmf
sudo systemctl enable --now libvirtd.socket
sudo usermod -aG libvirt $USER    # then log out and back in
```

## Usage

Put an ISO in `~/Documents` or `~/Downloads`, then:

```bash
./mkvm.sh --dry-run    # print the XML, change nothing
./mkvm.sh              # create it
./mkvm.sh --clean      # reclaim disk: delete staged ISOs nothing references
```

Answer six prompts. Open the VM in `virt-manager` when it finishes.

Once the install is done, run `./mkvm.sh --clean` to delete the staged copy of
the ISO. It skips any ISO a domain still points at, so it is safe to run at any
time — an install in progress will not be touched. Your original in
`~/Documents` is never removed.

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
