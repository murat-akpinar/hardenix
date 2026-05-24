# hardenix

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-1a1a1a?style=flat-square&labelColor=1a1a1a&color=8a6f3a)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-1a1a1a?style=flat-square&labelColor=1a1a1a&color=d8b66b)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4a9e6b)](https://github.com/YOUR_GITHUB_USER/hardenix)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4eaa25&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![OpenSCAP](https://img.shields.io/badge/OpenSCAP-1.3%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=cc0000)](https://www.open-scap.org)
[![Python](https://img.shields.io/badge/Python-3.8%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=3776ab&logo=python&logoColor=white)](https://www.python.org)
[![Distros](https://img.shields.io/badge/distros-8%20supported-1a1a1a?style=flat-square&labelColor=1a1a1a&color=e95420)](https://github.com/YOUR_GITHUB_USER/hardenix/tree/main/profiles)

> English version: [README.md](README.md)

OpenSCAP tabanlı Linux sıkılaştırma aracı. Distro'ya göre YAML profili indirir; tarama, uygulama ve geri alma işlemlerini tek script ile yönetir.

---

## Özellikler

- **`--scan`** — CIS/ANSSI/STIG profiliyle uyumluluk taraması, HTML/JSON rapor
- **`--install`** — Sıkılaştırma uygular; önce yedek alır, sonra before/after skor gösterir
- **`--uninstall`** — Son yedekten tüm değişiklikleri geri alır
- **`--dry-run`** — Neyin değişeceğini gösterir, sisteme dokunmaz
- **`--env`** — `production` / `staging` / `development` profili seçer
- **Exclusions** — Belirli kuralları, servisleri veya path'leri atlama
- **Hooks** — Sıkılaştırma öncesi/sonrası ve rollback için özel script çalıştırma
- **XCCDF Tailoring** — Exclusion kuralları otomatik tailoring dosyasına dönüştürülür

---

## Desteklenen Dağıtımlar

| Dağıtım | Profil (production) | Profil (development) | Motor |
|---------|---------------------|----------------------|-------|
| Ubuntu 22.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Ubuntu 24.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Debian 12 | ANSSI BP-028 Enhanced | Standard | SSG |
| RHEL 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Rocky Linux 9 | CIS Level 1 Server | Standard | SSG |
| AlmaLinux 9 | CIS Level 1 Server | Standard | SSG |
| Fedora 40 | OSPP | Standard | SSG |
| openSUSE Leap 15 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Arch Linux | sysctl + SSH hardening | — | Bash fallback |

---

## Kurulum

```bash
# Ubuntu / Debian
sudo apt-get install openscap-utils ssg-base ssg-debderived python3-yaml

# RHEL / Rocky / AlmaLinux
sudo dnf install openscap-utils scap-security-guide python3-pyyaml

# Fedora
sudo dnf install openscap-utils scap-security-guide python3-pyyaml

# openSUSE
sudo zypper install openscap scap-security-guide python3-PyYAML

# Arch
sudo pacman -S openscap python-yaml

# Script'i çalıştırılabilir yap
chmod +x linuxharden.sh
```

---

## Kullanım

```bash
# Uyumluluk taraması yap
sudo ./linuxharden.sh --scan

# HTML + JSON rapor üret
sudo ./linuxharden.sh --scan --format both

# Neyin değişeceğini önce gör (sisteme dokunmaz)
sudo ./linuxharden.sh --install --dry-run

# Development ortamı için daha hafif profil
sudo ./linuxharden.sh --install --env development

# Sıkılaştırma uygula (yedek alır → uygular → doğrular)
sudo ./linuxharden.sh --install

# Sıkılaştırmayı geri al
sudo ./linuxharden.sh --uninstall

# Belirli profil ID ile tarama
sudo ./linuxharden.sh --scan --profile xccdf_org.ssgproject.content_profile_cis_level2_server

# Yerel .yml profil kullan
sudo ./linuxharden.sh --scan --conf ./profiles/ubuntu-22.04.yml
```

---

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| `--scan` | Compliance taraması, rapor üretir |
| `--install` | Sıkılaştırma uygular (yedek → uygula → doğrula) |
| `--uninstall` | Son yedekten geri alır |
| `--dry-run` | `--install` ile: değişiklikleri göster, uygulama |
| `--env <profil>` | `production` \| `staging` \| `development` (varsayılan: production) |
| `--format <tip>` | `html` \| `json` \| `both` (varsayılan: html) |
| `--profile <id>` | SCAP profil ID override |
| `--conf <dosya>` | Yerel .yml profil dosyası kullan |

---

## Profil YAML Formatı

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
    production:  xccdf_org.ssgproject.content_profile_cis_level2_server
    staging:     xccdf_org.ssgproject.content_profile_cis_level2_server
    development: xccdf_org.ssgproject.content_profile_cis_level1_server

backup:
  config_dirs:
    - /etc/ssh
    - /etc/sysctl.d
    - /etc/security
    - /etc/pam.d

exclusions:
  rules:    []        # XCCDF rule ID'leri — tailoring dosyasına eklenir
  services: []        # Yedekten çıkarılacak servisler
  paths:    []        # Yedekten çıkarılacak path'ler
  users:    []

hooks:
  pre_hardening:  ""  # --install öncesi çalışır
  post_hardening: ""  # --install sonrası çalışır
  on_rollback:    ""  # --uninstall sırasında çalışır
```

---

## Yedekleme

`--install` her çalışmada önce `/var/lib/linuxharden/<tarih>/` altına yedek alır:

```
/var/lib/linuxharden/
├── 20260524_153000/
│   ├── configs.tar.gz          # Tüm config dizinleri
│   ├── services_enabled.txt    # Aktif servis listesi
│   ├── manifest.conf           # Metadata (distro, profil, hook bilgisi)
│   ├── profile.yml             # O anki profil kopyası
│   ├── pre_hardening.arf       # Uygulama öncesi tarama
│   └── post_hardening.arf      # Uygulama sonrası tarama
└── latest -> 20260524_153000/  # Symlink (--uninstall buraya bakar)
```

---

## Raporlar

`./reports/` klasörüne kaydedilir:

| Dosya | İçerik |
|-------|--------|
| `scan_<tarih>.html` | Görsel HTML raporu (oscap-report) |
| `scan_<tarih>.arf` | Ham ARF/XML çıktısı |
| `scan_<tarih>.json` | Özet: pass/fail sayıları, skor, failed rule listesi |

---

## Uyarılar

> **Root yetkisi gereklidir.** Script `sudo` ile çalıştırılmalıdır.

- `--install` SSH ayarlarını ve sistem servislerini değiştirebilir.
- `--uninstall` sonrası tam geri dönüş için **reboot önerilir**.
- Arch Linux'ta SSG desteği olmadığından temel `sysctl` + SSH hardening uygulanır.
- `--dry-run` sisteme hiçbir şey yazmaz, güvenle kullanılabilir.
