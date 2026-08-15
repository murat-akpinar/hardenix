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

## Quick start

```bash
git clone https://github.com/murat-akpinar/hardenix.git && cd hardenix

sudo ./linuxharden.sh --install     # 1. install the scan engines (once)
sudo ./linuxharden.sh --scan        # 2. where do we stand?
sudo ./linuxharden.sh --dry-run     # 3. what would --apply change?
sudo ./linuxharden.sh --apply       # 4. harden — takes a backup first
sudo ./linuxharden.sh --unapply     #    changed your mind? roll it back
```

Hardening a machine you reach over SSH? Add **`--deadman 15`** so it reverts
itself if the changes lock you out — see
[safe remote hardening](#safe-remote-hardening-dead-man-switch).

Five modes and five options cover almost every run, and that is exactly what
`--help` prints. The complete surface is one command away:

```bash
./linuxharden.sh --help        # the everyday set — fits one screen
./linuxharden.sh --help all    # every mode and option, grouped
```

---

## What it does

| Layer | The question it answers | Modes |
|-------|-------------------------|-------|
| **Compliance hardening** | Is this box configured to a recognised baseline? | `--apply` · `--unapply` · `--scan-compliance` |
| **Security audit** | What does a second, independent engine think? | `--scan-lynis` |
| **Vulnerability management** | Which installed packages have published CVEs? | `--scan-cve` · `--fix-cve` |

`--scan` runs all three read-only layers in one pass and ends with a single
posture box. A missing engine is skipped with a warning instead of failing the
run; `--min-score` gates the compliance score only.

### Hardening — `--apply` / `--unapply`

- Backs up **before** the first change, then re-scans and reports the
  before/after score
- `--unapply` restores the **exact** pre-apply state: configs byte-for-byte,
  service enable/disable state, and the packages hardening removed. Packages it
  *added* — and OpenSCAP itself — are kept: this reverts settings, it does not
  uninstall applications
- `--dry-run` lists the failing rules by severity and changes nothing
- `--level 1` = basic, `--level 2` = strict (default)

### Vulnerability management — `--scan-cve` / `--fix-cve`

- Checks installed packages against the vendor OVAL feed (e.g. Canonical USN);
  RHEL rebuilds use native `dnf updateinfo` instead, which does not over-report
- Severity-grouped summary + HTML report; `--fix-cve` installs **only** the
  security updates, then verifies

### Audit — `--scan-lynis`

- [Lynis](https://github.com/CISOfy/lynis) hardening index (0-100), warnings and
  suggestions — an OpenSCAP-independent second opinion, and the only audit engine
  available on Arch

### Safety

- **Dead-man switch** (`--deadman <min>` / `--confirm`) — auto-reverts unless you
  confirm you still have access. This is what makes hardening over SSH survivable.
- **SSH lockout warning** — the baseline sets `PermitRootLogin no`, so hardening a
  box you reached as root over SSH closes the door you came in through. `--apply`
  and `--dry-run` say so by name before the prompt, and check whether any non-root
  account with `sudo`/`wheel` **and** an SSH key would survive it. If none would,
  they say the console is the only way back.
- **Running-service protection** — detects active services (NFS/SMB,
  **Apache/nginx**) and offers to exclude the rules that would remove or disable them
- **Read-only means read-only** — every scan mode and `--dry-run` write nothing
  to the system
- `--yes` for unattended runs, `--min-score <N>` to gate a pipeline

### Built in

Per-profile **exclusions** (rules / services / paths), **hooks** (pre-hardening /
post-hardening / on-rollback), and an **XCCDF tailoring** file generated from the
profile.

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

Split the same way `--help` is: the everyday set first, everything else behind
the fold.

### Everyday

| Parameter | Description |
|-----------|-------------|
| `--install` | Installs the scan engines: OpenSCAP + SCAP content + Lynis |
| `--scan` | Full posture scan: compliance + Lynis audit + known CVEs (missing layers skipped) |
| `--apply` | Applies hardening (backup → apply → verify) |
| `--unapply` | Reverts to the pre-apply state (keeps OpenSCAP installed) |
| `--fix-cve` | Installs only the available security updates |
| `--level <1\|2>` | Hardening level: `1` = CIS Level 1 (basic), `2` = CIS Level 2 (strict, default) |
| `--dry-run` | Shows what `--apply` would change, grouped by severity — changes nothing |
| `--yes` | Assumes yes for every prompt (non-interactive / CI) |
| `--deadman <min>` | With `--apply`: auto-revert after `<min>` minutes unless `--confirm` |
| `--confirm` | Keeps the hardening — cancels a pending auto-revert |

<details>
<summary><b>Everything else</b> — single-layer scans, reporting, CI, tuning</summary>

**Run a single layer.** `--scan` already runs all three; reach for these when you
want one of them on its own.

| Parameter | Description |
|-----------|-------------|
| `--scan-compliance` | Compliance scan only (OpenSCAP) |
| `--scan-lynis` | Lynis audit only: hardening index (0-100) + warnings |
| `--scan-cve` | Known-CVE scan only (vendor OVAL feed, or `dnf` errata on RHEL rebuilds) |
| `--install-openscap` | Installs only OpenSCAP + SCAP content |
| `--install-lynis` | Installs only Lynis (RHEL family: requires EPEL) |
| `--uninstall` | Reverts hardening, then removes OpenSCAP + SCAP packages |

**Reporting and CI**

| Parameter | Description |
|-----------|-------------|
| `--format <type>` | `html` \| `json` \| `both` (default: html) |
| `--min-score <N>` | Exit `2` if the compliance score is below N (CI gate) |
| `--full` | Print every finding instead of trimming the listing to the screen |

**Tuning**

| Parameter | Description |
|-----------|-------------|
| `--keep <N>` | With `--apply`: keep only the newest N backups (default 5, `0` keeps all) |
| `--refresh-feed` | Re-download the OVAL feed instead of using the 24 h cache |
| `--conf <file>` | Use a local .yml profile instead of the bundled one |

</details>

### Console-friendly output

`--scan` is meant to be read on the machine's own console, where there is no
scrollback. It ends with a **single posture box** carrying all three layers plus
the findings that matter:

```
  ┌─ hardenix 1.5.0 · Ubuntu 24.04.4 LTS · CIS Level 1 (basic) ──────────────┐
  │  Compliance   92.9 %    245 pass · 19 fail                               │
  │  Failing      19        2 high · 12 medium · 5 low                       │
  │  Lynis        58/100    12 warnings · 41 suggestions                     │
  │  CVE          340       8 critical · 44 high · 92 advisories             │
  ├──────────────────────────────────────────────────────────────────────────┤
  │  HIGH    package_telnetd_removed                                         │
  │  HIGH    sshd_disable_root_login                                         │
  │  MEDIUM  mount_option_tmp_nodev                                          │
  │  … +16 more failing rules                                                │
  ├──────────────────────────────────────────────────────────────────────────┤
  │  reports/scan_20260815_141230.html                                       │
  └──────────────────────────────────────────────────────────────────────────┘
```

The **Failing** row breaks the fail count down by severity. It is what makes the
trimmed listing usable: `… +16 more failing rules` on its own tells you nothing
about what is in those 16, and a count of `19 fail` is not something you can act
on — `2 high` is.

On a wide terminal the failing rules are laid out in **one column per severity**,
each with its own count and its own `… +N more`, so the box height no longer
follows whichever severity happens to dominate:

```
  ├────────────────────────────────────────────────────────────────────────┤
  │  HIGH (4)              │ MEDIUM (94)            │ LOW (22)             │
  │  grub2_password        │ account_disable_post…  │ grub2_audit_argument │
  │  grub2_uefi_password   │ accounts_maximum_age…  │ kernel_module_cramf… │
  │  no_empty_passwords…   │ … +92 more             │ … +20 more           │
```

Columns appear only where they stay readable — below 20 characters per cell a
rule name collapses to a prefix several rules share, so a narrow console and
redirected output keep the flat, severity-ordered list. The box is sized to the
terminal, so it always fits one screen, and the ASCII banner collapses to one
line on short terminals.

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
