# hardenix — Lynis Entegrasyonu Planı (script-only, v1.2.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Hedef:** Lynis'i ikinci görüş denetim motoru olarak `linuxharden.sh`'e eklemek:
`--install` ailesi (varsayılan = OpenSCAP + Lynis, tekli bayraklar), `--scan-lynis`
modu ve `--scan`'in birleşik durum taramasına dönüşmesi (`--scan-compliance` eski
davranışı korur). Web UI / Ansible orkestrasyonu **2.0'a ertelendi** — bu plan
yalnız scripte dokunur.

**Mimari:** Tamamen additive. Lynis paket yöneticisinden kurulur (repo'ya
vendor edilmez); `packages.lynis` profillerden gelir (yoksa `lynis` varsayılır).
Mutasyon modları (`--apply`, `--fix-cve`, `--unapply`) **değişmez** — revert
sözleşmesi ve deadman semantiği aynen korunur. `--min-score` yalnız compliance
skorunu gate'ler.

**Stack:** bash 5 (`set -euo pipefail`), mevcut log/confirm/spinner yardımcıları,
Lynis raporu `/var/log/lynis-report.dat` (key=value; `hardening_index=NN`,
`warning[]=TEST-ID|metin|...`, `suggestion[]=...`).

## Global Kısıtlar

- Branch: `feature/lynis` (main'den açılır; fazlar bittikçe commit, sonda merge).
- Her task sonunda: `wsl bash -n ./linuxharden.sh` yeşil (+ `wsl shellcheck ./linuxharden.sh` varsa).
- Tüm kullanıcı çıktıları İngilizce; commit'ler conventional (İngilizce, imperative).
- Kod `set -euo pipefail` altında yaşar: `grep -c ... || true`, `[[ ]] && x=y` kalıplarına dikkat.
- Davranış doğrulaması (root + gerçek Linux) VM gerektirir → Task 6 kullanıcı geçidi;
  Task 1-5 içindeki otomatik doğrulamalar root gerektirmeyen `--help`/`bash -n`/grep kontrolleridir.
- `SCRIPT_VERSION` 1.1.0 → **1.2.0** yalnız Task 5'te bump edilir.
- Satır numaraları sürüklenir — konum tarifleri fonksiyon adlarıyla verilmiştir.

## Karar Özeti (bağlam)

| Komut | Davranış |
|---|---|
| `--install` | OpenSCAP + SSG + Lynis. Lynis kurulamazsa **uyar + devam + exit 0** (RHEL ailesinde EPEL ipucu basılır) |
| `--install-openscap` | Yalnız OpenSCAP + SSG (bugünkü `--install`) |
| `--install-lynis` | Yalnız Lynis; kurulamazsa **hard fail** |
| `--scan` | Birleşik: compliance → Lynis → CVE. Lynis yoksa / OVAL yoksa o katman uyarıyla atlanır. `--min-score` en sonda uygulanır |
| `--scan-compliance` | Bugünkü `--scan` (yalnız OpenSCAP; `--min-score` anında) |
| `--scan-lynis` | Yalnız Lynis; lynis yoksa hard fail (`--install-lynis` işaret edilir) |
| `--uninstall` | Lynis kuruluysa onu da kaldırır |
| Arch | `--scan` = arch_basic_check + Lynis katmanı; `--scan-compliance` = yalnız basic check; `--scan-lynis` çalışır |

---

### Task 1: Kurulum ailesi — profiller, parse_conf, `--install-*` bayrakları

**Files:**
- Modify: `profiles/*.yml` (9 dosya) — `packages.lynis` alanı
- Modify: `linuxharden.sh` — globals bloğu, `usage()`, `parse_args()`, `parse_conf()`,
  yeni `install_lynis_pkg()`, `run_install_deps()` (tam yeniden yazım), `main()` install dispatch

**Interfaces:**
- Produces: global `LYNIS_PKG` (parse_conf doldurur, varsayılan `lynis`);
  `install_lynis_pkg(strict)` — `strict=true` → başarısızlıkta exit 1, `false` → warn+return 0;
  `run_install_deps(component)` — `component ∈ all|openscap|lynis`, varsayılan `all`;
  MODE değerleri: `install`, `install_openscap`, `install_lynis`.

- [ ] **Step 1: 9 profile `packages.lynis` ekle**

Her `profiles/*.yml` dosyasında `packages:` bölümüne `lynis:` satırı eklenir.
Debian/Ubuntu/openSUSE/Fedora/Arch için:

```yaml
packages:
  manager: apt-get          # (mevcut satır — dosyaya göre değişir)
  oscap: openscap-utils     # (mevcut satır)
  ssg: ssg-base ssg-debderived  # (mevcut satır)
  lynis: lynis
```

`rhel-9.yml`, `rocky-9.yml`, `almalinux-9.yml` için EPEL yorumu ile:

```yaml
  lynis: lynis   # EPEL'de — eksikse önce: dnf install -y epel-release
```

- [ ] **Step 2: Globals bloğuna `LYNIS_PKG` ekle**

`linuxharden.sh` üst blokta `PKG_MANAGER="" OSCAP_PKG="" ...` satırının bulunduğu
"Populated by parse_conf" grubuna:

```bash
LYNIS_PKG=""            # packages.lynis (default: lynis) — for --install / --scan-lynis
```

- [ ] **Step 3: `parse_conf()` python bölümüne LYNIS_PKG çıktısı ekle**

`print(f'SSG_PKG=...')` satırından hemen sonra:

```python
print(f'LYNIS_PKG={q(pkgs.get("lynis","lynis"))}')
```

- [ ] **Step 4: `parse_args()` yeni modlar**

`--install)   MODE="install" ;;` satırının altına:

```bash
            --install-openscap) MODE="install_openscap" ;;
            --install-lynis)    MODE="install_lynis" ;;
```

- [ ] **Step 5: `usage()` güncelle**

Modes bölümünde `--install` satırını değiştir ve iki satır ekle:

```bash
    echo "  --install           Install OpenSCAP + SCAP content + Lynis for this distro"
    echo "  --install-openscap  Install only OpenSCAP + SCAP content"
    echo "  --install-lynis     Install only Lynis (audit engine)"
```

- [ ] **Step 6: `install_lynis_pkg()` fonksiyonunu ekle**

`run_install_deps()` fonksiyonunun hemen ÜSTÜNE:

```bash
# Install Lynis. strict=true (--install-lynis): failure exits non-zero.
# strict=false (--install): warn and continue — Lynis is a second-opinion
# layer; its absence must not fail the core OpenSCAP setup.
install_lynis_pkg() {
    local strict="${1:-false}"

    if command -v lynis &>/dev/null; then
        log_info "Lynis already installed."
        return 0
    fi

    log_info "Installing Lynis (${LYNIS_PKG})..."
    local rc=0
    # shellcheck disable=SC2086
    case "$PKG_MANAGER" in
        apt-get) apt-get install -y $LYNIS_PKG || rc=$? ;;
        dnf|yum) "$PKG_MANAGER" install -y $LYNIS_PKG || rc=$? ;;
        zypper)  zypper install -y $LYNIS_PKG || rc=$? ;;
        pacman)  pacman -S --noconfirm $LYNIS_PKG || rc=$? ;;
    esac

    if [[ $rc -ne 0 ]]; then
        if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
            echo -e "  Hint: Lynis lives in ${BOLD}EPEL${NC} — enable it first:"
            echo -e "        ${BOLD}${PKG_MANAGER} install -y epel-release${NC}"
        fi
        if [[ "$strict" == "true" ]]; then
            log_error "Lynis installation failed."
            exit 1
        fi
        log_warn "Lynis could not be installed — skipping (compliance/CVE features unaffected)."
        echo -e "  Retry later with: ${BOLD}sudo $(basename "$0") --install-lynis${NC}"
        return 0
    fi
    log_info "Lynis ready."
}
```

- [ ] **Step 7: `run_install_deps()` fonksiyonunu component parametreli tam haliyle değiştir**

Mevcut fonksiyonun TAMAMI şununla değiştirilir (pm/py_pkg türetme, universe,
apt update, python3-yaml blokları aynen korunur — yalnız başlık, arch dalı ve
sonu değişir):

```bash
run_install_deps() {
    local component="${1:-all}"    # all | openscap | lynis

    case "$component" in
        all)      log_section "Installing Dependencies (OpenSCAP + Lynis)" ;;
        openscap) log_section "Installing OpenSCAP Dependencies" ;;
        lynis)    log_section "Installing Lynis" ;;
    esac

    # Derive package manager from distro before parse_conf (python3-yaml not yet installed)
    local pm py_pkg
    case "$DISTRO_ID" in
        ubuntu|debian)
            pm="apt-get"; py_pkg="python3-yaml" ;;
        rhel|centos|rocky|almalinux|fedora)
            pm="dnf"; py_pkg="python3-pyyaml" ;;
        opensuse*|sles)
            pm="zypper"; py_pkg="python3-PyYAML" ;;
        arch)
            pm="pacman"; py_pkg="python-yaml" ;;
        *)
            log_error "Unsupported distro for automatic installation: $DISTRO_ID"
            exit 1 ;;
    esac

    # Ubuntu: enable universe repo first
    if [[ "$DISTRO_ID" == "ubuntu" ]]; then
        log_info "Enabling universe repository..."
        if ! grep -rq "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
            add-apt-repository -y universe
        fi
    fi

    # Update package lists for apt systems
    if [[ "$pm" == "apt-get" ]]; then
        log_info "Updating package lists..."
        apt-get update -q
    fi

    # Install python3-yaml so parse_conf can run
    log_info "Installing python3-yaml..."
    case "$pm" in
        apt-get) apt-get install -y "$py_pkg" ;;
        dnf)     dnf install -y "$py_pkg" ;;
        zypper)  zypper install -y "$py_pkg" ;;
        pacman)  pacman -S --noconfirm "$py_pkg" ;;
    esac

    # Parse the profile to get PKG_MANAGER, OSCAP_PKG, SSG_PKG, XML_PATH, LYNIS_PKG
    parse_conf

    if [[ "$component" != "lynis" ]]; then
        if [[ "$ARCH_FALLBACK" == "true" ]]; then
            # Arch: openscap only, no SSG
            log_info "Arch Linux: installing openscap (no SSG available)..."
            pacman -S --noconfirm openscap
            log_info "Use --apply for basic hardening mode."
        else
            # Install openscap
            log_info "Installing OpenSCAP (${OSCAP_PKG})..."
            # shellcheck disable=SC2086
            case "$PKG_MANAGER" in
                apt-get) apt-get install -y $OSCAP_PKG ;;
                dnf)     dnf install -y $OSCAP_PKG ;;
                zypper)  zypper install -y $OSCAP_PKG ;;
                pacman)  pacman -S --noconfirm $OSCAP_PKG ;;
            esac

            # Install SSG packages from distro repo (best-effort)
            if [[ -n "$SSG_PKG" ]]; then
                log_info "Installing SCAP Security Guide (${SSG_PKG})..."
                # shellcheck disable=SC2086
                case "$PKG_MANAGER" in
                    apt-get) apt-get install -y $SSG_PKG 2>/dev/null \
                        || log_warn "Some SSG packages not in distro repo — will try GitHub." ;;
                    dnf)    dnf install -y $SSG_PKG ;;
                    zypper) zypper install -y $SSG_PKG ;;
                esac
            fi

            # If XML content is still missing, download from GitHub
            if [[ -n "$XML_PATH" && ! -f "$XML_PATH" ]]; then
                log_warn "SCAP content not found: $XML_PATH"
                install_ssg_from_github
            else
                log_info "SCAP content: $XML_PATH"
            fi

            local ver; ver=$(oscap --version 2>&1 | awk 'NR==1{print $NF}')
            log_info "oscap ${ver} — ready"
        fi
    fi

    if [[ "$component" != "openscap" ]]; then
        local strict="false"
        [[ "$component" == "lynis" ]] && strict="true"
        install_lynis_pkg "$strict"
    fi

    echo ""
    log_info "All requested components installed."
    if [[ "$component" != "lynis" ]]; then
        echo -e "  Next: ${BOLD}sudo bash $(basename "$0") --apply${NC}"
    fi
}
```

- [ ] **Step 8: `main()` install dispatch**

Mevcut `if [[ "$MODE" == "install" ]]; then run_install_deps; return; fi` bloğu
şununla değiştirilir:

```bash
    case "$MODE" in
        install)          run_install_deps all;      return ;;
        install_openscap) run_install_deps openscap; return ;;
        install_lynis)    run_install_deps lynis;    return ;;
    esac
```

- [ ] **Step 9: Doğrula**

```
wsl bash -n ./linuxharden.sh                                  → sessiz (exit 0)
wsl bash ./linuxharden.sh --help | grep -c "install-"         → 2
grep -c "lynis:" profiles/*.yml                               → her dosyada 1 (9 dosya)
```

- [ ] **Step 10: Commit**

```bash
git add linuxharden.sh profiles/
git commit -m "feat: add --install-lynis/--install-openscap; --install now includes lynis"
```

---

### Task 2: `--scan-lynis` modu

**Files:**
- Modify: `linuxharden.sh` — constants, `usage()`, `parse_args()`, yeni
  `run_scan_lynis()` + `print_lynis_summary()`, `main()` skip-listesi + dispatch

**Interfaces:**
- Consumes: `install_lynis_pkg` yok — yalnız `lynis` binary'si; `REPORT_DIR`, `_spin`, log yardımcıları.
- Produces: `run_scan_lynis()` (hard-fail'li tekil mod; Task 3 bunu birleşik akışta
  yeniden kullanır), `print_lynis_summary(dat_path)`, readonly `LYNIS_REPORT_DAT`,
  MODE `scan_lynis`.

- [ ] **Step 1: Constant ekle**

Üstteki `readonly STATE_FILE=...` satırının altına:

```bash
readonly LYNIS_REPORT_DAT="/var/log/lynis-report.dat"   # written by `lynis audit system`
```

- [ ] **Step 2: `parse_args()` + `usage()`**

parse_args'ta `--scan)` satırının altına:

```bash
            --scan-lynis)       MODE="scan_lynis" ;;
```

usage()'da `--scan-cve` satırının üstüne:

```bash
    echo "  --scan-lynis        Lynis audit only: hardening index (0-100) + warnings"
```

- [ ] **Step 3: Yeni bölümü ekle — `run_scan_cve()` fonksiyonu ile "Security Patching" yorum bloğu arasına**

```bash
# ── Lynis Audit (second-opinion engine) ─────────────────────────────────────────

# Print hardening index + warnings/suggestions from a lynis-report.dat file.
print_lynis_summary() {
    local dat="$1"
    local index warns sugg
    index=$(awk -F'=' '/^hardening_index=/{print $2}' "$dat")
    warns=$(grep -c '^warning\[\]=' "$dat" || true)
    sugg=$(grep -c '^suggestion\[\]=' "$dat" || true)

    echo ""
    echo -e "  ┌─ Lynis Audit Summary ────────────────────────┐"
    printf  "  │  Hardening index   : %-23s │\n" "${index:-?}/100"
    printf  "  │  Warnings          : %-23s │\n" "${warns:-0}"
    printf  "  │  Suggestions       : %-23s │\n" "${sugg:-0}"
    echo -e "  └──────────────────────────────────────────────┘"

    if [[ "${warns:-0}" -gt 0 ]]; then
        echo ""
        echo -e "  ${BOLD}Warnings:${NC}"
        grep '^warning\[\]=' "$dat" | cut -d'=' -f2- \
            | awk -F'|' '{printf "    • [%s] %s\n", $1, $2}'
    fi
}

# Run a full Lynis system audit and summarize the report.
run_scan_lynis() {
    log_section "Lynis Audit (second opinion)"

    if ! command -v lynis &>/dev/null; then
        log_error "lynis not found — run ${BOLD}--install-lynis${NC} first."
        exit 1
    fi

    mkdir -p "$REPORT_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M%S)

    local pid
    lynis audit system --quiet --no-colors >/dev/null 2>&1 &
    pid=$!
    _spin "$pid" "Auditing system with Lynis..."
    wait "$pid" 2>/dev/null || true

    if [[ ! -f "$LYNIS_REPORT_DAT" ]]; then
        log_error "Lynis produced no report ($LYNIS_REPORT_DAT)."
        exit 1
    fi

    local report_copy="${REPORT_DIR}/lynis_${ts}.dat"
    cp "$LYNIS_REPORT_DAT" "$report_copy"
    log_info "Report : $report_copy"
    print_lynis_summary "$LYNIS_REPORT_DAT"
}
```

- [ ] **Step 4: `main()` — skip listesi + dispatch**

XCCDF hazırlık koşulundaki mod listesine `scan_lynis` ekle (mevcut koşul
`"$MODE" != "scan_cve" && "$MODE" != "fix_cve"` kısmına):

```bash
    if [[ "$MODE" != "unapply" && "$MODE" != "unapply_arch" && "$MODE" != "uninstall" \
          && "$MODE" != "scan_cve" && "$MODE" != "fix_cve" && "$MODE" != "scan_lynis" ]]; then
```

Dispatch case'ine `scan_cve)` satırının üstüne:

```bash
        scan_lynis)    run_scan_lynis ;;
```

- [ ] **Step 5: Doğrula**

```
wsl bash -n ./linuxharden.sh                                  → exit 0
wsl bash ./linuxharden.sh --help | grep -c "scan-lynis"       → 1
```

- [ ] **Step 6: Commit**

```bash
git add linuxharden.sh
git commit -m "feat: add --scan-lynis audit mode (hardening index + warnings)"
```

---

### Task 3: Birleşik `--scan` + `--scan-compliance` (+ Arch varyantları)

**Files:**
- Modify: `linuxharden.sh` — globals, `usage()`, `parse_args()`, `parse_conf()` arch
  remap, `enforce_min_score()` (yeni) + `run_scan()` gate refactor, yeni
  `run_scan_full()`, `run_scan_arch()` genişletme, yeni `run_scan_compliance_arch()`,
  `main()` dispatch

**Interfaces:**
- Consumes: `run_scan()` (Task öncesi mevcut), `run_scan_lynis()` (Task 2),
  `run_scan_cve()` (mevcut), `get_score()` (mevcut).
- Produces: `enforce_min_score(arf)`; globals `DEFER_MIN_SCORE` (bool),
  `LAST_SCAN_ARF` (path); `run_scan_full()`; MODE'lar: `scan` (artık birleşik),
  `scan_compliance`, `scan_compliance_arch`.

- [ ] **Step 1: Globals**

"Runtime flags" bloğuna (`MIN_SCORE=""` satırının altına):

```bash
DEFER_MIN_SCORE=false   # true during --scan (combined): gate runs after all layers
LAST_SCAN_ARF=""        # set by run_scan; consumed by run_scan_full's final gate
```

- [ ] **Step 2: `parse_args()` + `usage()`**

parse_args: `--scan)` satırının altına (Task 2'nin scan-lynis satırının üstü/altı fark etmez):

```bash
            --scan-compliance)  MODE="scan_compliance" ;;
```

usage(): `--scan` satırını değiştir, altına compliance satırı ekle:

```bash
    echo "  --scan              Full posture scan: compliance + Lynis audit + known CVEs"
    echo "  --scan-compliance   Compliance scan only (OpenSCAP)"
```

- [ ] **Step 3: `parse_conf()` arch remap güncelle**

Mevcut satır:

```bash
        case "$MODE" in
            scan|apply|unapply) MODE="${MODE}_arch" ;;
        esac
```

Yeni:

```bash
        case "$MODE" in
            scan|scan_compliance|apply|unapply) MODE="${MODE}_arch" ;;
        esac
```

- [ ] **Step 4: `enforce_min_score()` ekle + `run_scan()` gate'ini değiştir**

`get_score()` fonksiyonunun (Score Helpers bölümü) hemen altına:

```bash
# --min-score gate: exit 2 when the compliance score is below the threshold.
enforce_min_score() {
    local arf="$1"
    [[ -z "$MIN_SCORE" ]] && return 0
    local score; score=$(get_score "$arf")
    if (( ${score%.*} < MIN_SCORE )); then
        log_error "Score ${score}% is below --min-score ${MIN_SCORE}%."
        exit 2
    fi
    log_info "Score ${score}% meets --min-score ${MIN_SCORE}%."
}
```

`run_scan()` içindeki mevcut `# --min-score: fail ...` ile başlayan 10 satırlık
blok (if [[ -n "$MIN_SCORE" ]] ... fi) şununla değiştirilir:

```bash
    LAST_SCAN_ARF="$arf_file"
    # --min-score gate — deferred during the combined --scan so the Lynis and
    # CVE layers still run; run_scan_full enforces it at the very end.
    [[ "$DEFER_MIN_SCORE" == true ]] || enforce_min_score "$arf_file"
```

- [ ] **Step 5: `run_scan_full()` ekle — Task 2'de eklenen Lynis bölümünün altına**

```bash
# ── Combined Posture Scan (--scan) ──────────────────────────────────────────────
# All read-only layers in one run: compliance (OpenSCAP) → Lynis audit → CVE scan.
# Compliance is required (core); Lynis and CVE layers are skipped with a warning
# when their tooling/feed is missing. --min-score is enforced last.
run_scan_full() {
    DEFER_MIN_SCORE=true
    run_scan

    echo ""
    if command -v lynis &>/dev/null; then
        run_scan_lynis
    else
        log_warn "Lynis not installed — skipping audit layer (enable with --install-lynis)."
    fi

    echo ""
    if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || -n "$OVAL_URL" ]]; then
        run_scan_cve
    else
        log_warn "No OVAL feed configured (scap.oval_url) — skipping CVE layer."
    fi

    DEFER_MIN_SCORE=false
    [[ -n "$LAST_SCAN_ARF" ]] && enforce_min_score "$LAST_SCAN_ARF" || true
}
```

- [ ] **Step 6: Arch varyantları**

Mevcut `run_scan_arch()` tek satırlık tanımı şununla değiştirilir:

```bash
run_scan_arch() {
    log_warn "Arch: full SCAP not available (no SSG)."
    arch_basic_check
    echo ""
    if command -v lynis &>/dev/null; then
        run_scan_lynis
    else
        log_warn "Lynis not installed — skipping audit layer (enable with --install-lynis)."
    fi
}

run_scan_compliance_arch() {
    log_warn "Arch: full SCAP not available (no SSG)."
    arch_basic_check
}
```

- [ ] **Step 7: `main()` dispatch**

```bash
    case "$MODE" in
        scan)                 run_scan_full ;;
        scan_compliance)      run_scan ;;
        scan_lynis)           run_scan_lynis ;;
        scan_cve)             run_scan_cve ;;
        fix_cve)              run_fix_cve ;;
        apply)                run_apply ;;
        unapply)              run_unapply ;;
        uninstall)            run_uninstall ;;
        scan_arch)            run_scan_arch ;;
        scan_compliance_arch) run_scan_compliance_arch ;;
        apply_arch)           run_apply_arch ;;
        unapply_arch)         run_unapply_arch ;;
    esac
```

- [ ] **Step 8: Doğrula**

```
wsl bash -n ./linuxharden.sh                                    → exit 0
wsl bash ./linuxharden.sh --help | grep -c "scan-compliance"    → 1
grep -c "run_scan_full" linuxharden.sh                          → 2 (tanım + dispatch)
```

- [ ] **Step 9: Commit**

```bash
git add linuxharden.sh
git commit -m "feat: make --scan a combined posture scan; add --scan-compliance"
```

---

### Task 4: `--uninstall` simetrisi

**Files:**
- Modify: `linuxharden.sh` — `run_uninstall()`

**Interfaces:**
- Consumes: `LYNIS_PKG` (Task 1).
- Produces: davranış — lynis kuruluysa kaldırılır; değilse paket komutlarına girmez.

- [ ] **Step 1: `run_uninstall()` düzenle**

Başlıktaki uyarı metnini güncelle:

```bash
    log_section "Reverting Hardening + Removing OpenSCAP/Lynis"
    echo -e "  ${YELLOW}${BOLD}WARNING:${NC} Hardening settings will be reverted first, then"
    echo -e "  OpenSCAP, SCAP content and Lynis packages will be removed."
```

`log_info "Removing OpenSCAP packages..."` satırını ve remove bloklarını güncelle
(lynis yalnız kuruluysa listeye girer — `dnf remove` olmayan pakette exit≠0 verir):

```bash
    log_info "Removing OpenSCAP/Lynis packages..."

    local lynis_rm=""
    command -v lynis &>/dev/null && lynis_rm="$LYNIS_PKG"

    # Note: stderr is intentionally NOT suppressed — a silent `|| true` here
    # once masked an apt-lock failure and reported a removal that never happened.
    local rc=0
    # shellcheck disable=SC2086
    case "$PKG_MANAGER" in
        apt-get)
            apt-get remove -y $OSCAP_PKG $SSG_PKG $lynis_rm || rc=$?
            apt-get autoremove -y || true
            ;;
        dnf)
            dnf remove -y $OSCAP_PKG $SSG_PKG $lynis_rm || rc=$?
            ;;
        zypper)
            zypper remove -y $OSCAP_PKG $SSG_PKG $lynis_rm || rc=$?
            ;;
        pacman)
            pacman -Rns --noconfirm openscap $lynis_rm || rc=$?
            ;;
    esac

    if [[ $rc -ne 0 ]]; then
        log_error "Package removal failed (exit $rc) — packages may still be installed."
        exit "$rc"
    fi
    log_info "OpenSCAP/Lynis packages removed."
```

- [ ] **Step 2: Doğrula + Commit**

```
wsl bash -n ./linuxharden.sh   → exit 0
git add linuxharden.sh
git commit -m "feat: remove lynis on --uninstall"
```

---

### Task 5: Dokümantasyon + sürüm

**Files:**
- Modify: `linuxharden.sh` (SCRIPT_VERSION), `README.md`, `README_TR.md`,
  `docs/script-internals.md`, `docs/architecture.md`, `CLAUDE.md`,
  `todo/TESTING.md`, `todo/webui-plan.md`

**Interfaces:** —

- [ ] **Step 1: `SCRIPT_VERSION="1.1.0"` → `"1.2.0"`**

- [ ] **Step 2: README.md**

Parameters tablosunda `--install` ve `--scan` satırlarını güncelle, yeni satırları ekle:

```markdown
| `--install` | Installs OpenSCAP + SCAP content + Lynis for the detected distro |
| `--install-openscap` | Installs only OpenSCAP + SCAP content |
| `--install-lynis` | Installs only Lynis (RHEL family: requires EPEL) |
| `--scan` | Full posture scan: compliance + Lynis audit + known CVEs (missing layers skipped) |
| `--scan-compliance` | Compliance scan only (OpenSCAP) |
| `--scan-lynis` | Lynis audit only: hardening index (0-100) + warnings |
```

Features bölümüne (CVE bloğunun altına) yeni alt bölüm:

```markdown
### Audit — second opinion (Lynis)
- **`--scan-lynis`** — [Lynis](https://github.com/CISOfy/lynis) system audit:
  hardening index (0-100), warnings and suggestions — an OpenSCAP-independent
  second opinion (and the only audit engine available on Arch)
- Plain **`--scan`** now runs every read-only layer in one go: compliance +
  Lynis + CVE. Missing layers are skipped with a warning; use
  `--scan-compliance` for the old single-engine behavior. `--min-score` still
  gates the compliance score only.
```

Not: `Supported Distributions` tablosundaki Arch satırına " + Lynis audit" ibaresi eklenir.

- [ ] **Step 3: README_TR.md — aynı içerik Türkçe**

Parametre tablosu satırları:

```markdown
| `--install` | Tespit edilen dağıtım için OpenSCAP + SCAP içeriği + Lynis kurar |
| `--install-openscap` | Yalnız OpenSCAP + SCAP içeriği kurar |
| `--install-lynis` | Yalnız Lynis kurar (RHEL ailesi: EPEL gerekir) |
| `--scan` | Tam durum taraması: compliance + Lynis denetimi + bilinen CVE'ler (eksik katman atlanır) |
| `--scan-compliance` | Yalnız compliance taraması (OpenSCAP) |
| `--scan-lynis` | Yalnız Lynis denetimi: hardening index (0-100) + uyarılar |
```

Özellikler bölümüne eşdeğer "Denetim — ikinci görüş (Lynis)" alt bölümü eklenir
(Step 2'deki metnin Türkçesi).

- [ ] **Step 4: docs/script-internals.md**

"Modes" bölümüne `--scan-lynis` ve birleşik `--scan` anlatımı, `--install`
ailesine component parametresi notu eklenir; pipeline şemasındaki dispatch satırı
yeni modlarla güncellenir. docs/architecture.md katman tablosuna satır eklenir:

```markdown
| 1b. Second-opinion audit | Lynis hardening index, warnings | `--scan-lynis` (also inside `--scan`) | ✅ |
```

- [ ] **Step 5: CLAUDE.md haritası**

Map tablosundaki `linuxharden.sh` satırında mode listesine `run_scan_full`,
`run_scan_lynis` eklenir.

- [ ] **Step 6: todo/TESTING.md — smoke döngüsüne Lynis satırları**

"Smoke test" bloğunun altına:

```sh
sudo bash linuxharden.sh --scan-lynis          # hardening index üretmeli
sudo bash linuxharden.sh --scan                # 3 katman: compliance + lynis + cve
```

- [ ] **Step 7: todo/webui-plan.md — Notlar bölümüne tek satır**

```markdown
- v1.2.0'dan itibaren script'te `--scan-lynis` var: FAZ W5'teki Lynis işi artık
  kendi kurulum/çalıştırma akışını kurmaz — `--scan-lynis --yes` çağırıp
  `reports/lynis_*.dat` dosyasını çeker (diğer scan işleriyle aynı kalıp).
```

- [ ] **Step 8: Doğrula + Commit**

```
wsl bash -n ./linuxharden.sh   → exit 0
wsl bash ./linuxharden.sh --help | head -20   → yeni modlar görünür, sürüm banner'ı 1.2.0
git add -A
git commit -m "docs: document lynis integration; bump version to 1.2.0"
```

---

### Task 6: VM doğrulama geçidi (kullanıcı çalıştırır — Ubuntu 24.04 test kutusu)

Bu görev commit üretmez; `todo/TESTING.md` prosedürünün Lynis genişletmesidir.
Snapshot'a dönülebilir VM'de sırayla:

- [ ] `--install` → openscap **ve** lynis kurulu (`command -v lynis`)
- [ ] `--scan-lynis` → hardening index + warnings özeti; `reports/lynis_*.dat` oluştu
- [ ] `--scan` → üç katman sırayla çalıştı (compliance skoru ~%65 baseline, lynis
      index, CVE özeti); `--min-score 99` ile exit code 2 ve üç katmanın DA çalıştığı
      doğrulanır (gate en sonda)
- [ ] `--scan-compliance` → yalnız OpenSCAP çıktısı (eski davranışla birebir)
- [ ] lynis'i kaldırıp (`apt-get remove lynis`) `--scan` → "skipping audit layer"
      uyarısıyla diğer katmanlar çalışıyor
- [ ] `--install-lynis` → yalnız lynis kuruldu
- [ ] `--uninstall` → lynis + openscap kalktı
- [ ] **Stale-report koruması:** `--scan-lynis` iki kez çalıştır → lynis'i boz
      (`chmod -x $(command -v lynis)`) → `--scan-lynis` eski raporu basmak yerine
      "did not produce a fresh report" hatası veriyor (exit 1)
- [ ] `--confirm` (deadman yokken) ve `--help` exit code **0** dönüyor (EXIT-trap fix)
- [ ] (Varsa Rocky 9 kutusu) EPEL'siz `--install` → lynis uyarı + exit 0; EPEL sonrası
      `--install-lynis` → başarılı
- [ ] Smoke döngüsü (TESTING.md) hâlâ yeşil: scan → dry-run → apply L1 → scan → unapply → scan

**Geçit:** hepsi ✅ → `feature/lynis` → `main` merge.

---

## Kapsam Dışı (bilinçli)

- `--apply`/`--fix-cve` birleşimi yok — revert sözleşmesi gereği ayrı kalırlar.
- Lynis kaynağını vendor'lamak yok — her zaman paket yöneticisi.
- `--min-index` (Lynis eşiği) v1'de yok; ihtiyaç doğarsa ayrı küçük faz.
- JSON rapora lynis alanı eklemek v1'de yok — `.dat` kopyası webui'nin (2.0)
  `parse_lynis_report()` girdisi olarak yeterli.
- Web UI + Ansible entegrasyonu → 2.0 (`todo/webui-plan.md`).
