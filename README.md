# Debian GNOME for Termux

This project provides a Bash installer for running a Debian 13 GNOME desktop on Android through Termux, PRoot-Distro, and Termux:X11. It configures a focused desktop environment with PulseAudio support and optional Qualcomm Adreno GPU acceleration through Turnip and Zink.

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
