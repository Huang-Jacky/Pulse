# Pulse

[🇨🇳 中文](README.md) · [🇬🇧 English](README_EN.md)

---

Pulse is a lightweight macOS menu bar system monitoring tool.

It lives in your menu bar, showing key system metrics at a glance. Click to open a full detail panel — built for anyone who wants to keep an eye on their Mac's state without the clutter of a full‑screen app.

## Requirements

- macOS 13 or later
- Apple Silicon Mac only (M1 / M2 / M3 / M4 and later)
- Intel Mac is not supported

## Features

### System Monitoring

| Category | Metrics |
| --- | --- |
| **CPU** | Total usage · Per‑core usage · User/System/Nice/Idle breakdown · Load 1m/5m/15m · Uptime · History chart |
| **Memory** | Used / Total · Active · Wired · Compressed · Free · Inactive · Swap used / total · Page In / Out · Pressure level · History chart |
| **Disk** | Usage % · Total / Used / Available · Read & Write rates · Total I/O · Mounted volumes · I/O history chart |
| **Network** | Download / Upload rates · Per‑interface throughput · Total transfer · Wi‑Fi signal / channel / PHY mode / link rate · Proxy detection · VPN detection · Interface type identification · History chart |
| **GPU** | Utilization % · Model name · History chart |
| **Battery** | Charge level · Charging / Discharging · Time remaining · Health ratio · Cycle count · Adapter wattage · Temperature |
| **Processes** | Top 6 by CPU / Memory consumption |
| **System Info** | macOS version · Build number · Kernel version · Hardware model · Chip name · Total memory · Core topology (dynamic P/E core naming) · Host name · User name · Hardware UUID · Serial number |

### Menu Bar

- SF Symbols icons + value display
- Standard / Compact layout, auto‑fallback when space is tight
- Network traffic: dual‑line or single‑line layout
- Drag‑to‑reorder metric position
- Value color tracks alert level (normal / warning / critical)

### Dashboard Panel

- 7 tabs: CPU · GPU · Memory · Disk · Battery · Network · Settings · System Info
- Each tab has a HeroCard overview + SectionCard breakdown + history bar chart
- CPU stacked chart · GPU / Memory single‑value chart · Dual‑direction network chart · Disk I/O chart
- Unified dark theme

### Settings

- Enable / disable individual metrics (at least one required)
- Status bar ordering · Display mode · Network layout
- Refresh interval: 1–30 seconds
- Adaptive power saving — lowers sample rate when on battery or Low Power Mode
- Launch at login (SMAppService)
- Bilingual: Chinese / English, with live UI refresh
- Built‑in GitHub update checker

## Architecture

- **Swift 6** · SwiftUI + AppKit hybrid
- **Zero external dependencies** — reads system data directly through Darwin / IOKit / SystemConfiguration / CoreWLAN
- **Actor‑isolated sampler** for thread safety
- **Adaptive refresh**: panel open → 1s, on battery → ≥3s, Low Power Mode → ≥5s
- Full bilingual support (Chinese / English)

## License

Copyright © 2026 jackey.huang
