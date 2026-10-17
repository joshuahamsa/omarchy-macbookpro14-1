# Omarchy on the MacBookPro14,1

Fixes that make a 13" 2017 MacBook Pro without Touch Bar (MacBookPro14,1, A1708) fully work on [Omarchy](https://github.com/omacom/omarchy) 4.0. Tested on Omarchy 4.0.4-1 with kernel `7.2.5-3-omarchy`.

```bash
git clone https://github.com/joshuahamsa/omarchy-macbookpro14-1.git
cd omarchy-macbookpro14-1
./install.sh
```

Then reboot. The script is safe to re-run: it only changes what is missing, and says so when there is nothing to do. It refuses to run on another model unless you pass `--force`. Pass `--no-trim` to skip enabling TRIM.

## What it fixes

| Problem | Fix | Status |
|---|---|---|
| Lid-close sleep never wakes; a forced power-off is the only way out | Sleep hook that removes the Thunderbolt controller before suspend and rescans the PCI bus on wake | Verified, including a 22-hour overnight sleep |
| Speakers silent | Out-of-tree CS8409 driver ([davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)), with codec power saving off | Verified |
| Speakers silent after sleep | Patch to the driver's resume path, re-applied automatically on every driver update | Verified |
| No camera | FaceTime HD driver and firmware ([facetimehd](https://github.com/patjak/facetimehd)) | Verified, survives sleep |
| No TRIM on the encrypted SSD | `allow-discards` on the LUKS device | Verified |
| Screen stays dark after wake | `acpi_backlight=native` | Precautionary, see below |

Wi-Fi, Bluetooth, the keyboard, USB-C and the microphone work with Omarchy's own fixes.

## Details

### Sleep

Both deep sleep and s2idle hung with the journal ending at `PM: suspend entry`. Bisecting with `/sys/power/pm_test` showed `freezer` and `devices` completing, and `platform` hard-hanging: the Alpine Ridge Thunderbolt controller wedges the late suspend phase.

[`apple-thunderbolt-detach`](files/usr/lib/systemd/system-sleep/apple-thunderbolt-detach) removes the controller's upstream bridge (`8086:1578`) before sleep, which takes the whole Thunderbolt tree with it, and rescans the PCI bus on wake. Deep sleep then works with no change to the sleep mode or CPU idle states. The trade-off: anything plugged into USB-C is disconnected and reconnected across each sleep.

Reported in [omacom/omarchy#15630](https://github.com/omacom/omarchy/issues/15630).

### Speakers

The in-kernel `snd-hda-codec-cs8409` does not drive the 14,1's amplifiers, so the speakers are silent. The AUR package `snd-hda-macbookpro-dkms-git` replaces it with a patched build.

That driver has two more problems, both fixed here:

- With `snd_hda_intel` power saving on, the codec suspends when idle and comes back without its amp setup. [`macbook-audio.conf`](files/etc/modprobe.d/macbook-audio.conf) turns it off.
- Sleep powers off the codec and amplifiers, and the driver's resume code never sets them up again. [`cs8409-resume.diff`](files/usr/local/share/macbook-fixes/cs8409-resume.diff) makes resume re-run the boot-time setup. This is the same fix as the unmerged upstream [PR #198](https://github.com/davidjo/snd_hda_macbookpro/pull/198).

A pacman hook ([`60-cs8409-resume-patch.hook`](files/etc/pacman.d/hooks/60-cs8409-resume-patch.hook)) re-applies the patch whenever the driver package is installed or updated, before DKMS rebuilds the module. If upstream merges an equivalent fix, the hook notices and skips. If the patch stops applying, pacman prints a warning.

Don't reload `snd_hda_intel` or write to `/sys/class/sound/hwC0D0/reconfig` while the system is running. A codec reset loses the subsystem ID that Apple's firmware sets at boot, so the driver no longer recognizes the codec, and audio is gone until a reboot.

### Camera

`facetimehd-dkms`, `facetimehd-firmware` and `facetimehd-data` from the AUR, with `bdc_pci` blacklisted so it doesn't claim the camera first.

### TRIM

Adds `:allow-discards` to the `cryptdevice=` entry in `/etc/default/limine` and rebuilds the boot images, keeping a backup at `/etc/default/limine.bak`. TRIM through LUKS leaks which blocks are unused, a known trade-off for SSD health and performance. Skip it with `--no-trim`.

### Backlight

`acpi_backlight=native` lets i915 control the panel backlight. It was added while chasing a dark screen after wake, before the Thunderbolt hang turned out to be the cause. It does no harm, but it may not be needed.

## Uninstalling

Remove the files listed under [`files/`](files) from the same paths, remove the AUR packages, take `:allow-discards` out of `/etc/default/limine` if you want, and run `sudo limine-update`.
