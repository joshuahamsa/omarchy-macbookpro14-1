#!/bin/bash

# Apply the MacBookPro14,1 fixes to an Omarchy install. Safe to re-run.
# Usage: ./install.sh [--force] [--no-trim]

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
force=0
trim=1
changed=0

for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --no-trim) trim=0 ;;
    *) echo "Usage: $0 [--force] [--no-trim]" >&2; exit 1 ;;
  esac
done

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [[ $model != "MacBookPro14,1" ]] && (( ! force )); then
  echo "This is a $model, not a MacBookPro14,1. Re-run with --force to apply anyway." >&2
  exit 1
fi

install_file() {
  local path="$1" mode="$2"
  if ! sudo cmp -s "$repo/files$path" "$path" 2>/dev/null; then
    echo "Installing $path"
    sudo install -Dm"$mode" "$repo/files$path" "$path"
    changed=1
  fi
}

# Sleep: detach the Thunderbolt controller around suspend. Omarchy's own copy
# (same name) replaces this once omacom/omarchy ships it.
install_file /usr/lib/systemd/system-sleep/apple-thunderbolt-detach 755
if [[ -e /usr/lib/systemd/system-sleep/thunderbolt-detach ]]; then
  echo "Removing the older thunderbolt-detach hook"
  sudo rm /usr/lib/systemd/system-sleep/thunderbolt-detach
fi

# Speakers: the re-patch hook must exist before the driver package is installed,
# so the first DKMS build already carries the resume fix.
install_file /usr/local/share/macbook-fixes/cs8409-resume.diff 644
install_file /usr/local/bin/cs8409-resume-patch 755
install_file /etc/pacman.d/hooks/60-cs8409-resume-patch.hook 644
install_file /etc/modprobe.d/macbook-audio.conf 644

# Camera.
install_file /etc/modprobe.d/facetimehd.conf 644

packages=(snd-hda-macbookpro-dkms-git facetimehd-dkms facetimehd-firmware facetimehd-data)
if omarchy-pkg-missing "${packages[@]}"; then
  omarchy-pkg-aur-add "${packages[@]}"
  changed=1
fi

# An already-installed driver package never triggered the hook; patch and
# rebuild it now if needed.
src=$(echo /usr/src/snd-hda-macbookpro-*/patch_cirrus/cirrus_apple.h)
if [[ -f $src ]] && ! grep -q "local fix (MacBookPro14,1)" "$src"; then
  sudo /usr/local/bin/cs8409-resume-patch
  if grep -q "local fix (MacBookPro14,1)" "$src"; then
    version=$(basename "$(dirname "$(dirname "$src")")")
    version=${version#snd-hda-macbookpro-}
    for kernel in /usr/lib/modules/*/build; do
      kernel=$(basename "$(dirname "$kernel")")
      sudo dkms build --force "snd-hda-macbookpro/$version" -k "$kernel"
      sudo dkms install --force "snd-hda-macbookpro/$version" -k "$kernel"
    done
    changed=1
  fi
fi

# Kernel command line: native backlight control, and TRIM through LUKS.
rebuild=0
if ! sudo cmp -s "$repo/files/etc/limine-entry-tool.d/macbook.conf" /etc/limine-entry-tool.d/macbook.conf 2>/dev/null; then
  install_file /etc/limine-entry-tool.d/macbook.conf 644
  rebuild=1
fi
if (( trim )) && grep -q "cryptdevice=" /etc/default/limine && ! grep -q ":allow-discards" /etc/default/limine; then
  echo "Enabling TRIM through LUKS (backup: /etc/default/limine.bak)"
  sudo cp /etc/default/limine /etc/default/limine.bak
  sudo sed -i -E 's/(cryptdevice=[^ "]*:root)([ "])/\1:allow-discards\2/' /etc/default/limine
  rebuild=1
fi
if (( rebuild )); then
  sudo limine-update
  changed=1
fi

if (( changed )); then
  echo "Done. Reboot to apply the changes."
else
  echo "Nothing to do: every fix is already in place."
fi
