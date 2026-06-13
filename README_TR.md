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

- **`--install`** — OpenSCAP ve SCAP içeriklerini distro'ya göre otomatik kurar; Ubuntu 24.04 gibi repo'su yetersiz distrolarda GitHub'dan indirir
- **`--uninstall`** — `--install` ile kurulan OpenSCAP + SCAP paketlerini kaldırır
- **`--apply`** — Sıkılaştırma uygular; önce yedek alır, sonra before/after skor gösterir
- **`--unapply`** — Son yedekten hardening değişikliklerini geri alır
- **`--scan`** — CIS/ANSSI/STIG profiliyle uyumluluk taraması, HTML/JSON rapor
- **`--dry-run`** — Neyin değişeceğini severity gruplarına göre gösterir, sisteme dokunmaz
- **`--level`** — Sıkılaştırma seviyesini doğrudan seçer: `1` = CIS Level 1 (temel), `2` = CIS Level 2 (sıkı)
- **`--env`** — `production` / `staging` / `development` profili seçer
- **Exclusions** — Belirli kuralları, servisleri veya path'leri atlama
- **Hooks** — Sıkılaştırma öncesi/sonrası ve rollback için özel script çalıştırma
- **XCCDF Tailoring** — Exclusion kuralları otomatik tailoring dosyasına dönüştürülür

---

## Desteklenen Dağıtımlar

`--level 2` (varsayılan) sıkı profili, `--level 1` temel profili seçer.

| Dağıtım | Level 2 — sıkı (varsayılan) | Level 1 — temel (`--level 1`) | Motor |
|---------|-----------------------------|-------------------------------|-------|
| Ubuntu 22.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Ubuntu 24.04 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Debian 12 | ANSSI BP-028 Enhanced | Standard | SSG |
| RHEL 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Rocky Linux 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| AlmaLinux 9 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Fedora 40 | OSPP | Standard | SSG |
| openSUSE Leap 15 | CIS Level 2 Server | CIS Level 1 Server | SSG |
| Arch Linux | sysctl + SSH hardening | — | Bash fallback |

> Debian ve Fedora için SSG bir CIS profili yayınlamıyor; ANSSI BP28 / OSPP kullanılır.
> Burada `--level 2` "sıkı baseline", `--level 1` "hafif baseline" anlamına gelir.

---

## Sıkılaştırma Seviyeleri

| | **Level 1** (`--level 1`) | **Level 2** (`--level 2`, varsayılan) |
|---|---|---|
| Amaç | Günlük kullanım için temel güvenlik | Yüksek güvenlik / regülasyon |
| Etki | Pratik, bozma riski düşük | Bazı fonksiyonları kısıtlayabilir |
| Örnek | Parola politikası, dosya izinleri | Zorunlu denetim (auditd), mount kısıtları, ek servis kaldırma |
| Tipik kullanıcı | Çoğu sunucu | Bankacılık, kamu, hassas veri |

```bash
sudo ./linuxharden.sh --apply --level 1    # temel
sudo ./linuxharden.sh --apply --level 2    # sıkı (varsayılan)
```

> `--level`, profil seçiminin kısa yoludur ve `--env`'e göre önceliklidir.
> Seviye belirtmeden `--apply` çalıştırmak Level 2'yi (sıkı) varsayar.

---

## Kurulum

```bash
git clone https://github.com/YOUR_GITHUB_USER/hardenix.git
cd hardenix
chmod +x linuxharden.sh

# OpenSCAP + SCAP içeriklerini otomatik kur (tüm distrolarda çalışır)
sudo ./linuxharden.sh --install
```

`--install` aşağıdakileri otomatik yapar:

- Distro'yu tespit eder (`apt-get` / `dnf` / `zypper` / `pacman`)
- Ubuntu'da `universe` reposunu etkinleştirir
- `openscap` ve distro'ya uygun SSG paketini kurar
- Ubuntu 24.04 gibi repo'su yetersiz sistemlerde SCAP içeriğini GitHub'dan indirir (`/usr/share/xml/scap/ssg/content/` altına koyar)

---

## Kullanım

```bash
# 1. Bağımlılıkları kur (ilk kez)
sudo ./linuxharden.sh --install

# 2. Neyin değişeceğini önce gör — sisteme dokunmaz
sudo ./linuxharden.sh --dry-run

# 3. Sıkılaştırma uygula (yedek alır → uygular → doğrular) — varsayılan Level 2 (sıkı)
sudo ./linuxharden.sh --apply

# Sıkılaştırma seviyesini doğrudan seç
sudo ./linuxharden.sh --apply --level 1     # CIS Level 1 (temel)
sudo ./linuxharden.sh --apply --level 2     # CIS Level 2 (sıkı)

# Sıkılaştırmayı geri al (backup'tan config'leri restore eder)
sudo ./linuxharden.sh --unapply

# Uyumluluk taraması yap
sudo ./linuxharden.sh --scan

# HTML + JSON rapor üret
sudo ./linuxharden.sh --scan --format both

# OpenSCAP paketlerini tamamen kaldır
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
| `--install` | OpenSCAP + SCAP içeriklerini distro'ya göre otomatik kurar |
| `--uninstall` | OpenSCAP + SCAP paketlerini kaldırır |
| `--apply` | Sıkılaştırma uygular (yedek → uygula → doğrula) |
| `--unapply` | Son yedekten hardening ayarlarını geri alır |
| `--scan` | Compliance taraması, rapor üretir |
| `--dry-run` | Başarısız kuralları severity gruplarına göre gösterir, sisteme dokunmaz (`--apply`'ı ima eder) |
| `--level <1\|2>` | Sıkılaştırma seviyesi: `1` = CIS Level 1 (temel), `2` = CIS Level 2 (sıkı, varsayılan) |
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
  pre_hardening:  ""  # --apply öncesi çalışır
  post_hardening: ""  # --apply sonrası çalışır
  on_rollback:    ""  # --unapply sırasında çalışır
```

---

## Yedekleme

`--apply` her çalışmada önce `/var/lib/linuxharden/<tarih>/` altına yedek alır (`--unapply` bu yedekten geri alır):

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

- `--apply` SSH ayarlarını ve sistem servislerini değiştirebilir.
- `--unapply` sonrası tam geri dönüş için **reboot önerilir**.
- `--uninstall` paketleri kaldırır; aktif hardening ayarlarını geri almaz — önce `--unapply` çalıştırın.
- Arch Linux'ta SSG desteği olmadığından temel `sysctl` + SSH hardening uygulanır.
- `--dry-run` sisteme hiçbir şey yazmaz, güvenle kullanılabilir.
