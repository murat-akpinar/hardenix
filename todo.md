# hardenix — TODO

Projenin tek planlama dosyası. Eski `todo/plan.md`, `todo/lynis-plan.md`,
`todo/webui-plan.md` ve `todo/TESTING.md` burada birleştirildi.

| Bölüm | İçerik |
|---|---|
| [1. Durum](#1-durum-v120) | Bugün ne var |
| [2. Yapılacaklar](#2-yapılacaklar) | Sıralı iş listesi (P0 → P3) |
| [3. Web UI planı](#3-web-ui-planı-faz-w0w8) | Filo yönetimi, FAZ W0–W8 (başlanmadı) |
| [4. Test prosedürü](#4-test-prosedürü) | Smoke döngüsü + statik kontrol |
| [5. Arşiv](#5-arşiv-tamamlanan-fazlar) | Tamamlanan fazlar ve VM sonuçları |

---

## 1. Durum (v1.2.0)

Üç katmanlı güvenlik modeli:

| Katman | Mod | Durum |
|---|---|---|
| 1. Compliance hardening (CIS/SCAP) | `--scan-compliance` · `--apply` · `--unapply` | ✅ |
| 1b. İkinci görüş denetimi (Lynis) | `--scan-lynis` | ✅ |
| 2. Açık yönetimi (CVE/OVAL) | `--scan-cve` | ✅ |
| 3. Yama | `--fix-cve` | ✅ |
| 4. Birleşik duruş | `--scan` (üç katman) | ✅ |
| 5. Çalışma-zamanı tespiti (auditd/AIDE/fail2ban) | — | ⬜ P2 |
| 6. Drift + uyarı (zamanlı tarama, bildirim) | — | ⬜ P1 |

Ayrıca: 9 distro profili, tailoring + exclusions, hooks, dead-man switch
(`--deadman`/`--confirm`), `--yes`, `--min-score`, backup→apply→verify sözleşmesi,
exact-restore unapply, Arch fallback.

> **Kapsam:** hardenix = compliance + açık duruşu aracı. Tam güvenlik yığını değil
> (ağ kontrolü, en az yetki, SIEM, yedek, olay müdahalesi ayrıca gerekir).
> Tamamlayıcılar: Trivy/Grype (container CVE), Vuls/OSV (çoklu sunucu), Wazuh + auditd.

---

## 2. Yapılacaklar

Sıralama **değer / efor** oranına göre. P0 = bir sonraki sürümde yapılmalı.

### P0 — Planda ✅ görünüyor ama kodda yok

Eski FAZ 2 tamamlanmış işaretlenmişti; gerçekte yalnız **backup kapsamı genişletme**
kısmı yapıldı. Kalan 5 madde hâlâ açık ve hepsi üretimde canını yakacak türden:

- [x] **Backup rotasyonu — `--keep N` (varsayılan 5).** ✅ v1.4.0. `prune_backups()`
      `latest`'in gösterdiği dizini yaşı ne olursa olsun asla budamıyor (unapply'ın
      kullanacağı yedek o). Linux'ta 10 birim testi + Rocky'de canlı: 3 yedek →
      `--apply --keep 2` → 4 oldu → 2'ye budandı, `latest` hâlâ çözülüyor.
      `--keep 0` hepsini tutar.
- [x] **Backup bütünlük doğrulaması.** ✅ v1.2.1. `create_backup()` artık `tar` çıkışını
      ayırt ediyor (≥2 = ölümcül, 1 = "dosya değişti" uyarısı), arşivi `tar tzf` ile
      geri okuyor ve **arşivlemeyi hedeflediği her yolun listede olduğunu** doğruluyor;
      üçü de başarısızsa `run_apply()` sistem daha hiç değişmeden duruyor.
      Düşünüldüğünden ağırdı: `revert_hardening()` arşivde **olmayan** dosyaları
      siliyor, yani sessizce eksik bir arşiv `--unapply`'ı config öğütücüsüne
      çeviriyordu.
- [ ] **`--unapply --from <timestamp>`.** Bugün yalnız `latest` symlink'i okunuyor
      (`latest_backup_dir()`); iki apply üst üste gelmişse ilkine dönmenin tek yolu
      elle symlink oynatmak.
- [x] **SSH lockout uyarısı.** ✅ v1.5.0 — `warn_ssh_lockout()` (arşiv).
- [ ] **Pre-flight kontrolleri:** disk alanı (backup için), `/etc` yazılabilir mi, ağ
      var mı (unapply'ın paket reinstall'ı için). Şu an hepsi iş ortasında patlıyor —
      yarım uygulanmış hardening en kötü durum.
      **Paket yöneticisi kilidi de buraya:** 2026-08-15 testinde 151'de
      `unattended-upgrades` dpkg kilidini tutuyordu; `--install` ham bir
      `E: Could not get lock /var/lib/dpkg/lock-frontend` ile düştü — hardenix
      seviyesinde tek satır mesaj yok. `fuser /var/lib/dpkg/lock-frontend` /
      `dnf` `/var/run/dnf.pid` kontrolü + anlaşılır hata.
- [ ] **`oscap` çağrılarında watchdog yok — asılı kalan tarama sonsuza kadar asılı
      kalıyor.** 2026-08-15, Ubuntu 24.04.4, oscap **1.3.9**: `--scan --level 1
      --full` çalışırken oscap **deadlock**'a girdi. Ölçülen kanıt: 15 dakika
      boyunca `%CPU 0.1`, `utime/stime` iki örnekleme arasında **birebir aynı**
      (95/23 jiffies), `rchar`/`syscr` **sabit** (372334035 / 174101), ARF dosyası
      hiç oluşmadı, **59 thread'in tamamı** `futex_wait_queue`'da — hiçbiri
      çalışabilir durumda değil. Thread kompozisyonu 19×(`input_handler` +
      `icache_worker` + `common_main`) + 1 `probe_worker`, yani probe icache
      katmanı. `SIGTERM` **yutuldu** (handler çalışamıyor), `SIGKILL` gerekti.
      Sistem sağlıklıydı: `systemctl is-system-running` = running, bekleyen job
      yok, 0 failed unit, dbus ayakta.
      **Bu bir hardenix kusuru değil** — upstream OpenSCAP 1.3.9 probe deadlock'u.
      **Hardenix kusuru şu:** `oscap` çağrılarının hiçbirinde timeout/watchdog yok,
      dolayısıyla `--scan` süresiz asılı kalıyor. Cron/systemd timer altında bu
      kalıcı takılı iş demek. Test harness'ında `timeout 1800` olduğu için kurtuldu.
      Gerekli: `oscap` çağrılarını yapılandırılabilir bir watchdog'a al
      (`--timeout <dk>`, makul varsayılan), aşımda anlaşılır hata + exit 1, ve
      `--apply` ortasında olursa yedeğin durumu net söylensin.

**Test geçidi:** rotasyon eski backup'ları buduyor · bozuk tarball apply'ı durduruyor ·
`--from` doğru backup'ı seçiyor · uzak oturumda lockout uyarısı çıkıyor · disksiz/
oscap'sız ortamda temiz hata. → `v1.3.0`

### P0 — İşletim ergonomisi

- [ ] **`REPORT_DIR="$(pwd)/reports"` → sabit yol.** Raporlar çalışma dizinine yazılıyor;
      cron/systemd timer'dan (cwd=`/`) çalıştırınca `/reports` denenir.
      `/var/lib/linuxharden/reports` + `--report-dir` bayrağı. Web UI de uzak raporları
      sabit yoldan topluyor — FAZ W5 buna bağlı.
- [ ] **Dosyaya log** (`/var/log/hardenix/run-<ts>.log`), TTY'den bağımsız. Otomasyondan
      çalışan bir apply'ın ne yaptığına dair bugün kalıcı iz yok.
- [x] **Çıkış kodu sözleşmesi** (0 başarı / 1 hata / 2 eşik altı) + README'de tablo.
      ✅ v1.2.1: her iki README'de ve `docs/script-internals.md`'de tablo var; kullanım
      hataları artık 1 dönüyor (eskiden 0 dönüp CI'da temiz koşu gibi görünüyordu).
- [ ] **`--version`** (tek satır, makine-okur). Web UI planının script'e dokunmasına izin
      verilen **tek** istisnası; şimdi eklenirse deploy sürüm tespiti script'i hiç
      açmadan çalışır.

**Test geçidi:** `cd / && linuxharden.sh --scan` rapor üretiyor · log dosyası yazılıyor ·
`--min-score 99` belgelenmiş kodu dönüyor · `--version` tek satır basıyor. → `v1.4.0`

### P1 — Yeni yetenekler

- [ ] **Before/after diff raporu.** Hangi kural `fail→pass`, hangisi `pass→fail`. Skorun
      65→93 çıkması *neyin* değiştiğini söylemiyor; "bu makinede ne değişti" sorusunun
      tek cevabı bu.
- [ ] **Zamanlı tarama** (systemd timer + `--scan --yes --format json`). CVE'ler günlük
      çıkıyor; tek seferlik tarama bir hafta sonra yalan. Bildirim için önce exit-code +
      log yeter, e-posta/webhook sonra.
- [ ] **Trend saklama** — çalıştırma başına `score`, `cve_count`, `lynis_index` tek satır
      JSONL. Web UI'ın zaman çizelgesi zaten bunu istiyor; script tarafında ~10 satır ve
      UI'ı beklemeden değer üretir.
- [ ] **`--min-cvss` / CVE için CI eşiği.** `--scan-cve` bugün her şeyi basıyor;
      "kritik varsa build'i kes" yapılamıyor.
- [ ] **`--only-severity high` ile seçici remediation.** Tam apply'ın riskini göze
      alamayan makineler için giriş yolu.

### P1 — Distro & profil kapsamı

- [ ] **9 profilin gerçek doğrulaması.** Yalnız Ubuntu 24.04 + Rocky 9.8 VM'de koşturuldu;
      kalan 7 profil "yazıldı, denenmedi". En azından Debian 12 + AlmaLinux 9 +
      openSUSE Leap 15 → `--scan`.
- [ ] **Profil ID'lerini datastream'e karşı otomatik doğrula** (`oscap info`). SSG sürüm
      yükseltmesi profil ID'sini değiştirdiğinde bugün ancak makinede hata alarak
      öğreniliyor (bkz. `34566d1`).
- [ ] **STIG profili desteği** (`--level stig`). SSG'de zaten var; `--level` case'ine
      üçüncü dal + profil anahtarı yeter.
- [ ] **Yeni profiller:** Ubuntu 20.04, Debian 11, RHEL/Rocky/Alma 8, Amazon Linux 2023,
      SLES. Her biri bir YAML — kod değişmiyor.
- [ ] SSG paketi eksikse otomatik indirme/uyarı (kısmen `install_ssg_from_github()` var).

### P2 — Kalite / CI

- [ ] **GitHub Actions: `bash -n` + `shellcheck`.** Gate'ler bugün elle çalıştırılıyor;
      "her commit öncesi" pratikte insan disiplinine bağlı. En ucuz kalıcı kazanç.
- [ ] **bats birim testleri** — root gerektirmeyen saf fonksiyonlar: `parse_args`
      doğrulamaları, `parse_conf`, tailoring XML üretimi, exclusion birleştirme, CVE
      özet parse'ı. Mutasyon yolları VM'de kalır.
- [ ] **Docker tabanlı `--scan` matrisi.** Apply/unapply container'da anlamsız
      (systemd/kernel), ama `--install` + `--scan-compliance` + `--scan-cve` distro başına
      container'da koşar → 9 profilin çoğu insansız doğrulanır.
- [ ] **`tmp/*.sh` temizliği** — eski `oscap generate fix` müsveddeleri; sil veya
      `examples/legacy/`'ye taşı.
- [x] **Bilinen kozmetik hata:** `revert_hardening()`'de `xargs -I{} log_info` shell
      fonksiyonunu çağıramıyor → "sysctl reloaded" yerine stderr'e xargs hatası düşüyor.
      ✅ v1.2.1: sayım değişkene alınıp `log_info` doğrudan çağrılıyor.

### P2 — Ek hardening modülleri

SSG'nin kapsamadığı veya kasten dışladığımız yerler. Her biri bağımsız ve
apply/unapply sözleşmesine uymak zorunda (bu yüzden ucuz değiller):

- [ ] **Firewall sihirbazı** — önce SSH portunu aç, sonra default-deny (ufw/nftables/
      firewalld). Firewall kuralları profillerde bilinçli olarak `exclusions` içinde;
      yani hardening sonrası makinede firewall politikası **yok**. En büyük kapsam
      boşluğu, en yüksek kilitlenme riski → dead-man switch zorunlu.
- [ ] **unattended-upgrades / dnf-automatic** — `--fix-cve`'yi elle çalıştırmayı unutan
      herkes için. Küçük ve yüksek değerli.
- [ ] **fail2ban + sshd jail**, **AIDE init + zamanlı kontrol**, **mount sıkılaştırma**
      (`/tmp`, `/var/tmp`, `/dev/shm`), **kernel modül kara listesi**, **login banner /
      MOTD**, **core dump/ptrace kısıtları**, **NTP**, **uzak log**.
      ⚠ Çoğu SSG kurallarıyla örtüşüyor — eklemeden önce "SSG bunu zaten yapıyor mu"
      kontrolü şart, yoksa iki kaynaklı çakışma.

### P3 — Kasıtlı yapılmayanlar

- **Web UI** → bölüm 3. Script tarafındaki P0 maddeleri (sabit rapor yolu, `--version`,
  çıkış kodları) bitmeden başlanırsa UI onların etrafında yamalanır.
- **Container/imaj taraması, SIEM entegrasyonu, ajan mimarisi** — hardenix'in kapsamı
  değil; tamamlayıcı araçlar listesi bölüm 1'de.
- **Script'i modüllere bölmek.** 2130 satır tek dosya rahatsız edici, ama tek-dosya
  dağıtım modeli aracın en güçlü yanı; bölmek dağıtımı bozar, karşılığında hiçbir
  kullanıcı sorununu çözmez.
- **`--apply` + `--fix-cve` birleşimi** — revert sözleşmesi gereği ayrı kalırlar.
- **Lynis'i vendor'lamak** — her zaman paket yöneticisi. `--min-index` (Lynis eşiği) de
  yok; ihtiyaç doğarsa ayrı küçük faz.

### Önerilen sıra

1. P0 backup/pre-flight beşlisi → `v1.3.0` (hepsi aynı test geçidinde).
2. Rapor yolu + dosya log + çıkış kodları + `--version` → otomasyon tabanı, `v1.4.0`.
3. shellcheck CI + bats → bundan sonrası regresyonsuz gider.
4. Diff raporu + zamanlı tarama + trend → "tek seferlik araç"tan "sürekli duruş"a.
5. Firewall modülü ve Web UI en sona; ikisi de yukarıdaki tabana yaslanıyor.

---

## 3. Web UI planı (FAZ W0–W8)

**Durum: başlanmadı. Tasarım kararları bağlayıcı.** Mimari doküman:
[`docs/fleet-webui.md`](docs/fleet-webui.md).

**Hedef:** cihaz envanteri tutan, SSH ile `linuxharden.sh`'i `/opt/hardenix`'e dağıtan ve
toplu `--install`/`--scan`/`--scan-cve`/`--fix-cve`/`--apply`/`--unapply` çalıştırıp
sonuçları merkezde toplayan çok kullanıcılı web UI.

**Stack:** FastAPI + Celery + PostgreSQL 16 + Redis 7, Docker Compose. Python 3.11+,
SQLAlchemy 2 + Alembic, paramiko, cryptography (Fernet), Jinja2 + htmx (vendored — CDN
yok), passlib[argon2], pytest + httpx.

**Ölçek hedefi:** bugün 10-20 cihaz, hedef 1000 — mimari değişmeden worker sayısı
artırılarak (`docker compose up --scale worker=4`).

### Onaylanmış tasarım kararları

1. **Celery + Redis + Postgres** mimarisi (1000 cihaz hedefi için).
2. **Karışık SSH auth** (anahtar VEYA parola, cihaz başına credential referansı) +
   filoyu tek yönetim anahtarına yakınsatan **key-rollout** iş tipi.
3. **RBAC:** `viewer` (görüntüleme) / `operator` (ping, deploy, install, scan, scan-cve) /
   `admin` (apply, unapply, fix-cve, key-rollout, kullanıcı+credential yönetimi).
4. **Ölçekleme disiplinleri baştan:** raporlar diske (DB'ye değil) + retention; iki
   kuyruk (`interactive` + `bulk`); tüm listeler sunucu tarafı sayfalı; dashboard SQL
   agregasyonla; canlı iş takibi sayaç özetiyle; **toplu confirm**.
5. **Apply güvenliği:** UI'dan `--apply` her zaman `--deadman <N>` ile gider (varsayılan
   30 dk, kapatılamaz); tekil + toplu "Confirm" akışı `--confirm` gönderir.
6. `jobs.schedule` alanı şemada rezerve (v2'de Celery Beat).
7. **Lynis:** script'te `--scan-lynis` var (v1.2.0) → FAZ W5'teki Lynis işi kendi kurulum
   akışını kurmaz, `--scan-lynis --yes` çağırıp `reports/lynis_*.dat` çeker.
8. **Zafiyet görünürlüğü v1'de:** zafiyetli makine listesi (severity filtreli) + cihaz ve
   filo bazında skor/CVE zaman çizelgesi.

### Global kısıtlar

- **Script'e dokunulmaz** (tek istisna: makine-okur `--version` — bkz. P0).
- Uzak dizin `/opt/hardenix` (root:root, 700); raporlar `/opt/hardenix/reports/`.
- Çalıştırma kalıbı: `cd /opt/hardenix && sudo -n bash linuxharden.sh <MOD> --yes ...`
  (SSH kullanıcısı root değilse NOPASSWD sudo şart — README'ye yaz).
- Sırlar **Fernet** ile şifreli; master key `HARDENIX_MASTER_KEY` env'den. DB dump'ı tek
  başına sır içermez. Host key politikası **TOFU**.
- Timeout (sn): connect 15 · ping 30 · deploy 120 · install 900 · scan/scan-cve/fix-cve
  1800 · apply 3600 · unapply 1800. Retry: yalnız bağlantı hatasında 1 kez (60 sn sonra).
- Retention: cihaz başına son **10** rapor. Sayfalama: 50 satır. UI dili İngilizce.
- Her faz sonunda `pytest` yeşil + faz test geçidi + commit. Akış: test yaz → kızart →
  implement → yeşert.

### Dizin yapısı

```
webui/
├── docker-compose.yml        # api + worker + postgres + redis
├── Dockerfile · .env.example · requirements.txt · alembic/
├── app/
│   ├── main.py config.py db.py models.py crypto.py auth.py
│   ├── routes/  dashboard.py devices.py jobs.py users.py api.py
│   ├── templates/           # Jinja2, base.html + sayfalar
│   └── static/              # htmx.min.js (vendored), app.css
├── worker/  celery_app.py ssh.py tasks.py parsers.py
├── reports/                 # reports/<device_id>/ (volume)
└── tests/   conftest.py test_{crypto,auth,devices,parsers,jobs,ssh_integration}.py
```

### Veri modeli

```
users        (id, username UQ, password_hash, role ENUM[admin,operator,viewer],
              is_active, created_at)
credentials  (id, name UQ, kind ENUM[ssh_key,password], username,
              secret_enc BYTEA, created_at)
devices      (id, name UQ, host, port=22, credential_id FK, tags JSONB,
              os_name, os_version, status ENUM[unknown,reachable,unreachable],
              hardenix_version, hardening_state, host_key, last_seen, notes, created_at)
jobs         (id, kind ENUM[ping,deploy,install,scan,scan_cve,fix_cve,apply,unapply,
              confirm,key_rollout,lynis_audit], params JSONB, created_by FK,
              status ENUM[queued,running,done], schedule NULL, created_at)
job_targets  (id, job_id FK, device_id FK, status ENUM[queued,running,success,failed,
              skipped], exit_code, log TEXT, started_at, finished_at)
scan_results (id, device_id FK, job_target_id FK, kind ENUM[compliance,cve,lynis],
              score NUMERIC, rules_pass, rules_fail,
              cve_critical, cve_high, cve_medium, cve_low,
              lynis_warnings, lynis_suggestions, report_json JSONB, html_path, created_at)
              # score: compliance % | cve'de NULL | lynis hardening index (0-100)
audit_log    (id, user_id FK, action, detail JSONB, created_at)

Index: job_targets(job_id,status) · scan_results(device_id,created_at DESC) · devices(name)
```

### Fazlar

- [ ] **W0 — İskelet + Compose.** `webui/` iskeleti (api, worker, postgres:16, redis:7,
      healthcheck, `reports/` volume), `config.py` (pydantic-settings), `main.py` +
      `GET /healthz`, Alembic baseline, `tests/conftest.py`.
      **Geçit:** `docker compose up -d` → `/healthz` 200; pytest yeşil.
      → `feat(webui): scaffold FastAPI+Celery compose stack`
- [ ] **W1 — Auth + RBAC.** `users` + migration + startup admin seed; argon2,
      signed-cookie session, `require_role()`; login/logout + kullanıcı yönetimi;
      `audit_log` + `audit()` helper.
      **Geçit:** anonim=302, viewer→admin sayfası=403; pytest yeşil.
      → `feat(webui): auth, roles, audit log`
- [ ] **W2 — Envanter + şifreli credential.** `crypto.py` (Fernet round-trip testi);
      `credentials` + `devices`; credential CRUD (sır asla geri gösterilmez); device CRUD
      + sayfalı liste + filtre; **CSV import** (`name,host,port,credential_name,tags`,
      hatalı satır raporlanır, geçerliler işlenir).
      **Geçit:** `SELECT secret_enc` okunamaz. → `feat(webui): inventory + encrypted credentials`
- [ ] **W3 — İş altyapısı + ping.** 2 kuyruk, `acks_late`, `prefetch_multiplier=1`,
      tip bazlı `time_limit`; `jobs`/`job_targets`; `ssh.py` (TOFU connect, run,
      sftp_push/pull); `tasks.run_job_target()` tek giriş noktası; ping işi
      (`/etc/os-release` → envanter); iş sihirbazı + sayaç özetli detay (htmx 2 sn poll).
      **Geçit:** test sshd konteynerlerine toplu ping uçtan uca yeşil.
      → `feat(webui): job engine + ping`
- [ ] **W4 — Deploy + install.** Deploy: `/opt/hardenix` (700) → SFTP push
      (`linuxharden.sh` + `profiles/*.yml`) → uzakta `sha256sum` doğrulama →
      `hardenix_version` envantere. Install: `--install --yes` (timeout 900).
      **Geçit:** hash doğru; install log üretiyor, başarısızlık `failed` raporlanıyor.
      → `feat(webui): deploy + install jobs`
- [ ] **W5 — Scan + sonuç toplama.** `parsers.py` (scan JSON, CVE çıktısı, lynis `.dat`);
      scan / scan-cve / fix-cve (→ otomatik scan-cve zinciri) / lynis işleri; rapor pull +
      retention 10; **zafiyetli makine listesi** (CVE sütunları + filtre, dashboard'da en
      riskli 10); **zaman çizelgesi** (inline SVG, CDN yok); cihaz detayı (son 20 sonuç,
      HTML rapor `FileResponse`); dashboard SQL agregasyonla.
      **Geçit:** deploy→install→scan uçtan uca; iki tarama sonrası trend 2 nokta.
      → `feat(webui): scan collection + lynis + vulnerability views + trends`
- [ ] **W6 — Apply/unapply + deadman/confirm.** Apply (admin): `level`, `deadman_min`
      (varsayılan 30, kapatılamaz), sihirbazda yazılı onay ("APPLY") + audit; confirm
      akışı + **toplu confirm**; ops. `auto_confirm_min_score`; unapply (admin);
      `hardening_state` envanterde.
      **Geçit:** VM'de (konteyner değil) deadman 5 → geri aldı; ikinci apply → UI'dan
      confirm → kalıcı. → `feat(webui): apply/unapply with deadman+confirm`
- [ ] **W7 — Key rollout + cilalar.** Parolalı credential ile bağlan → yönetim public
      key'i `authorized_keys`'e (idempotent) → cihazı anahtarlı credential'a çevir →
      doğrulama ping'i; audit log ekranı; toplu etiketleme; "etikete göre seç".
      **Geçit:** rollout sonrası cihaz anahtarla erişiliyor. → `feat(webui): key rollout + audit UI`
- [ ] **W8 — Ölçek doğrulama + dokümantasyon.** 100 sshd konteyneri → 1000 hedefli iş;
      `--scale worker=4` ile ~4× iyileşme; ayar dokümantasyonu (worker/konkurens formülü,
      timeout, retention); `webui/README.md` (kurulum, .env, ilk admin, NOPASSWD sudo,
      HTTPS reverse proxy); ana README'lere "Fleet Web UI" bölümü.
      **Geçit:** yük testi hatasız; sıfırdan kurulum dokümanla tekrarlanabilir.
      → `feat(webui): scale validation + docs`

### Web UI v2 backlog

Zamanlanmış tarama (Celery Beat — `jobs.schedule` hazır) · e-posta/webhook bildirimi ·
5000+ cihaz / NAT arkası için pull-agent modu · LDAP/SSO.

**Notlar:** repo kökü worker'a **read-only** mount edilir → "script güncelle" işi =
yeniden deploy. Parola tabanlı SSH'ta paramiko `password=` kullanır, `sshpass` gerekmez.

---

## 4. Test prosedürü

Geliştirme Windows'ta, hedef Linux. Davranış doğrulaması **snapshot'a dönülebilir VM**
gerektirir.

### Statik kontrol (her commit öncesi — sert geçit)

```sh
bash -n linuxharden.sh        # syntax — zorunlu
shellcheck linuxharden.sh     # lint — kuruluysa
```

### Test ortamı

- Temiz Ubuntu 24.04 VM. **Pristine baseline: %65.2** (L2, 242 pass / 129 fail).
- Kurulum: `git clone -b <branch> ... && sudo bash linuxharden.sh --install`

### Smoke döngüsü (her faz)

```sh
sudo bash linuxharden.sh --scan                   # baseline (~%65.2)
sudo bash linuxharden.sh --dry-run                # ne değişecek (uygulamaz)
sudo bash linuxharden.sh --apply --level 1 --yes  # uygula (yedek alır)
sudo bash linuxharden.sh --scan                   # skor yükselmeli (~%93)
sudo bash linuxharden.sh --unapply --yes          # geri al
sudo bash linuxharden.sh --scan                   # baseline'a dönmeli (~%65-67)
sudo bash linuxharden.sh --scan-lynis             # hardening index üretmeli
sudo bash linuxharden.sh --scan                   # 3 katman: compliance + lynis + cve
```

Uzaktan (SSH) apply/unapply, oturum kopsa da tamamlansın diye **nohup + remote poll** ile:

```sh
sudo bash -c 'nohup bash linuxharden.sh --apply --level 1 --yes >/tmp/a.log 2>&1 &'
# sonra /tmp/a.log poll edilir; süreç bitince skor kontrol edilir
```

### Notlar

- Test sonrası kutuyu temiz bırak: kurulan servisleri purge et, hardening uygulandıysa
  `--unapply` (ya da snapshot'a dön).
- `detect_active_services()` etkileşimsiz modda (pipe/SSH) servis kurallarını **otomatik**
  hariç tutar; TTY'de kullanıcıya sorar. Her yeni prompt `--yes`'i onurlandırmalı.

---

## 5. Arşiv (tamamlanan fazlar)

### Script yol haritası — FAZ 0–6 ✅

| Faz | İş | Sonuç |
|---|---|---|
| 0 | Baseline + test prosedürü | %65.2 referans sabitlendi |
| 1 | Apache/nginx + DB servis koruması | nginx aktifken 2 kural otomatik hariç |
| 2 | Genişletilmiş backup kapsamı | clean apply→unapply 70.4% → 67.0% (kalan ~2 kural, unapply'ın kasıtlı tuttuğu aide/pwquality paketlerinden) |
| 3 | Dead-man switch (`--deadman`/`--confirm`) | deadman 1 → otomatik geri alındı; confirm → timer iptal |
| 4 | `--yes` / `--min-score` | prompt'suz çalışıyor, eşik altında non-zero |
| 5 | `--scan-cve` (OVAL/USN) | curl düşürülünce 8 USN / 27 CVE yakalandı; python3 ile bz2 decompress |
| 6 | `--fix-cve` | curl düşür → fix-cve → scan-cve 0. Döngü tam |

> **FAZ 2'nin diğer maddeleri (SSH lockout, pre-flight, backup bütünlüğü, `--keep`,
> `--from`) yapılmadı** → bölüm 2, P0.

### Lynis entegrasyonu — v1.2.0 ✅ (2026-07-07)

`--install` ailesi (varsayılan openscap + lynis; `--install-openscap` / `--install-lynis`
tekli), `--scan-lynis`, `--scan` birleşik duruş taramasına dönüştü, `--scan-compliance`
eski davranışı koruyor, `--uninstall` lynis'i de kaldırıyor. Mutasyon modları
değişmedi. Arch: `--scan` = basic check + Lynis.

**VM geçidi sonuçları:**

- **Ubuntu 24.04.4** (temiz kutu): install → scan-lynis (index 58/100) → birleşik scan
  (65.5% / 58 / 340 CVE) → `--min-score 99`: exit 2 + üç katman koştu → scan-compliance
  izole → lynis'siz scan: skip uyarısı → install-lynis → stale-report koruması exit 1 →
  dry-run → apply L1: 68.5% → **93.4%**, deadman 15 dk armed → confirm: timer iptal,
  exit 0 → unapply: **%67.0** (tarihsel değerle birebir) → uninstall temiz.
- **Rocky 9.8:** EPEL'siz install → lynis uyarı + EPEL ipucu + exit 0 ✓ → epel-release +
  install-lynis → lynis 3.1.7 ✓ → birleşik scan (47.1% / 66 / dnf errata) ✓ →
  `--confirm` (deadman yokken) exit 0 ✓.
- **Geçitte yakalanan:** Windows checkout'tan deploy'da CRLF → `.gitattributes` ile
  `*.sh`/`*.yml` `eol=lf` zorlandı (`5ae2304`).

### Hata avı — v1.2.1 ✅ (2026-08-15)

Kod incelemesinde çıkan ve **VM'de doğrulanan** kusurlar (Ubuntu 24.04.4 @ .151,
Rocky 9.8 @ .190):

| # | Kusur | Etkisi |
|---|---|---|
| 1 | `run_apply()` son satırı `[[ -n "$DEADMAN_MIN" ]] && arm_deadman ...` | **`--deadman` verilmeyen her başarılı `--apply` exit 1 dönüyordu.** `set -e` + `&&` listesi. v1.2.0 VM turu hep `--deadman` ile koştuğu için maskelenmişti. |
| 2 | `create_backup()` `tar` hatasını yalnız uyarıyordu | Eksik/bozuk arşiv apply'ı durdurmuyordu; `revert_hardening()` arşivde olmayan dosyaları **sildiği** için `--unapply` config öğütücüsüne dönüyordu. |
| 3 | `download_conf()` yalnız `<id>-<sürüm>.yml` deniyordu | Arch'ta `VERSION_ID` yok → `arch-rolling.yml` aranıyordu; **`profiles/arch.yml` hiç ulaşılamıyordu.** Tüm Arch yolu ölü koddu. |
| 4 | `usage()` her durumda `exit 0` | Yanlış yazılmış bayrak / mod verilmemesi CI'da **temiz koşu** gibi görünüyordu. |
| 5 | `--level` gibi değer alan bayrak satır sonunda | Döngüdeki `shift` sınırı aşıyor → `set -e` scripti **mesajsız** öldürüyordu. |
| 6 | İki mod aynı anda (`--scan --apply`) | Sessizce sonuncusu kazanıyordu — bir yazım hatası uzağı sertleştirebilirdi. |
| 7 | `run_scan_full()` katmanları doğrudan çağırıyordu | Bayat lynis raporu / erişilemez OVAL feed **tüm `--scan`'i** öldürüyor, `--min-score` barajı hiç çalışmıyordu. |
| 8 | `TMP_DIR=/tmp/linuxharden_$$`, `/tmp/ssg_$$` | Root olarak tahmin edilebilir `/tmp` yolu → symlink/TOCTOU yüzeyi. |
| 9 | `revert_hardening()` `xargs -I{} log_info` | xargs shell fonksiyonu çağıramaz → stderr'e hata. |
| 10 | `arch_basic_harden()` `limits.conf`'a her koşuda ekliyordu | Her apply'da bir çift satır daha. |
| 11 | `run_apply_arch()` `STATE_FILE` yazmıyordu | Arch'ta apply sonrası banner "Hardening applied: None" diyordu. |

**VM geçidi sonuçları (2026-08-15):**

- **Ubuntu 24.04.4 (.151):** `--install` ✓ → `--scan-compliance --level 1` **%70.1**
  (exit 0) → `--apply --level 1 --yes` **deadman'siz exit 0** ✓ (%70.1 → **%92.9**),
  yedek "archived and verified (30 paths)" → `--scan-compliance` %92.9 (exit 0) →
  `--unapply --yes` **exit 0**, `sysctl: 14 settings reloaded` ✓, paketler geri kuruldu
  (rsync/telnet/ftp/ubuntu-standard), ssh ayakta → kasten bozulmuş lynis ile
  `--scan --min-score 99`: "Lynis layer failed — continuing" → CVE katmanı yine koştu →
  **exit 2** (baraj çalıştı).
- **Rocky 9.8 (.190):** baseline `--scan-compliance --level 1` %58.5 ✓ →
  `--scan-cve` (native `dnf updateinfo`) 176 CVE / 92 advisory, exit 0 ✓ →
  argüman doğrulamaları (bilinmeyen bayrak=1, çakışan mod, eksik değer,
  yedeksiz `--unapply`=1) ✓.
- **Profil çözümleme (gerçek Linux'ta):** `arch → arch.yml` ✓,
  `ubuntu 24.04 → ubuntu-24.04.yml`, `rocky 9.8 → rocky-9.yml`,
  `opensuse-leap 15.6 → opensuse-leap-15.yml`, `debian 12 → debian-12.yml` — regresyon yok.
- **Geçitte yakalanan:** `unattended-upgrades` dpkg kilidini tutarken `--install`
  ham apt hatasıyla düşüyor → pre-flight maddesine eklendi (bölüm 2, P0).

### Konsol dostu çıktı — v1.3.0 ✅ (2026-08-15)

**Sorun:** makinenin kendi konsoluna oturan (SSH atamayan) biri için `--scan`
183 satır = 24 satırlık ekranda ~8 ekran; scrollback yok, geri bakılamıyor.

**Karar:** birleşik özet + terminal yüksekliğine göre kırpılmış detay.

- `--scan` sonunda tek **duruş kutusu**: compliance / Lynis / CVE başlık sayıları +
  en kötü kurallar + rapor yolu. Bu moddayken katmanların kendi kutuları bastırılır;
  tek katmanlı modlar (`--scan-compliance` / `--scan-lynis` / `--scan-cve`) kendi
  kutularını aynen korur.
- Listeler `TERM_ROWS`'a göre boyutlanır; ASCII banner 30 satırın altında tek satıra iner.
- **TTY değilse hiçbir şey kırpılmaz** — yönlendirme/boru/CI tam listeyi alır,
  yani log ve raporlar değişmez. `--full` terminalde de tam listeyi zorlar.
- Katmanlar subshell'de koştuğu için `POSTURE_STATS` dosyası üzerinden raporlar
  (global değişken subshell sınırını geçmez).

**Ölçüm (Ubuntu 24.04.4, gerçek 24 satırlık pty):**

| Senaryo | Önce | Sonra |
|---|---|---|
| `--scan`, 24 satırlık terminal | 183 satır (~8 ekran) | **29 satır**; kutu 19 satır, ekrana tam sığıyor |
| `--scan-compliance`, 24 satırlık terminal (Rocky) | 159 satır | **29 satır** |
| `--scan` > dosya (CI/log) | 183 satır | 154 satır, **103 kuralın tamamı** listeleniyor, kırpma yok |
| `--scan --full` terminalde | — | 142 satır (tam) |

`--min-score 99` barajı kutudan sonra hâlâ tetikleniyor (exit 2).

**Geçitte yakalanan:** ilk sürüm sessizce hiçbir şey yapmıyordu — `term_height`
`$( )` içinden çağrılıyordu, orada stdout boru olduğu için `-t 1` hep false
dönüyor. Tespit `detect_term_rows()` ile `main()`'e, substitution dışına alındı.
Bunu yalnız gerçek pty'de test etmek ortaya çıkardı; `bash -n` + shellcheck
ikisi de yeşildi.

### Tam özellik taraması — v1.3.1 ✅ (2026-08-15)

Scriptin **her modu ve bayrağı** iki VM'de koşturuldu (Ubuntu 24.04.4 @ .151,
Rocky 9.8 @ .190): 33 argüman/salt-okunur testi + 8 mutasyon testi + 5 kurulum
yaşam döngüsü testi, kutu başına. Çıkış kodlarının tamamı beklendiği gibi.

**Bulunan iki gerçek kusur:**

1. **`--unapply` 9 profilden 8'inde tam geri döndürmüyordu.** `revert_hardening()`
   yalnız `backup.config_dirs` kapsamındakini geri yükler; genişletilmiş liste
   sadece `ubuntu-24.04.yml`'ye uygulanmıştı. Rocky'de ölçüm: bir `--level 1`
   apply `/etc` altında **58 dosya** yazdı ve **hiçbiri** profilin yedek kümesinde
   değildi. scan → apply → unapply → scan döngüsü sonunda baseline'da `fail` olan
   **40 kural hâlâ `pass`** kaldı; %58.5 geri gelmedi, %73.5'te durdu.
   → `fix(profiles)`: 8 profile remediation'ın gerçekten dokunduğu yollar eklendi
   (12 → 42 yol). Rocky'de yeniden doğrulandı: **%75.0 → %98.1 → %75.0, takılı
   kural 0.** Kasten dışarıda bırakılanlar: `/etc/passwd|shadow|group|gshadow`
   (apply sonrası yapılan kullanıcı/parola değişikliklerini geri almak, bir
   maxdays ayarının kalmasından çok daha kötü), üretilen cache'ler
   (`ld.so.cache`, `hwdb.bin`) ve `config` dışındaki `/etc/selinux`.

2. **`--fix-cve` başarı diyor ama yama devrede değil.** *(reboot sonrası doğrulandı:
   kutu `687.39.1` ile açıldı, `--scan-cve` **93 → 0**; yani o 93 CVE tarayıcı
   hatası değil, gerçekten reboot bekleyen açıklardı. `reboot_pending_reason()`
   artık iki kutuda da boş dönüyor. `--fix-cve → reboot → --scan-cve = 0` döngüsü
   uçtan uca kapandı.)* Rocky'de 156 paket
   yamalandı, `dnf check-update --security` temiz döndü, ama kutu hâlâ eski
   çekirdekle çalışıyordu (`687.10.1` çalışıyor / `687.39.1` kurulu) → `--scan-cve`
   93 CVE göstermeye devam etti. Sayı doğruydu, mesaj eksikti.
   → `feat(fix-cve)`: `reboot_pending_reason()` eklendi; çekirdek boşluğu varsa
   "reboot edene kadar açıksın", yalnız kütüphaneler kullanımdaysa ayrı mesaj.
   Ubuntu'da `services`, Rocky'de `kernel` sebebi doğru tespit edildi.

**Doğrulanan davranışlar:** salt-okunur invaryantı (`--scan-compliance`,
`--dry-run`, `--scan-cve`, `--scan-lynis` `/etc` ve `/var/lib/linuxharden`'a
**0 değişiklik** yazdı) · `--level 1|2` gerçekten farklı profil kullanıyor
(Ubuntu 103/125 fail, Rocky 108/193) · `--format json` yalnız `.json`, `both`
ikisini üretiyor, JSON içi tutarlı (fail sayısı = listelenen kural sayısı) ·
CVE motoru aileye göre doğru (Ubuntu OVAL/USN, Rocky native `dnf updateinfo`) ·
dead-man kuruluyor, `--confirm` iptal ediyor, ikinci `--confirm` "iptal edilecek
bir şey yok" diyor, timer gerçekten siliniyor · EPEL'siz Rocky'de
`--install-lynis` sert hata + ipucu (exit 1), `--install` uyarıyla devam (exit 0) ·
`--uninstall` → kaldırılmışken tarama anlaşılır hatayla duruyor → `--install` →
skor aynı.

**Yeni backlog maddeleri (bölüm 2'ye taşınacak):**

- [x] **OVAL feed cache'ini tazeleme yolu yok.** ✅ v1.4.0 `--refresh-feed`.
      Ubuntu'da doğrulandı: bayraksız cache kullanılıyor, bayrakla yeniden
      indiriliyor (feed mtime değişti). Cache mesajı da bayrağı hatırlatıyor.
- [x] **`--conf` profil/distro uyuşmazlığını uyarmıyor.** ✅ v1.4.0. `parse_conf()`
      artık `meta.distro`/`meta.version` okuyup `DISTRO_ID` ile karşılaştırıyor;
      uyuşmuyorsa uyarıp devam ediyor (`--conf` bir override, hata değil).
      İki kutuda doğrulandı: `--conf profiles/arch.yml` uyarıyor, doğru profil 0 uyarı.
- [x] **Yedekler birikiyor (ölçüldü).** ✅ v1.4.0 `--keep N` ile çözüldü (yukarı).

### Yardım çıktısını katmanlama — v1.4.1 ✅ (2026-08-15)

**Sorun:** v1.3.0'da `--scan`'i 183 → 29 satıra indirdik ama `--help`'e hiç
dokunmamıştık. 11 mod + 12 seçenek = **44 satır** (+banner) → 24 satırlık
konsolda iki ekran. Aynı problem, düzeltilmemiş yer. Dahası hata yolu daha
kötüydü: `--bogus` yazınca önce hata basılıyor, sonra 44 satır yardım onu
ekrandan kaydırıyordu — operatörün ihtiyacı olan tek satır kayboluyordu.

**Karar:** bayrak silme yok (hepsi kullanımda ve dokümanlı), sunumu katmanla.

- `usage()` → günlük set: 5 mod, 5 seçenek, 3 örnek. **22 satır.**
- `usage_full()` → `--help all` (veya `full`): her bayrak, gruplu (modlar ·
  seçenekler · tek katman · raporlama/CI · ince ayar · seviyeler · örnekler ·
  çıkış kodları). 51 satır, opt-in.
- `usage_error()` → hata + tek satır mod listesi + `--help` işareti. **Yardım
  basmıyor**, çünkü basarsa hatanın kendisi ekrandan kayıyor.
- `banner` artık `parse_args`'tan **sonra** çağrılıyor: yardım ve hata çıktıları
  logonun altından değil ekranın tepesinden başlıyor.

**Ölçüm (Git Bash, ANSI temizlenmiş):**

| Çıktı | Satır | En geniş satır | Çıkış kodu |
|---|---|---|---|
| `--help` | **22** | 75 sütun | 0 |
| `--help all` | 51 | 79 sütun | 0 |
| argümansız | 22 (kısa yardım) | — | 1 |
| `--bogus` | 4 | — | 1 |

**README'ler:** `## Hızlı başlangıç` bloğu en üste alındı (klonla → install →
scan → dry-run → apply → unapply); `Özellikler` bölümü `Ne yapar` başlığıyla
katman tablosuna dönüştürüldü (Parametreler ile birebir tekrar ediyordu);
`Parametreler` tablosu `--help` ile aynı şekilde ikiye bölündü — **Günlük** (10
satır) açıkta, gerisi `<details>` altında üç grup halinde. Her iki dil de aynı.

**Not:** shellcheck bu iş sırasında geliştirme makinesinde kurulu değildi;
`bash -n` + `check-docs.py` + davranış ölçümleri yeşil. shellcheck bir sonraki
VM turunda koşturulmalı.

### Motor satırı + severity dökümü — v1.4.2 ✅ (2026-08-15)

**Sorun 1:** tarama başında yalnız `[✓] oscap 1.3.9 — OK` yazıyordu. Lynis kurulu
mu değil mi belli değildi; eksikse uyarı **dakikalar sonra**, compliance bitip
audit katmanına gelindiğinde çıkıyordu. `check_dependencies()` artık motor kümesini
tek satırda söylüyor: `Engines: oscap 1.3.9 · lynis 3.0.9`, yoksa `--install-lynis`
işaret eden uyarı. Lynis opsiyonel kalmaya devam ediyor — eksikliği asla hata değil.

**Sorun 2:** `128 fail` eyleme dönüşmüyor, kırpılmış listenin altındaki
`… +118 more failing rules` ise o 118'in içinde ne olduğunu hiç söylemiyor. Kutuya
**Failing** satırı eklendi: `128  ·  4 high · 98 medium · 22 low · 4 unknown`.
Yeni veri toplamaya gerek olmadı — kutuyu çizen python zaten ARF'i parse edip
severity tutuyordu; parse yukarı alındı, liste hem sayım hem listeleme için
kullanılıyor. Kuyruk `W-23` sütuna kırpılıyor, böylece dört haneli sayılar sağ
kenarı bozamıyor. Kutu 4 sabit satıra çıktığı için liste bütçesi `h-14` → `h-15`.

**Geçitte yakalanan — invaryant #1'i kırıyordum.** İlk sürüm versiyonu
`lynis show version` çalıştırarak alıyordu. Gerçek kutuda kontrollü ölçüm:
12 saniye boşta bekleyişte sıfır oynama, ama komuttan sonra
`/var/log/lynis-report.dat` **31831 → 709 byte**. Yani `lynis show version` bir
**yazma** işlemi ve `check_dependencies()` `--scan`/`--dry-run` yolunda koşuyor —
her salt-okunur tarama Lynis raporunu siliyor olacaktı. Versiyon artık
`/usr/sbin/lynis` içindeki `PROGRAM_VERSION="3.0.9"` satırından **okunuyor**,
lynis hiç çalıştırılmıyor. `bash -n` ve shellcheck ikisi de yeşildi; bunu yalnız
gerçek kutuda kontrol grubuyla ölçmek yakaladı.

**Ölçüm (Ubuntu 24.04.4, gerçek ARF):**

| Kontrol | Sonuç |
|---|---|
| `Engines` satırı, lynis kurulu | `oscap 1.3.9 · lynis 3.0.9` |
| `Engines` satırı, lynis PATH'ten gizli | uyarı + `--install-lynis` ipucu |
| lynis dosyaları tarama öncesi/sonrası | 709 / 610286 → **709 / 610286** (değişmedi) |
| kontrol grubu (12 sn boşta) | sıfır oynama |
| kutu satır genişlikleri | hepsi **70 sütun** (4 haneli sayılarla da) |
| kutu yüksekliği, `rows=9` | 20 satır — 24 satırlık konsola sığıyor |

### SSH lockout uyarısı + terminale uyan kutu — v1.5.0 ✅ (2026-08-15)

**SSH lockout uyarısı (P0 maddesi kapandı).** `warn_ssh_lockout()`, `--apply` ve
`--dry-run` yollarında prompt'tan **önce** çalışıyor. Sadece SSH oturumundaysa
konuşuyor, kural profilde hariç tutulmuşsa susuyor, `sshd -T` ile **etkin**
`PermitRootLogin` değerini okuyup zaten `no` ise susuyor. Geri dönüş yolu
kontrolü: uid ≥ 1000, `sudo`/`wheel` üyesi **ve** dolu `authorized_keys` olan
kullanıcı arıyor; yoksa "konsol tek yol" diyor. Yeni prompt eklenmedi — mevcut
`Continue?` kapı olarak kaldı, yani `--yes` invaryantı bozulmadı.

Canlı `--apply` çıktısı (Ubuntu 24.04.4):

```
[!] This session is over SSH, and the baseline disables root SSH login.
    Rule sshd_disable_root_login sets PermitRootLogin no (currently: yes).
    This login will stop working after the apply.
[✗] No account survives this: no non-root user has both sudo and an SSH key.
    The console will be the only way back into this machine.
[✓] Dead-man switch armed for 60 min — it reverts unless --confirm arrives.
```

Admin grubunu distroya göre ayırıyor: Ubuntu'da `sudo`, Rocky'de `wheel`.

**Kutu genişliği artık terminale uyuyor.** Sabit 62 gerçek veride yetmiyordu:
Rocky 9.8 baseline'ı (193 fail, üç haneli sayılar) hem başlığı hem severity
kuyruğunu kırpıyordu (`4 unkno…`). `TERM_COLS` tespiti `detect_term_rows()`'a
eklendi (yine `main()`'den bir kez — `$( )` tuzağı). `W`: TTY yoksa 70, varsa
`min(max(cols-10, 40), 110)`.

| pty | TERM_COLS | W | kutu | sığdı mı |
|---|---|---|---|---|
| 80×24 | 80 | 70 | 78 | ✓ |
| 120×40 | 120 | 110 | 118 | ✓ (canlı `--scan` ile doğrulandı) |
| 200×50 | 200 | 110 (tavan) | 118 | ✓ |
| boru / CI | 0 | 70 | 78 | ✓ |

**Çoklu sütun — önce reddedildim, maintainer ısrar etti, yapıldı.** İtirazım
ölçüye dayanıyordu: kural adları medyan 28 / p90 41 / max 48 karakter, dar
hücrede `sshd_disable_…` beş kuralla eşleşiyor. Maintainer iki kez istedi; karar
onun, uyguladım — ama sütunlar yalnız **okunabilir kaldıkları yerde** çıkacak
şekilde:

`cell = (W - 3*(n-1)) // n`, n = mevcut severity sayısı. `cell >= 20` ise
severity başına bir sütun (`HIGH (4) │ MEDIUM (94) │ LOW (22) │ UNKNOWN (3)`),
altındaysa bugünkü düz liste. Her sütun aynı satır bütçesiyle sınırlı ve kendi
`… +N more` satırını taşıyor, böylece kutu yüksekliği baskın severity'ye
(genelde medium, fail'lerin ~%75'i) bağlı kalmıyor. Genişlik tavanı (110)
kaldırıldı — sütunların yaşaması için terminalin tamamı gerekiyor.

| Terminal | W | hücre | Yerleşim |
|---|---|---|---|
| 80 | 70 | 15 | tek sütun |
| 120 | 110 | 25 | 4 sütun |
| 160 | 150 | 35 | 4 sütun, isimlerin ~%87'si kesilmiyor |
| 200 | 190 | 45 | 4 sütun, ~%98 |
| boru / CI | 70 | 15 | tek sütun, **tüm** kurallar |

Gerçek ARF ile doğrulandı: 120→118 sütun, 160→158 sütun, 80→78 sütun/20 satır,
boru→133 satır (123 kuralın tamamı). Tüm satır genişlikleri her modda tutarlı.

**Doğrulama — Ubuntu 24.04.4, tam yaşam döngüsü 8/8 rc=0:**

| Adım | Sonuç |
|---|---|
| `--apply --level 1 --deadman 60` | rc=0, 6 dk · `PermitRootLogin` yes → **no** |
| dead-man timer | kuruldu (1) → `--confirm` sonrası **0** |
| ikinci `--confirm` | "No pending dead-man switch found" |
| apply sonrası tarama | %88.2 — 337 pass / 45 fail · Lynis 68/100 |
| `--unapply` | rc=0 · `PermitRootLogin` **yes**'e geri döndü |
| unapply sonrası tarama | %67.3 — 259 pass / 126 fail |
| `--fix-cve` | 97 güvenlik güncellemesi kuruldu, rc=0 |
| `--scan-cve` (sonra) | **0 CVE** |

`PermitRootLogin` yes → no → yes zinciri hem lockout teşhisinin hem de
`--unapply`'ın tam geri döndürdüğünün doğrudan kanıtı.

### Basılan komutların hiçbiri çalışmıyordu — v1.5.0 ✅ (2026-08-15)

Maintainer yakaladı: `Retry later with: sudo linuxharden.sh --install-lynis`.
Bu komut **hiçbir zaman çalışmıyordu** — araç `$PATH`'te değil.

Kök neden: `basename "$0"` nasıl çağırırsan çağır çıplak `linuxharden.sh`
veriyor. Ölçüldü: `bash t.sh` → `t.sh`, `./t.sh` → `t.sh`, `bash /tmp/t.sh` →
`t.sh`. Yani hiçbir çağırma biçiminde çalışan bir komut üretmiyor. **11 yerde**
kullanılıyordu; biri ([:1619]) `sudo bash` diyordu, diğer 10'u demiyordu — kendi
içinde de tutarsız.

Çözüm: `SELF_CMD="bash ${SCRIPT_DIR}/linuxharden.sh"` — mutlak yol (cwd'den
bağımsız) ve `bash` üzerinden (executable bit kaybını tolere eder; depo Windows'ta
da checkout ediliyor). Tüm çalışma-zamanı ipuçları buna geçti; `usage()`
örnekleri README'nin biçimiyle uyumlu `./linuxharden.sh` oldu.

Ubuntu'da kanıt:

```
yeni:  bash /opt/hardenix/linuxharden.sh --help   → başka dizinden ÇALIŞTI (rc=0)
eski:  linuxharden.sh --help                      → command not found
```

**Aynı sınıfta taranan ve bulunan diğer üç hata:**

1. **Sabitlenmiş `apt-get`.** "oscap eski" uyarısı dokuz distronun dördünde var
   olmayan `apt-get install --reinstall` basıyordu. Artık `$PKG_MANAGER`'a göre:
   `dnf reinstall` / `zypper install --force` / `pacman -S`.
2. **Kendi yeni eklediğim `Engines:` ipucu.** RHEL ailesinde `--install-lynis`
   öneriyordu ama EPEL olmadan o komut da başarısız — kullanıcıyı çalışmayan
   komuta yönlendiriyordum. Artık dnf/yum'da önce `epel-release` diyor.
   Üç paket yöneticisiyle de doğrulandı.
3. **`X.X.XX` yer tutucusu.** SSG manuel kurulum talimatı literal `X.X.XX`
   içeriyordu, yapıştıran 404 alırdı. Üstelik gereksizdi: `--install-openscap`
   bu indirmeyi zaten kendisi yapıyor. Mesaj artık önce onu gösteriyor,
   sürümü de `SSG_FALLBACK_VER` global'inden gerçek değerle yazıyor.

**Kural olarak yazıldı** (`docs/script-internals.md`): basılan her komut
yapıştırıldığında çalışmalı; kendine referans `$SELF_CMD`, paket yöneticisi
komutları `$PKG_MANAGER` üzerinden ya da onu test etmiş bir dalın içinden.

### Bulgular (kalıcı, davranışı etkiler)

- **Mask sırası:** boş sistemi hardenleyip **sonra** nginx/apache kurarsan servis maskeli
  gelmez — SSG yalnız apply anında var olan paketi maskeler. Golden-image akışı:
  **önce hardenle, sonra kur.**
- **Debian/Fedora** SSG'de CIS profili yok → ANSSI BP-028 / OSPP kullanılıyor; orada
  `--level 2|1` = strict|light baseline, literal CIS seviyesi değil.
- **RHEL rebuild'leri** (Rocky/Alma) `--scan-cve` için OVAL kullanmıyor (over-report
  ediyor) → native `dnf updateinfo` (`scan_cve_dnf()`).
