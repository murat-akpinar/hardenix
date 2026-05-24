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
MODE="" REPORT_FORMAT="html" PROFILE_OVERRIDE="" LOCAL_CONF="" CONF_FILE=""
DRY_RUN=false ENV_PROFILE="production"

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
    echo "  --scan              Scan system compliance and generate report"
    echo "  --install           Apply hardening (creates backup, then verifies)"
    echo "  --uninstall         Revert hardening from latest backup"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --dry-run           Preview what would change without applying (implies --install)"
    echo "  --env <profile>     Environment: production | staging | development  (default: production)"
    echo "  --format <type>     Report format: html | json | both  (default: html)"
    echo "  --profile <id>      Override SCAP profile ID"
    echo "  --conf <file>       Use a local .yml instead of downloading"
    echo "  --help              Show this help"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  sudo $(basename "$0") --scan"
    echo "  sudo $(basename "$0") --dry-run"
    echo "  sudo $(basename "$0") --install --env development"
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
            --dry-run)   DRY_RUN=true ;;
            --env)       shift; ENV_PROFILE="${1:-production}" ;;
            --format)    shift; REPORT_FORMAT="${1:-html}" ;;
            --profile)   shift; PROFILE_OVERRIDE="${1:-}" ;;
            --conf)      shift; LOCAL_CONF="${1:-}" ;;
            --help|-h)   usage ;;
            *) log_error "Unknown option: $1"; echo ""; usage ;;
        esac
        shift
    done

    if [[ "$DRY_RUN" == true && -z "$MODE" ]]; then MODE="install"; fi
    if [[ -z "$MODE" ]]; then log_error "No mode specified."; echo ""; usage; fi

    case "$REPORT_FORMAT" in
        html|json|both) ;;
        *) log_error "Invalid --format: $REPORT_FORMAT (use: html | json | both)"; exit 1 ;;
    esac

    case "$ENV_PROFILE" in
        production|staging|development) ;;
        *) log_error "Invalid --env: $ENV_PROFILE (use: production | staging | development)"; exit 1 ;;
    esac

    if [[ "$DRY_RUN" == true && "$MODE" != "install" ]]; then
        log_warn "--dry-run only applies to --install, ignoring."
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
    log_info "Environment: ${ENV_PROFILE}"
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

    if [[ -n "$PROFILE_OVERRIDE" ]]; then PROFILE_ID="$PROFILE_OVERRIDE"; fi

    if [[ -z "$PKG_MANAGER" ]]; then log_error "Invalid .yml: missing packages.manager"; exit 1; fi

    if [[ "$ARCH_FALLBACK" == "true" ]]; then
        MODE="${MODE}_arch"
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
        missing=1
    fi

    if [[ ! -f "$XML_PATH" ]]; then
        log_warn "SCAP content not found: $XML_PATH"
        echo -e "  Install: ${BOLD}${PKG_MANAGER} install ${SSG_PKG}${NC}"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then echo ""; log_error "Missing dependencies. Aborting."; exit 1; fi

    local ver; ver=$(oscap --version 2>&1 | awk 'NR==1{print $NF}')
    log_info "oscap ${ver} — OK"
}

# ── Tailoring File ────────────────────────────────────────────────────────────

setup_tailoring() {
    ACTIVE_PROFILE_ID="$PROFILE_ID"
    TAILORING_FILE=""

    if [[ -z "$EXCLUSION_RULES" ]]; then return; fi

    local tailored_id="xccdf_linuxharden.custom_profile_tailored"
    local tfile="${TMP_DIR}/tailoring.xml"
    mkdir -p "$TMP_DIR"

    python3 - "$XML_PATH" "$PROFILE_ID" "$EXCLUSION_RULES" "$tfile" "$tailored_id" <<'PYEOF' && {
import sys

xml_path, profile_id, excl_str, out_file, new_id = sys.argv[1:]
excluded = [r for r in excl_str.split() if r]

if not excluded:
    sys.exit(0)

selects = '\n    '.join(
    f'<xccdf:select idref="{r}" selected="false"/>' for r in excluded
)

xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<xccdf:Tailoring
    xmlns:xccdf="http://checklists.nist.gov/xccdf/1.2"
    id="xccdf_linuxharden.custom_tailoring_1">
  <xccdf:benchmark href="{xml_path}"/>
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
    args+=(--results "$results_file")
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

    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$arf_file") 2>&1 \
        | grep -E '^(Rule|Title|Result|Severity|Fixing)' | tail -20 \
        || true

    [[ ! -f "$arf_file" ]] && { log_error "Scan produced no output."; exit 1; }

    case "$REPORT_FORMAT" in
        html) generate_html_report "$arf_file" "${REPORT_DIR}/scan_${ts}.html" ;;
        json) generate_json_report "$arf_file" "${REPORT_DIR}/scan_${ts}.json" ;;
        both)
            generate_html_report "$arf_file" "${REPORT_DIR}/scan_${ts}.html"
            generate_json_report "$arf_file" "${REPORT_DIR}/scan_${ts}.json"
            ;;
    esac

    print_scan_summary "$arf_file"
}

# ── Install ───────────────────────────────────────────────────────────────────

run_install() {
    if [[ "$DRY_RUN" == true ]]; then
        log_section "Dry Run — Hardening Preview"
        log_warn "No changes will be made to the system."
        echo ""
        log_info "Profile  : $ACTIVE_PROFILE_ID"
        log_info "Env      : $ENV_PROFILE"
        [[ -n "$EXCLUSION_RULES" ]] && log_info "Excluded : $(echo "$EXCLUSION_RULES" | wc -w) rule(s)"
        echo ""
        log_info "Scanning — this may take a moment..."
        echo ""

        mkdir -p "$REPORT_DIR"
        local ts; ts=$(date +%Y%m%d_%H%M%S)
        local arf="${REPORT_DIR}/dryrun_${ts}.arf"

        # shellcheck disable=SC2046
        oscap xccdf eval $(oscap_eval_args "$arf") 2>/dev/null || true

        if [[ -f "$arf" ]]; then
            python3 - "$arf" <<'PYEOF'
import sys, xml.etree.ElementTree as ET

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
    'unknown': '\033[0m',
}
NC   = '\033[0m'
BOLD = '\033[1m'

failed = []
for rr in tree.iter(f'{{{NS}}}rule-result'):
    r = rr.find(f'{{{NS}}}result')
    if r is not None and r.text and r.text.strip() == 'fail':
        rid = rr.get('idref', '')
        title, sev = rules.get(rid, ('', 'unknown'))
        failed.append((SEV_ORDER.get(sev, 3), sev, rid, title))

failed.sort()

if not failed:
    print(f"  {BOLD}No failing rules found.{NC}")
    sys.exit(0)

print(f"  {BOLD}{'SEV':<8} {'RULE ID':<55} TITLE{NC}")
print(f"  {'─'*8} {'─'*55} {'─'*30}")
for _, sev, rid, title in failed:
    col   = SEV_COLOR.get(sev, NC)
    short = rid.split('_rule_')[-1] if '_rule_' in rid else rid
    print(f"  {col}{sev:<8}{NC} {short:<55} {title[:60]}")

print(f"\n  {BOLD}Total failing rules: {len(failed)}{NC}")
PYEOF
            echo ""
            print_scan_summary "$arf"
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
    log_info "Baseline scan (before)..."
    local pre_arf="${backup_dir}/pre_hardening.arf"
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$pre_arf") 2>/dev/null || true
    local pre_score; pre_score=$(get_score "$pre_arf")

    # Apply fixes
    echo ""
    log_info "Applying fixes — this may take several minutes..."
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "${backup_dir}/remediation.arf" "true") 2>&1 \
        | grep -E '^(Fixing|Rule|Title|Result)' \
        || true

    # Verification scan after remediation
    echo ""
    log_info "Verification scan (after)..."
    local post_arf="${backup_dir}/post_hardening.arf"
    # shellcheck disable=SC2046
    oscap xccdf eval $(oscap_eval_args "$post_arf") 2>/dev/null || true
    local post_score; post_score=$(get_score "$post_arf")

    print_improvement "$pre_score" "$post_score"

    run_hook "$HOOK_POST" "post_hardening"

    echo ""
    log_info "Backup at: $backup_dir"
    log_warn "A reboot may be required for some changes to take effect."
    echo -e "  To revert: ${BOLD}sudo $(basename "$0") --uninstall${NC}"
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

run_uninstall() {
    log_section "Reverting Hardening"

    local latest="${BACKUP_BASE}/latest"
    if [[ ! -L "$latest" ]]; then
        log_error "No backup found at ${BACKUP_BASE}/latest"
        echo "  Run --install first."
        exit 1
    fi

    local backup_dir; backup_dir=$(readlink -f "$latest")
    if [[ ! -f "${backup_dir}/manifest.conf" ]]; then
        log_error "Backup manifest missing: ${backup_dir}/manifest.conf"
        exit 1
    fi

    local ts; ts=$(awk -F'=' '/^timestamp/{print $2}' "${backup_dir}/manifest.conf")
    local rollback_hook; rollback_hook=$(awk -F'=' '/^hook_rollback/{print $2}' "${backup_dir}/manifest.conf")
    log_info "Restoring from: $ts"
    echo -n "  Continue? [y/N] "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then log_warn "Aborted."; exit 0; fi

    # Restore config files
    if [[ -f "${backup_dir}/configs.tar.gz" ]]; then
        tar xzf "${backup_dir}/configs.tar.gz" -C / 2>/dev/null \
            && log_info "Config files restored" \
            || log_warn "Some files could not be restored"
    else
        log_warn "No config archive in backup"
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

        # Re-enable services that were originally enabled
        comm -13 "$current" "${backup_dir}/services_enabled.txt" \
            | xargs -r systemctl enable --now 2>/dev/null || true

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

    log_info "Revert complete."
    log_warn "A reboot is strongly recommended."
}

# ── Arch Fallback ─────────────────────────────────────────────────────────────

run_scan_arch()      { log_warn "Arch: full SCAP not available (no SSG)."; arch_basic_check; }
run_uninstall_arch() { run_uninstall; }

run_install_arch() {
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
    echo -e "  To revert: ${BOLD}sudo $(basename "$0") --uninstall${NC}"
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
    check_pyyaml
    parse_conf

    if [[ "$MODE" != "uninstall" && "$MODE" != "uninstall_arch" ]]; then
        check_dependencies
        setup_tailoring
    fi

    case "$MODE" in
        scan)           run_scan ;;
        install)        run_install ;;
        uninstall)      run_uninstall ;;
        scan_arch)      run_scan_arch ;;
        install_arch)   run_install_arch ;;
        uninstall_arch) run_uninstall_arch ;;
    esac
}

main "$@"
