# hardenix

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-1a1a1a?style=flat-square&labelColor=1a1a1a&color=8a6f3a)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-1a1a1a?style=flat-square&labelColor=1a1a1a&color=d8b66b)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4a9e6b)](https://github.com/YOUR_GITHUB_USER/hardenix)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4eaa25&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![OpenSCAP](https://img.shields.io/badge/OpenSCAP-1.3%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=cc0000)](https://www.open-scap.org)
[![Python](https://img.shields.io/badge/Python-3.8%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=3776ab&logo=python&logoColor=white)](https://www.python.org)
[![Distros](https://img.shields.io/badge/distros-8%20supported-1a1a1a?style=flat-square&labelColor=1a1a1a&color=e95420)](https://github.com/YOUR_GITHUB_USER/hardenix/tree/main/profiles)

> Turkish version: [README_TR.md](README_TR.md)

OpenSCAP-based Linux hardening tool. Downloads a YAML profile based on the distro; manages scanning, applying, and rolling back with a single script.

---

## Features

- **`--scan`** — Compliance scan with CIS/ANSSI/STIG profile, generates HTML/JSON report
- **`--install`** — Applies hardening; takes a backup first, then shows before/after score
- **`--uninstall`** — Rolls back all changes from the latest backup
- **`--dry-run`** — Shows what would change without touching the system
- **`--env`** — Selects `production` / `staging` / `development` profile
- **Exclusions** — Skip specific rules, services, or paths
- **Hooks** — Run custom scripts before/after hardening and on rollback
- **XCCDF Tailoring** — Exclusion rules are automatically converted to a tailoring file

---

## Supported Distributions

| Distribution | Profile (production) | Profile (development) | Engine |
|--------------|----------------------|-----------------------|--------|
| Ubuntu 22.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Ubuntu 24.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Debian 12 | ANSSI BP-028 Enhanced | Standard | SSG |
| RHEL 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Rocky Linux 9 | CIS Level 1 Server | Standard | SSG |
| AlmaLinux 9 | CIS Level 1 Server | Standard | SSG |
| Fedora 40 | OSPP | Standard | SSG |
| openSUSE Leap 15 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Arch Linux | sysctl + SSH hardening | — | Bash fallback |

---

## Installation

```bash
# Ubuntu / Debian
sudo apt-get install openscap-utils ssg-base ssg-debderived python3-yaml

# RHEL / Rocky / AlmaLinux
sudo dnf install openscap-utils scap-security-guide python3-pyyaml

# Fedora
sudo dnf install openscap-utils scap-security-guide python3-pyyaml

# openSUSE
sudo zypper install openscap scap-security-guide python3-PyYAML

# Arch
sudo pacman -S openscap python-yaml

# Make the script executable
chmod +x linuxharden.sh
```

---

## Usage

```bash
# Run a compliance scan
sudo ./linuxharden.sh --scan

# Generate HTML + JSON report
sudo ./linuxharden.sh --scan --format both

# Preview what would change (does not touch the system)
sudo ./linuxharden.sh --install --dry-run

# Use a lighter profile for development environments
sudo ./linuxharden.sh --install --env development

# Apply hardening (backup → apply → verify)
sudo ./linuxharden.sh --install

# Roll back hardening
sudo ./linuxharden.sh --uninstall

# Scan with a specific profile ID
sudo ./linuxharden.sh --scan --profile xccdf_org.ssgproject.content_profile_cis_level2_server

# Use a local .yml profile
sudo ./linuxharden.sh --scan --conf ./profiles/ubuntu-22.04.yml
```

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--scan` | Compliance scan, generates report |
| `--install` | Applies hardening (backup → apply → verify) |
| `--uninstall` | Rolls back from latest backup |
| `--dry-run` | Used with `--install`: shows changes, does not apply |
| `--env <profile>` | `production` \| `staging` \| `development` (default: production) |
| `--format <type>` | `html` \| `json` \| `both` (default: html) |
| `--profile <id>` | SCAP profile ID override |
| `--conf <file>` | Use a local .yml profile file |

---

## Profile YAML Format

```yaml
meta:
  distro: ubuntu
  version: "22.04"
  arch_fallback: false

packages:
  manager: apt-get
  oscap: openscap-utils
  ssg: ssg-base ssg-debderived

scap:
  xml_path: /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml
  profiles:
    production:  xccdf_org.ssgproject.content_profile_cis_level2_server
    staging:     xccdf_org.ssgproject.content_profile_cis_level2_server
    development: xccdf_org.ssgproject.content_profile_cis_level1_server

backup:
  config_dirs:
    - /etc/ssh
    - /etc/sysctl.d
    - /etc/security
    - /etc/pam.d

exclusions:
  rules:    []        # XCCDF rule IDs — added to tailoring file
  services: []        # Services to exclude from backup
  paths:    []        # Paths to exclude from backup
  users:    []

hooks:
  pre_hardening:  ""  # Runs before --install
  post_hardening: ""  # Runs after --install
  on_rollback:    ""  # Runs during --uninstall
```

---

## Backup

`--install` always takes a backup under `/var/lib/linuxharden/<date>/` before making any changes:

```
/var/lib/linuxharden/
├── 20260524_153000/
│   ├── configs.tar.gz          # All config directories
│   ├── services_enabled.txt    # List of active services
│   ├── manifest.conf           # Metadata (distro, profile, hook info)
│   ├── profile.yml             # Copy of the profile at that time
│   ├── pre_hardening.arf       # Scan before applying
│   └── post_hardening.arf      # Scan after applying
└── latest -> 20260524_153000/  # Symlink (--uninstall looks here)
```

---

## Reports

Saved to the `./reports/` directory:

| File | Content |
|------|---------|
| `scan_<date>.html` | Visual HTML report (oscap-report) |
| `scan_<date>.arf` | Raw ARF/XML output |
| `scan_<date>.json` | Summary: pass/fail counts, score, failed rule list |

---

## Warnings

> **Root privileges required.** The script must be run with `sudo`.

- `--install` may modify SSH settings and system services.
- A **reboot is recommended** after `--uninstall` for a complete rollback.
- Arch Linux has no SSG support; basic `sysctl` + SSH hardening is applied instead.
- `--dry-run` writes nothing to the system and is safe to use.
