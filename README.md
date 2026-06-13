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

- **`--install`** — Automatically installs OpenSCAP and SCAP content for the detected distro; downloads from GitHub for distros with outdated repos (e.g. Ubuntu 24.04)
- **`--uninstall`** — Removes OpenSCAP + SCAP packages installed by `--install`
- **`--apply`** — Applies hardening; takes a backup first, then shows before/after score
- **`--unapply`** — Reverts hardening changes from the latest backup
- **`--scan`** — Compliance scan with CIS/ANSSI/STIG profile, generates HTML/JSON report
- **`--dry-run`** — Shows failing rules grouped by severity without touching the system
- **`--level`** — Picks the hardening level: `1` = CIS Level 1 (basic), `2` = CIS Level 2 (strict, default)
- **Exclusions** — Skip specific rules, services, or paths
- **Hooks** — Run custom scripts before/after hardening and on rollback
- **XCCDF Tailoring** — Exclusion rules are automatically converted to a tailoring file

---

## Supported Distributions

`--level 2` (default) selects the strict baseline; `--level 1` selects the basic one.

| Distribution | Level 2 — strict (default) | Level 1 — basic (`--level 1`) | Engine |
|--------------|----------------------------|-------------------------------|--------|
| Ubuntu 22.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Ubuntu 24.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Debian 12 | ANSSI BP-028 Enhanced | Standard | SSG |
| RHEL 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Rocky Linux 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| AlmaLinux 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Fedora 40 | OSPP | Standard | SSG |
| openSUSE Leap 15 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Arch Linux | sysctl + SSH hardening | — | Bash fallback |

> Debian and Fedora ship no CIS profile in SSG, so they use ANSSI BP28 / OSPP.
> Here `--level 2` means "strict baseline" and `--level 1` means "light baseline".

---

## Hardening Levels

| | **Level 1** (`--level 1`) | **Level 2** (`--level 2`, default) |
|---|---|---|
| Goal | Basic security for everyday use | High security / regulated environments |
| Impact | Practical, low risk of breakage | May restrict some functionality |
| Examples | Password policy, file permissions | Mandatory auditing (auditd), mount restrictions, extra service removal |
| Typical user | Most servers | Finance, government, sensitive data |

```bash
sudo ./linuxharden.sh --apply --level 1    # basic
sudo ./linuxharden.sh --apply --level 2    # strict (default)
```

> `--level` is the single way to choose the baseline; when omitted it defaults to level 2 (strict).
> Running `--apply` with no level defaults to Level 2 (strict).

---

## Installation

```bash
git clone https://github.com/YOUR_GITHUB_USER/hardenix.git
cd hardenix
chmod +x linuxharden.sh

# Install OpenSCAP + SCAP content automatically (works on all supported distros)
sudo ./linuxharden.sh --install
```

`--install` handles the following automatically:

- Detects the distro and package manager (`apt-get` / `dnf` / `zypper` / `pacman`)
- Enables the `universe` repo on Ubuntu
- Installs `openscap` and the appropriate SSG package for the distro
- Downloads SCAP content from GitHub for distros whose repos are too old (e.g. Ubuntu 24.04 lacks `ssg-ubuntu2404-ds.xml` in `ssg-debderived` 0.1.71)

---

## Usage

```bash
# 1. Install dependencies (first time only)
sudo ./linuxharden.sh --install

# 2. Preview what would change — does not touch the system
sudo ./linuxharden.sh --dry-run

# 3. Apply hardening (backup → apply → verify)
sudo ./linuxharden.sh --apply

# Choose the hardening level explicitly
sudo ./linuxharden.sh --apply --level 1     # CIS Level 1 (basic)
sudo ./linuxharden.sh --apply --level 2     # CIS Level 2 (strict)

# Revert hardening (restores configs from backup)
sudo ./linuxharden.sh --unapply

# Run a compliance scan
sudo ./linuxharden.sh --scan

# Generate HTML + JSON report
sudo ./linuxharden.sh --scan --format both

# Remove OpenSCAP packages entirely
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
| `--install` | Installs OpenSCAP + SCAP content for the detected distro |
| `--uninstall` | Removes OpenSCAP + SCAP packages |
| `--apply` | Applies hardening (backup → apply → verify) |
| `--unapply` | Reverts hardening settings from the latest backup |
| `--scan` | Compliance scan, generates report |
| `--dry-run` | Shows failing rules grouped by severity, does not apply (implies `--apply`) |
| `--level <1\|2>` | Hardening level: `1` = CIS Level 1 (basic), `2` = CIS Level 2 (strict, default) |
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
    production:  xccdf_org.ssgproject.content_profile_cis_level2_server  # --level 2
    development: xccdf_org.ssgproject.content_profile_cis_level1_server  # --level 1

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
  pre_hardening:  ""  # Runs before --apply
  post_hardening: ""  # Runs after --apply
  on_rollback:    ""  # Runs during --unapply
```

---

## Backup

`--apply` always takes a backup under `/var/lib/linuxharden/<date>/` before making any changes (`--unapply` restores from this backup):

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

- `--apply` may modify SSH settings and system services.
- A **reboot is recommended** after `--unapply` for a complete rollback.
- `--uninstall` removes packages only; run `--unapply` first if you also want to revert hardening settings.
- Arch Linux has no SSG support; basic `sysctl` + SSH hardening is applied instead.
- `--dry-run` writes nothing to the system and is safe to use.
