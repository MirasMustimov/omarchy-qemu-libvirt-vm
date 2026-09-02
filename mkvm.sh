#!/usr/bin/env bash
# mkvm - create a libvirt VM with q35/UEFI, virtio, 3D acceleration and a USB tablet.
#
#   ./mkvm.sh              create the VM
#   ./mkvm.sh --dry-run    print the XML, change nothing
#   ./mkvm.sh --clean      remove staged ISOs no domain references
set -euo pipefail

IMAGE_DIR=/var/lib/libvirt/images
CONNECT=qemu:///system

die() { echo "$*" >&2; exit 1; }

# Remove staged ISOs, skipping any a domain still points at. Safe at any time:
# an install in progress still references its ISO, so it will not be touched.
if [[ ${1:-} == --clean ]]; then
  echo "Cleaning staged ISOs in $IMAGE_DIR"
  echo "(originals elsewhere, e.g. ~/Documents, are never touched)"
  echo
  for iso in "$IMAGE_DIR"/*.iso; do
    [[ -e $iso ]] || continue
    used=false
    for dom in $(virsh --connect "$CONNECT" list --all --name); do
      [[ -n $dom ]] || continue
      virsh --connect "$CONNECT" dumpxml "$dom" | grep -qF "$iso" && used=true
    done
    if $used; then
      echo "  keeping  $iso"
      echo "           (still referenced by a domain)"
    else
      echo "  removing $iso  ($(du -h "$iso" | cut -f1))"
      sudo rm -f "$iso"
    fi
  done
  exit 0
fi

DRY_RUN=false
[[ ${1:-} == --dry-run ]] && DRY_RUN=true

# If we staged an ISO and then failed, do not leave several GB behind.
STAGED=""
STAGED_BY_US=false
cleanup() { $STAGED_BY_US && sudo rm -f "$STAGED"; }
trap cleanup ERR INT TERM

# mapfile, not $(find ...) - unquoted word splitting breaks paths with spaces.
mapfile -t CANDIDATES < <(find ~/Documents ~/Downloads -maxdepth 1 -name '*.iso' 2>/dev/null)
[[ ${#CANDIDATES[@]} -gt 0 ]] || die "No .iso found in ~/Documents or ~/Downloads"

ISO=$(gum choose --header "Which ISO?" "${CANDIDATES[@]}")
[[ -n $ISO ]] || die "cancelled"

NAME=$(gum input --prompt "Name: " --value "$(basename "$ISO" .iso)")

OS_VARIANT=$(gum choose --header "OS variant?" \
  archlinux fedora44 debian13 ubuntu24.04 opensusetumbleweed alpinelinux3.24 generic)

# Offer only what this host can actually back.
TOTAL_MB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
MEMORY=$(gum choose --header "Memory (MiB)?" \
         $(for m in 4096 2048 8192 16384 32768; do ((m <= TOTAL_MB / 2)) && echo $m; done))

VCPUS=$(gum choose --header "vCPUs?" \
        $(for c in 4 2 6 8 12 16; do ((c <= $(nproc))) && echo $c; done))

FREE_GB=$(df -BG --output=avail "$IMAGE_DIR" | tail -1 | tr -dc '0-9')
DISK_SIZE=$(gum choose --header "Disk size (GiB)?" \
            $(for d in 30 20 50 100 200; do ((d <= FREE_GB)) && echo $d; done))

# Escaping a gum prompt leaves the variable empty; $() hides that from set -e.
for v in NAME OS_VARIANT MEMORY VCPUS DISK_SIZE; do
  [[ -n ${!v} ]] || die "cancelled"
done

# Fail clearly rather than letting virt-install complain about a collision.
if virsh --connect "$CONNECT" dominfo "$NAME" >/dev/null 2>&1; then
  die "a domain named '$NAME' already exists"
fi
if [[ -e "$IMAGE_DIR/$NAME.qcow2" ]]; then
  die "disk image already exists: $IMAGE_DIR/$NAME.qcow2"
fi

# Find a GPU that can back virgl. The proprietary NVIDIA driver exposes no
# usable EGL render node; virt-install's auto-pick takes the lowest PCI
# address, which on a hybrid laptop is exactly the wrong one.
RENDERNODE=""
for node in /dev/dri/renderD*; do
  dev=$(basename "$node")
  [[ $(basename "$(readlink -f "/sys/class/drm/$dev/device/driver")") == nvidia ]] && continue
  RENDERNODE=$(find /dev/dri/by-path -lname "*/$dev" -print -quit)
  break
done

if [[ -n $RENDERNODE ]]; then
  GRAPHICS="spice,listen=none,gl.enable=yes,gl.rendernode=$RENDERNODE"
  VIDEO="virtio,accel3d=yes"
else
  echo "No Mesa-backed GPU found - creating without 3D acceleration."
  GRAPHICS="spice,listen=none"
  VIDEO="virtio"
fi

# QEMU runs as an unprivileged account here and can't read $HOME, so copy the
# ISO somewhere it can, rather than opening up your home directory.
# Skipped on a dry run - copying several GB is not a rehearsal.
if $DRY_RUN; then
  STAGED="$ISO"
else
  STAGED="$IMAGE_DIR/$(basename "$ISO")"
  if [[ ! -f $STAGED ]]; then
    echo "Copying $(du -h "$ISO" | cut -f1) ISO into $IMAGE_DIR (needs sudo)"
    sudo -v                     # prompt for the password before the spinner hides it
    # Run the copy in the background and spin on a plain wait loop. Using
    # `gum spin -- sudo cp` instead lets sudo grab /dev/tty, which garbles
    # gum's output into raw escape sequences. /proc, not `kill -0`: the copy
    # runs as root and signalling it from here fails with EPERM.
    sudo cp "$ISO" "$STAGED" &
    cp_pid=$!
    gum spin --title "Copying $(basename "$ISO")…" -- \
      bash -c "while [ -d /proc/$cp_pid ]; do sleep 0.5; done"
    wait "$cp_pid"
    STAGED_BY_US=true
  fi
fi

DRY_ARGS=()
$DRY_RUN && DRY_ARGS=(--dry-run --print-xml)

virt-install --connect "$CONNECT" \
  --name "$NAME" \
  --memory "$MEMORY" --vcpus "$VCPUS" --cpu host-passthrough \
  --machine q35 --boot uefi \
  --disk "path=$IMAGE_DIR/$NAME.qcow2,size=$DISK_SIZE,format=qcow2,bus=virtio" \
  --cdrom "$STAGED" \
  --network user,model=virtio \
  --graphics "$GRAPHICS" \
  --video "$VIDEO" \
  --input tablet,bus=usb \
  --channel none --redirdev none \
  --osinfo "$OS_VARIANT" --noautoconsole \
  "${DRY_ARGS[@]}"

$DRY_RUN || cat <<EOF

Created '$NAME' successfully.

Next:  open '$NAME' in virt-manager and run the installer
Then:  ./mkvm.sh --clean     to delete the staged ISO copy
EOF
