## [unreleased]

### 🚀 Features

- *(scan)* Fit the posture scan on one console screen ([a69b948](https://github.com/murat-akpinar/hardenix/commit/a69b9480826c65dd7caa71f2c76246f2223c7d03))
hardenix is often read on the machine's own console, where there is no scrollback. `--scan` printed 183 lines — roughly eight screens on a 24-row terminal — and the operator could not page back through them.

### 🐛 Bug Fixes

- Repair defects found in a full script review ([294e1cf](https://github.com/murat-akpinar/hardenix/commit/294e1cfda8c251dbef3bc5870e836d4abccee4a6))
Eleven defects, each reproduced and re-verified on the Ubuntu 24.04.4 and Rocky 9.8 test VMs.

### 📚 Documentation

- Add v1.2.0 lynis validation results to test sections ([7adabb0](https://github.com/murat-akpinar/hardenix/commit/7adabb00b5e0abad1eddc46f2fc2d53500c9f8ac))
- Merge the todo/ plans into a single todo.md ([ffbb515](https://github.com/murat-akpinar/hardenix/commit/ffbb515f0999133d3e2edbb2ccbfc5c1fb044b8a))
The four files under todo/ carried three problems: a finished plan taking up 817 lines of step-by-step instructions, a roadmap that marked FAZ 2 complete when five of its six items were never implemented, and a test procedure split away from the plan whose gates it defines.
- Rewrite CLAUDE.md as the in-repo rulebook ([ced1b38](https://github.com/murat-akpinar/hardenix/commit/ced1b389febf6a080ccf3ce0c8893fac30b8ee92))
CLAUDE.md pointed at four rulebooks under .rules/ that do not exist in the repository - the directory was gitignored, so the rules had no history and no presence on a fresh checkout. The rules now live in CLAUDE.md itself.
- Document exit codes, backup verification and profile lookup ([1ed568a](https://github.com/murat-akpinar/hardenix/commit/1ed568af880c88065c4e774286080cd77f531272))
- Both READMEs gain an exit-code table: usage errors are now 1, the --min-score   gate is 2, and --apply is 0 with or without --deadman. - Record that create_backup() verifies the archive before the first mutation and   that the optional --scan layers degrade instead of aborting. - Describe the three-candidate profile lookup and why rolling releases need the   bare <id>.yml form. - Correct the pipeline diagram: detect_distro(), not banner(), prints the applied   level. - Replace the YOUR_GITHUB_USER placeholder, fix the distro badge (9, not 8), and   drop exclusions.users from the sample profile — parse_conf() never read it.
- Document --full and the one-screen posture output ([f4c3a5b](https://github.com/murat-akpinar/hardenix/commit/f4c3a5b59505d49ae281c315f0d9426eb086fba4))
Both READMEs gain a "Console-friendly output" section with the posture box and the terminal-vs-pipe rule; `--full` joins the parameter tables. script-internals gains a "Terminal-aware output" section, including why `detect_term_rows()` must run outside command substitution.

### 🎨 Styling

- *(profiles)* Translate remaining comments to english ([226504e](https://github.com/murat-akpinar/hardenix/commit/226504eb0d7161c7037b931f4e40e58b743398b9))
CLAUDE.md makes English the language of everything that lands in the repo, with todo.md as the sole exception; eight profiles still carried Turkish comments.

### ⚙️ Miscellaneous Tasks

- Add doc-link checker and git-cliff config ([37bc6d9](https://github.com/murat-akpinar/hardenix/commit/37bc6d98d64b441b865929e054dec3df2280c3f0))
check-docs.py verifies that every relative Markdown link and anchor in the repo resolves; the docs cross-reference each other heavily and nothing caught a broken link before. cliff.toml generates CHANGELOG.md from the conventional commit history (v1.2.0 is already tagged).
- Mark linuxharden.sh executable ([e3bae2b](https://github.com/murat-akpinar/hardenix/commit/e3bae2b1ab282a596f0527e32c261e9769907b9c))
- Add vscode settings for todo.md formatting ([7319c62](https://github.com/murat-akpinar/hardenix/commit/7319c62dc4c0cedbe136e467ce9c5192f58111f0))
## [1.2.0] - 2026-07-06

### 🚀 Features

- Prefer local profiles/ directory before fetching from GitHub ([6f335bf](https://github.com/murat-akpinar/hardenix/commit/6f335bf87502552841bd25ea5f88c6c67b51915c))
When resolving a distro profile, the script now first checks profiles/<name>.yml relative to its own location. Only if the file is absent does it fall back to downloading from GitHub. This makes the script work fully offline when the profiles directory is present.
- Dry-run now lists all failing rules with severity and title ([8be1243](https://github.com/murat-akpinar/hardenix/commit/8be1243657d1e7a3c71f8ebec0c3bc01115078b3))
Instead of raw grep output, parse the ARF with Python and print a sorted table (high → medium → low) showing rule ID, severity, and title for every failing rule, followed by the scan summary.
- Split --install (deps) and --apply (hardening) modes ([8d22dbf](https://github.com/murat-akpinar/hardenix/commit/8d22dbf716b187ba7663ce4582080436453fda12))
--install now installs OpenSCAP + SCAP content for the detected distro, including automatic GitHub download of SSG when distro repos lack content (e.g. Ubuntu 24.04 ssg-ubuntu2404-ds.xml). --apply replaces the old --install and applies the hardening profile. --dry-run implies --apply.
- Introduce --unapply and redefine --uninstall ([8990723](https://github.com/murat-akpinar/hardenix/commit/89907234bd91cc582f6a62c5cb905d101b292e16))
Split the lifecycle into two symmetric pairs:   --install  / --uninstall  → package lifecycle (OpenSCAP + SCAP content)   --apply    / --unapply    → hardening lifecycle (backup-based config restore)
- Add --level flag, NFS/SMB protection, and profile cleanup ([466f236](https://github.com/murat-akpinar/hardenix/commit/466f2361d2612c8e6e34eecff8579b76fab37cb4))
Hardening level selection: - Add --level <1|2> as a friendly alias for picking the CIS baseline   (1 = Level 1 basic, 2 = Level 2 strict). Maps onto the existing   profile keys, takes precedence over --env, and stays backward compatible. - Show the active level in detect output and the apply summary.
- Unapply now reverts package and service-mask changes ([93f467f](https://github.com/murat-akpinar/hardenix/commit/93f467f30873e9867a49c3f07cf99012ba29a06b))
Hardening via oscap --remediate removes/installs packages and masks services, none of which the config-file backup captured — so --unapply left the system partially hardened. Now:
- *(detect)* Protect running Apache/nginx from hardening (FAZ 1) ([453f79a](https://github.com/murat-akpinar/hardenix/commit/453f79af77c41236f657f74f5bd9baf57a00f518))
Extends detect_active_services to also detect a running web server (apache2/httpd, nginx) and, like the existing NFS/SMB handling, offer to exclude the rules that would remove the package or disable the service. Prevents hardening from taking down a live web server. Messaging generalized from "NFS/SMB" to "active services".
- Add --yes and --min-score for non-interactive/CI use (FAZ 4) ([e55ed5a](https://github.com/murat-akpinar/hardenix/commit/e55ed5a135afcddb259e3c436897fd2b8551811e))
- --yes / --non-interactive: skip the apply/unapply/uninstall   confirmation prompts and auto-accept service-exclusion, via a new   confirm() helper. Enables automation and unattended runs. - --min-score N: after --scan, exit 2 if the compliance score is   below N — a CI/build gate.
- Add --scan-cve OVAL vulnerability scanning (FAZ 5) ([da5785a](https://github.com/murat-akpinar/hardenix/commit/da5785a74c105d64f53ce9a7775c0e4d3d0b836c))
New self-contained mode that scans installed packages for known CVEs using the vendor OVAL feed (separate from XCCDF/CIS compliance):
- Add --fix-cve security patching (FAZ 6) ([53d912f](https://github.com/murat-akpinar/hardenix/commit/53d912f4fa6603cd72860b7ff34b6a825a5e55f2))
Completes the CVE loop (scan -> fix -> rescan). --fix-cve refreshes package metadata, lists packages with a pending *security* update (apt/dnf/zypper), confirms (honors --yes), and installs only those. Arch/pacman has no security-only channel, so it is skipped with a hint.
- Add dead-man switch for safe remote hardening (FAZ 3) ([5c87b01](https://github.com/murat-akpinar/hardenix/commit/5c87b0133dd8f82ee73d1095c39a547259eb2e74))
--apply --deadman <min> schedules a transient systemd timer that runs --unapply --yes after <min>. If hardening locks you out, the box reverts itself; if you can still log in, --confirm cancels the timer and keeps the changes. Falls back gracefully when systemd-run is absent.
- *(scan-cve)* CVE-centric summary listing the CVE IDs ([8bdd044](https://github.com/murat-akpinar/hardenix/commit/8bdd044d9c9b315dc9a2aeedf496da5b848d2d27))
People search by CVE, not USN — so the summary now lists the actual CVE IDs (worst severity first), each with the USN that fixes it as a reference. The box reports vulnerable CVE count + fixing-advisory count; per-CVE severity drives the breakdown. Capped at 40 with a pointer to the HTML report for the rest.
- *(scan-cve)* Native dnf updateinfo backend for RHEL family ([47c3a45](https://github.com/murat-akpinar/hardenix/commit/47c3a45f81a5ed459fb8a090cd9a14e527017d1e))
OVAL is inaccurate on RHEL rebuilds — Red Hat's feed gates on redhat-release (absent on Rocky/Alma) and version strings differ, so it over-reports massively (1763 false "vulnerable" defs on Rocky 9.8). --scan-cve now dispatches by package manager: dnf/yum use the vendor's native updateinfo errata (RLSA/RHSA/ALSA + CVEs), apt/zypper keep the OVAL path. Same CVE-centric summary for both.
- Banner shows applied hardening state, not selected level ([979bbd7](https://github.com/murat-akpinar/hardenix/commit/979bbd7257b2101aa11e8f13b01c3f13868ce4a2))
The startup line now reports the *applied* level read from a state file (/var/lib/linuxharden/applied_level): "Hardening applied: CIS Level 1 (basic)" with a check once applied, or "Hardening applied: None" (warn marker) on an un-hardened box. --apply writes the level it applied; --unapply/--uninstall clear it. No more misleading green "CIS Level 2" on a fresh system.
- Add OVAL feeds for Ubuntu 22.04 + openSUSE; document Debian gap ([cfe51fb](https://github.com/murat-akpinar/hardenix/commit/cfe51fbbb474789d83e4d67b7fbeeec3e811d2b1))
Other apt/zypper distros hit the same "No OVAL feed" error Rocky did, since only ubuntu-24.04 had a feed. Added (URLs verified reachable): - ubuntu-22.04: Canonical USN OVAL (jammy) - opensuse-leap-15: SUSE OVAL (15.6; pin to your Leap minor) RHEL family (rocky/rhel/alma/fedora) needs none — it uses dnf updateinfo. Debian: www.debian.org OVAL returns 403 to automated fetches and has no stable mirror, so CVE scan stays unavailable there (documented in yml). Also: count FEDORA-* advisories in the dnf summary; clearer error when no feed is configured.
- Add Debian 12 OVAL feed for --scan-cve ([ecdfb75](https://github.com/murat-akpinar/hardenix/commit/ecdfb75bce8d6b85f48674efe72f47d454c5dd43))
The bare .xml path 403s, but the actual file is published as .xml.bz2 under www.debian.org/security/oval/ (verified: 200, valid OVAL). So Debian CVE scanning works after all — added the bookworm feed.
- Add --install-lynis/--install-openscap; --install now includes lynis ([20d217d](https://github.com/murat-akpinar/hardenix/commit/20d217def5a69289210f7d463b20afaee1edb0c2))
- Add --scan-lynis audit mode (hardening index + warnings) ([3ca29aa](https://github.com/murat-akpinar/hardenix/commit/3ca29aaf717364e5d524218a2041a47439d364ff))
- Make --scan a combined posture scan; add --scan-compliance ([57ae09a](https://github.com/murat-akpinar/hardenix/commit/57ae09a8bdd58d8e8236596eeb78a45c5eab7937))
- Remove lynis on --uninstall ([99892c6](https://github.com/murat-akpinar/hardenix/commit/99892c6f5ebd799362d5ada22c2b662b3d1068b3))

### 🐛 Bug Fixes

- Rename VERSION to SCRIPT_VERSION to avoid /etc/os-release collision ([b934758](https://github.com/murat-akpinar/hardenix/commit/b934758aead817d20d0cdd086e92fe4ec7566a79))
`/etc/os-release` exports a `VERSION` variable on most distros (e.g. Ubuntu). Sourcing it inside `detect_distro()` caused bash to throw a readonly variable error because `VERSION` was already declared `readonly` at script startup. Renaming it to `SCRIPT_VERSION` eliminates the name collision.
- Set correct GitHub raw URL for profile downloads ([3f3ba68](https://github.com/murat-akpinar/hardenix/commit/3f3ba687b8bb36ee8e9e39e2c3b0531ec7b8d309))
Replace the YOUR_GITHUB_USER placeholder with the actual repository (murat-akpinar/hardenix) so profile YAMLs can be fetched at runtime.
- Silent exit in check_pyyaml caused by set -e + && return pattern ([184c546](https://github.com/murat-akpinar/hardenix/commit/184c546089fc0488ae0c749442d6bc48ef1a81cd))
`cmd && return` with set -euo pipefail causes a silent exit when cmd fails — set -e triggers before the error message is printed. Changed to `if cmd; then return; fi` which is safe under set -e.
- Create_backup stdout pollution breaks --install, fix box alignment ([fc5f997](https://github.com/murat-akpinar/hardenix/commit/fc5f9970a8cca7a8cc53050d90c6e00578d13d12))
- create_backup: redirect all log_info/log_warn calls to stderr so that   backup_dir=$(create_backup) captures only the path; previously the   variable contained log messages, making every subsequent path   (pre_arf, post_arf, remediation.arf) invalid and breaking --install - print_improvement: replace fixed {'':<35} padding with dynamic   (35-len(val)) so box rows always match the top/bottom border width - print_scan_summary: reduce hardcoded padding from 27 to 25 chars and   fix Score row with dynamic padding to maintain consistent box width
- Replace all [[ ]] && cmd patterns with if forms to prevent set -e silent exit ([11afa7d](https://github.com/murat-akpinar/hardenix/commit/11afa7dbe392a215c76a120652015019e18328a4))
With set -euo pipefail, a [[ condition ]] && action expression exits with the condition's non-zero status when the condition is false, which causes bash to exit silently without executing any error handling. This is the same class of bug that was fixed in check_pyyaml (commit 184c546).
- Improve dependency error messages and add oscap version guard ([0b50887](https://github.com/murat-akpinar/hardenix/commit/0b50887cd725cc8f8658a012e68d6e4147476bd7))
- check_dependencies: when SSG content is missing on apt systems, hint   that packages live in the 'universe' repo and suggest   'add-apt-repository universe && apt-get update' before installing - check_dependencies: add oscap version check; exit with clear error if   version < 1.3 (Ubuntu 22.04 SSG content requires oscap 1.3+; 1.2.x   is from Ubuntu 18.04 repos and cannot parse current datastreams)
- Detect outdated ssg-debderived and show GitHub download instructions ([6a589a6](https://github.com/murat-akpinar/hardenix/commit/6a589a6684db7f69bbd363197a3ba0388ca087bc))
When the SSG package is installed but the expected XML datastream is missing (e.g. Ubuntu 24.04 content requires SSG >= 0.1.73 but distro repos only ship 0.1.71), the previous error was misleading.
- Correct profile inconsistencies across distros ([5715538](https://github.com/murat-akpinar/hardenix/commit/5715538ee6065e10437ea0355d4d6b28e611dc9b))
- Rocky 9, AlmaLinux 9: bump production/staging to CIS L2 (matches RHEL 9) - Ubuntu 22.04, 24.04: add /etc/apparmor.d to backup dirs - Fedora 40: add /etc/selinux to backup dirs - openSUSE Leap 15: clarify ssg-sle15 datastream usage
- Show oscap errors on scan failure and use --results-arf ([79df82e](https://github.com/murat-akpinar/hardenix/commit/79df82e3ad7ccf80d3fced1af29f07ee66a081ae))
- Add missing xccdf:version element to tailoring XML ([608b0bb](https://github.com/murat-akpinar/hardenix/commit/608b0bb54eb67636fb5ff2dd4f7b2ad5aca51dba))
XCCDF 1.2 schema requires version before Profile; oscap was rejecting the tailoring file and producing no scan output.
- Correct tailoring XML element order and version time attribute ([7a5a35f](https://github.com/murat-akpinar/hardenix/commit/7a5a35f3334ee75b18caaaa5681915a2245caed3))
XCCDF 1.2 schema requires benchmark before version, and version must carry a required 'time' attribute.
- Silence spinner on non-TTY and validate --profile against datastream ([3d42a7e](https://github.com/murat-akpinar/hardenix/commit/3d42a7ee5316260f22d7ee9534252bc5abcd758e))
- _spin now prints the message once instead of hundreds of animation   frames when stdout is not a terminal (pipe, CI, log file). - validate_profile rejects an unknown profile ID up front instead of   letting oscap produce an empty result reported as a misleading 0.0%.
- Non-TTY spinner aborted script under set -e ([633d4c2](https://github.com/murat-akpinar/hardenix/commit/633d4c24f8d2d2ee96c07240258ce0d98da7b5a5))
The non-TTY _spin branch returned oscap's exit code (2 when rules fail). As a bare call under `set -euo pipefail` this aborted every scan/apply right after the spinner message. Swallow the wait status and return 0.
- Snapshot only installed (ii) packages on Debian ([0a248a9](https://github.com/murat-akpinar/hardenix/commit/0a248a9b4cc3679867540e70c199373411822602))
dpkg-query -W also lists packages in the 'rc' state (removed but config files kept), so an `apt-get remove` was invisible to the unapply reconcile diff. Filter on install status 'ii'.
- Exact config restore on revert + surface uninstall removal errors ([cbe8d52](https://github.com/murat-akpinar/hardenix/commit/cbe8d52b7443d09be274a3ae52d1ab6ecb248696))
Revert problem: plain `tar x` only overwrites/adds, so files the hardening created inside a backed-up dir (cramfs.conf, new sysctl.d drop-ins, etc.) survived and the system stayed hardened — a scan after --unapply still showed a high score. Now revert extracts to a staging dir and deletes files no longer in the backup before copying the originals back, restoring each path to its exact prior state.
- *(backup)* Expand ubuntu-24.04 backup coverage for full revert (FAZ 2) ([d59e412](https://github.com/murat-akpinar/hardenix/commit/d59e412d507b9f3632499b1b286396b21238affb))
A clean-box apply -> unapply did not return to baseline (65.2% -> 70.4%) because CIS touches config outside the backed-up dirs (e.g. /etc/rsyslog.conf FileCreateMode), so unapply could not revert it. Adds the CIS-touched locations to backup.config_dirs: rsyslog, logrotate, systemd, /etc/default, banners, chrony, cron/at access, hosts.allow/deny, fstab. Non-existent paths are skipped at backup time.
- *(scan-cve)* Decompress OVAL feed via python3, not bunzip2 ([938f6b3](https://github.com/murat-akpinar/hardenix/commit/938f6b32a01f680fcd77b3eecc436973d898dcda))
bzip2/gzip binaries aren't always installed; python3 (already a dependency) handles .bz2/.gz natively, so the feed decompresses without an extra package.
- *(scan-cve)* Exclude inventory definition from CVE counts ([f6fb0b0](https://github.com/murat-akpinar/hardenix/commit/f6fb0b0ca0c0a0777680d30450999956a2eaf3ca))
The OVAL feed's single class="inventory" definition (is-Ubuntu-installed) always evaluates true and was wrongly counted as a vulnerable advisory. Count only class="patch" definitions.
- *(scan-cve)* Align CVE summary box border (inner width 46) ([f36513a](https://github.com/murat-akpinar/hardenix/commit/f36513ac90354cffb28bced27fe3e5f0761fd736))
Top/bottom borders and content lines used mismatched widths so the box did not line up. Normalized to the same 46-char inner width as the compliance Scan Summary box.
- *(profiles)* Correct CIS L2 Server profile id for RHEL 9 family ([34566d1](https://github.com/murat-akpinar/hardenix/commit/34566d102d041b4bd09e7777d3e2f4ec8afe8d6c))
The L2 Server profile in the RHEL/Rocky/Alma 9 datastream is xccdf_org.ssgproject.content_profile_cis (not ..._cis_server_l2), which made --scan/--apply fail with "Profile not found in datastream" on Rocky. Fixed rocky-9, rhel-9 and almalinux-9 (L1 id was correct).
- Only show "Hardening level" for compliance modes ([45fdb24](https://github.com/murat-akpinar/hardenix/commit/45fdb24fb55ebbb43295690143deeba90a5f2f1e))
The banner printed "Hardening level: CIS Level 2 (strict)" for every mode, including --scan-cve / --install where the level is irrelevant — which read like an applied state rather than a selection. Now shown only for scan/apply/unapply.
- *(scan-cve)* Match --scan layout (CVE list on top, summary box last) ([8d94089](https://github.com/murat-akpinar/hardenix/commit/8d94089f801e6f4104989c3d5aedb538514477a9))
Both the OVAL and dnf summaries now print the CVE list first, then the severity line and the summary box at the bottom — consistent with --scan (findings first, score box last) so users see one layout.
- Only run service-protection prompt for --apply, not --scan ([0b96285](https://github.com/murat-akpinar/hardenix/commit/0b96285d5a9e4cec5bbc3d14502d6c229351d0b6))
detect_active_services prompts to exclude rules that would remove/disable a running service — relevant only when applying. --scan is read-only, so prompting (and excluding rules) there was confusing and hid results. Now it runs for apply/apply_arch only; --scan reports full compliance.
- Prevent SELinux boot freeze after unapply (RHEL family) ([a6d7828](https://github.com/murat-akpinar/hardenix/commit/a6d7828f495532a8fe198230c43a3b83220d413e))
A tar/cp config restore does not carry SELinux contexts, so on enforcing systems (Rocky/RHEL/Alma) restored files came back mislabeled — bricking boot with "Failed to initialize SELinux support. Freezing execution." after --unapply + reboot.
- Skip XCCDF prep on Arch fallback (empty xml_path aborted scans) ([951c096](https://github.com/murat-akpinar/hardenix/commit/951c096072683c65c101e49dd192b2c0874cab76))
- Guard against stale lynis report; warn when --min-score is inert ([8322921](https://github.com/murat-akpinar/hardenix/commit/83229218495a1bdbd81266c26a17e52d7ab40580))
- Don't let EXIT trap flip exit status when TMP_DIR absent ([55c3a3e](https://github.com/murat-akpinar/hardenix/commit/55c3a3e2a4ae4f2c5f3ee584cf94b85f3939faeb))
- Force LF for shell scripts and profiles via .gitattributes ([5ae2304](https://github.com/murat-akpinar/hardenix/commit/5ae2304adf9a2423ce7ec47e4580a16800d55a06))

### 🚜 Refactor

- Remove GitHub profile download, resolve from local profiles/ only ([827b0a5](https://github.com/murat-akpinar/hardenix/commit/827b0a583b2d793c390e99011c691573db25361b))
Network fetching during system hardening is a supply chain risk. Profiles ship with the repo, so remote download adds no value. wget is no longer a runtime dependency.
- Extract print_failing_rules(), apply to --scan and --apply ([4c1c47e](https://github.com/murat-akpinar/hardenix/commit/4c1c47e88f687ebcf4511509a391fffc40e696dd))
The grouped HIGH/MEDIUM/LOW/UNKNOWN severity table (previously only in --dry-run) is now a reusable print_failing_rules() function called from:   - --dry-run  (replaces the inline Python block)   - --scan     (replaces the grep|tail -20 verbose stream)   - --apply    (replaces the compact single-line remaining count)
- Remove redundant --env flag in favor of --level ([6fc1351](https://github.com/murat-akpinar/hardenix/commit/6fc1351857532b53fe7d054c47d75bfc970994d1))
The --env flag (production/staging/development) duplicated what --level already does. staging was identical to production in every profile, so only two real baselines existed: strict (level 2) and basic (level 1), both already selectable via --level. ENV_PROFILE is now an internal key driven solely by --level, defaulting to level 2 (strict).
- Remove --profile flag in favor of --level ([c536d51](https://github.com/murat-akpinar/hardenix/commit/c536d519d157d52bba458ba31844bc19ab0cfa89))
The --profile override required a raw XCCDF profile ID, which was clunky and error-prone. --level 1|2 already maps to the correct CIS server profiles from the yml, so --profile is redundant for the common case. validate_profile still guards against a misconfigured profile ID in the yml.
- Unapply reverts settings only; uninstall reverts then removes ([2d3f908](https://github.com/murat-akpinar/hardenix/commit/2d3f908ac5d0405335c01e7f804586fd4b40c547))
Per intended semantics: - --unapply now restores configs, reinstalls packages the hardening   removed, and restores service state — but no longer removes any   package or the OpenSCAP tooling (it must not delete applications). - --uninstall first runs the full settings revert, then removes the   OpenSCAP packages.

### 📚 Documentation

- Update README for --install / --apply split ([1091672](https://github.com/murat-akpinar/hardenix/commit/10916728c90edad7c29e1c73da4feb28ddf24741))
--install now describes dependency installation (OpenSCAP + SCAP content), --apply describes hardening. Usage examples, parameter table, backup section, and hook comments updated in both README.md and README_TR.md.
- Add phased security roadmap (todo/plan.md) ([55c20ec](https://github.com/murat-akpinar/hardenix/commit/55c20ec556235153cdab367d1b27c75a5343e5db))
Splits the planned work into isolated, additive phases (FAZ 0-10), each with its own test gate so changes can be validated incrementally instead of all at once. Covers CIS hardening, running-service protection, rollback safety, dead-man's switch, automation, OVAL-based CVE scanning (--scan-cve), security patching (--fix-cve), extra hardening modules, reporting/drift, distro coverage, and CI.
- Add test procedure with phase acceptance gates (FAZ 0) ([3497e7b](https://github.com/murat-akpinar/hardenix/commit/3497e7b2ee70f5dc90cbafbb58c07c970b7dae70))
Documents the repeatable smoke-test loop, pristine baseline (65.2%), the nohup+poll pattern for remote apply/unapply, and per-phase acceptance criteria. FAZ 0 and FAZ 1 gates verified on a clean Ubuntu 24.04 box.
- Record FAZ 0/1/2/4 status and mask finding ([59039ee](https://github.com/murat-akpinar/hardenix/commit/59039eed706323217e35cddce9bf03874b55f843))
- FAZ 2 validated: expanded backup improved clean apply->unapply from   70.4% to 67.0% (vs 65.2% baseline); residual ~2 rules are packages   unapply intentionally keeps. - Mask finding: hardening a blank system does NOT mask nginx/apache;   installing them afterwards yields a normal active/enabled service.
- Mark FAZ 5 (--scan-cve) done and validated ([5af20d9](https://github.com/murat-akpinar/hardenix/commit/5af20d98aec317d6c169427a079d0faca0878b0a))
Clean box: 0 CVEs (matches apt). Downgraded curl: 8 USNs / 27 CVEs detected, grouped by severity with HTML report.
- Mark FAZ 3 (dead-man switch) done and validated ([2781ead](https://github.com/murat-akpinar/hardenix/commit/2781ead7162badafff469fbd4ba895c25c8def8a))
Auto-revert fired after the timeout (system rescued itself); --confirm cancelled the timer and kept hardening. Both paths verified.
- Update README (EN/TR) for CVE scanning, dead-man switch, automation ([8f88e31](https://github.com/murat-akpinar/hardenix/commit/8f88e3101d8d8a12e7dedd7d60942c2586e4442f))
Documents the new capabilities and removes the dropped --profile flag: - --scan-cve / --fix-cve (OVAL vulnerability management) + a dedicated   CVE section - --deadman / --confirm (safe remote hardening) + examples - --yes / --min-score (automation / CI gating) - running Apache/nginx service protection - exact-restore unapply, packages.txt backup, oval_url in the YAML
- Update CVE example output to CVE-centric format (EN/TR) ([357a92e](https://github.com/murat-akpinar/hardenix/commit/357a92e8a9ad9f253b10c27d244e7754e1022f30))
- Add Test Results section (Ubuntu 24.04 + Rocky 9.8) ([1e5cde4](https://github.com/murat-akpinar/hardenix/commit/1e5cde424c63a4a2754073fe3b4e4f1963f37efb))
Real end-to-end runs with kernel/oscap versions and scores: - Ubuntu 24.04.4: scan 65.2%, apply L1 68.5%->93.7%, scan-cve verified - Rocky 9.8: scan 47.4%, apply L1 58.7%->98.1%, scan-cve 39 CVEs (dnf)
- Add lynis integration plan ([5335f2a](https://github.com/murat-akpinar/hardenix/commit/5335f2a2331051bec7d508c1d7e8b1251691dcfc))
- Document lynis integration; bump version to 1.2.0 ([cff3792](https://github.com/murat-akpinar/hardenix/commit/cff379212b19f16c89306d44bd9deb2b0621ca7e))
- Align remaining --scan/--install text with lynis behavior ([2c1a650](https://github.com/murat-akpinar/hardenix/commit/2c1a650a6a02667adff7e2a05f095ce700c1a1aa))
- Reframe intro as three security layers ([207bbb0](https://github.com/murat-akpinar/hardenix/commit/207bbb0bfbeff1ff65db8ac61b4b4806fda629a7))
- Add stale-report and exit-code checks to VM gate ([128553e](https://github.com/murat-akpinar/hardenix/commit/128553e24f0f15fdefc3756349c4d4657bd130ab))
- Mark lynis plan complete — VM gate passed (ubuntu 24.04 + rocky 9.8) ([684e3fe](https://github.com/murat-akpinar/hardenix/commit/684e3fec51bca65aca304afa6c598886ad61a949))

### 🎨 Styling

- Replace banner ASCII art with HARDENIX lettering ([339420d](https://github.com/murat-akpinar/hardenix/commit/339420d46c00065173eb05cd9af80ae66a592a2e))
- Make --dry-run usable without --install ([84f77f2](https://github.com/murat-akpinar/hardenix/commit/84f77f2aae961ccc12d733013f08d085ed242155))
--dry-run now implies --install when no mode is given, so users can type just: sudo linuxharden.sh --dry-run
- Grouped dry-run output by severity, suppress oscap verbose lines ([f8bd106](https://github.com/murat-akpinar/hardenix/commit/f8bd1067c285aa792b68b52af5bd820a72641488))
Failing rules are now shown in HIGH / MEDIUM / LOW / UNKNOWN sections with separator lines, rule short name and title columns. The per-rule Title/Rule/Result stream from oscap is suppressed (redirected to /dev/null) since the ARF file holds all needed data and the raw stream was noisy.
- Suppress oscap verbose output in --apply, show compact summary ([e6fcd71](https://github.com/murat-akpinar/hardenix/commit/e6fcd7139b9019f9ad97e5c765a6e3d117e0b420))
The Title/Rule/Result stream from oscap is now suppressed during baseline, remediation, and verification scans. After apply, output shows: - before/after score box - pass/fail/score summary box - one-line remaining issues count by severity - hint to run --dry-run for the full list
- Add spinner to oscap scans so users know the script is running ([fa30640](https://github.com/murat-akpinar/hardenix/commit/fa3064047fb3f84b7f998ced7a29157fc78acfcb))
All silent oscap eval calls (dry-run scan, baseline, remediation, and verification) now show an animated |/-\ spinner with a status message while running. The spinner clears itself when done so log output stays clean. Prevents the script from appearing frozen during long scans.

### ⚙️ Miscellaneous Tasks

- Translate remaining user-facing output to English ([e92a801](https://github.com/murat-akpinar/hardenix/commit/e92a80116310267369bf8f74bc513b56cdefdf8b))
The active-service detection prompts/messages and the datastream exclusion warning were in Turkish; translated them (and the service labels) to English for a consistent CLI. Prompt default is now [Y/n].

### 🛡️ Security

- Security phases — CVE management, safe rollback, automation ([36788fc](https://github.com/murat-akpinar/hardenix/commit/36788fc71cfa5535130b09b80d726fc92e1b5105))
Brings the feature/security-phases work into main. Adds a second security layer (vulnerability management) on top of CIS hardening and makes both safer to run, especially remotely.
