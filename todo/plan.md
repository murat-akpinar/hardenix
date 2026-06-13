# hardenix — Geliştirme Planı (Fazlı Yol Haritası)

`linuxharden.sh`'i güvenli, adım adım geliştirmek için fazlara böldük. **Her faz
izole, additive (mevcut yapıyı bozmaz) ve kendi test geçidiyle bitiyor.** Böylece
en sonda topluca test etmek zorunda kalmayız.

- **Branch:** `feature/security-phases` (geliştirme burada; `main` stabil kalır)
- **Akış (her faz için):** geliştir → `bash -n` + shellcheck → test kutusunda doğrula
  → commit (faz etiketiyle) → bir sonraki faza geç
- **Birleştirme:** her faz testten geçince commit; branch stabilleşince `main`'e PR

---

## Mevcut Durum (referans)

- Modlar: `--install`, `--scan`, `--apply`, `--unapply`, `--uninstall` (+ Arch fallback)
- Seçenekler: `--level 1|2`, `--format html|json|both`, `--conf`, `--dry-run`
- OpenSCAP `oscap --remediate` + SSG; tailoring + exclusions; hooks (pre/post/rollback)
- Backup: `configs.tar.gz`, `services_enabled.txt`, `packages.txt`, `manifest.conf`
- Exact-restore unapply + paket reinstall; `detect_active_services` (NFS/autofs/SMB)
- 9 distro profili

## Katmanlı Güvenlik Modeli (hedef çerçeve)

1. **Hardening** (CIS/SCAP) — ✅ var
2. **Açık yönetimi** (CVE/OVAL) — ⭐ FAZ 5
3. **Yama** (security upgrade) — FAZ 6
4. **Çalışma-zamanı tespiti** (auditd/AIDE/fail2ban) — FAZ 7
5. **Drift + uyarı** (zamanlı tarama, bildirim) — FAZ 8

> Kapsam: hardenix güçlü bir "compliance + açık duruşu" aracı olur; tam güvenlik yığını
> değildir (ağ kontrolü, en az yetki, SIEM, yedek, olay müdahalesi ayrıca gerekir).

---

# FAZLAR

## Durum (feature/security-phases)

- ✅ **FAZ 0** — baseline (%65.2) + `TESTING.md`
- ✅ **FAZ 1** — apache/nginx servis koruması (test edildi)
- ✅ **FAZ 2** — genişletilmiş backup kapsamı; clean apply→unapply 70.4% → 67.0%
  (config revert esasen tam; kalan ~2 kural unapply'ın kasıtlı tuttuğu kurulu
  paketlerden — aide/pwquality)
- ✅ **FAZ 4** — `--yes` / `--min-score` (test edildi)
- Bulgu (mask): Boş sistemi hardenleyip **sonra** nginx/apache kurarsan servis
  **maskeli gelmez** (active/enabled/loaded). SSG yalnızca paket apply anında
  varsa mask yapar. → "önce hardenle, sonra kur" golden-image akışı güvenli.

---

## FAZ 0 — Hazırlık & Test Altyapısı  `[temel]`

Amaç: her fazı hızlı ve tekrarlanabilir doğrulayabilmek.

- [ ] `feature/security-phases` branch (✅ açıldı)
- [ ] **Smoke test prosedürü** (`todo/TESTING.md`): test kutusunda standart döngü
      — `--scan` → `--dry-run` → `--apply --level 1` → `--scan` → `--unapply` → `--scan`.
- [ ] **Statik kontrol:** `bash -n` + `shellcheck` (varsa) her commit öncesi.
- [ ] **Tekrarlanabilir uzak test yardımcı** (nohup + remote poll deseni; SSH kopsa da
      apply/unapply tamamlanır).
- [ ] Pristine baseline backup'ı sabitle (temiz skor referansı: ubuntu 24.04 ≈ %65/L2).

**Test geçidi:** smoke test tek komutla çalışıyor ve mevcut davranış bozulmamış.

---

## FAZ 1 — "Çalışanı Koru": Web/DB Servis Tespiti  `[düşük risk · yüksek değer]`

Tek fonksiyona (`detect_active_services`) additive ekleme. Mevcut NFS/SMB desenini izler.

- [ ] **Apache/nginx tespiti** → çalışıyorsa şu kuralları otomatik hariç tut:
      - Apache: `...package_httpd_removed`, `...service_httpd_disabled`
        (tespit: `systemctl is-active apache2` **veya** `httpd`)
      - nginx: `...package_nginx_removed`, `...service_nginx_disabled`
- [ ] **DB/diğer** (aynı desen): mysql/mariadb, postgresql, docker/containerd, redis,
      mongodb, postfix. Çalışıyorsa ilgili `package_*_removed`/`service_*_disabled` hariç.
- [ ] (Ops.) `ss -tlnp` ile açık port özeti.

**Test geçidi:** test kutusunda nginx kur+başlat → `--dry-run` → nginx kuralları
exclusions'a girmiş; nginx kapalıyken girmiyor. Davranış: çalışanı koruyor.

---

## FAZ 2 — Güvenlik & Geri Alınabilirlik (P0)  `[orta risk]`

apply/unapply'a additive güvenlik ağları.

- [ ] **SSH lockout koruması:** uzak oturum tespiti (`$SSH_CONNECTION`/`who`); sshd'yi
      kesebilecek kurallarda (Ciphers/MACs/Kex, `AllowUsers`, `PermitRootLogin`, password
      auth) ek uyarı + onay.
- [ ] **Pre-flight kontrolleri:** root, disk alanı, oscap mevcut, ağ (reinstall için),
      datastream var mı, `/etc` yazılabilir.
- [ ] **Backup bütünlüğü:** apply öncesi `tar tzf` doğrulaması; bozuksa dur.
- [ ] **Backup rotasyonu:** `--keep N` (varsayılan 5), eskileri buda.
- [ ] **`--unapply --from <timestamp>`:** belirli backup'tan geri al (manuel symlink
      gerekmesin).

**Test geçidi:** her madde tek tek; lockout uyarısı tetikleniyor, disksiz/oscap'sız
ortamda temiz hata, rotasyon eski backup'ları buduyor, `--from` doğru backup'ı seçiyor.

---

## FAZ 3 — Dead-man's Switch (Otomatik Geri Alma)  `[orta-yüksek risk]`

Uzaktan hardening'in güvenli olmasını sağlar (bizim SSH kopma sorunumuzun da çözümü).

- [ ] Apply sonrası zamanlayıcı (`systemd-run --on-active=Nmin` veya `at`).
- [ ] Yönetici süre içinde `linuxharden.sh --confirm` çalıştırmazsa otomatik `--unapply`.
- [ ] `--deadman <dakika>` ve `--confirm` modları; net kullanıcı bilgilendirmesi.

**Test geçidi:** apply --deadman 2 → confirm etme → 2 dk sonra otomatik revert; confirm
edince timer iptal, hardening kalıcı.

---

## FAZ 4 — Otomasyon & Etkileşimsizlik (CI hazırlığı)  `[düşük risk]`

Sonraki fazların testini de kolaylaştırır.

- [ ] **`--yes` / `--non-interactive`:** tüm onayları atla (build-time/CI).
- [ ] **`--min-score N`:** skor altındaysa non-zero exit.
- [ ] **Her zaman dosyaya log:** `/var/log/hardenix/run-<ts>.log` (TTY'den bağımsız).
- [ ] **Çıkış kodları sözleşmesi** (başarı/uyarı/hata) dokümante.

**Test geçidi:** `--apply --yes` prompt'suz çalışıyor; `--min-score 99` düşük skorda
non-zero dönüyor; log dosyası yazılıyor.

---

## FAZ 5 — ⭐ CVE / Açık Taraması: `--scan-cve` (OVAL)  `[yüksek değer · yeni mod]`

"Günlük CVE" sorununun doğrudan cevabı. OpenSCAP zaten kurulu, ek araç gerekmez.
Yeni ve self-contained bir mod — mevcut akışı etkilemez.

- [ ] **`--scan-cve` modu:** satıcı OVAL feed'ine karşı `oscap oval eval`
      → kurulu paketlerdeki bilinen CVE'ler + düzelten güncelleme (USN/RHSA).
      `oscap oval eval --results cve-results.xml --report cve-report.html <oval.xml>`
- [ ] **Feed yönetimi:** profillere `scap.oval_url` ekle; indir, önbellekle, eskiyse yenile.
      - Ubuntu: `com.ubuntu.<codename>.usn.oval.xml.bz2` (security-metadata.canonical.com)
      - RHEL/Rocky/Alma/Oracle/Debian/SUSE: ilgili OVAL feed'leri
- [ ] **Severity/CVSS özeti** + `--min-cvss 7.0` filtresi.
- [ ] **CI eşiği:** kritik/yüksek açıkta non-zero exit.

**Test geçidi:** test kutusunda Ubuntu USN OVAL feed'iyle `--scan-cve` → gerçek CVE
raporu üretiyor (HTML + özet); bilinçli eski bir paket kurup CVE yakalandığını doğrula.

---

## FAZ 6 — `--fix-cve` (Kontrollü Güvenlik Yaması)  `[FAZ 5'e bağlı]`

- [ ] CVE raporundaki açıkları mevcut güncellemelerle eşleştir.
- [ ] `--fix-cve`: yalnızca güvenlik paketlerini güncelle (apt/dnf security upgrade).
- [ ] Yama öncesi backup; sonrası `--scan-cve` ile doğrulama.

**Test geçidi:** eski paket → `--scan-cve` (yakalar) → `--fix-cve` → `--scan-cve` (temiz).

---

## FAZ 7 — Ek Hardening Kuralları (Modüler)  `[opsiyonel modüller]`

Her biri ayrı, açılıp kapanabilir modül; çekirdeği bozmaz.

- [ ] **Firewall sihirbazı** (önce SSH portu, sonra default-deny: ufw/nftables/firewalld).
- [ ] **fail2ban** kurulum + sshd jail.
- [ ] **unattended-upgrades / dnf-automatic** (otomatik güvenlik yamaları).
- [ ] **AIDE** başlatma + zamanlı bütünlük kontrolü.
- [ ] **Mount sıkılaştırma** (`/tmp`,`/var/tmp`,`/dev/shm`: nodev,nosuid,noexec).
- [ ] **Kernel modül kara liste** yönetimi (hariç tutma destekli).
- [ ] **Login banner / MOTD**, core dump/ptrace kısıtları, NTP, uzak log.

**Test geçidi:** her modül tek tek apply→doğrula→unapply ile geri alınabiliyor.

---

## FAZ 8 — Raporlama & Drift  `[değer · düşük risk]`

- [ ] **Before/after diff** (hangi kural pass→fail / fail→pass).
- [ ] **Birleşik durum raporu:** compliance skoru + CVE sayısı (severity) + yama durumu.
- [ ] **Skor/CVE trendi** (çalıştırmalar arası saklama).
- [ ] **Zamanlı tarama + uyarı** (systemd timer/cron; yeni kritik CVE'de bildirim).
- [ ] **`--only-severity high`** ile seçici remediation.

**Test geçidi:** diff raporu doğru değişimleri gösteriyor; zamanlı tarama tetikleniyor.

---

## FAZ 9 — Distro & Profil Doğrulama  `[genişleme]`

- [ ] Mevcut 9 profili gerçek ortamda doğrula (şu an yalnız ubuntu test edildi).
- [ ] **STIG profili** desteği (`--level stig` / ayrı bayrak).
- [ ] Yeni profiller: Ubuntu 20.04, Debian 11, RHEL/Rocky/Alma 8, SLES, Amazon Linux.
- [ ] SSG eksikse otomatik indirme/uyarı.

**Test geçidi:** en az 2 ek distroda (örn. Rocky 9, Debian 12) apply→scan→unapply.

---

## FAZ 10 — Test Matrisi, CI & Temizlik  `[kalite]`

- [ ] **shellcheck** GitHub Actions.
- [ ] **bats** birim testleri (parse_conf, tailoring, exclusions, revert).
- [ ] **Vagrant/Docker** test matrisi (distro başına döngü).
- [ ] Tüm `profiles/*.yml`'i datastream'lerine karşı doğrula.
- [ ] `tmp/*.sh` eski `oscap generate fix` müsveddelerini `examples/legacy/`'ye taşı veya sil.

**Test geçidi:** CI yeşil; matris tüm hedef distrolarda geçiyor.

---

## Komut Ailesi (hedef)

| Mod | İş | Durum |
|-----|-----|------|
| `--scan` | CIS/SCAP compliance taraması | ✅ var |
| `--scan-cve` | OVAL ile CVE taraması | FAZ 5 |
| `--apply` | Hardening uygula | ✅ var |
| `--fix-cve` | Güvenlik paketlerini güncelle | FAZ 6 |
| `--unapply` | Ayarları geri al (openscap kalır) | ✅ var |
| `--uninstall` | Revert + openscap'i kaldır | ✅ var |

## Tamamlayıcı Araçlar (referans)

Trivy/Grype (container CVE), Lynis (ek hardening denetimi), Vuls/OSV (çoklu sunucu CVE),
Wazuh/SIEM + auditd (çalışma-zamanı tespit). hardenix = compliance + OVAL CVE çekirdeği.

## Notlar

- `tmp/*.sh` eski standalone `oscap generate fix` çıktıları; mevcut akışın parçası değil
  (FAZ 10'da temizlenecek).
- Önerilen başlangıç sırası: **FAZ 0 → 1 → 5** (en yüksek değer/risk oranı), sonra 2/3/4.
