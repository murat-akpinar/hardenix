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

- [ ] **Backup rotasyonu — `--keep N` (varsayılan 5).** `create_backup()` her apply'da
      `/var/lib/linuxharden/<ts>/` altına yeni `configs.tar.gz` yazıyor, hiçbiri
      silinmiyor. `/etc` tarball'ı × sınırsız apply = disk dolar.
- [ ] **Backup bütünlük doğrulaması.** Apply *öncesi* `tar tzf` ile arşivi test et;
      bozuksa dur. Şu an bozuk yedek ancak `--unapply` anında — yani geri dönüşün
      gerektiği anda — fark ediliyor.
- [ ] **`--unapply --from <timestamp>`.** Bugün yalnız `latest` symlink'i okunuyor
      (`latest_backup_dir()`); iki apply üst üste gelmişse ilkine dönmenin tek yolu
      elle symlink oynatmak.
- [ ] **SSH lockout uyarısı.** `SSH_CONNECTION` script'te hiç geçmiyor. Uzak oturumdan
      `--apply` çalıştıran biri sshd Ciphers/MACs/Kex/PermitRootLogin kurallarında ek
      uyarı almıyor. Dead-man switch bunu kurtarıyor ama **yalnız `--deadman`
      verildiyse**; uyarı ucuz sigorta.
- [ ] **Pre-flight kontrolleri:** disk alanı (backup için), `/etc` yazılabilir mi, ağ
      var mı (unapply'ın paket reinstall'ı için). Şu an hepsi iş ortasında patlıyor —
      yarım uygulanmış hardening en kötü durum.

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
- [ ] **Çıkış kodu sözleşmesi** (0 başarı / 1 hata / 2 eşik altı …) + README'de tablo.
      `--min-score` ve CVE gate'lerinin kodları dokümante değil; CI'dan kullanmak tahmine
      dayalı.
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
- [ ] **Bilinen kozmetik hata:** `revert_hardening()`'de `xargs -I{} log_info` shell
      fonksiyonunu çağıramıyor → "sysctl reloaded" yerine stderr'e xargs hatası düşüyor.
      İşlev etkilenmiyor.

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

### Bulgular (kalıcı, davranışı etkiler)

- **Mask sırası:** boş sistemi hardenleyip **sonra** nginx/apache kurarsan servis maskeli
  gelmez — SSG yalnız apply anında var olan paketi maskeler. Golden-image akışı:
  **önce hardenle, sonra kur.**
- **Debian/Fedora** SSG'de CIS profili yok → ANSSI BP-028 / OSPP kullanılıyor; orada
  `--level 2|1` = strict|light baseline, literal CIS seviyesi değil.
- **RHEL rebuild'leri** (Rocky/Alma) `--scan-cve` için OVAL kullanmıyor (over-report
  ediyor) → native `dnf updateinfo` (`scan_cve_dnf()`).
