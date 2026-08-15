# CLAUDE.md

Working rules for AI agents in this repository. The decisions live in
[docs/](docs/README.md) and [todo.md](todo.md), not here.

**Project:** hardenix — OpenSCAP-based Linux hardening + CVE management. One bash
script (`linuxharden.sh`, v1.2.0) driven by per-distro YAML profiles. Three layers:
compliance hardening (`--scan-compliance` / `--apply` / `--unapply`), Lynis
second-opinion audit (`--scan-lynis`), CVE management (`--scan-cve` / `--fix-cve`);
plain `--scan` is the combined posture scan. A multi-user fleet web UI (FastAPI +
Celery) is planned under `webui/` — see [todo.md](todo.md#3-web-ui-planı-faz-w0w8).

---

## Workflow — follow this order, every time

1. **Write the code.**
2. **Review the diff yourself** before running anything. Look for: does it break a
   hard invariant below, does it make a read-only mode write, does it break the
   backup→apply→verify contract, does it leave an unguarded command under
   `set -euo pipefail`, is `SCRIPT_VERSION` bumped if behavior changed.
3. **Test.**
   ```sh
   bash -n ./linuxharden.sh              # syntax — hard gate
   shellcheck ./linuxharden.sh           # lint — if installed
   python3 scripts/check-docs.py         # every relative doc link resolves
   ```
   **Green gates are not working software.** `bash -n` proves the script parses,
   nothing more — this tool runs as root on live systems and every real bug it has
   shipped was found on a VM, not by a linter. Behavioral changes need the smoke
   cycle below, and you say what you actually saw, with the numbers.
4. **Only if all of it passes: commit.** If anything fails, fix it or report the
   failure — never commit red.
5. **Check off the `todo.md` item in the same commit as the work.** An unchecked
   done item and a checked undone item are the same bug (this repo has already
   shipped the second one).
6. **Update the changelog:** `git cliff -o CHANGELOG.md`, then commit it separately
   as `chore(changelog): update`.
7. **Push once**, at the end — after the changelog commit, not two pushes.

Never skip 2 or 3. Never report "done" for work that was not tested.

### Which process skill applies

1. New feature / behavior change → `superpowers:brainstorming` **before** any code.
2. Multi-step work → a written plan as a section in `todo.md`
   (`superpowers:writing-plans`): phases, each additive, each ending with an
   explicit test gate + commit message.
3. Executing a plan → `superpowers:subagent-driven-development` or
   `superpowers:executing-plans`; one phase = implement → gate green → commit.
4. Bug → `superpowers:systematic-debugging` before proposing fixes.
5. Web UI code → `superpowers:test-driven-development` (the plan mandates test-first).
6. Before claiming done → `superpowers:verification-before-completion`.
7. Branch complete → `superpowers:finishing-a-development-branch`.

## Behavioral verification (the smoke cycle)

Development happens on Windows/WSL; the script targets Linux. Real verification
needs a **snapshot-restorable Linux VM**:

```sh
sudo bash linuxharden.sh --scan                   # baseline (Ubuntu 24.04 L2 ≈ 65.2 %)
sudo bash linuxharden.sh --dry-run                # what would change
sudo bash linuxharden.sh --apply --level 1 --yes  # apply (takes a backup)
sudo bash linuxharden.sh --scan                   # score must rise (≈ 93 %)
sudo bash linuxharden.sh --unapply --yes          # revert
sudo bash linuxharden.sh --scan                   # back to baseline (≈ 65-67 %)
```

Full procedure, remote-run pattern and phase gates: [todo.md](todo.md#4-test-prosedürü).
Leave the box clean afterwards (purge installed services, `--unapply`, or restore
the snapshot).

## Commits — attribution

- **Commits go out under the repository owner's signature only.**
- **Never** add `Co-Authored-By: Claude`, `Generated with Claude Code`, `🤖`, or any
  other AI attribution — not to commit messages, not to PR bodies, not to code
  comments. (Older commits in this history carry such trailers; they stay as they
  are, new ones do not get them.)
- Do not change `user.name` / `user.email`; use whatever git is configured with.

## Commits — format

Conventional Commits are **mandatory**. `cliff.toml` sets
`filter_unconventional = true`, so a non-conventional message silently disappears
from the changelog.

```
<type>(<scope>): <subject>
```

- **types:** `feat` `fix` `docs` `refactor` `perf` `style` `test` `chore` `ci` `revert`
- **scopes** (optional, use when it narrows the blast radius): `scan` `scan-cve`
  `scan-lynis` `apply` `unapply` `backup` `profiles` `install` `detect` `docs`
- **subject:** English, imperative, lowercase, no trailing period

```
feat(scan-cve): native dnf updateinfo backend for RHEL family
fix(backup): verify the config tarball before applying
docs: merge the todo/ plans into a single todo.md
```

Breaking changes (a mode or flag changes meaning): `feat(apply)!: ...` plus a
`BREAKING CHANGE:` footer.

## Language

Everything that lands in the repository is **English**: code, comments, user-facing
output, documentation, commit messages. The single exception is `todo.md`, which is
Turkish planning material.

Chat with the maintainer in **Turkish**.

## Hard invariants — do not break these without an explicit decision

1. **This tool runs as root on live systems.** `--scan`, `--scan-compliance`,
   `--scan-lynis`, `--scan-cve` and `--dry-run` are strictly **read-only**. A
   scan that writes to the target system is a defect, no matter how useful.
2. **Backup → apply → verify.** Every mutating path takes a backup first, applies,
   then verifies. `--unapply` must restore the **exact** pre-apply state — configs
   byte-for-byte, service enable/disable state, and packages the remediation
   removed. It deliberately does not remove packages the remediation added.
3. **Never weaken remote-safety features** as a side effect of another change:
   dead-man switch (`--deadman`/`--confirm`), running-service protection
   (`detect_active_services()`), SSH-lockout warnings.
4. **Every prompt honours `--yes`** (`ASSUME_YES`) — go through `confirm()`, never
   read from stdin directly. A prompt that blocks in CI breaks unattended apply.
5. **Changes are additive.** Do not restructure working modes while adding a
   feature. New capability = new mode or new flag, existing flows untouched.
6. **Web UI work never modifies `linuxharden.sh`.** The single sanctioned exception
   is machine-readable `--version` output.
7. **`SCRIPT_VERSION` is bumped in the same commit** as any user-visible behavior
   change.
8. **One file, no dependencies beyond the distro.** The tool is a single bash
   script plus its `profiles/` directory (cloned, not curl'd — the script alone
   cannot resolve a profile); runtime needs are bash 5, coreutils, `python3` +
   PyYAML (profile parsing), and the distro's package manager. No new runtime
   dependency without asking — splitting the script into modules is explicitly
   rejected ([todo.md](todo.md#p3--kasıtlı-yapılmayanlar)).

## Before adding a feature

Check [todo.md § P3 — kasıtlı yapılmayanlar](todo.md#p3--kasıtlı-yapılmayanlar)
first. If it is on that list the answer is no, unless the maintainer reverses the
decision explicitly — and a reversal is recorded in `todo.md`, not applied
silently.

## Bash style

- `set -euo pipefail` is the environment everything lives in. Commands that may
  legitimately fail get an explicit guard: `grep -c ... || true`,
  `cmd || return 1`, `[[ cond ]] && x=y || true`. A bare `[[ ]] && x=y` as the
  last line of a function returns non-zero and kills the script.
- **Return values go to stdout, human output goes to stderr.** A function whose
  result is captured with `$(...)` logs with `>&2` (see `create_backup()`).
- Use the existing helpers — `log_info/warn/error`, `log_section`, `confirm`,
  `_spin` — never raw `echo` for user-facing status.
- Quote everything: `"$var"`, `"${arr[@]}"`. Prefer `[[ ]]` over `[ ]`.
- Every mode is a `run_*()` function dispatched from `main()`. Keep the dispatch
  flat; no indirection layers.
- **Few comments.** Comment what the code cannot say: a non-obvious invariant, a
  deliberate deviation, a distro trap. The reasoning belongs in `docs/`.
- New user-visible flag → update `usage()`, `README.md`, `README_TR.md`, and
  `docs/script-internals.md` in the same commit.

## Security rules

- Anything touching SSH, authentication, secrets or feed downloads is reviewed as
  a security change: state what an attacker gains if it is wrong.
- **Feeds are downloaded over HTTPS only** and parsed, never executed. Do not add
  a feed URL to a profile without checking it is a vendor-controlled host.
- Hooks (`pre_hardening`/`post_hardening`/`on_rollback`) run arbitrary commands as
  root from the profile YAML. Profiles are trusted input; never widen that to
  remote or user-supplied YAML without an explicit decision.
- Do not log secrets, tokens or full credential values. Reports are written
  world-readable-by-root only.
- Never disable SELinux/AppArmor as a shortcut, and never restore
  `/etc/selinux/targeted` raw from a backup (it bricked a box once — see `a6d7828`).

## Map

| Path | What |
|------|------|
| `linuxharden.sh` | The entire tool (~2100 lines, bash, `set -euo pipefail`). `main()` at the bottom dispatches modes: `run_install_deps`, `run_scan_full`, `run_scan`, `run_scan_lynis`, `run_scan_cve`, `run_fix_cve`, `run_apply`, `run_unapply`, `run_uninstall`, `run_confirm` (+ `run_*_arch` fallbacks). |
| `profiles/*.yml` | One per distro (9). Parsed by `parse_conf()` (python3 + PyYAML). Auto-selected as `${DISTRO_ID}-${DISTRO_VERSION}.yml` by `detect_distro()`. |
| `todo.md` | The single planning doc (Turkish): status · ranked backlog P0–P3 · Web UI plan FAZ W0–W8 (not started, design binding) · test procedure · archive of finished phases. Work top to bottom. |
| `docs/` | Architecture docs (final target state): `architecture.md`, `script-internals.md`, `fleet-webui.md`. Keep in sync when modes/flows change. |
| `scripts/check-docs.py` | Verifies every relative Markdown link and anchor resolves. |
| `cliff.toml` | git-cliff config. Conventional commits required. |
| `CHANGELOG.md` | Generated by `git cliff`. **Never edit by hand.** |
| `README.md` / `README_TR.md` | User-facing. Keep both in sync — an English-only change is half a change. |
| `reports/`, `tmp/` | Generated scan output / legacy scratch. Both gitignored; never commit contents. |

## Documentation upkeep

When a decision changes, update the document that owns it — do not leave two
documents disagreeing. `docs/` describes the **target state** and marks what ships
today (✅) versus what is planned (🔜); `todo.md` owns the backlog and the archive.

## Gotchas

- `.claude/`, `reports/`, `/tmp/` are gitignored. `tmp/*.sh` are legacy
  `oscap generate fix` drafts, not part of the tool.
- Debian/Fedora ship no CIS profile in SSG → they use ANSSI BP-028 / OSPP; there
  `--level 2|1` means strict|light baseline, not literal CIS levels.
- RHEL-family rebuilds (Rocky/Alma) don't use OVAL for `--scan-cve` (it
  over-reports); they use native `dnf updateinfo` (`scan_cve_dnf()`).
- SSG only masks services present at apply time — installing nginx/apache *after*
  hardening leaves them active (golden-image order matters: harden first, then apps).
- `detect_active_services()` auto-excludes service rules when not on a TTY; on a
  TTY it prompts.
- The repo is checked out on Windows too: `.gitattributes` forces LF on `*.sh` and
  `*.yml`. A CRLF script fails on the target with an opaque error.
