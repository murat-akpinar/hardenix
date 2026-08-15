# hardenix

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-1a1a1a?style=flat-square&labelColor=1a1a1a&color=8a6f3a)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-1a1a1a?style=flat-square&labelColor=1a1a1a&color=d8b66b)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4a9e6b)](https://github.com/murat-akpinar/hardenix)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4eaa25&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![OpenSCAP](https://img.shields.io/badge/OpenSCAP-1.3%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=cc0000)](https://www.open-scap.org)
[![Python](https://img.shields.io/badge/Python-3.8%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=3776ab&logo=python&logoColor=white)](https://www.python.org)
[![Distros](https://img.shields.io/badge/distros-9%20supported-1a1a1a?style=flat-square&labelColor=1a1a1a&color=e95420)](https://github.com/murat-akpinar/hardenix/tree/main/profiles)

> Turkish version: [README_TR.md](README_TR.md)

OpenSCAP-based Linux hardening **and vulnerability management** tool. A single
script handles three complementary layers of security from one YAML profile:

1. **Compliance hardening** — CIS / ANSSI / STIG configuration baselines (`--scan-compliance`, `--apply`).
2. **Security auditing** — Lynis second-opinion audit with a 0-100 hardening index (`--scan-lynis`).
3. **Vulnerability management** — known-CVE scanning against vendor OVAL feeds and
   security patching (`--scan-cve`, `--fix-cve`).

Plain `--scan` runs all read-only layers in one go.

Built for the **golden-image workflow**: harden a blank server template, bake it
into your base image, then layer applications on top.

---

## Features

### Compliance hardening
- **`--scan`** — Full posture scan: compliance (CIS/ANSSI/STIG) + Lynis audit + known CVEs; HTML/JSON report + score (`--scan-compliance` = compliance layer only)
- **`--apply`** — Apply hardening; backs up first, then shows before/after score
- **`--unapply`** — Revert hardening to the exact pre-apply state (configs **and**
  packages the hardening removed; keeps OpenSCAP and any apps it added)
- **`--dry-run`** — Show failing rules by severity without changing anything
- **`--level 1|2`** — CIS Level 1 (basic) or Level 2 (strict, default)

### Vulnerability management (CVE)
- **`--scan-cve`** — Scan installed packages for **known CVEs** using the vendor
  OVAL feed (e.g. Ubuntu USN); severity-grouped summary + HTML report
- **`--fix-cve`** — Install **only** the available security updates, then verify

### Audit — second opinion (Lynis)
- **`--scan-lynis`** — [Lynis](https://github.com/CISOfy/lynis) system audit:
  hardening index (0-100), warnings and suggestions — an OpenSCAP-independent
  second opinion (and the only audit engine available on Arch)
- Plain **`--scan`** now runs every read-only layer in one go: compliance +
  Lynis + CVE. Missing layers are skipped with a warning; use
  `--scan-compliance` for the old single-engine behavior. `--min-score` still
  gates the compliance score only.

### Safety & automation
- **`--deadman <min>` / `--confirm`** — Dead-man switch: auto-revert after N minutes
  unless you confirm — makes **remote** hardening safe against SSH lockout
- **`--yes`** — Non-interactive (CI / unattended runs)
- **`--min-score <N>`** — Exit non-zero if compliance score is below N (CI gate)
- **Running-service protection** — Detects active services (NFS/SMB, **Apache/nginx**)
  and offers to exclude the rules that would remove/disable them
- **Setup** — `--install` (OpenSCAP + SCAP content + Lynis) / `--uninstall` (revert, then remove)

### Built-in
- **Exclusions** (rules / services / paths), **hooks** (pre/post/rollback),
  **XCCDF tailoring** auto-generated from the profile

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
| Arch Linux | sysctl + SSH hardening + Lynis audit | — | Bash fallback |

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
git clone https://github.com/murat-akpinar/hardenix.git
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
- Installs Lynis for the second-opinion audit (best-effort; retry alone with `--install-lynis`)

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

# Run a full posture scan (compliance + Lynis audit + CVE)
sudo ./linuxharden.sh --scan

# Generate HTML + JSON report
sudo ./linuxharden.sh --scan --format both

# Lynis audit only (hardening index + warnings)
sudo ./linuxharden.sh --scan-lynis

# Scan installed packages for known CVEs (OVAL feed)
sudo ./linuxharden.sh --scan-cve

# Install available security updates, then re-scan to verify
sudo ./linuxharden.sh --fix-cve
sudo ./linuxharden.sh --scan-cve

# Remove OpenSCAP packages entirely (reverts hardening first)
sudo ./linuxharden.sh --uninstall

# Use a local .yml profile
sudo ./linuxharden.sh --scan --conf ./profiles/ubuntu-22.04.yml
```

### Safe remote hardening (dead-man switch)

When hardening a box you reach over SSH, arm the dead-man switch so it reverts
itself if the changes lock you out:

```bash
# Apply, then auto-revert in 10 min unless you confirm you still have access
sudo ./linuxharden.sh --apply --deadman 10

# Still logged in? Keep the changes and cancel the auto-revert:
sudo ./linuxharden.sh --confirm
```

### Automation / CI

```bash
# Unattended apply (no prompts) — e.g. in a Packer/cloud-init build
sudo ./linuxharden.sh --apply --level 2 --yes

# Fail the pipeline if compliance drops below a threshold
sudo ./linuxharden.sh --scan --min-score 90 || echo "below baseline — blocking deploy"
```

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--install` | Installs OpenSCAP + SCAP content + Lynis for the detected distro |
| `--install-openscap` | Installs only OpenSCAP + SCAP content |
| `--install-lynis` | Installs only Lynis (RHEL family: requires EPEL) |
| `--uninstall` | Reverts hardening, then removes OpenSCAP + SCAP packages |
| `--apply` | Applies hardening (backup → apply → verify) |
| `--unapply` | Reverts hardening to the pre-apply state (keeps OpenSCAP installed) |
| `--scan` | Full posture scan: compliance + Lynis audit + known CVEs (missing layers skipped) |
| `--scan-compliance` | Compliance scan only (OpenSCAP) |
| `--scan-lynis` | Lynis audit only: hardening index (0-100) + warnings |
| `--scan-cve` | Scans installed packages for known CVEs via the vendor OVAL feed |
| `--fix-cve` | Installs only the available security updates |
| `--dry-run` | Shows failing rules grouped by severity, does not apply (implies `--apply`) |
| `--level <1\|2>` | Hardening level: `1` = CIS Level 1 (basic), `2` = CIS Level 2 (strict, default) |
| `--format <type>` | `html` \| `json` \| `both` (default: html) |
| `--deadman <min>` | With `--apply`: auto-revert after `<min>` minutes unless `--confirm` |
| `--confirm` | Cancel a pending dead-man auto-revert (keep the hardening) |
| `--yes` | Skip confirmation prompts (non-interactive / CI) |
| `--full` | Print every finding instead of trimming the listing to the screen |
| `--keep <N>` | With `--apply`: keep only the newest N backups (default 5, `0` keeps all) |
| `--refresh-feed` | Re-download the OVAL feed instead of using the 24 h cache |
| `--min-score <N>` | Exit non-zero if the `--scan` score is below N (CI gate) |
| `--conf <file>` | Use a local .yml profile file |

### Console-friendly output

`--scan` is meant to be read on the machine's own console, where there is no
scrollback. It ends with a **single posture box** carrying all three layers plus
the findings that matter:

```
  ┌─ hardenix 1.3.0 · Ubuntu 24.04.4 LTS · CIS Level 1 (basic) ───┐
  │  Compliance   92.9 %    245 pass · 19 fail                    │
  │  Lynis        58/100    12 warnings · 41 suggestions          │
  │  CVE          340       8 critical · 44 high · 92 advisories  │
  ├───────────────────────────────────────────────────────────────┤
  │  HIGH    package_telnetd_removed                              │
  │  HIGH    sshd_disable_root_login                              │
  │  MEDIUM  mount_option_tmp_nodev                               │
  │  … +126 more failing rules                                    │
  ├───────────────────────────────────────────────────────────────┤
  │  reports/scan_20260815_141230.html                            │
  └───────────────────────────────────────────────────────────────┘
```

The listing is sized to the terminal, so the box always fits one screen, and the
ASCII banner collapses to one line on short terminals.

**Nothing is dropped when output is not a terminal.** Redirect it, pipe it or run
it in CI and the box lists *every* failing rule; `--full` does the same on a
terminal. `--format json` is unaffected either way. Single-layer modes
(`--scan-compliance`, `--scan-lynis`, `--scan-cve`) keep their own summary boxes
and their original grouped-by-severity listing.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success (including `--help`) |
| `1` | Error: usage error, unknown/conflicting flag, missing dependency, no usable backup, failed backup, failed patching |
| `2` | `--min-score N` gate: the compliance score is below the threshold |

A usage error always exits non-zero, so a typo'd flag fails a pipeline instead of
looking like a clean run. `--apply` exits `0` on success whether or not
`--deadman` was given.

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
  # Vendor OVAL feed for --scan-cve (Ubuntu USN shown; .bz2/.gz auto-decompressed)
  oval_url: https://security-metadata.canonical.com/oval/com.ubuntu.jammy.usn.oval.xml.bz2
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

hooks:
  pre_hardening:  ""  # Runs before --apply
  post_hardening: ""  # Runs after --apply
  on_rollback:    ""  # Runs during --unapply
```

---

## Backup & rollback

`--apply` always takes a backup under `/var/lib/linuxharden/<date>/` before making
any changes. The archive is **verified before the first change** — a `tar` failure,
an unreadable archive or a missing path aborts the apply while the system is still
untouched. The newest **5** backups are kept (`--keep N`, `--keep 0` keeps all);
the one `latest` points at is never pruned.

```
/var/lib/linuxharden/
├── 20260524_153000/
│   ├── configs.tar.gz          # All backed-up config directories
│   ├── services_enabled.txt    # Enabled services at backup time
│   ├── packages.txt            # Installed packages at backup time
│   ├── manifest.conf           # Metadata (distro, profile, hook info)
│   ├── profile.yml             # Copy of the profile at that time
│   ├── pre_hardening.arf       # Scan before applying
│   └── post_hardening.arf      # Scan after applying
└── latest -> 20260524_153000/  # Symlink used by --unapply / --uninstall
```

`--unapply` restores the system to its **exact** pre-apply state:

- Config files are restored *exactly* — files the hardening **created** in a
  backed-up directory are removed (a plain `tar x` would leave them behind).
- Packages the hardening **removed** are reinstalled.
- Service enable/disable state is restored (masked units are unmasked first).
- Packages the hardening **added** and OpenSCAP itself are **kept** — `--unapply`
  reverts settings, it does not uninstall applications. Use `--uninstall` to
  revert *and* remove OpenSCAP.

---

## Reports

Saved to the `./reports/` directory:

| File | Content |
|------|---------|
| `scan_<date>.html` | Visual HTML report (oscap-report) |
| `scan_<date>.arf` | Raw ARF/XML output |
| `scan_<date>.json` | Summary: pass/fail counts, score, failed rule list |
| `cve_<date>.html` | CVE/OVAL report from `--scan-cve` |

---

## CVE / Vulnerability Scanning

Compliance hardening reduces attack surface, but it doesn't tell you which
installed packages have **known, published vulnerabilities**. `--scan-cve` covers
that second layer using the same OpenSCAP engine with the vendor's OVAL feed:

```bash
sudo ./linuxharden.sh --scan-cve
```

```
  ┌─ CVE Scan Summary ───────────────────────────┐
  │  Vulnerable CVEs       : 21                   │
  │  Fixing advisories     : 1                    │
  └──────────────────────────────────────────────┘
  8 High  ·  8 Medium  ·  5 Low

  Vulnerable CVEs:
    High      CVE-2026-31676     USN-8373-1
    High      CVE-2026-43284     USN-8373-1
    ...
```

The listing is **CVE-centric** (that's what people search for); the USN is shown
only as the advisory that ships the fix. The full list is in the HTML report.

- The OVAL feed (`scap.oval_url` in the profile) is downloaded, decompressed with
  Python (no `bzip2`/`gzip` binary needed), and cached for 24h.
- `--fix-cve` then installs only the available **security** updates; re-run
  `--scan-cve` to confirm they're cleared.
- **A kernel fix is not live until you reboot.** `--fix-cve` says so explicitly
  when the machine is still running an older kernel than the one it just
  installed — until the reboot the box remains exposed and `--scan-cve` keeps
  reporting those CVEs. That is accurate, not a stale result.
- The feed is cached for 24 h; pass **`--refresh-feed`** to re-download it. A
  vendor publishes advisories daily, so a cached feed can be a day behind.

> Pair this with scheduled runs to catch the steady stream of new CVEs, and use
> `--min-score` / exit codes to gate deployments in CI.

---

## Test Results

End-to-end runs (scan → apply → unapply → CVE scan) on real machines:

### Ubuntu 24.04.4 LTS
- Kernel `6.8.0-generic` · oscap 1.3.9 · profile `cis_level2_server` / `cis_level1_server`
- **`--scan` (baseline, Level 2):** 65.2 % — 242 pass / 129 fail
- **`--apply --level 1`:** 68.5 % → **93.7 %** (+25.2)
- **`--unapply`:** restores config exactly + reinstalls removed packages
- **`--scan-cve`** (Canonical USN OVAL): 0 CVEs on a fully-patched box (matches `apt`).
  Detection verified by downgrading `curl` → **8 advisories / 27 CVEs** caught;
  **`--fix-cve`** patched them → back to 0.
- **v1.2.0 (Lynis) validation run:**
  - **`--install`** set up OpenSCAP + SSG + **Lynis** in one shot
  - **`--scan` (combined):** compliance 65.5 % + Lynis hardening index **58/100**
    + 340 known CVEs in a single run; `--min-score 99` exited 2 with all three
    layers still executed (the gate is enforced last)
  - **`--apply --level 1 --deadman 15`:** 68.5 % → **93.4 %**; `--confirm`
    cancelled the timer; `--unapply` → 67.0 %
  - Stale-report guard: with lynis broken mid-cycle, `--scan-lynis` failed
    loudly (exit 1) instead of re-printing the previous index

### Rocky Linux 9.8 (Blue Onyx)
- Kernel `5.14.0-687.10.1.el9_8` · oscap 1.3.13 · profile `cis` / `cis_server_l1`
- **`--scan` (baseline, Level 2):** 47.4 % — 191 failing rules
- **`--apply --level 1`:** 58.7 % → **98.1 %** (+39.4)
- **`--scan-cve`** (native `dnf updateinfo` errata): **39 CVEs / 7 advisories**
  (34 Important · 5 Moderate) — OVAL is not used on RHEL rebuilds (it over-reports).
- **v1.2.0 (Lynis) validation run:**
  - **`--install` without EPEL:** degrades gracefully — warning + EPEL hint,
    **exit 0** (compliance/CVE features unaffected); after `epel-release`,
    `--install-lynis` installed Lynis 3.1.7
  - **`--scan` (combined):** compliance 47.1 % + Lynis hardening index **66/100**
    + CVEs via native `dnf updateinfo` in a single run

> Numbers vary with how up to date the machine is; CVE counts reflect pending
> vendor security advisories at scan time.

---

## Warnings

> **Root privileges required.** The script must be run with `sudo`.

- `--apply` may modify SSH settings and system services. When hardening over SSH,
  use **`--apply --deadman <min>`** so the box reverts itself if you get locked out.
- A **reboot is recommended** after `--unapply` for a complete rollback.
- `--uninstall` reverts hardening **first**, then removes OpenSCAP packages.
- Arch Linux has no SSG support; basic `sysctl` + SSH hardening is applied instead.
- `--dry-run` and `--scan` / `--scan-cve` write nothing to the system and are safe to use.
