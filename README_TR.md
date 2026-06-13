# hardenix

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-1a1a1a?style=flat-square&labelColor=1a1a1a&color=8a6f3a)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-1a1a1a?style=flat-square&labelColor=1a1a1a&color=d8b66b)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4a9e6b)](https://github.com/YOUR_GITHUB_USER/hardenix)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4eaa25&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![OpenSCAP](https://img.shields.io/badge/OpenSCAP-1.3%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=cc0000)](https://www.open-scap.org)
[![Python](https://img.shields.io/badge/Python-3.8%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=3776ab&logo=python&logoColor=white)](https://www.python.org)
[![Distros](https://img.shields.io/badge/distros-8%20supported-1a1a1a?style=flat-square&labelColor=1a1a1a&color=e95420)](https://github.com/YOUR_GITHUB_USER/hardenix/tree/main/profiles)

> English version: [README.md](README.md)

OpenSCAP tabanlı Linux sıkılaştırma **ve güvenlik açığı yönetim** aracı. Tek script,
tek YAML profili ile birbirini tamamlayan iki güvenlik katmanını yönetir:

1. **Uyumluluk sıkılaştırması** — CIS / ANSSI / STIG yapılandırma baseline'ları (`--scan`, `--apply`).
2. **Açık yönetimi** — satıcı OVAL feed'lerine karşı bilinen-CVE taraması ve güvenlik
   yaması (`--scan-cve`, `--fix-cve`).

**Golden-image akışı** için tasarlandı: boş bir sunucu template'ini sıkılaştır, base
imaja göm, sonra uygulamaları üstüne kur.

---

## Özellikler

### Uyumluluk sıkılaştırması
- **`--scan`** — Uyumluluk taraması (CIS/ANSSI/STIG), HTML/JSON rapor + skor
- **`--apply`** — Sıkılaştırma uygular; önce yedek alır, before/after skor gösterir
- **`--unapply`** — Sistemi apply öncesi **tam** haline döndürür (config'ler **ve**
  hardening'in kaldırdığı paketler; openscap'i ve eklenen uygulamaları korur)
- **`--dry-run`** — Neyin değişeceğini severity'ye göre gösterir, sisteme dokunmaz
- **`--level 1|2`** — CIS Level 1 (temel) veya Level 2 (sıkı, varsayılan)

### Açık yönetimi (CVE)
- **`--scan-cve`** — Kurulu paketleri satıcı OVAL feed'iyle (örn. Ubuntu USN)
  **bilinen CVE**'lere karşı tarar; severity gruplu özet + HTML rapor
- **`--fix-cve`** — **Yalnızca** mevcut güvenlik güncellemelerini kurar, sonra doğrular

### Güvenlik & otomasyon
- **`--deadman <dk>` / `--confirm`** — Dead-man switch: N dakika içinde onaylanmazsa
  otomatik geri alır — **uzaktan** sıkılaştırmayı SSH lockout'a karşı güvenli kılar
- **`--yes`** — Etkileşimsiz (CI / gözetimsiz çalıştırma)
- **`--min-score <N>`** — Skor N'in altındaysa hata koduyla çıkar (CI barajı)
- **Çalışan servis koruması** — Aktif servisleri (NFS/SMB, **Apache/nginx**) tespit
  edip onları kaldıracak/durduracak kuralları hariç tutmayı önerir
- **Kurulum** — `--install` (OpenSCAP + SCAP içeriği) / `--uninstall` (geri al, sonra kaldır)

### Yerleşik
- **Exclusions** (kural/servis/path), **hooks** (pre/post/rollback),
  profilden otomatik **XCCDF tailoring**

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

> `--level`, baseline'ı seçmenin tek yoludur; belirtilmezse Level 2 (sıkı) varsayılır.

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

# Kurulu paketleri bilinen CVE'lere karşı tara (OVAL feed)
sudo ./linuxharden.sh --scan-cve

# Mevcut güvenlik güncellemelerini kur, sonra tekrar tara
sudo ./linuxharden.sh --fix-cve
sudo ./linuxharden.sh --scan-cve

# OpenSCAP paketlerini tamamen kaldır (önce hardening'i geri alır)
sudo ./linuxharden.sh --uninstall

# Yerel .yml profil kullan
sudo ./linuxharden.sh --scan --conf ./profiles/ubuntu-22.04.yml
```

### Güvenli uzaktan sıkılaştırma (dead-man switch)

SSH ile eriştiğin bir kutuyu sıkılaştırırken, değişiklikler seni kilitlerse kendini
geri alması için dead-man switch'i kur:

```bash
# Uygula, 10 dk içinde onaylamazsan otomatik geri al
sudo ./linuxharden.sh --apply --deadman 10

# Hâlâ giriş yapabiliyor musun? Değişiklikleri koru, geri almayı iptal et:
sudo ./linuxharden.sh --confirm
```

### Otomasyon / CI

```bash
# Etkileşimsiz apply (promptsuz) — örn. Packer/cloud-init build
sudo ./linuxharden.sh --apply --level 2 --yes

# Skor eşiğin altındaysa pipeline'ı kır
sudo ./linuxharden.sh --scan --min-score 90 || echo "baseline altında — deploy durdu"
```

---

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| `--install` | OpenSCAP + SCAP içeriklerini distro'ya göre otomatik kurar |
| `--uninstall` | Hardening'i geri alır, sonra OpenSCAP + SCAP paketlerini kaldırır |
| `--apply` | Sıkılaştırma uygular (yedek → uygula → doğrula) |
| `--unapply` | Sistemi apply öncesi haline döndürür (OpenSCAP'i korur) |
| `--scan` | Compliance taraması, rapor üretir |
| `--scan-cve` | Kurulu paketleri satıcı OVAL feed'iyle bilinen CVE'lere karşı tarar |
| `--fix-cve` | Yalnızca mevcut güvenlik güncellemelerini kurar |
| `--dry-run` | Başarısız kuralları severity gruplarına göre gösterir, sisteme dokunmaz (`--apply`'ı ima eder) |
| `--level <1\|2>` | Sıkılaştırma seviyesi: `1` = CIS Level 1 (temel), `2` = CIS Level 2 (sıkı, varsayılan) |
| `--format <tip>` | `html` \| `json` \| `both` (varsayılan: html) |
| `--deadman <dk>` | `--apply` ile: `<dk>` dakika sonra `--confirm` yoksa otomatik geri al |
| `--confirm` | Bekleyen dead-man geri almasını iptal et (hardening'i koru) |
| `--yes` | Onay promptlarını atla (etkileşimsiz / CI) |
| `--min-score <N>` | `--scan` skoru N'in altındaysa hata koduyla çıkar (CI barajı) |
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
  # --scan-cve için satıcı OVAL feed'i (Ubuntu USN; .bz2/.gz otomatik açılır)
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

## Yedekleme & geri alma

`--apply` her çalışmada, değişiklik yapmadan önce `/var/lib/linuxharden/<tarih>/`
altına yedek alır:

```
/var/lib/linuxharden/
├── 20260524_153000/
│   ├── configs.tar.gz          # Yedeklenen tüm config dizinleri
│   ├── services_enabled.txt    # Yedek anındaki aktif servisler
│   ├── packages.txt            # Yedek anındaki kurulu paketler
│   ├── manifest.conf           # Metadata (distro, profil, hook bilgisi)
│   ├── profile.yml             # O anki profil kopyası
│   ├── pre_hardening.arf       # Uygulama öncesi tarama
│   └── post_hardening.arf      # Uygulama sonrası tarama
└── latest -> 20260524_153000/  # --unapply / --uninstall buraya bakar
```

`--unapply` sistemi apply öncesi **tam** haline döndürür:

- Config dosyaları *tam* restore edilir — hardening'in yedeklenen bir dizinde
  **oluşturduğu** dosyalar da silinir (düz `tar x` bunları bırakırdı).
- Hardening'in **kaldırdığı** paketler yeniden kurulur.
- Servis enable/disable durumu geri yüklenir (masked unit'ler önce unmask edilir).
- Hardening'in **eklediği** paketler ve OpenSCAP **korunur** — `--unapply` ayarları
  geri alır, uygulama silmez. Geri alıp OpenSCAP'i de kaldırmak için `--uninstall`.

---

## Raporlar

`./reports/` klasörüne kaydedilir:

| Dosya | İçerik |
|-------|--------|
| `scan_<tarih>.html` | Görsel HTML raporu (oscap-report) |
| `scan_<tarih>.arf` | Ham ARF/XML çıktısı |
| `scan_<tarih>.json` | Özet: pass/fail sayıları, skor, failed rule listesi |
| `cve_<tarih>.html` | `--scan-cve`'den CVE/OVAL raporu |

---

## CVE / Güvenlik Açığı Taraması

Uyumluluk sıkılaştırması saldırı yüzeyini azaltır, ama kurulu paketlerde hangi
**bilinen, yayınlanmış açıkların** olduğunu söylemez. `--scan-cve` bu ikinci katmanı
aynı OpenSCAP motoruyla, satıcının OVAL feed'ini kullanarak kapatır:

```bash
sudo ./linuxharden.sh --scan-cve
```

```
  ┌─ CVE Scan Summary ───────────────────────────┐
  │  Vulnerable advisories : 8                    │
  │  Distinct CVEs         : 27                   │
  └──────────────────────────────────────────────┘
  6 Medium  ·  2 Low
```

- OVAL feed'i (profildeki `scap.oval_url`) indirilir, Python ile açılır (`bzip2`/`gzip`
  binary'sine gerek yok) ve 24 saat önbelleğe alınır.
- `--fix-cve` yalnızca mevcut **güvenlik** güncellemelerini kurar; `--scan-cve`'yi
  tekrar çalıştırarak temizlendiğini doğrula.

> Bunu zamanlı çalıştırmalarla eşleştirerek sürekli çıkan yeni CVE'leri yakala;
> `--min-score` / çıkış kodlarıyla CI'da deploy'ları kapıda durdur.

---

## Uyarılar

> **Root yetkisi gereklidir.** Script `sudo` ile çalıştırılmalıdır.

- `--apply` SSH ayarlarını ve sistem servislerini değiştirebilir. SSH üzerinden
  sıkılaştırırken **`--apply --deadman <dk>`** kullan ki kilitlenirsen kutu kendini geri alsın.
- `--unapply` sonrası tam geri dönüş için **reboot önerilir**.
- `--uninstall` önce hardening'i geri alır, **sonra** OpenSCAP paketlerini kaldırır.
- Arch Linux'ta SSG desteği olmadığından temel `sysctl` + SSH hardening uygulanır.
- `--dry-run` ve `--scan` / `--scan-cve` sisteme hiçbir şey yazmaz, güvenle kullanılabilir.
