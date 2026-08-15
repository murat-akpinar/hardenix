# hardenix

[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-1a1a1a?style=flat-square&labelColor=1a1a1a&color=8a6f3a)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/built%20with-Claude%20Code-1a1a1a?style=flat-square&labelColor=1a1a1a&color=d8b66b)](https://claude.com/claude-code)
[![Status](https://img.shields.io/badge/status-active-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4a9e6b)](https://github.com/murat-akpinar/hardenix)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=4eaa25&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![OpenSCAP](https://img.shields.io/badge/OpenSCAP-1.3%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=cc0000)](https://www.open-scap.org)
[![Python](https://img.shields.io/badge/Python-3.8%2B-1a1a1a?style=flat-square&labelColor=1a1a1a&color=3776ab&logo=python&logoColor=white)](https://www.python.org)
[![Distros](https://img.shields.io/badge/distros-9%20supported-1a1a1a?style=flat-square&labelColor=1a1a1a&color=e95420)](https://github.com/murat-akpinar/hardenix/tree/main/profiles)

> English version: [README.md](README.md)

OpenSCAP tabanlı Linux sıkılaştırma **ve güvenlik açığı yönetim** aracı. Tek script,
tek YAML profili ile birbirini tamamlayan üç güvenlik katmanını yönetir:

1. **Uyumluluk sıkılaştırması** — CIS / ANSSI / STIG yapılandırma baseline'ları (`--scan-compliance`, `--apply`).
2. **Güvenlik denetimi** — 0-100 sıkılaştırma endeksi veren Lynis ikinci görüş denetimi (`--scan-lynis`).
3. **Açık yönetimi** — satıcı OVAL feed'lerine karşı bilinen-CVE taraması ve güvenlik
   yaması (`--scan-cve`, `--fix-cve`).

Düz `--scan` tüm read-only katmanları tek seferde çalıştırır.

**Golden-image akışı** için tasarlandı: boş bir sunucu template'ini sıkılaştır, base
imaja göm, sonra uygulamaları üstüne kur.

---

## Hızlı başlangıç

```bash
git clone https://github.com/murat-akpinar/hardenix.git && cd hardenix

sudo ./linuxharden.sh --install     # 1. tarama motorlarını kur (bir kez)
sudo ./linuxharden.sh --scan        # 2. şu an neredeyiz?
sudo ./linuxharden.sh --dry-run     # 3. --apply neyi değiştirirdi?
sudo ./linuxharden.sh --apply       # 4. sıkılaştır — önce yedek alır
sudo ./linuxharden.sh --unapply     #    fikrin mi değişti? geri al
```

SSH ile eriştiğin bir makineyi mi sıkılaştırıyorsun? **`--deadman 15`** ekle ki
değişiklikler seni kilitlerse kutu kendini geri alsın — bkz.
[güvenli uzaktan sıkılaştırma](#güvenli-uzaktan-sıkılaştırma-dead-man-switch).

Beş mod ve beş seçenek neredeyse her çalıştırmayı karşılıyor; `--help` tam olarak
bunu basar. Tamamı bir komut ötede:

```bash
./linuxharden.sh --help        # günlük set — tek ekrana sığar
./linuxharden.sh --help all    # her mod ve seçenek, gruplanmış
```

---

## Ne yapar

| Katman | Cevapladığı soru | Modlar |
|--------|------------------|--------|
| **Uyumluluk sıkılaştırması** | Bu kutu tanınmış bir baseline'a göre yapılandırılmış mı? | `--apply` · `--unapply` · `--scan-compliance` |
| **Güvenlik denetimi** | İkinci, bağımsız bir motor ne diyor? | `--scan-lynis` |
| **Açık yönetimi** | Kurulu paketlerin hangisinde yayınlanmış CVE var? | `--scan-cve` · `--fix-cve` |

`--scan` üç salt-okunur katmanı tek geçişte çalıştırır ve tek bir duruş kutusuyla
biter. Eksik bir motor çalıştırmayı hataya düşürmek yerine uyarıyla atlanır;
`--min-score` yalnızca uyumluluk skorunu kapı olarak kullanır.

### Sıkılaştırma — `--apply` / `--unapply`

- İlk değişiklikten **önce** yedek alır, sonra tekrar tarayıp before/after skoru
  raporlar
- `--unapply` sistemi apply öncesi **tam** haline döndürür: config'ler byte-byte,
  servis enable/disable durumu ve sıkılaştırmanın kaldırdığı paketler. Sıkılaştırmanın
  *eklediği* paketler — ve OpenSCAP'in kendisi — korunur: bu ayarları geri alır,
  uygulama silmez
- `--dry-run` başarısız kuralları severity'ye göre listeler, hiçbir şey değiştirmez
- `--level 1` = temel, `--level 2` = sıkı (varsayılan)

### Açık yönetimi — `--scan-cve` / `--fix-cve`

- Kurulu paketleri satıcı OVAL feed'ine karşı kontrol eder (örn. Canonical USN);
  RHEL klonları bunun yerine aşırı raporlamayan native `dnf updateinfo` kullanır
- Severity gruplu özet + HTML rapor; `--fix-cve` **yalnızca** güvenlik
  güncellemelerini kurar, sonra doğrular

### Denetim — `--scan-lynis`

- [Lynis](https://github.com/CISOfy/lynis) sıkılaştırma endeksi (0-100), uyarılar
  ve öneriler — OpenSCAP'ten bağımsız bir ikinci görüş ve Arch'ta kullanılabilen
  tek denetim motoru

### Güvenlik

- **Dead-man switch** (`--deadman <dk>` / `--confirm`) — erişiminin sürdüğünü
  onaylamazsan otomatik geri alır. SSH üzerinden sıkılaştırmayı hayatta kalınabilir
  kılan şey budur.
- **SSH lockout uyarısı** — baseline `PermitRootLogin no` yapıyor; yani SSH'tan root
  olarak girdiğin kutuyu sıkılaştırmak, girdiğin kapıyı kapatıyor. `--apply` ve
  `--dry-run` bunu prompt'tan önce **kuralın adıyla** söylüyor ve `sudo`/`wheel`
  üyesi **ve** SSH anahtarı olan root dışı bir hesap kalıyor mu diye bakıyor.
  Kalmıyorsa geriye tek yolun konsol olduğunu açıkça yazıyor.
- **Çalışan servis koruması** — aktif servisleri (NFS/SMB, **Apache/nginx**) tespit
  edip onları kaldıracak veya durduracak kuralları hariç tutmayı önerir
- **Salt-okunur gerçekten salt-okunurdur** — tüm tarama modları ve `--dry-run`
  sisteme hiçbir şey yazmaz
- Gözetimsiz çalıştırma için `--yes`, pipeline'ı kapıda durdurmak için `--min-score <N>`

### Yerleşik

Profil bazlı **exclusions** (kural / servis / path), **hooks** (pre-hardening /
post-hardening / on-rollback) ve profilden üretilen **XCCDF tailoring** dosyası.

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
| Arch Linux | sysctl + SSH hardening + Lynis audit | — | Bash fallback |

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
git clone https://github.com/murat-akpinar/hardenix.git
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
- İkinci görüş denetimi için Lynis'i kurar (best-effort; tek başına tekrar: `--install-lynis`)

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

# Tam durum taraması (compliance + Lynis denetimi + CVE)
sudo ./linuxharden.sh --scan

# HTML + JSON rapor üret
sudo ./linuxharden.sh --scan --format both

# Yalnız Lynis denetimi (hardening index + uyarılar)
sudo ./linuxharden.sh --scan-lynis

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

`--help` ile aynı şekilde bölündü: önce günlük set, gerisi katlanmış halde.

### Günlük

| Parametre | Açıklama |
|-----------|----------|
| `--install` | Tarama motorlarını kurar: OpenSCAP + SCAP içeriği + Lynis |
| `--scan` | Tam durum taraması: compliance + Lynis denetimi + bilinen CVE'ler (eksik katman atlanır) |
| `--apply` | Sıkılaştırma uygular (yedek → uygula → doğrula) |
| `--unapply` | Sistemi apply öncesi haline döndürür (OpenSCAP'i korur) |
| `--fix-cve` | Yalnızca mevcut güvenlik güncellemelerini kurar |
| `--last` | Son taramanın kutusunu diskten tekrar basar — tarama yapmaz |
| `--level <1\|2>` | Sıkılaştırma seviyesi: `1` = CIS Level 1 (temel), `2` = CIS Level 2 (sıkı, varsayılan) |
| `--dry-run` | `--apply`'ın neyi değiştireceğini severity'ye göre gösterir — hiçbir şey değiştirmez |
| `--yes` | Her prompta evet varsayar (etkileşimsiz / CI) |
| `--deadman <dk>` | `--apply` ile: `<dk>` dakika sonra `--confirm` yoksa otomatik geri al |
| `--confirm` | Sıkılaştırmayı korur — bekleyen otomatik geri almayı iptal eder |

<details>
<summary><b>Geri kalan her şey</b> — tek katmanlı taramalar, raporlama, CI, ince ayar</summary>

**Tek katman çalıştır.** `--scan` zaten üçünü birden yapıyor; birini tek başına
istediğinde bunlara başvur.

| Parametre | Açıklama |
|-----------|----------|
| `--scan-compliance` | Yalnız compliance taraması (OpenSCAP) |
| `--scan-lynis` | Yalnız Lynis denetimi: hardening index (0-100) + uyarılar |
| `--scan-cve` | Yalnız bilinen-CVE taraması (satıcı OVAL feed'i, RHEL klonlarında `dnf` errata) |
| `--install-openscap` | Yalnız OpenSCAP + SCAP içeriği kurar |
| `--install-lynis` | Yalnız Lynis kurar (RHEL ailesi: EPEL gerekir) |
| `--uninstall` | Hardening'i geri alır, sonra OpenSCAP + SCAP paketlerini kaldırır |

**Raporlama ve CI**

| Parametre | Açıklama |
|-----------|----------|
| `--format <tip>` | `html` \| `json` \| `both` (varsayılan: html) |
| `--min-score <N>` | Uyumluluk skoru N'in altındaysa `2` ile çık (CI barajı) |
| `--full` | Listeyi ekrana kırpmak yerine tüm bulguları yazdır |

**İnce ayar**

| Parametre | Açıklama |
|-----------|----------|
| `--keep <N>` | `--apply` ile: yalnız en yeni N yedeği tut (varsayılan 5, `0` = hepsi) |
| `--refresh-feed` | OVAL feed'ini 24 saatlik cache yerine yeniden indir |
| `--conf <dosya>` | Gömülü profil yerine yerel bir .yml profili kullan |
| `--report-dir <dizin>` | Raporların yazılacağı yer (varsayılan `/var/lib/linuxharden/reports`) |
| `--with-epel` | `--install` RHEL ailesinde EPEL'i etkinleştirsin (Lynis orada) |

</details>

### Konsol dostu çıktı

`--scan` makinenin kendi konsolunda okunmak üzere tasarlandı; orada scrollback
yok. Çıktı **tek bir duruş kutusuyla** biter — üç katman ve önemli bulgular:

```
  ┌─ hardenix 1.5.0 · Ubuntu 24.04.4 LTS · CIS Level 1 (basic) ──────────────┐
  │  Compliance   92.9 %    245 pass · 19 fail                               │
  │  Failing      19        2 high · 12 medium · 5 low                       │
  │  Lynis        58/100    12 warnings · 41 suggestions                     │
  │  CVE          340       8 critical · 44 high · 92 advisories             │
  ├──────────────────────────────────────────────────────────────────────────┤
  │  HIGH    package_telnetd_removed                                         │
  │  HIGH    sshd_disable_root_login                                         │
  │  MEDIUM  mount_option_tmp_nodev                                          │
  │  … +16 more failing rules                                                │
  ├──────────────────────────────────────────────────────────────────────────┤
  │  reports/scan_20260815_141230.html                                       │
  └──────────────────────────────────────────────────────────────────────────┘
```

**Failing** satırı fail sayısını severity'ye göre ayırır. Kırpılmış listeyi
kullanılabilir yapan şey budur: tek başına `… +16 more failing rules` o 16'nın
içinde ne olduğunu söylemiyor, `19 fail` de eyleme dönüşmüyor — `2 high` dönüşüyor.

Geniş terminalde başarısız kurallar **severity başına bir sütun** olarak
diziliyor; her sütunun kendi sayısı ve kendi `… +N more` satırı var, böylece kutu
yüksekliği hangi severity baskınsa ona bağlı kalmıyor:

```
  ├────────────────────────────────────────────────────────────────────────┤
  │  HIGH (4)              │ MEDIUM (94)            │ LOW (22)             │
  │  grub2_password        │ account_disable_post…  │ grub2_audit_argument │
  │  grub2_uefi_password   │ accounts_maximum_age…  │ kernel_module_cramf… │
  │  no_empty_passwords…   │ … +92 more             │ … +20 more           │
```

Sütunlar yalnız okunabilir kaldıkları yerde çıkar — hücre 20 karakterin altına
inince kural adı birden çok kuralın paylaştığı bir öneke çöküyor, o yüzden dar
konsol ve yönlendirilmiş çıktı düz severity sıralı listeyi koruyor. Kutu
terminale göre boyutlanır, hep tek ekrana sığar; ASCII banner kısa terminalde
tek satıra iner.

**Çıktı terminale gitmiyorsa hiçbir şey düşmez.** Dosyaya yönlendir, boruya ver
ya da CI'da çalıştır — kutu *bütün* başarısız kuralları listeler; `--full`
terminalde de aynısını yapar. `--format json` her iki durumda da etkilenmez.
Tek katmanlı modlar (`--scan-compliance`, `--scan-lynis`, `--scan-cve`) kendi
özet kutularını ve orijinal severity-gruplu listelerini korur.

### Çıkış kodları

| Kod | Anlamı |
|-----|--------|
| `0` | Başarılı (`--help` dahil) |
| `1` | Hata: kullanım hatası, bilinmeyen/çakışan bayrak, eksik bağımlılık, kullanılabilir yedek yok, yedek alınamadı, yamalama başarısız |
| `2` | `--min-score N` barajı: uyumluluk skoru eşiğin altında |

Kullanım hatası her zaman sıfırdan farklı döner; yanlış yazılmış bir bayrak
temiz koşu gibi görünmek yerine pipeline'ı kırar. `--apply`, `--deadman`
verilsin ya da verilmesin, başarıda `0` döner.

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

`/var/lib/linuxharden/reports/` altına kaydedilir (`--report-dir <dizin>` ile
değiştirilebilir). Yol çalışma dizinine göre değil sabit; böylece cron/systemd
çalıştırması beklediğin yere yazıyor ve `--last` dünkü taramayı bulabiliyor:

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
  │  Vulnerable CVEs       : 21                   │
  │  Fixing advisories     : 1                    │
  └──────────────────────────────────────────────┘
  8 High  ·  8 Medium  ·  5 Low

  Vulnerable CVEs:
    High      CVE-2026-31676     USN-8373-1
    High      CVE-2026-43284     USN-8373-1
    ...
```

Liste **CVE-merkezlidir** (herkes CVE ile arar); USN yalnızca düzeltmeyi getiren
advisory referansı olarak gösterilir. Tam liste HTML raporda.

- OVAL feed'i (profildeki `scap.oval_url`) indirilir, Python ile açılır (`bzip2`/`gzip`
  binary'sine gerek yok) ve 24 saat önbelleğe alınır.
- `--fix-cve` yalnızca mevcut **güvenlik** güncellemelerini kurar; `--scan-cve`'yi
  tekrar çalıştırarak temizlendiğini doğrula.
- **Çekirdek yaması reboot'a kadar devrede değildir.** Makine yeni kurduğu
  çekirdekten eskisiyle çalışmaya devam ediyorsa `--fix-cve` bunu açıkça söyler —
  reboot edilene dek kutu açık kalır ve `--scan-cve` o CVE'leri raporlamayı
  sürdürür. Bu bayat sonuç değil, doğru sonuçtur.
- Feed 24 saat önbelleklenir; yeniden indirmek için **`--refresh-feed`** ver.
  Satıcılar her gün advisory yayımladığı için cache'li feed bir gün geride kalabilir.

> Bunu zamanlı çalıştırmalarla eşleştirerek sürekli çıkan yeni CVE'leri yakala;
> `--min-score` / çıkış kodlarıyla CI'da deploy'ları kapıda durdur.

---

## Test Sonuçları

Gerçek makinelerde uçtan uca çalıştırmalar (scan → apply → unapply → CVE taraması):

### Ubuntu 24.04.4 LTS
- Kernel `6.8.0-generic` · oscap 1.3.9 · profil `cis_level2_server` / `cis_level1_server`
- **`--scan` (baseline, Level 2):** %65.2 — 242 pass / 129 fail
- **`--apply --level 1`:** %68.5 → **%93.7** (+25.2)
- **`--unapply`:** config'i tam geri yükler + kaldırılan paketleri yeniden kurar
- **`--scan-cve`** (Canonical USN OVAL): tam yamalı kutuda 0 CVE (`apt` ile uyumlu).
  Tespit doğrulaması: `curl` eski sürüme düşürüldü → **8 advisory / 27 CVE** yakalandı;
  **`--fix-cve`** yamaladı → tekrar 0.
- **v1.2.0 (Lynis) doğrulama turu:**
  - **`--install`** tek seferde OpenSCAP + SSG + **Lynis** kurdu
  - **`--scan` (birleşik):** tek çalıştırmada compliance %65.5 + Lynis sıkılaştırma
    endeksi **58/100** + 340 bilinen CVE; `--min-score 99` üç katmanı da
    çalıştırdıktan sonra exit 2 verdi (gate en sonda uygulanır)
  - **`--apply --level 1 --deadman 15`:** %68.5 → **%93.4**; `--confirm` timer'ı
    iptal etti; `--unapply` → %67.0
  - Bayat rapor koruması: lynis bozukken `--scan-lynis` eski endeksi basmak
    yerine sesli şekilde hata verdi (exit 1)

### Rocky Linux 9.8 (Blue Onyx)
- Kernel `5.14.0-687.10.1.el9_8` · oscap 1.3.13 · profil `cis` / `cis_server_l1`
- **`--scan` (baseline, Level 2):** %47.4 — 191 failing kural
- **`--apply --level 1`:** %58.7 → **%98.1** (+39.4)
- **`--scan-cve`** (native `dnf updateinfo` errata): **39 CVE / 7 advisory**
  (34 Important · 5 Moderate) — RHEL klonlarında OVAL kullanılmaz (aşırı raporlar).
- **v1.2.0 (Lynis) doğrulama turu:**
  - **EPEL'siz `--install`:** zarif düşüş — uyarı + EPEL ipucu, **exit 0**
    (compliance/CVE özellikleri etkilenmez); `epel-release` sonrası
    `--install-lynis` Lynis 3.1.7'yi kurdu
  - **`--scan` (birleşik):** tek çalıştırmada compliance %47.1 + Lynis
    sıkılaştırma endeksi **66/100** + native `dnf updateinfo` ile CVE'ler

> Sayılar makinenin ne kadar güncel olduğuna göre değişir; CVE sayıları tarama
> anındaki bekleyen satıcı güvenlik advisory'lerini yansıtır.

---

## Uyarılar

> **Root yetkisi gereklidir.** Script `sudo` ile çalıştırılmalıdır.

- `--apply` SSH ayarlarını ve sistem servislerini değiştirebilir. SSH üzerinden
  sıkılaştırırken **`--apply --deadman <dk>`** kullan ki kilitlenirsen kutu kendini geri alsın.
- `--unapply` sonrası tam geri dönüş için **reboot önerilir**.
- `--uninstall` önce hardening'i geri alır, **sonra** OpenSCAP paketlerini kaldırır.
- Arch Linux'ta SSG desteği olmadığından temel `sysctl` + SSH hardening uygulanır.
- `--dry-run` ve `--scan` / `--scan-cve` sisteme hiçbir şey yazmaz, güvenle kullanılabilir.
