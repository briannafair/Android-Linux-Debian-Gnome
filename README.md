# Debian GNOME for Termux

This project provides a Bash installer for running a Debian 13 GNOME desktop on Android through Termux, PRoot-Distro, and Termux:X11. It configures a focused desktop environment with PulseAudio support and optional Qualcomm Adreno GPU acceleration through Freedreno/KGSL and Turnip.

## What it installs

- A Debian 13 PRoot container
- A compact GNOME desktop environment
- Termux:X11 display integration
- PulseAudio connectivity between Termux and Debian
- Firefox ESR and common command-line utilities
- Optional KGSL/Turnip acceleration on supported ARM64 Adreno devices

The installer also creates start, stop, and shell launchers and installs convenient commands in Termux's executable path.

## Requirements

- Android with [Termux](https://github.com/termux/termux-app/releases) installed
- The separate [Termux:X11](https://github.com/termux/termux-x11) Android application
- An active internet connection
- Sufficient storage for Debian and GNOME

## Installation

```bash
curl -fLO https://raw.githubusercontent.com/briannafair/Android-Linux-Debian-Gnome/refs/heads/main/install-debian-gnome-gpu.sh
```

Then run the installer from Termux:

```bash
chmod +x install-debian-gnome-gpu.sh
./install-debian-gnome-gpu.sh
```

During installation, you can enter a lowercase username for the Debian desktop and command-line sessions. Press Enter without entering a name to use the default `root` account. When a regular account is selected, the installer adds it to the `sudo` group and prompts for a Debian password when needed. It also adds the account to available audio, video, rendering, and device-access groups.

The following commands are available immediately after installation:

```text
debian        Start the Debian GNOME desktop
debian-shell  Open a Debian command-line session
debian-stop   Stop the desktop session
```

## Notes

GNOME runs without systemd inside PRoot, so some features available on a conventional Debian installation may be limited. GPU acceleration is device-dependent; unsupported devices use Mesa's normal software fallback.

## Troubleshooting

If `debian` reports that Debian system D-Bus could not start, update the
installer and run it again so the launchers are regenerated:

```bash
curl -fL -o install-debian-gnome-gpu.sh \
  "https://raw.githubusercontent.com/briannafair/Android-Linux-Debian-Gnome/refs/heads/main/install-debian-gnome-gpu.sh?$(date +%s)"
chmod +x install-debian-gnome-gpu.sh
./install-debian-gnome-gpu.sh
```

The installer reuses the existing `debian-gnome` container; rerunning it does
not create another Debian installation. The launcher starts GNOME and its
D-Bus compatibility service in one regular-user PRoot session and prints the
connection-test error if that service cannot respond.

The launcher uses GPU acceleration for GNOME Shell while selecting GTK's Cairo
renderer for application windows. This avoids invisible GTK4 windows on
Termux:X11 systems where Mesa-EGL cannot obtain a normal DRI3 render device.
It also disables Mutter's experimental framebuffer scaling and forces 1x X11
coordinates, preventing application windows from being placed outside the
visible Android workspace.

On high-density Samsung displays the launcher configures Termux:X11 for
`scaled` resolution at 200%, producing a logical-pixel framebuffer instead of
the observed 2x native framebuffer. To select another scale for a different
display, start the desktop with, for example:

```bash
TERMUX_X11_DISPLAY_SCALE=150 debian
```
