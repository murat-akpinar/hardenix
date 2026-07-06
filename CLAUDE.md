# hardenix

OpenSCAP-based Linux hardening + CVE/vulnerability management tool. One bash script
(`linuxharden.sh`) driven by per-distro YAML profiles. Two layers: compliance
hardening (`--scan` / `--apply` / `--unapply`) and CVE management (`--scan-cve` /
`--fix-cve`). A multi-user fleet web UI (FastAPI + Celery) is planned under `webui/`
— see `todo/webui-plan.md`.

## Map

| Path | What |
|------|------|
| `linuxharden.sh` | The entire tool (~2100 lines, bash, `set -euo pipefail`). `main()` at the bottom dispatches modes: `run_install_deps`, `run_scan_full`, `run_scan`, `run_scan_lynis`, `run_scan_cve`, `run_fix_cve`, `run_apply`, `run_unapply`, `run_uninstall`, `run_confirm` (+ `run_*_arch` fallbacks). |
| `profiles/*.yml` | One per distro (9). Parsed by `parse_conf()` (python3 + PyYAML). Auto-selected as `${DISTRO_ID}-${DISTRO_VERSION}.yml` by `detect_distro()`. |
| `todo/plan.md` | Script roadmap (FAZ 0–10; FAZ 0–6 done). Turkish. |
| `todo/webui-plan.md` | Web UI plan (FAZ W0–W8, not started). Its design decisions are binding. |
| `todo/TESTING.md` | Smoke-test procedure + phase acceptance gates. |
| `docs/` | Architecture docs (final target state): `architecture.md`, `script-internals.md`, `fleet-webui.md`. Keep in sync when modes/flows change. |
| `.rules/` | Project rulebooks — local, gitignored (see Rules below). |
| `reports/`, `tmp/` | Generated scan output / legacy scratch. Both gitignored; never commit contents. |

## Verify & test

Development happens on Windows; the script targets Linux. Gates before every commit
that touches `linuxharden.sh`:

```powershell
wsl bash -n ./linuxharden.sh      # syntax — hard gate
wsl shellcheck ./linuxharden.sh   # lint — if installed
```

Behavioral verification needs a Linux VM (snapshot-restorable). Follow the smoke
cycle in `todo/TESTING.md`: `--scan` → `--dry-run` → `--apply --level 1 --yes` →
`--scan` → `--unapply --yes` → `--scan`. Reference baseline: Ubuntu 24.04 L2 ≈ 65.2 %.

## Workflow (the standing order)

1. **New feature / behavior change** → superpowers:brainstorming before any code.
2. **Multi-step work** → written plan in `todo/<topic>-plan.md`
   (superpowers:writing-plans): phases, each additive, each ending with an explicit
   test gate + commit message.
3. **Executing a plan** → superpowers:subagent-driven-development (or
   superpowers:executing-plans); one phase = implement → gate green → commit.
4. **Bug** → superpowers:systematic-debugging before proposing fixes.
5. **Web UI code** → superpowers:test-driven-development (the plan mandates test-first).
6. **Before claiming done** → superpowers:verification-before-completion + the gates above.
7. **Branch complete** → superpowers:finishing-a-development-branch.

## Rules (read on demand — don't skip)

Rulebooks live in `.rules/` (local, gitignored; originals archived in `.rules/_archive/`):

- Touching `linuxharden.sh` or `profiles/` → read `.rules/bash-script.rules.md` first.
- Any `webui/` work → read `.rules/webui.rules.md` **and** `todo/webui-plan.md`.
- Security-sensitive change (SSH, auth, secrets, feeds) → `.rules/security.rules.md`.
- Committing, branching, releasing → `.rules/git.rules.md`.

## Hard constraints (always)

- This tool runs **as root on live systems**. `--scan`, `--scan-cve`, `--dry-run`
  must remain strictly read-only. Mutating paths keep the backup→apply→verify
  contract; `--unapply` must restore the exact pre-apply state.
- Never weaken remote-safety features (dead-man switch, running-service protection,
  SSH-lockout warnings) as a side effect of another change.
- All user-facing output, code, comments, and commits: **English**. Planning docs in
  `todo/` may be Turkish.
- Changes are **additive** — don't restructure working modes while adding features.
- Web UI work never modifies `linuxharden.sh` (plan: "script'e dokunulmaz"); the
  single sanctioned exception is a machine-readable `--version` output.
- `SCRIPT_VERSION` (top of script) is bumped in the same commit as any user-visible
  behavior change.

## Gotchas

- `.claude/`, `.rules/`, `reports/`, `/tmp/` are gitignored — `.rules` edits are
  local-only and have **no git history**. `tmp/*.sh` are legacy `oscap generate fix`
  drafts, not part of the tool (FAZ 10 removes them).
- Debian/Fedora ship no CIS profile in SSG → they use ANSSI BP-028 / OSPP; there
  `--level 2|1` means strict|light baseline, not literal CIS levels.
- RHEL-family rebuilds (Rocky/Alma) don't use OVAL for `--scan-cve` (it over-reports);
  they use native `dnf updateinfo` (`scan_cve_dnf()`).
- SSG only masks services present at apply time — installing nginx/apache *after*
  hardening leaves them active (golden-image order matters: harden first, then apps).
- `detect_active_services()` auto-excludes service rules when not on a TTY; on a TTY
  it prompts. Every new prompt must honor `--yes` (`ASSUME_YES`).
