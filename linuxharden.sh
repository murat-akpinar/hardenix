#!/bin/bash

set -euo pipefail

readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_BASE="/var/lib/linuxharden"
readonly REPORT_DIR="$(pwd)/reports"
readonly TMP_DIR="/tmp/linuxharden_$$"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# Runtime flags
MODE="" REPORT_FORMAT="html" LOCAL_CONF="" CONF_FILE=""
DRY_RUN=false
# ENV_PROFILE is the internal key into scap.profiles; it is driven solely by --level.
# Default: level 2 (strict). --level 1 switches to the basic baseline.
ENV_PROFILE="production"
SEC_LEVEL="2" SEC_LEVEL_LABEL="CIS Level 2 (strict)"

# Populated by parse_conf
PKG_MANAGER="" OSCAP_PKG="" SSG_PKG="" XML_PATH="" PROFILE_ID="" ARCH_FALLBACK="false"
BACKUP_DIRS="" EXCLUSION_RULES="" EXCLUSION_SERVICES="" EXCLUSION_PATHS=""
HOOK_PRE="" HOOK_POST="" HOOK_ROLLBACK=""

# Set after parse_conf + setup_tailoring
ACTIVE_PROFILE_ID="" TAILORING_FILE=""

# ── Logging ───────────────────────────────────────────────────────────────────

log_info()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1" >&2; }

# Spinner: _spin <pid> <message> — shows animated progress while pid is running
_spin() {
    local pid=$1 msg=$2
    # Non-interactive (pipe, CI, log file): print message once, no animation.
    # NOTE: must return 0 — oscap exits 2 when rules fail, and under
    # `set -e` a non-zero return from this bare call would abort the script.
    if [[ ! -t 1 ]]; then
        printf "  %s\n" "$msg"
        wait "$pid" 2>/dev/null || true
        return 0
    fi
    local frames=('|' '/' '-' '\') i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}[%s]${NC}  %s" "${frames[i % 4]}" "$msg"
        i=$((i + 1))
        sleep 0.12
    done
    printf "\r%-72s\r" ""
}
log_section() {
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗██╗  ██╗"
    echo "  ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║╚██╗██╔╝"
    echo "  ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║ ╚███╔╝ "
    echo "  ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║ ██╔██╗ "
    echo "  ██║  ██║██║  ██║██║  ██╗██████╔╝███████╗██║ ╚████║██║██╔╝ ██╗"
    echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Linux Hardening Script v${SCRIPT_VERSION}${NC} — powered by OpenSCAP"
    echo ""
}

usage() {
    echo -e "${BOLD}Usage:${NC} $(basename "$0") [MODE] [OPTIONS]"
    echo ""
    echo -e "${BOLD}Modes:${NC}"
    echo "  --install           Install OpenSCAP + SCAP content for this distro"
    echo "  --uninstall         Revert hardening, then remove OpenSCAP + SCAP packages"
    echo "  --scan              Scan system compliance and generate report"
    echo "  --apply             Apply hardening (creates backup, then verifies)"
    echo "  --unapply           Revert hardening settings (keeps OpenSCAP installed)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --dry-run           Preview what would change without applying (implies --apply)"
    echo "  --level <1|2>       Hardening level: 1 = CIS Level 1 (basic), 2 = CIS Level 2 (strict, default)"
    echo "  --format <type>     Report format: html | json | both  (default: html)"
    echo "  --conf <file>       Use a local .yml instead of downloading"
    echo "  --help              Show this help"
    echo ""
    echo -e "${BOLD}Hardening levels:${NC}"
    echo "  Level 1  Basic, practical hardening — safe for everyday servers"
    echo "  Level 2  Strict hardening for high-security/regulated environments"
    echo "  (Debian → ANSSI BP28, Fedora → OSPP; level 2 = strict, level 1 = light)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  sudo $(basename "$0") --install"
    echo "  sudo $(basename "$0") --scan"
    echo "  sudo $(basename "$0") --dry-run"
    echo "  sudo $(basename "$0") --apply --level 1     # CIS Level 1 (basic)"
    echo "  sudo $(basename "$0") --apply --level 2     # CIS Level 2 (strict)"
    echo "  sudo $(basename "$0") --unapply"
    echo "  sudo $(basename "$0") --uninstall"
    exit 0
}

# ── Argument Parsing ──────────────────────────────────────────────────────────

parse_args() {
    if [[ $# -eq 0 ]]; then usage; fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scan)      MODE="scan" ;;
            --install)   MODE="install" ;;
            --uninstall) MODE="uninstall" ;;
            --apply)     MODE="apply" ;;
            --unapply)   MODE="unapply" ;;
            --dry-run)   DRY_RUN=true ;;
            --level)     shift; SEC_LEVEL="${1:-}" ;;
            --format)    shift; REPORT_FORMAT="${1:-html}" ;;
            --conf)      shift; LOCAL_CONF="${1:-}" ;;
            --help|-h)   usage ;;
            *) log_error "Unknown option: $1"; echo ""; usage ;;
        esac
        shift
    done

    if [[ "$DRY_RUN" == true && -z "$MODE" ]]; then MODE="apply"; fi
    if [[ -z "$MODE" ]]; then log_error "No mode specified."; echo ""; usage; fi

    case "$REPORT_FORMAT" in
        html|json|both) ;;
        *) log_error "Invalid --format: $REPORT_FORMAT (use: html | json | both)"; exit 1 ;;
    esac

    # --level picks the strict vs. basic baseline and maps onto the scap.profiles keys.
    case "$SEC_LEVEL" in
        1) ENV_PROFILE="development"; SEC_LEVEL_LABEL="CIS Level 1 (basic)" ;;
        2) ENV_PROFILE="production";  SEC_LEVEL_LABEL="CIS Level 2 (strict)" ;;
        *) log_error "Invalid --level: $SEC_LEVEL (use: 1 | 2)"; exit 1 ;;
    esac

    if [[ "$DRY_RUN" == true && "$MODE" != "apply" ]]; then
        log_warn "--dry-run only applies to --apply, ignoring."
        DRY_RUN=false
    fi
}

# ── Root Check ────────────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        echo -e "  Try: ${BOLD}sudo $(basename "$0") $*${NC}"
        exit 1
    fi
}

# ── Distro Detection ──────────────────────────────────────────────────────────

detect_distro() {
    [[ ! -f /etc/os-release ]] && { log_error "/etc/os-release not found."; exit 1; }

    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_ID="${ID,,}"
    DISTRO_VERSION="${VERSION_ID:-rolling}"
    DISTRO_PRETTY="${PRETTY_NAME:-$ID}"
    DISTRO_VERSION_MAJOR="${DISTRO_VERSION%%.*}"

    log_info "Detected: ${DISTRO_PRETTY}"
    log_info "Hardening level: ${SEC_LEVEL_LABEL}"
}

# ── Profile Resolution ────────────────────────────────────────────────────────

download_conf() {
    if [[ -n "$LOCAL_CONF" ]]; then
        [[ ! -f "$LOCAL_CONF" ]] && { log_error "Local conf not found: $LOCAL_CONF"; exit 1; }
        CONF_FILE="$LOCAL_CONF"
        log_info "Using local conf: $CONF_FILE"
        return
    fi

    local candidates=(
        "${DISTRO_ID}-${DISTRO_VERSION}.yml"
        "${DISTRO_ID}-${DISTRO_VERSION_MAJOR}.yml"
    )

    for conf_name in "${candidates[@]}"; do
        local local_path="${SCRIPT_DIR}/profiles/${conf_name}"
        if [[ -f "$local_path" ]]; then
            CONF_FILE="$local_path"
            log_info "Profile loaded: $conf_name"
            return
        fi
    done

    log_error "No compatible profile found for: ${DISTRO_PRETTY}"
    echo ""
    echo "  Available profiles: ${SCRIPT_DIR}/profiles/"
    echo "  Use a custom profile with: --conf /path/to/your.yml"
    exit 1
}

# ── YAML Dependency ───────────────────────────────────────────────────────────

check_pyyaml() {
    if python3 -c "import yaml" 2>/dev/null; then
        return
    fi

    log_error "python3-yaml (pyyaml) is required to parse .yml profiles."
    if   command -v apt-get &>/dev/null; then echo -e "  Install: ${BOLD}apt-get install python3-yaml${NC}"
    elif command -v dnf     &>/dev/null; then echo -e "  Install: ${BOLD}dnf install python3-pyyaml${NC}"
    elif command -v pacman  &>/dev/null; then echo -e "  Install: ${BOLD}pacman -S python-yaml${NC}"
    elif command -v zypper  &>/dev/null; then echo -e "  Install: ${BOLD}zypper install python3-PyYAML${NC}"
    fi
    exit 1
}

# ── .yml Parser ───────────────────────────────────────────────────────────────

parse_conf() {
    mkdir -p "$TMP_DIR"
    local py_script="${TMP_DIR}/parse_conf.py"

    cat > "$py_script" << 'PYEOF'
import sys, yaml, shlex

with open(sys.argv[1]) as f:
    c = yaml.safe_load(f)

env = sys.argv[2]

def q(v):
    return shlex.quote(str(v)) if v else "''"

def qlist(lst):
    if not lst:
        return "''"
    items = [str(x) for x in lst if x]
    return shlex.quote(' '.join(items))

meta  = c.get('meta', {})
pkgs  = c.get('packages', {})
scap  = c.get('scap', {})
bkup  = c.get('backup', {})
excl  = c.get('exclusions', {})
hooks = c.get('hooks', {})

profiles   = scap.get('profiles', {})
profile_id = profiles.get(env) or profiles.get('production') or ''

print(f'PKG_MANAGER={q(pkgs.get("manager",""))}')
print(f'OSCAP_PKG={q(pkgs.get("oscap",""))}')
print(f'SSG_PKG={q(pkgs.get("ssg",""))}')
print(f'XML_PATH={q(scap.get("xml_path",""))}')
print(f'PROFILE_ID={q(profile_id)}')
print(f'ARCH_FALLBACK={q(str(meta.get("arch_fallback", False)).lower())}')
print(f'BACKUP_DIRS={qlist(bkup.get("config_dirs", []))}')
print(f'EXCLUSION_RULES={qlist(excl.get("rules", []))}')
print(f'EXCLUSION_SERVICES={qlist(excl.get("services", []))}')
print(f'EXCLUSION_PATHS={qlist(excl.get("paths", []))}')
print(f'HOOK_PRE={q(hooks.get("pre_hardening",""))}')
print(f'HOOK_POST={q(hooks.get("post_hardening",""))}')
print(f'HOOK_ROLLBACK={q(hooks.get("on_rollback",""))}')
PYEOF

    local output
    if ! output=$(python3 "$py_script" "$CONF_FILE" "$ENV_PROFILE" 2>&1); then
        log_error "Failed to parse profile YAML:"
        echo "$output" >&2
        exit 1
    fi
    eval "$output"

    if [[ -z "$PKG_MANAGER" ]]; then log_error "Invalid .yml: missing packages.manager"; exit 1; fi

    if [[ "$ARCH_FALLBACK" == "true" ]]; then
        case "$MODE" in
            scan|apply|unapply) MODE="${MODE}_arch" ;;
        esac
        return
    fi

    if [[ -z "$XML_PATH" ]];   then log_error "Invalid .yml: missing scap.xml_path"; exit 1; fi
    if [[ -z "$PROFILE_ID" ]]; then log_error "Invalid .yml: missing scap.profiles.${ENV_PROFILE}"; exit 1; fi
}

# ── Dependency Check ──────────────────────────────────────────────────────────

check_dependencies() {
    local missing=0

    if ! command -v oscap &>/dev/null; then
        log_warn "openscap not installed."
        echo -e "  Install: ${BOLD}${PKG_MANAGER} install ${OSCAP_PKG}${NC}"
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            echo -e "  Hint: ${BOLD}apt-get update${NC} first, then install."
        fi
        missing=1
    fi

    if [[ ! -f "$XML_PATH" ]]; then
        log_warn "SCAP content not found: $XML_PATH"
        if [[ "$PKG_MANAGER" == "apt-get" ]] && dpkg -s ssg-debderived &>/dev/null; then
            local ssg_ver; ssg_ver=$(dpkg -s ssg-debderived | awk '/^Version:/{print $2}')
            log_warn "ssg-debderived ${ssg_ver} is installed but lacks content for this OS version."
            echo -e "  The distro package is too old — download newer content from GitHub:"
            echo -e "  ${BOLD}https://github.com/ComplianceAsCode/content/releases${NC}"
            echo -e "  Then place the xml file at: ${BOLD}$(dirname "$XML_PATH")/${NC}"
            echo ""
            echo -e "  Quick install (replace X.X.XX with latest version):"
            echo -e "  ${BOLD}wget https://github.com/ComplianceAsCode/content/releases/download/vX.X.XX/scap-security-guide-X.X.XX.zip${NC}"
            echo -e "  ${BOLD}unzip scap-security-guide-X.X.XX.zip${NC}"
            echo -e "  ${BOLD}cp scap-security-guide-X.X.XX/$(basename "$XML_PATH") $(dirname "$XML_PATH")/${NC}"
        else
            echo -e "  Install: ${BOLD}${PKG_MANAGER} install ${SSG_PKG}${NC}"
            if [[ "$PKG_MANAGER" == "apt-get" ]]; then
                echo -e "  Hint: packages are in the ${BOLD}universe${NC} repo."
                echo -e "  Run : ${BOLD}add-apt-repository universe && apt-get update${NC}"
            fi
        fi
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then echo ""; log_error "Missing dependencies. Aborting."; exit 1; fi

    local ver; ver=$(oscap --version 2>&1 | awk 'NR==1{print $NF}')
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    if [[ "$major" -lt 1 ]] || [[ "$major" -eq 1 && "$minor" -lt 3 ]]; then
        log_warn "oscap ${ver} is outdated — 1.3+ required for current SSG content."
        echo -e "  Reinstall: ${BOLD}apt-get install --reinstall ${OSCAP_PKG}${NC}"
        echo ""
        log_error "Incompatible oscap version. Aborting."
        exit 1
    fi
    log_info "oscap ${ver} — OK"
}

# ── Active Service Detection ──────────────────────────────────────────────────

detect_active_services() {
    [[ "$ARCH_FALLBACK" == "true" ]] && return

    local detected=()
    local rules_to_add=()

    local nfs_pkg_rule="xccdf_org.ssgproject.content_rule_package_nfs-kernel-server_removed"
    if [[ "$DISTRO_ID" != "ubuntu" && "$DISTRO_ID" != "debian" ]]; then
        nfs_pkg_rule="xccdf_org.ssgproject.content_rule_package_nfs-utils_removed"
    fi

    if systemctl is-active --quiet nfs-server 2>/dev/null || \
       systemctl is-active --quiet nfs-kernel-server 2>/dev/null; then
        detected+=("NFS sunucusu")
        rules_to_add+=(
            "xccdf_org.ssgproject.content_rule_service_nfs_disabled"
            "$nfs_pkg_rule"
            "xccdf_org.ssgproject.content_rule_package_rpcbind_removed"
            "xccdf_org.ssgproject.content_rule_service_rpcbind_disabled"
        )
    fi

    if systemctl is-active --quiet autofs 2>/dev/null; then
        detected+=("autofs")
        rules_to_add+=(
            "xccdf_org.ssgproject.content_rule_package_autofs_removed"
            "xccdf_org.ssgproject.content_rule_service_autofs_disabled"
        )
    fi

    if systemctl is-active --quiet smb 2>/dev/null || \
       systemctl is-active --quiet smbd 2>/dev/null; then
        detected+=("Samba (SMB)")
        rules_to_add+=("xccdf_org.ssgproject.content_rule_service_smb_disabled")
    fi

    [[ ${#detected[@]} -eq 0 ]] && return

    echo ""
    log_warn "Aktif ağ paylaşım servisleri tespit edildi:"
    for svc in "${detected[@]}"; do
        echo "    • $svc"
    done
    echo ""

    local add_exclusions=true
    if [[ -t 0 ]]; then
        echo -e "  CIS kuralları bu servisleri kaldırabilir veya devre dışı bırakabilir."
        printf "  İlgili kurallar hariç tutulsun mu? [E/h]: "
        local answer
        read -r answer
        case "${answer,,}" in
            h|n|no|hayır) add_exclusions=false ;;
        esac
    else
        log_warn "Etkileşimsiz mod — NFS/SMB kuralları otomatik olarak hariç tutuldu."
    fi

    if [[ "$add_exclusions" == true ]]; then
        for rule in "${rules_to_add[@]}"; do
            [[ "$EXCLUSION_RULES" != *"$rule"* ]] && \
                EXCLUSION_RULES="${EXCLUSION_RULES:+$EXCLUSION_RULES }$rule"
        done
        log_info "NFS/SMB kuralları hariç tutuldu (${#rules_to_add[@]} kural)."
    else
        log_warn "Servis koruma atlandı — ilgili kurallar uygulanacak."
    fi
}

# ── Profile Validation ────────────────────────────────────────────────────────

# Datastream içinde PROFILE_ID gerçekten var mı? yml'deki profil id'si yanlışsa
# oscap boş sonuç üretir ve script yanıltıcı bir %0.0 raporlar — erkenden yakala.
validate_profile() {
    [[ ! -f "$XML_PATH" ]] && return 0

    local profiles
    profiles=$(oscap info --profiles "$XML_PATH" 2>/dev/null | cut -d: -f1)
    [[ -z "$profiles" ]] && return 0  # oscap info desteklemiyorsa atla

    if ! grep -qxF "$PROFILE_ID" <<<"$profiles"; then
        log_error "Profile not found in datastream: $PROFILE_ID"
        echo ""
        echo "  Available profiles:"
        echo "$profiles" | sed 's/^/    • /'
        exit 1
    fi
}

# ── Tailoring File ────────────────────────────────────────────────────────────

setup_tailoring() {
    ACTIVE_PROFILE_ID="$PROFILE_ID"
    TAILORING_FILE=""

    if [[ -z "$EXCLUSION_RULES" ]]; then return; fi

    # Hariç tutulan rule ID'lerini datastream'e karşı doğrula — yazım hatası
    # olursa kural sessizce yok sayılır, kullanıcıyı uyaralım.
    if [[ -f "$XML_PATH" ]]; then
        local unknown=()
        for rule in $EXCLUSION_RULES; do
            grep -q "id=\"${rule}\"" "$XML_PATH" 2>/dev/null || unknown+=("$rule")
        done
        if [[ ${#unknown[@]} -gt 0 ]]; then
            log_warn "Datastream'de bulunamayan ${#unknown[@]} exclusion kuralı (yok sayılacak):"
            for r in "${unknown[@]}"; do
                echo "    • $r"
            done
        fi
    fi

    local tailored_id="xccdf_linuxharden.custom_profile_tailored"
    local tfile="${TMP_DIR}/tailoring.xml"
    mkdir -p "$TMP_DIR"

    python3 - "$XML_PATH" "$PROFILE_ID" "$EXCLUSION_RULES" "$tfile" "$tailored_id" <<'PYEOF' && {
import sys
from datetime import datetime, timezone

xml_path, profile_id, excl_str, out_file, new_id = sys.argv[1:]
excluded = [r for r in excl_str.split() if r]

if not excluded:
    sys.exit(0)

selects = '\n    '.join(
    f'<xccdf:select idref="{r}" selected="false"/>' for r in excluded
)

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')

xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<xccdf:Tailoring
    xmlns:xccdf="http://checklists.nist.gov/xccdf/1.2"
    id="xccdf_linuxharden.custom_tailoring_1">
  <xccdf:benchmark href="{xml_path}"/>
  <xccdf:version time="{now}">1</xccdf:version>
  <xccdf:Profile id="{new_id}" extends="{profile_id}">
    <xccdf:title>linuxharden Custom Profile</xccdf:title>
    <xccdf:description>Auto-generated tailoring — excluded rules from .yml</xccdf:description>
    {selects}
  </xccdf:Profile>
</xccdf:Tailoring>
'''
with open(out_file, 'w') as f:
    f.write(xml)
PYEOF
        TAILORING_FILE="$tfile"
        ACTIVE_PROFILE_ID="$tailored_id"
        local count; count=$(echo "$EXCLUSION_RULES" | wc -w)
        log_info "Tailoring: ${count} rule(s) excluded"
    } || log_warn "Tailoring generation failed — using original profile"
}

# Build oscap eval arguments array
oscap_eval_args() {
    local results_file="$1"
    local remediate="${2:-false}"

    local args=()
    [[ -n "$TAILORING_FILE" ]] && args+=(--tailoring-file "$TAILORING_FILE")
    args+=(--profile "$ACTIVE_PROFILE_ID")
    args+=(--results-arf "$results_file")
    [[ "$remediate" == "true" ]] && args+=(--remediate)
    args+=("$XML_PATH")
    echo "${args[@]}"
}

# ── Hooks ─────────────────────────────────────────────────────────────────────

run_hook() {
    local path="$1" name="$2"
    [[ -z "$path" ]] && return 0
    if [[ ! -f "$path" ]]; then
        log_warn "Hook not found ($name): $path"
        return 0
    fi
    if [[ ! -x "$path" ]]; then
        log_warn "Hook not executable ($name): $path"
        return 0
    fi
    log_info "Running hook: $name → $path"
    "$path" || log_warn "Hook exited non-zero: $path"
}

# ── Score Helpers ─────────────────────────────────────────────────────────────

get_score() {
    local arf="$1"
    [[ ! -f "$arf" ]] && echo "0" && return

    python3 - "$arf" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
NS = 'http://checklists.nist.gov/xccdf/1.2'
p = f = 0
for rr in ET.parse(sys.argv[1]).getroot().iter(f'{{{NS}}}rule-result'):
    r = rr.find(f'{{{NS}}}result')
    t = r.text.strip() if r is not None else ''
    if t == 'pass':   p += 1
    elif t == 'fail': f += 1
total = p + f
print(f"{round(p/total*100,1) if total > 0 else 0}")
PYEOF
}

print_improvement() {
    local before="$1" after="$2"
    echo ""
    python3 - "$before" "$after" <<'PYEOF'
import sys
b, a = float(sys.argv[1]), float(sys.argv[2])
diff = a - b
G = '\033[0;32m'; R = '\033[0;31m'; Y = '\033[1;33m'; B = '\033[1m'; NC = '\033[0m'
color = G if diff > 0 else (Y if diff == 0 else R)
val_b = f"{b}%"; val_a = f"{a}%"; val_c = f"{diff:+.1f}%"
print(f"  {B}┌─ Hardening Result {'─'*27}┐{NC}")
print(f"  │  Before : {val_b}{' '*(35-len(val_b))}│")
print(f"  │  After  : {val_a}{' '*(35-len(val_a))}│")
print(f"  │  Change : {color}{val_c}{NC}{' '*(35-len(val_c))}│")
print(f"  {B}└{'─'*46}┘{NC}")
PYEOF
}

# ── Package Helpers ───────────────────────────────────────────────────────────

# Print the sorted list of installed package names for the active manager.
snapshot_packages() {
    case "$PKG_MANAGER" in
        # Filter on install status 'ii' — dpkg-query also lists packages left in
        # the 'rc' (removed, config-files remain) state, which would mask a
        # `apt-get remove` from the reconcile diff.
        apt-get)        dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1=="ii"{print $2}' ;;
        dnf|yum|zypper) rpm -qa --qf '%{NAME}\n' 2>/dev/null ;;
        pacman)         pacman -Qq 2>/dev/null ;;
    esac | sort -u
}

pkg_install() {
    [[ $# -eq 0 ]] && return 0
    case "$PKG_MANAGER" in
        apt-get) apt-get install -y "$@" ;;
        dnf|yum) "$PKG_MANAGER" install -y "$@" ;;
        zypper)  zypper install -y "$@" ;;
        pacman)  pacman -S --noconfirm "$@" ;;
    esac
}

# ── Backup ────────────────────────────────────────────────────────────────────

create_backup() {
    local backup_dir="${BACKUP_BASE}/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    local dirs_to_backup=()
    IFS=' ' read -ra dirs_to_backup <<< "$BACKUP_DIRS"

    local existing=()
    for d in "${dirs_to_backup[@]}"; do
        # Skip exclusion paths
        local skip=false
        if [[ -n "$EXCLUSION_PATHS" ]]; then
            for ex in $EXCLUSION_PATHS; do
                [[ "$d" == "$ex" || "$d" == "$ex"/* ]] && skip=true && break
            done
        fi
        [[ "$skip" == false && -e "$d" ]] && existing+=("$d")
    done

    if [[ ${#existing[@]} -gt 0 ]]; then
        tar czf "${backup_dir}/configs.tar.gz" "${existing[@]}" 2>/dev/null \
            && log_info "Config files archived (${#existing[@]} dirs)" >&2 \
            || log_warn "Some files could not be archived" >&2
    fi

    # Exclude specified services from saved state
    local svc_filter="cat"
    if [[ -n "$EXCLUSION_SERVICES" ]]; then
        local ex_pattern; ex_pattern=$(echo "$EXCLUSION_SERVICES" | tr ' ' '|')
        svc_filter="grep -vE '($ex_pattern)'"
    fi

    systemctl list-units --type=service --state=enabled --no-legend --plain 2>/dev/null \
        | awk '{print $1}' \
        | eval "$svc_filter" \
        | sort > "${backup_dir}/services_enabled.txt"
    log_info "Service states saved" >&2

    # Snapshot installed packages so --unapply can reinstall any the
    # remediation removed (and remove any it added).
    snapshot_packages > "${backup_dir}/packages.txt"
    log_info "Package list saved ($(wc -l < "${backup_dir}/packages.txt") packages)" >&2

    # Save current .yml profile alongside backup
    cp "$CONF_FILE" "${backup_dir}/profile.yml" 2>/dev/null || true

    cat > "${backup_dir}/manifest.conf" <<EOF
[meta]
timestamp=$(date -Iseconds)
distro_pretty=${DISTRO_PRETTY}
distro_id=${DISTRO_ID}
distro_version=${DISTRO_VERSION}
profile_id=${PROFILE_ID}
active_profile_id=${ACTIVE_PROFILE_ID}
env=${ENV_PROFILE}
xml_path=${XML_PATH}
hook_rollback=${HOOK_ROLLBACK}
EOF

    ln -sfn "$backup_dir" "${BACKUP_BASE}/latest"
    log_info "Backup complete: $backup_dir" >&2
    echo "$backup_dir"
}

# ── Reports ───────────────────────────────────────────────────────────────────

generate_html_report() {
    local arf="$1" html="$2"
    if command -v oscap-report &>/dev/null; then
        oscap-report --output "$html" "$arf" 2>/dev/null \
            && log_info "HTML report: $html" \
            || log_warn "oscap-report failed (try: pip3 install openscap-report)"
    else
        oscap xccdf generate report --output "$html" "$arf" 2>/dev/null \
            && log_info "HTML report: $html" \
            || log_warn "HTML report generation failed"
    fi
}

generate_json_report() {
    local arf="$1" json="$2"
    command -v python3 &>/dev/null || { log_warn "python3 not found — JSON skipped"; return; }

    python3 - "$arf" "$json" <<'PYEOF'
import sys, json, xml.etree.ElementTree as ET

NS = 'http://checklists.nist.gov/xccdf/1.2'
p = f = e = o = 0
failed = []

for rr in ET.parse(sys.argv[1]).getroot().iter(f'{{{NS}}}rule-result'):
    rule_id = rr.get('idref', '')
    r = rr.find(f'{{{NS}}}result')
    t = r.text.strip() if r is not None else 'unknown'
    if t == 'pass':    p += 1
    elif t == 'fail':  f += 1; failed.append({'id': rule_id, 'result': t})
    elif t == 'error': e += 1
    else:              o += 1

total = p + f
out = {
    'summary': {
        'pass': p, 'fail': f, 'error': e, 'notchecked': o,
        'total': p + f + e + o,
        'score_pct': round(p / total * 100, 1) if total > 0 else 0.0,
    },
    'failed_rules': failed,
}
with open(sys.argv[2], 'w') as fp:
    json.dump(out, fp, indent=2)
PYEOF
    log_info "JSON report: $json"
}

print_failing_rules() {
    local arf="$1"
    [[ ! -f "$arf" ]] && return
    command -v python3 &>/dev/null || return

    python3 - "$arf" <<'PYEOF'
import sys
from collections import defaultdict
import xml.etree.ElementTree as ET

NS   = 'http://checklists.nist.gov/xccdf/1.2'
tree = ET.parse(sys.argv[1]).getroot()

rules = {}
for rule in tree.iter(f'{{{NS}}}Rule'):
    rid   = rule.get('id', '')
    title = rule.findtext(f'{{{NS}}}title') or ''
    sev   = rule.get('severity', 'unknown')
    rules[rid] = (title.strip(), sev)

SEV_ORDER = {'high': 0, 'medium': 1, 'low': 2, 'unknown': 3}
SEV_COLOR = {
    'high':    '\033[0;31m',
    'medium':  '\033[1;33m',
    'low':     '\033[0;34m',
    'unknown': '\033[0;37m',
}
NC   = '\033[0m'
BOLD = '\033[1m'

failed = []
for rr in tree.iter(f'{{{NS}}}rule-result'):
    r = rr.find(f'{{{NS}}}result')
    if r is not None and r.text and r.text.strip() == 'fail':
        rid = rr.get('idref', '')
        title, sev = rules.get(rid, ('', 'unknown'))
        short = rid.split('_rule_')[-1] if '_rule_' in rid else rid
        failed.append((SEV_ORDER.get(sev, 3), sev, short, title))

failed.sort()

if not failed:
    print(f"\n  {BOLD}No failing rules found.{NC}")
    sys.exit(0)

groups = defaultdict(list)
for _, sev, short, title in failed:
    groups[sev].append((short, title))

SEP_W = 72
RW    = 42
TW    = 34

for sev in ['high', 'medium', 'low', 'unknown']:
    items = groups.get(sev, [])
    if not items:
        continue
    col   = SEV_COLOR.get(sev, NC)
    label = f"  {sev.upper()}  ({len(items)} rule{'s' if len(items) != 1 else ''})"
    print(f"\n  {col}{'━' * SEP_W}{NC}")
    print(f"  {col}{BOLD}{label}{NC}")
    print(f"  {col}{'━' * SEP_W}{NC}")
    for short, title in items:
        r = (short[:RW-1] + '…') if len(short) > RW else short
        t = (title[:TW-1] + '…') if len(title) > TW else title
        print(f"    {r:<{RW}}  {t}")

counts = {s: len(groups.get(s, [])) for s in ['high', 'medium', 'low', 'unknown']}
total  = sum(counts.values())
parts  = []
for s in ['high', 'medium', 'low', 'unknown']:
    if counts[s]:
        col = SEV_COLOR.get(s, NC)
        parts.append(f"{col}{counts[s]} {s}{NC}")
print(f"\n  {BOLD}Total: {total} failing rules{NC}  ({'  ·  '.join(parts)})")
PYEOF
}

print_scan_summary() {
    local arf="$1"
    [[ ! -f "$arf" ]] && return
    command -v python3 &>/dev/null || return

    python3 - "$arf" <<'PYEOF'
import sys, xml.etree.ElementTree as ET

NS = 'http://checklists.nist.gov/xccdf/1.2'
p = f = e = o = 0

for rr in ET.parse(sys.argv[1]).getroot().iter(f'{{{NS}}}rule-result'):
    r = rr.find(f'{{{NS}}}result')
    t = r.text.strip() if r is not None else ''
    if t == 'pass':    p += 1
    elif t == 'fail':  f += 1
    elif t == 'error': e += 1
    else:              o += 1

total = p + f
score = round(p / total * 100, 1) if total > 0 else 0.0
G = '\033[0;32m'; R = '\033[0;31m'; Y = '\033[1;33m'; B = '\033[1m'; NC = '\033[0m'

score_str = f"{score}%"
print(f"\n  {B}┌─ Scan Summary {'─'*31}┐{NC}")
print(f"  │  {G}Pass       {NC}: {p:<6}                         │")
print(f"  │  {R}Fail       {NC}: {f:<6}                         │")
print(f"  │  {Y}Error      {NC}: {e:<6}                         │")
print(f"  │  Not checked: {o:<6}                         │")
print(f"  │  Score      : {B}{score_str}{NC}{' '*(31-len(score_str))}│")
print(f"  {B}└{'─'*46}┘{NC}")
PYEOF
}

# ── Dependency Installer ─────────────────────────────────────────────────────

install_ssg_from_github() {
    local xml_filename; xml_filename=$(basename "$XML_PATH")
    local dest_dir; dest_dir=$(dirname "$XML_PATH")
    local ssg_ver="0.1.74"

    log_info "Fetching latest SSG release from GitHub..."
    local api_out=""
    if command -v curl &>/dev/null; then
        if api_out=$(curl -sf \
            "https://api.github.com/repos/ComplianceAsCode/content/releases/latest" 2>/dev/null); then
            local fv
            if fv=$(echo "$api_out" | \
                python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" \
                2>/dev/null); then
                ssg_ver="$fv"
            fi
        fi
    elif command -v wget &>/dev/null; then
        if api_out=$(wget -qO- \
            "https://api.github.com/repos/ComplianceAsCode/content/releases/latest" 2>/dev/null); then
            local fv
            if fv=$(echo "$api_out" | \
                python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" \
                2>/dev/null); then
                ssg_ver="$fv"
            fi
        fi
    fi
    log_info "Downloading SSG v${ssg_ver}..."

    local zip_url="https://github.com/ComplianceAsCode/content/releases/download/v${ssg_ver}/scap-security-guide-${ssg_ver}.zip"
    local tmp_zip; tmp_zip="/tmp/ssg_$$.zip"
    local tmp_dir; tmp_dir="/tmp/ssg_extract_$$"

    local downloaded=false
    if command -v wget &>/dev/null; then
        if wget -q --show-progress "$zip_url" -O "$tmp_zip"; then downloaded=true; fi
    elif command -v curl &>/dev/null; then
        if curl -L --progress-bar "$zip_url" -o "$tmp_zip"; then downloaded=true; fi
    else
        log_error "wget or curl is required to download SSG content."
        exit 1
    fi

    if [[ "$downloaded" != true ]]; then
        log_error "Download failed. Install manually from:"
        echo "  https://github.com/ComplianceAsCode/content/releases"
        rm -f "$tmp_zip"
        exit 1
    fi

    log_info "Extracting..."
    mkdir -p "$tmp_dir"
    python3 -m zipfile -e "$tmp_zip" "$tmp_dir" 2>/dev/null \
        || { log_error "Failed to extract archive."; rm -rf "$tmp_zip" "$tmp_dir"; exit 1; }

    local xml_src="${tmp_dir}/scap-security-guide-${ssg_ver}/${xml_filename}"
    if [[ ! -f "$xml_src" ]]; then
        log_error "Expected file not in archive: ${xml_filename}"
        log_warn "This distro may not be supported in SSG v${ssg_ver} yet."
        rm -rf "$tmp_zip" "$tmp_dir"
        exit 1
    fi

    mkdir -p "$dest_dir"
    cp "$xml_src" "$dest_dir/"
    rm -rf "$tmp_zip" "$tmp_dir"
    log_info "SCAP content installed: ${dest_dir}/${xml_filename}"
}

run_install_deps() {
    log_section "Installing OpenSCAP Dependencies"

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

    # Parse the profile to get PKG_MANAGER, OSCAP_PKG, SSG_PKG, XML_PATH
    parse_conf

    # Arch: openscap only, no SSG
    if [[ "$ARCH_FALLBACK" == "true" ]]; then
        log_info "Arch Linux: installing openscap (no SSG available)..."
        pacman -S --noconfirm openscap
        log_info "Done. Use --apply for basic hardening mode."
        return
    fi

    # Install openscap
    log_info "Installing OpenSCAP (${OSCAP_PKG})..."
    case "$PKG_MANAGER" in
        apt-get) apt-get install -y $OSCAP_PKG ;;
        dnf)     dnf install -y $OSCAP_PKG ;;
        zypper)  zypper install -y $OSCAP_PKG ;;
        pacman)  pacman -S --noconfirm $OSCAP_PKG ;;
    esac

    # Install SSG packages from distro repo (best-effort)
    if [[ -n "$SSG_PKG" ]]; then
        log_info "Installing SCAP Security Guide (${SSG_PKG})..."
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
    echo ""
    log_info "All dependencies installed."
    echo -e "  Next: ${BOLD}sudo bash $(basename "$0") --apply${NC}"
}

# ── Scan ──────────────────────────────────────────────────────────────────────

run_scan() {
    log_section "Running Compliance Scan"

    mkdir -p "$REPORT_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local arf_file="${REPORT_DIR}/scan_${ts}.arf"

    log_info "Profile : $ACTIVE_PROFILE_ID"
    log_info "Content : $XML_PATH"
    log_info "Reports : $REPORT_DIR"
    echo ""

    local scan_pid err_log="${REPORT_DIR}/scan_${ts}.err"
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$arf_file") >"$err_log" 2>&1 &
    scan_pid=$!
    _spin "$scan_pid" "Scanning system..."
    wait "$scan_pid" 2>/dev/null || true

    if [[ ! -f "$arf_file" ]]; then
        log_error "Scan produced no output."
        if [[ -s "$err_log" ]]; then
            echo ""
            sed 's/^/  /' "$err_log"
        fi
        exit 1
    fi
    rm -f "$err_log"

    case "$REPORT_FORMAT" in
        html) generate_html_report "$arf_file" "${REPORT_DIR}/scan_${ts}.html" ;;
        json) generate_json_report "$arf_file" "${REPORT_DIR}/scan_${ts}.json" ;;
        both)
            generate_html_report "$arf_file" "${REPORT_DIR}/scan_${ts}.html"
            generate_json_report "$arf_file" "${REPORT_DIR}/scan_${ts}.json"
            ;;
    esac

    print_failing_rules "$arf_file"
    echo ""
    print_scan_summary "$arf_file"
}

# ── Apply ─────────────────────────────────────────────────────────────────────

run_apply() {
    if [[ "$DRY_RUN" == true ]]; then
        log_section "Dry Run — Hardening Preview"
        log_warn "No changes will be made to the system."
        echo ""
        log_info "Profile  : $ACTIVE_PROFILE_ID"
        log_info "Level    : ${SEC_LEVEL_LABEL}"
        [[ -n "$EXCLUSION_RULES" ]] && log_info "Excluded : $(echo "$EXCLUSION_RULES" | wc -w) rule(s)"
        echo ""
        mkdir -p "$REPORT_DIR"
        local ts; ts=$(date +%Y%m%d_%H%M%S)
        local arf="${REPORT_DIR}/dryrun_${ts}.arf"

        local scan_pid
        # shellcheck disable=SC2046
        oscap xccdf eval $(oscap_eval_args "$arf") >/dev/null 2>&1 &
        scan_pid=$!
        _spin "$scan_pid" "Scanning system..."
        wait "$scan_pid" 2>/dev/null || true

        if [[ -f "$arf" ]]; then
            print_failing_rules "$arf"
            echo ""
            print_scan_summary "$arf"
        else
            log_warn "Dry-run scan produced no output — check oscap manually."
        fi

        echo ""
        log_info "Run without --dry-run to apply the above fixes."
        return
    fi

    log_section "Applying Hardening"
    echo -e "  ${YELLOW}${BOLD}WARNING:${NC} System configuration will be modified."
    echo -e "  Backup → ${BOLD}${BACKUP_BASE}/${NC}"
    echo -n "  Continue? [y/N] "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then log_warn "Aborted."; exit 0; fi

    run_hook "$HOOK_PRE" "pre_hardening"

    mkdir -p "$BACKUP_BASE"
    local backup_dir; backup_dir=$(create_backup)

    # Baseline score before remediation
    echo ""
    local pre_arf="${backup_dir}/pre_hardening.arf"
    local pre_pid
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$pre_arf") >"${backup_dir}/pre.err" 2>&1 &
    pre_pid=$!
    _spin "$pre_pid" "Baseline scan (before)..."
    wait "$pre_pid" 2>/dev/null || true
    local pre_score; pre_score=$(get_score "$pre_arf")
    log_info "Baseline score: ${pre_score}%"

    # Apply fixes
    echo ""
    local fix_pid
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "${backup_dir}/remediation.arf" "true") >"${backup_dir}/fix.err" 2>&1 &
    fix_pid=$!
    _spin "$fix_pid" "Applying fixes — this may take several minutes..."
    wait "$fix_pid" 2>/dev/null || true
    log_info "Fixes applied."

    # Verification scan after remediation
    echo ""
    local post_arf="${backup_dir}/post_hardening.arf"
    local post_pid
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$post_arf") >"${backup_dir}/post.err" 2>&1 &
    post_pid=$!
    _spin "$post_pid" "Verification scan (after)..."
    wait "$post_pid" 2>/dev/null || true
    local post_score; post_score=$(get_score "$post_arf")

    echo ""
    print_improvement "$pre_score" "$post_score"

    if [[ -f "$post_arf" ]]; then
        print_failing_rules "$post_arf"
        echo ""
        print_scan_summary "$post_arf"
    fi

    run_hook "$HOOK_POST" "post_hardening"

    echo ""
    log_info "Backup at: $backup_dir"
    log_warn "A reboot may be required for some changes to take effect."
    echo -e "  To revert: ${BOLD}sudo $(basename "$0") --unapply${NC}"
}

# ── Unapply ───────────────────────────────────────────────────────────────────

# Locate the most recent backup directory; echo its path, or return 1 if none.
latest_backup_dir() {
    local latest="${BACKUP_BASE}/latest"
    [[ -e "$latest" ]] || return 1
    local dir; dir=$(readlink -f "$latest")
    [[ -f "${dir}/manifest.conf" ]] || return 1
    echo "$dir"
}

# Revert the hardening changes recorded in a backup: restore config files,
# reinstall packages the hardening removed, and restore service enable/disable
# state. Deliberately does NOT remove any package or the OpenSCAP tooling —
# --unapply only undoes the settings the hardening wrote. (Use --uninstall to
# also remove OpenSCAP afterwards.)
revert_hardening() {
    local backup_dir="$1"
    local rollback_hook; rollback_hook=$(awk -F'=' '/^hook_rollback/{print $2}' "${backup_dir}/manifest.conf")

    # Restore config files
    if [[ -f "${backup_dir}/configs.tar.gz" ]]; then
        tar xzf "${backup_dir}/configs.tar.gz" -C / 2>/dev/null \
            && log_info "Config files restored" \
            || log_warn "Some files could not be restored"
    else
        log_warn "No config archive in backup"
    fi

    # Reinstall packages the hardening removed. Packages the hardening *added*
    # are left in place — unapply must not delete applications.
    if [[ -f "${backup_dir}/packages.txt" ]]; then
        log_info "Checking for packages removed by hardening..."
        local cur_pkgs; cur_pkgs=$(mktemp)
        snapshot_packages > "$cur_pkgs"
        local removed; mapfile -t removed < <(comm -23 "${backup_dir}/packages.txt" "$cur_pkgs")
        if [[ ${#removed[@]} -gt 0 ]]; then
            log_info "Reinstalling ${#removed[@]} package(s): ${removed[*]}"
            pkg_install "${removed[@]}" 2>/dev/null \
                || log_warn "Some packages could not be reinstalled (check network/repos)"
        else
            log_info "No removed packages to reinstall."
        fi
        rm -f "$cur_pkgs"
    fi

    # Restore service states
    if [[ -f "${backup_dir}/services_enabled.txt" ]]; then
        log_info "Restoring service states..."
        local current; current=$(mktemp)
        systemctl list-units --type=service --state=enabled --no-legend --plain 2>/dev/null \
            | awk '{print $1}' | sort > "$current"

        # Disable services not in original list
        comm -23 "$current" "${backup_dir}/services_enabled.txt" \
            | xargs -r systemctl disable --now 2>/dev/null || true

        # Re-enable services that were originally enabled — unmask first, since
        # hardening may have masked them (a masked service cannot be enabled).
        while read -r svc; do
            [[ -z "$svc" ]] && continue
            systemctl unmask "$svc" 2>/dev/null || true
            systemctl enable --now "$svc" 2>/dev/null || true
        done < <(comm -13 "$current" "${backup_dir}/services_enabled.txt")

        rm -f "$current"
        log_info "Service states restored"
    fi

    # Reload system
    sysctl --system 2>/dev/null | grep -c 'Applying' | xargs -I{} log_info "sysctl: {} settings reloaded" || true
    systemctl daemon-reload 2>/dev/null && log_info "systemd daemon reloaded" || true

    for svc in sshd ssh auditd; do
        systemctl is-active "$svc" &>/dev/null \
            && systemctl restart "$svc" 2>/dev/null \
            && log_info "Restarted: $svc" || true
    done

    # Rollback hook (read from manifest so it's the hook that was set at install time)
    if [[ -n "$rollback_hook" ]]; then run_hook "$rollback_hook" "on_rollback"; fi
    return 0
}

run_unapply() {
    log_section "Reverting Hardening"

    local backup_dir
    if ! backup_dir=$(latest_backup_dir); then
        log_error "No usable backup found at ${BACKUP_BASE}/latest"
        echo "  Run --apply first."
        exit 1
    fi

    local ts; ts=$(awk -F'=' '/^timestamp/{print $2}' "${backup_dir}/manifest.conf")
    log_info "Restoring from: $ts"
    echo -n "  Continue? [y/N] "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then log_warn "Aborted."; exit 0; fi

    revert_hardening "$backup_dir"

    log_info "Revert complete. OpenSCAP stays installed — use --uninstall to remove it."
    log_warn "A reboot is strongly recommended."
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

run_uninstall() {
    log_section "Reverting Hardening + Removing OpenSCAP"
    echo -e "  ${YELLOW}${BOLD}WARNING:${NC} Hardening settings will be reverted first, then"
    echo -e "  OpenSCAP and SCAP content packages will be removed."
    echo -e "  You will no longer be able to run ${BOLD}--scan${NC} or ${BOLD}--apply${NC}."
    echo ""
    echo -n "  Continue? [y/N] "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then log_warn "Aborted."; exit 0; fi

    # Step 1: revert hardening settings (if a backup exists).
    local backup_dir
    if backup_dir=$(latest_backup_dir); then
        local ts; ts=$(awk -F'=' '/^timestamp/{print $2}' "${backup_dir}/manifest.conf")
        echo ""
        log_info "Reverting hardening from: $ts"
        revert_hardening "$backup_dir"
    else
        log_warn "No backup found — skipping settings revert, removing packages only."
    fi

    # Step 2: remove the OpenSCAP tooling.
    echo ""
    log_info "Removing OpenSCAP packages..."

    # shellcheck disable=SC2086
    case "$PKG_MANAGER" in
        apt-get)
            apt-get remove -y $OSCAP_PKG $SSG_PKG 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            ;;
        dnf)
            dnf remove -y $OSCAP_PKG $SSG_PKG 2>/dev/null || true
            ;;
        zypper)
            zypper remove -y $OSCAP_PKG $SSG_PKG 2>/dev/null || true
            ;;
        pacman)
            pacman -Rns --noconfirm openscap 2>/dev/null || true
            ;;
    esac

    log_info "OpenSCAP packages removed."
    log_warn "A reboot is strongly recommended."
}

# ── Arch Fallback ─────────────────────────────────────────────────────────────

run_scan_arch()     { log_warn "Arch: full SCAP not available (no SSG)."; arch_basic_check; }
run_unapply_arch()  { run_unapply; }

run_apply_arch() {
    if [[ "$DRY_RUN" == true ]]; then
        log_section "Dry Run — Arch Basic Hardening Preview"
        log_warn "Would apply: sysctl kernel params, sshd_config, core dump limits."
        arch_basic_check
        return
    fi
    log_warn "Arch: applying basic hardening (no SSG)."
    run_hook "$HOOK_PRE" "pre_hardening"
    arch_basic_harden
    run_hook "$HOOK_POST" "post_hardening"
}

arch_basic_check() {
    log_section "Basic Security Check (Arch)"
    local pass=0 fail=0

    _chk() {
        local label="$1"; shift
        if eval "$*" &>/dev/null; then
            echo -e "  ${GREEN}[PASS]${NC} $label"; pass=$((pass + 1))
        else
            echo -e "  ${RED}[FAIL]${NC} $label"; fail=$((fail + 1))
        fi
    }

    _chk "SSH PermitRootLogin disabled"    "grep -qE '^PermitRootLogin (no|prohibit-password)' /etc/ssh/sshd_config"
    _chk "SSH PasswordAuthentication off"  "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
    _chk "Firewall active"                 "systemctl is-active ufw nftables iptables 2>/dev/null | grep -q active"
    _chk "auditd running"                  "systemctl is-active auditd"
    _chk "Core dumps disabled"             "grep -qE '^\*\s+hard\s+core\s+0' /etc/security/limits.conf"
    _chk "ASLR enabled (=2)"               "sysctl kernel.randomize_va_space 2>/dev/null | grep -q '= 2'"
    _chk "IPv4 forwarding disabled"        "sysctl net.ipv4.ip_forward 2>/dev/null | grep -q '= 0'"
    _chk "SYN cookies enabled"             "sysctl net.ipv4.tcp_syncookies 2>/dev/null | grep -q '= 1'"
    _chk "dmesg restricted"                "sysctl kernel.dmesg_restrict 2>/dev/null | grep -q '= 1'"

    echo ""
    echo -e "  ${GREEN}Pass: $pass${NC}  ${RED}Fail: $fail${NC}"
}

arch_basic_harden() {
    log_section "Basic Hardening (Arch)"

    local backup_dir; backup_dir=$(create_backup)

    cat > /etc/sysctl.d/99-linuxharden.conf <<'EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
    sysctl --system 2>/dev/null | tail -3
    log_info "sysctl params applied"

    local sshd_conf="/etc/ssh/sshd_config"
    if [[ -f "$sshd_conf" ]]; then
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'              "$sshd_conf"
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_conf"
        sed -i 's/^#*X11Forwarding.*/X11Forwarding no/'                  "$sshd_conf"
        sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/'                      "$sshd_conf"
        systemctl is-active sshd &>/dev/null && systemctl restart sshd || true
        log_info "sshd_config hardened"
    fi

    echo "* hard core 0" >> /etc/security/limits.conf
    echo "* soft core 0" >> /etc/security/limits.conf
    log_info "Core dumps disabled"

    log_info "Backup at: $backup_dir"
    log_warn "Review changes and reboot."
    echo -e "  To revert: ${BOLD}sudo $(basename "$0") --unapply${NC}"
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

cleanup() { [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    banner
    parse_args "$@"
    check_root "$@"
    detect_distro
    download_conf

    if [[ "$MODE" == "install" ]]; then
        run_install_deps
        return
    fi

    check_pyyaml
    parse_conf

    if [[ "$MODE" != "unapply" && "$MODE" != "unapply_arch" && "$MODE" != "uninstall" ]]; then
        detect_active_services
        check_dependencies
        validate_profile
        setup_tailoring
    fi

    case "$MODE" in
        scan)          run_scan ;;
        apply)         run_apply ;;
        unapply)       run_unapply ;;
        uninstall)     run_uninstall ;;
        scan_arch)     run_scan_arch ;;
        apply_arch)    run_apply_arch ;;
        unapply_arch)  run_unapply_arch ;;
    esac
}

main "$@"
