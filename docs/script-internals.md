# linuxharden.sh — Internals

Single bash file (~2100 lines, `set -euo pipefail`), version in `SCRIPT_VERSION`.
Everything below is implemented and tested (✅). Line references drift; function
names are stable.

## Execution pipeline

Every invocation runs the same spine (`main()` at the bottom of the file):

```
main()
 ├─ parse_args()                # flags → MODE + runtime flags; validation
 │                              #   --help / usage errors exit here, before the
 │                              #   banner, so they start at the top of the screen
 ├─ banner()                    # version banner (one line below 30 rows)
 ├─ check_root()
 ├─ detect_distro()             # /etc/os-release → DISTRO_ID, DISTRO_VERSION;
 │                              #   prints applied level from STATE_FILE if present
 ├─ download_conf()             # pick profiles/${DISTRO_ID}-${DISTRO_VERSION}.yml
 │                              #   (or --conf override); fallback name variants
 ├─ [--install/--install-openscap/--install-lynis → run_install_deps(component); exit]
 ├─ [--confirm  → run_confirm();      exit]
 ├─ check_pyyaml() + parse_conf()     # YAML → PKG_MANAGER, XML_PATH, PROFILE_ID,
 │                                    #   OVAL_URL, BACKUP_DIRS, EXCLUSION_*, HOOK_*
 │                                    #   ARCH_FALLBACK=true → MODE remapped to *_arch
 │                                    #   and parse_conf() returns early (see below)
 ├─ XCCDF prep — skipped for unapply/uninstall/scan-cve/fix-cve/scan-lynis, and
 │    skipped *entirely* when ARCH_FALLBACK (no SCAP datastream to validate):
 │    ├─ detect_active_services()     # --apply only (scan must stay honest)
 │    ├─ check_dependencies()  ├─ validate_profile()  └─ setup_tailoring()
 └─ dispatch: run_scan_full (--scan) | run_scan (--scan-compliance)
              | run_scan_lynis | run_scan_cve | run_fix_cve | run_apply
              | run_unapply | run_uninstall | run_*_arch
```

`parse_args()` validates before anything runs: a second, different mode is a hard
error (`--scan --apply` must never silently apply), a value-taking option with no
value is a hard error (a bare `shift` past the end would otherwise kill the script
silently under `set -e`), and any usage error exits **non-zero** so a typo'd flag
fails CI instead of looking like a clean run.

### Help is tiered

23 flags on one screen is the same overwhelm problem as a 180-line scan, so the
help has two levels and errors have neither:

| Entry point | Function | Output |
|-------------|----------|--------|
| `--help`, no args | `usage()` | 5 modes, 5 options, 3 examples — **22 rows**, fits a 24-row console |
| `--help all` (or `full`) | `usage_full()` | every flag, grouped: modes · options · single layer · reporting/CI · tuning · levels · examples · exit codes |
| unknown flag, no mode | `usage_error()` | the error, one line of modes, one line pointing at `--help` |

`usage_error()` deliberately does **not** print the help: on a console with no
scrollback a 22-line dump would scroll the error message itself off the top, which
is the one line the operator needs. `usage()` still takes an exit code (`usage 1`
for a bare invocation); `usage_full()` is always `0`.

Anything added to `usage_full()` must also land in the `Parameters` tables of
`README.md` and `README_TR.md` — those are the same list in a different medium.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success, `--help` included |
| `1` | Usage error, missing dependency, no usable backup, backup failure, patch failure |
| `2` | `--min-score N` gate: compliance score below the threshold |

`--apply` returns `0` on success regardless of `--deadman`.

Key dispatch subtleties:

- **Service protection runs only for `--apply`.** `--scan`/`--scan-compliance` are
  read-only, so they report the true compliance state without offering exclusions.
- **CVE and Lynis modes skip XCCDF/profile validation** — they need only oscap+feed
  or `lynis`, never the SCAP datastream/profile.
- **Optional layers of `--scan` are non-fatal.** `run_scan_lynis`/`run_scan_cve`
  are invoked in a subshell there, so a stale Lynis report or an unreachable OVAL
  feed degrades to a warning instead of aborting the posture scan — and, worse,
  skipping the `--min-score` gate that runs last. Called directly they still
  hard-fail.
- **Arch fallback**: `meta.arch_fallback: true` reroutes `scan`/`scan_compliance`/
  `apply`/`unapply` to `run_*_arch` (basic sysctl + sshd hardening; no SSG content
  exists for Arch) and, since `parse_conf()` returns immediately after remapping,
  also skips the XCCDF prep block entirely — this is what lets `--scan`/`--apply`
  run on Arch at all instead of aborting on the profile's empty `xml_path`.

## Modes

### `--scan-compliance` / `--dry-run` (read-only)

`run_scan()`: `oscap xccdf eval` against the datastream (`scap.xml_path`) with the
active profile, results to `./reports/scan_<ts>.arf`. `get_score()` computes
`pass/(pass+fail)` from the ARF via embedded python3. Reports: HTML via
`oscap-report`, JSON summary via `generate_json_report()` (`--format html|json|both`).
`--min-score N` exits non-zero below the threshold (CI gate). `--dry-run` is the
same evaluation but prints failing rules grouped by severity and applies nothing.
This is the old single-engine `--scan` behavior, kept under its own flag.

### `--scan` (`run_scan_full()`) — combined posture scan

Runs every read-only layer in one call, in order:

1. **Compliance** — `run_scan()` (above), with `DEFER_MIN_SCORE=true` so a low
   score doesn't short-circuit the remaining layers.
2. **Lynis** — `run_scan_lynis()` (below) if `lynis` is on `PATH`; otherwise
   `log_warn`s "Lynis not installed — skipping audit layer (enable with
   `--install-lynis`)" and moves on.
3. **CVE** — `run_scan_cve()` if the package manager is `dnf`/`yum` or
   `scap.oval_url` is set; otherwise `log_warn`s "No OVAL feed configured
   (scap.oval_url) — skipping CVE layer."

It then prints **one posture box** (`print_posture_summary()`) carrying all three
headline numbers, the worst failing rules and the report path — see *Terminal-aware
output* below. In this mode the per-layer summary boxes are suppressed
(`COMBINED_SCAN=true`); the single-layer flags keep theirs.

Because the optional layers run in a subshell, they cannot report back through
globals. Each writes `key=value` lines to `POSTURE_STATS` (a file under `TMP_DIR`)
via `stat_put()`, and the posture box reads that file.

`--min-score` is enforced **once, at the end**, against the compliance ARF
(`LAST_SCAN_ARF`) — deferring it is what lets the Lynis/CVE layers run even on a
failing compliance score, and it still gates the compliance score only, never the
Lynis index or CVE count.

### `--scan-lynis` (`run_scan_lynis()`)

Exits early ("run `--install-lynis` first") if `lynis` isn't installed. Runs
`lynis audit system --quiet --no-colors`, then reads the hardening index and
counts from the report Lynis writes to `/var/log/lynis-report.dat`
(`LYNIS_REPORT_DAT`): `print_lynis_summary()` extracts `hardening_index=` via
`awk`, and counts `warning[]=` / `suggestion[]=` lines, printing the warnings
themselves. The raw `.dat` is copied to `./reports/lynis_<ts>.dat` for retention —
same convention as the compliance/CVE report files. Skipped (with a warning, not a
hard failure) when called as a layer of `--scan`; hard-fails only when invoked
directly via `--scan-lynis`.

### `--apply` (`run_apply()`)

```
warn + confirm()                        # ASSUME_YES-aware
→ run_hook(pre_hardening)
→ create_backup()                       # see Backup contract below
→ pre-hardening scan  → pre_hardening.arf  → baseline score
→ oscap xccdf eval --remediate          # the actual hardening
→ post-hardening scan → post_hardening.arf → verification score
→ print_improvement(before, after) + remaining failing rules
→ run_hook(post_hardening)
→ echo level > STATE_FILE               # /var/lib/linuxharden/applied_level
→ [--deadman N → arm_deadman(N)]
```

Both scans and the remediation write their ARF/stderr **into the backup dir**, so
every backup is a self-documenting before/after record.

### Dead-man switch (`arm_deadman()` / `run_confirm()`)

`systemd-run --unit=hardenix-deadman --on-active=<N>min bash <script> --unapply --yes`
— a transient timer, no unit files left behind. `--confirm` stops the timer/service
and `reset-failed`s it. If hardening cuts your SSH session, the box reverts itself;
if you can still log in, you confirm and keep it. Stale timers are cleared before
arming a new one.

### `--unapply` (`run_unapply()` → `revert_hardening()`)

Restores the **exact** pre-apply state from `${BACKUP_BASE}/latest`:

1. **Configs — exact restore.** `configs.tar.gz` is extracted to a staging dir;
   for each backed-up path, files that exist now but are absent from the backup
   (i.e. files the hardening *created*, like `/etc/modprobe.d/cramfs.conf`) are
   deleted, then originals are copied back with `cp -a`. A plain `tar x` would
   leave hardening drop-ins behind — this is the core trick.
2. **SELinux contexts.** On enforcing systems (RHEL family) a tar/cp restore
   mislabels files, which can freeze boot; `restorecon -RF` is run over every
   restored path.
3. **Packages.** `comm -23 backup_pkgs current_pkgs` → reinstall what hardening
   removed. Packages hardening *added* (and OpenSCAP itself) are kept — unapply
   reverts settings, it does not uninstall applications (`--uninstall` does).
4. **Services.** Diff enabled-service lists both directions: disable newly-enabled,
   re-enable originally-enabled (unmask first — hardening may have masked them).
5. **Reload.** `sysctl --system`, `systemctl daemon-reload`, restart
   sshd/ssh/auditd; run the `on_rollback` hook recorded in the backup's
   `manifest.conf`; clear `STATE_FILE`.

A reboot is recommended afterwards for kernel-level settings.

### `--scan-cve` (`run_scan_cve()`)

Two engines, chosen by package manager:

| Family | Engine | Why |
|--------|--------|-----|
| `dnf`/`yum` (RHEL, Rocky, Alma, Fedora) | `dnf updateinfo list cves --security` | Red Hat's OVAL feed over-reports on rebuilds; native errata are authoritative |
| `apt-get` / `zypper` (Ubuntu, Debian, openSUSE) | `oscap oval eval` against `scap.oval_url` | Vendor OVAL (e.g. Canonical USN) is the authoritative source |

The OVAL path (`scan_cve_oval()`): feed is downloaded with curl/wget, decompressed
by **python3** (`bz2`/`gzip` modules — no external binaries), cached under
`./reports/oval-feed/` and reused if younger than 24 h — `--refresh-feed` skips
the cache. Results are summarized
**CVE-centric** (severity-grouped; the advisory/USN shown as the fix reference),
full detail in `cve_<ts>.html`.

### `--fix-cve` (`run_fix_cve()`)

`security_updates()` lists pending *security-only* updates per package manager
(apt simulation grep, `dnf updateinfo list security`, `zypper list-patches
--category security`; Arch has no security channel → unsupported). Installs only
those, then recommends re-running `--scan-cve` to verify. The scan→fix→rescan loop
is the intended usage.

### `--install` / `--install-openscap` / `--install-lynis` / `--uninstall`

All three install flags dispatch to `run_install_deps(component)` with
`component` = `all` | `openscap` | `lynis`. `--install` (`all`): detects the
package manager, enables Ubuntu `universe` if needed, installs `openscap` + the
distro's SSG package (where repos ship no/old content, e.g. Ubuntu 24.04,
`install_ssg_from_github()` fetches the SCAP datastream from the ComplianceAsCode
releases), then installs Lynis. `--install-openscap` runs only the OpenSCAP/SSG
half; `--install-lynis` runs only the Lynis half.

Lynis installation itself is `install_lynis_pkg(strict)`: `strict=true` (only via
`--install-lynis`) makes a failed install a hard error (`exit 1`); `strict=false`
(the Lynis leg of plain `--install`) logs a warning and **continues** — Lynis is a
second-opinion layer and its absence must not break the core OpenSCAP setup. On
RHEL family (`dnf`/`yum`) a failed install prints an EPEL hint (`dnf install -y
epel-release`), since Lynis isn't in the base repos there.

`--uninstall` reverts hardening **first** (same path as `--unapply`), then removes
the OpenSCAP/SSG packages **and** Lynis (if installed).

## Backup contract

Written by `create_backup()` before any mutation; consumed by `revert_hardening()`:

```
/var/lib/linuxharden/<YYYYmmdd_HHMMSS>/
├── configs.tar.gz          # profile's backup.config_dirs (minus exclusions.paths)
├── services_enabled.txt    # enabled units (minus exclusions.services)
├── packages.txt            # installed-package snapshot
├── manifest.conf           # distro, profile IDs, env, xml_path, rollback hook
├── profile.yml             # the profile used, frozen at apply time
├── pre_hardening.arf       # scan before  ┐ self-documenting
├── remediation.arf         # the apply    │ before/after
└── post_hardening.arf      # scan after   ┘ record
/var/lib/linuxharden/latest → symlink to newest (used by unapply/uninstall)
/var/lib/linuxharden/applied_level   # STATE_FILE — shown in the banner
```

**The archive is verified before the first mutation.** `revert_hardening()` deletes
files that exist now but are absent from `configs.tar.gz`, so a silently partial
archive would turn `--unapply` into a config shredder. `create_backup()` therefore
treats `tar` exit ≥ 2 as fatal, re-reads the archive with `tar tzf`, and asserts
that every path it meant to archive is actually present. Any of those failing
returns non-zero and `run_apply()` aborts while the system is still untouched.

`prune_backups()` keeps the newest `--keep N` (default 5) and never touches the
directory `latest` resolves to, whatever its age — that is the one `--unapply`
would use.

**Rule for contributors:** any new mutation must be captured here *and* reverted
in `revert_hardening()` — extend both sides, additively. The profile's
`backup.config_dirs` is the other half: a path the remediation writes but the
profile does not list simply stays applied after `--unapply`. That was measured
on a VM (58 files, 40 rules stuck) before the profiles were extended.

## Profiles (`profiles/*.yml`)

Selected by trying, in order, `${DISTRO_ID}-${DISTRO_VERSION}.yml`,
`${DISTRO_ID}-${DISTRO_VERSION_MAJOR}.yml` and plain `${DISTRO_ID}.yml` — or
forced via `--conf`. The bare `${DISTRO_ID}.yml` is what rolling releases need:
Arch ships no `VERSION_ID`, so both versioned candidates resolve to
`arch-rolling.yml`, a name no profile has. Parsed by `parse_conf()` (python3 +
PyYAML) into globals:

| Section | Drives |
|---------|--------|
| `meta` | distro identity, `arch_fallback` |
| `packages` | package manager, oscap + SSG package names |
| `scap.xml_path` | SCAP datastream location |
| `scap.oval_url` | CVE feed for `--scan-cve` (OVAL engines only) |
| `scap.profiles.production` / `.development` | XCCDF profile ID for `--level 2` / `--level 1` |
| `backup.config_dirs` | what `create_backup()` archives |
| `exclusions.rules/services/paths` | tailoring + backup filters |
| `hooks.pre_hardening/post_hardening/on_rollback` | user extension points |

## Tailoring & service protection

`setup_tailoring()` turns `exclusions.rules` into a standards-compliant **XCCDF
tailoring file** (generated by embedded python3): a custom profile
`xccdf_linuxharden.custom_profile_tailored` that `extends` the base profile with
`<select selected="false"/>` per excluded rule. Rule IDs are validated against the
datastream first — typos produce a warning instead of being silently ignored. On
generation failure it falls back to the untailored profile.

`detect_active_services()` (apply-only) checks for running NFS/autofs/SMB and
Apache/nginx units; for each active one it offers (TTY) or auto-applies (non-TTY /
`--yes`) exclusion of the exact `package_*_removed` / `service_*_disabled` rules,
so hardening never kills a serving workload. New service patterns follow this same
detect → exclude-rule-IDs template.

## Terminal-aware output

The tool is often read on the machine's own console, where there is no scrollback:
a `--scan` that prints 180 lines is eight screens the operator cannot page back
through. So listings are sized to the terminal.

`detect_term_rows()` sets `TERM_ROWS` **once, from `main()`**. It must not be
called from inside `$( )`: command substitution replaces stdout with a pipe, so
`-t 1` is false there and every listing looks unbounded — the first version of
this feature was silently inert for exactly that reason, and only a real pty
caught it.

| Context | `TERM_ROWS` | Behaviour |
|---------|-------------|-----------|
| Terminal | rows from `tput lines`, else `stty size`, else 24 | listings trimmed, banner collapses below 30 rows |
| Pipe / redirect / CI | `0` | nothing trimmed — logs and reports stay complete |
| `--full` | `term_height()` returns `0` | nothing trimmed on a terminal either |

`print_failing_rules()` and the two CVE summaries take a row budget; `0` means
unlimited and keeps the original grouped-by-severity layout. With a budget they
switch to a flat, severity-ordered list ending in `… +N more`, because the
per-severity banners cost three rows each that a short console cannot spare.

## Conventions that keep it safe

- All prompts go through `confirm()`, which honors `--yes` (`ASSUME_YES`) and
  non-TTY execution — the script is CI-safe by construction.
- All output goes through `log_info/warn/error/section`; long operations get a
  `_spin` spinner around a background PID.
- `trap cleanup EXIT` removes `TMP_DIR`, created on demand by `ensure_tmpdir()`
  via `mktemp -d`. The scratch path must stay unpredictable — the script runs as
  root, and a symlink pre-planted at a guessable `/tmp` name would redirect root's
  writes. `install_ssg_from_github()` follows the same rule for its download dir.
- `oscap` exit codes are tolerated (`|| true`) where non-zero is informational
  (e.g. "fails found"), and hard-checked where it means the operation failed.
- Verification gates for changes: `bash -n`, shellcheck, and the smoke cycle in
  `todo.md` (scan → dry-run → apply L1 → scan → unapply → scan on a
  snapshot-restorable VM; Ubuntu 24.04 L2 baseline ≈ 65 %).
