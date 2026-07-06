# hardenix Fleet — Web UI + Envanter + Toplu Yönetim Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Hedef:** Cihaz envanteri tutan, SSH ile `linuxharden.sh`'i `/opt/hardenix`'e dağıtan ve
toplu `--install` / `--scan` / `--scan-cve` / `--fix-cve` / `--apply` / `--unapply`
çalıştırıp sonuçları merkezde toplayan çok kullanıcılı bir web UI.

**Mimari:** FastAPI (UI + API) + Celery worker (SSH işleri) + PostgreSQL (envanter/işler/
sonuçlar) + Redis (kuyruk). Docker Compose ile tek komut kurulum. Script'e **dokunulmaz** —
mevcut `--yes`, `--format json`, `--deadman/--confirm` yetenekleri olduğu gibi kullanılır.

**Stack:** Python 3.11+, FastAPI, SQLAlchemy 2 + Alembic, Celery 5, paramiko,
cryptography (Fernet), Jinja2 + htmx (vendored — CDN yok), passlib[argon2],
pytest + httpx. İmajlar: `postgres:16`, `redis:7`.

**Ölçek hedefi:** Bugün 10-20 cihaz, hedef 1000. Mimari değişmeden worker sayısı
artırılarak büyür (`docker compose up --scale worker=4`).

---

## Onaylanmış Tasarım Kararları

1. **B mimarisi** (Celery+Redis+Postgres) — 1000 cihaz hedefi için seçildi.
2. **Karışık SSH auth** desteklenir (anahtar VEYA parola, cihaz başına credential
   referansı) + filoyu tek yönetim anahtarına yakınsatan **key-rollout** iş tipi.
3. **Çok kullanıcılı** RBAC: `viewer` (görüntüleme) / `operator` (ping, deploy,
   install, scan, scan-cve) / `admin` (apply, unapply, fix-cve, key-rollout,
   kullanıcı+credential yönetimi).
4. **Ölçekleme disiplinleri baştan:** raporlar diske (DB'ye değil) + retention;
   iki Celery kuyruğu (`interactive` + `bulk`); tüm listeler sunucu tarafı sayfalı;
   dashboard SQL agregasyonla; canlı iş takibi sayaç özetiyle; **toplu confirm**.
5. **Apply güvenliği:** UI'dan `--apply` her zaman `--deadman <N>` ile gider
   (varsayılan 30 dk); UI'da tekil + toplu "Confirm" akışı `--confirm` gönderir.
6. `jobs.schedule` alanı şemada rezerve (v2'de Celery Beat ile zamanlanmış tarama).
7. **Lynis entegrasyonu:** OpenSCAP'e ek ikinci görüş — `lynis audit system` uzaktan
   çalıştırılır, hardening index (0-100) + warning/suggestion sayıları envantere işlenir.
   Script'e dokunulmaz; Lynis tamamen web UI iş tipi olarak eklenir.
8. **Zafiyet görünürlüğü v1'de:** zafiyetli makine listesi (CVE severity filtreli) +
   cihaz ve filo bazında skor/CVE **zaman çizelgesi** (trend) — v2'ye ertelenmez.

## Global Kısıtlar

- Uzak dizin: `/opt/hardenix` (root:root, `chmod 700`); raporlar `/opt/hardenix/reports/`.
- Uzak çalıştırma kalıbı: `cd /opt/hardenix && sudo -n bash linuxharden.sh <MOD> --yes ...`
  (SSH kullanıcısı root ise `sudo -n` atlanır; değilse NOPASSWD sudo şart — README'ye yaz).
- Credential sırları **Fernet** ile şifrelenir; master key `HARDENIX_MASTER_KEY` env'den
  (`.env` — compose secret). DB dump'ı tek başına sır içermez.
- Host key politikası: TOFU — ilk bağlantıda `devices.host_key`e kaydet, sonra doğrula.
- Zaman aşımı (saniye): connect 15 · ping 30 · deploy 120 · install 900 · scan 1800 ·
  scan-cve 1800 · fix-cve 1800 · apply 3600 · unapply 1800. Retry: yalnızca bağlantı
  hatasında 1 kez (60 sn sonra).
- Rapor retention: cihaz başına son **10** rapor dosyası; yenisi yazılınca eskiler silinir.
- Sayfalama: varsayılan 50 satır, `?page=N`.
- UI dili: İngilizce (script ile tutarlı); kod/commit İngilizce.
- Her faz sonunda: `pytest` yeşil + faz test geçidi + commit.

## Dizin Yapısı

```
webui/
├── docker-compose.yml        # api + worker + postgres + redis
├── Dockerfile                # api ve worker aynı imaj
├── .env.example              # HARDENIX_MASTER_KEY, DB/Redis URL, SESSION_SECRET
├── requirements.txt
├── alembic/                  # migration'lar
├── app/
│   ├── main.py               # app factory, router mount, startup admin seed
│   ├── config.py             # pydantic-settings
│   ├── db.py                 # engine + session dependency
│   ├── models.py             # 7 tablo (aşağıda)
│   ├── crypto.py             # encrypt_secret()/decrypt_secret() (Fernet)
│   ├── auth.py               # login/session + require_role() dependency
│   ├── routes/
│   │   ├── dashboard.py      # filo özeti (SQL agregasyon)
│   │   ├── devices.py        # envanter CRUD + CSV import + cihaz detayı
│   │   ├── jobs.py           # iş sihirbazı + iş listesi/detayı + confirm
│   │   ├── users.py          # kullanıcı + credential yönetimi (admin)
│   │   └── api.py            # htmx polling JSON uçları (iş sayaçları)
│   ├── templates/            # Jinja2; base.html + sayfa şablonları
│   └── static/               # htmx.min.js (vendored), app.css
├── worker/
│   ├── celery_app.py         # broker, 2 kuyruk, acks_late, time-limit'ler
│   ├── ssh.py                # connect() TOFU, run(), sftp_push(), sftp_pull()
│   ├── tasks.py              # run_job_target(job_target_id) — tüm iş tipleri
│   └── parsers.py            # parse_scan_json(), parse_cve_output(), parse_lynis_report()
├── reports/                  # merkeze çekilen raporlar (volume): reports/<device_id>/
└── tests/
    ├── conftest.py           # test DB (sqlite yok — postgres testcontainer/compose)
    ├── test_crypto.py  test_auth.py  test_devices.py  test_parsers.py
    ├── test_jobs.py    test_ssh_integration.py
    └── fixtures/             # örnek scan_*.json, cve çıktısı, sshd test imajı
```

## Veri Modeli

```
users        (id, username UQ, password_hash, role ENUM[admin,operator,viewer],
              is_active, created_at)
credentials  (id, name UQ, kind ENUM[ssh_key,password], username,
              secret_enc BYTEA, created_at)          # secret = private key VEYA parola
devices      (id, name UQ, host, port=22, credential_id FK, tags JSONB,
              os_name, os_version, status ENUM[unknown,reachable,unreachable],
              hardenix_version, hardening_state, host_key, last_seen, notes, created_at)
jobs         (id, kind ENUM[ping,deploy,install,scan,scan_cve,fix_cve,apply,
              unapply,confirm,key_rollout,lynis_audit], params JSONB, created_by FK,
              status ENUM[queued,running,done], schedule NULL, created_at)
job_targets  (id, job_id FK, device_id FK, status ENUM[queued,running,success,
              failed,skipped], exit_code, log TEXT, started_at, finished_at)
scan_results (id, device_id FK, job_target_id FK, kind ENUM[compliance,cve,lynis],
              score NUMERIC, rules_pass, rules_fail,
              cve_critical, cve_high, cve_medium, cve_low,
              lynis_warnings, lynis_suggestions,
              report_json JSONB, html_path, created_at)
              # score: compliance %  |  cve'de NULL  |  lynis hardening index (0-100)
audit_log    (id, user_id FK, action, detail JSONB, created_at)

Index: job_targets(job_id,status) · scan_results(device_id,created_at DESC) · devices(name)
```

---

# FAZLAR

Her faz kendi başına çalışan, test edilmiş yazılım bırakır. Akış: test yaz → kızart →
implement → yeşert → commit.

## FAZ W0 — İskelet + Compose  `[temel]`

- [ ] `webui/` iskeleti: `Dockerfile`, `docker-compose.yml` (api, worker, postgres:16,
      redis:7; healthcheck'ler; `reports/` volume), `.env.example`, `requirements.txt`
- [ ] `app/config.py` (pydantic-settings: `DATABASE_URL`, `REDIS_URL`,
      `HARDENIX_MASTER_KEY`, `SESSION_SECRET`, `REPORTS_DIR`)
- [ ] `app/main.py`: app factory + `GET /healthz` (DB ping + Redis ping → 200)
- [ ] Alembic init + boş baseline migration
- [ ] `tests/conftest.py`: compose'daki postgres'e karşı test session'ı

**Test geçidi:** `docker compose up -d` → `curl localhost:8000/healthz` = 200;
`pytest tests/` yeşil. → commit `feat(webui): scaffold FastAPI+Celery compose stack`

## FAZ W1 — Auth + RBAC  `[güvenlik temeli]`

- [ ] `models.py`: `users` + migration; startup'ta env'den ilk admin seed
      (`ADMIN_USERNAME`/`ADMIN_PASSWORD`, yalnız tablo boşsa)
- [ ] `auth.py`: argon2 hash, signed-cookie session, `require_role(min_role)`
      dependency (viewer < operator < admin)
- [ ] Login/logout sayfaları; `users.py` route: kullanıcı listesi/ekle/pasifleştir (admin)
- [ ] `audit_log` tablosu + `audit(user, action, detail)` yardımcı fonksiyonu
- [ ] Testler: parola hash, rol sıralaması, korumalı uca anonim=302 / viewer=403

**Test geçidi:** pytest yeşil; tarayıcıda login → dashboard iskeleti; viewer, admin
sayfasına giremiyor. → commit `feat(webui): auth, roles, audit log`

## FAZ W2 — Envanter + Şifreli Credential  `[çekirdek veri]`

- [ ] `crypto.py`: `encrypt_secret(str)->bytes` / `decrypt_secret(bytes)->str` (Fernet,
      key env'den). Test: round-trip + yanlış key → hata
- [ ] `models.py`: `credentials`, `devices` + migration
- [ ] Credential CRUD (admin): ad + tür (anahtar/parola) + kullanıcı + sır (yazınca
      şifrelenir, **asla geri gösterilmez**, yalnız değiştirilebilir)
- [ ] Device CRUD (operator+): sayfalı liste (50/sayfa, ad/etiket/durum filtresi),
      ekle/düzenle/sil
- [ ] **CSV import:** `name,host,port,credential_name,tags` başlıklı dosya → toplu ekle;
      hatalı satırlar rapor edilir, geçerli satırlar işlenir
- [ ] Testler: CRUD, sayfalama, CSV (geçerli+bozuk satır karışık)

**Test geçidi:** pytest yeşil; UI'dan 3 cihaz + 1 CSV import; sırlar DB'de şifreli
(`SELECT secret_enc` okunamaz). → commit `feat(webui): inventory + encrypted credentials`

## FAZ W3 — İş Altyapısı + İlk İş: Ping  `[SSH çekirdeği]`

- [ ] `worker/celery_app.py`: 2 kuyruk (`interactive`, `bulk`), `acks_late=True`,
      `prefetch_multiplier=1`, iş tipine göre `time_limit`
- [ ] `models.py`: `jobs`, `job_targets` + migration
- [ ] `worker/ssh.py`:
      - `connect(device, credential)` → paramiko client; TOFU: `host_key` boşsa kaydet,
        doluysa doğrula (uyuşmazlık → `failed` + log)
      - `run(client, cmd, timeout)` → `(exit_code, output)`
      - `sftp_push(client, local, remote, mode)` / `sftp_pull(client, remote, local)`
- [ ] `worker/tasks.py`: `run_job_target(job_target_id)` — tek giriş noktası; job.kind'e
      göre dispatch; durum/log/exit_code'u `job_targets`'a yazar; bağlantı hatasında
      1 retry (60 sn); cihaz `status`/`last_seen` güncellenir
- [ ] **Ping işi:** bağlan + `cat /etc/os-release` → `os_name`/`os_version` envantere
- [ ] İş oluşturma: cihaz seç (filtre/etiket/tümü) → tip seç → kuyruğa at. Tek cihaz →
      `interactive`, çoklu → `bulk`
- [ ] İş listesi + detay sayfası: **sayaç özeti** (success/failed/queued/running,
      htmx 2 sn polling `api.py` ucundan) + sayfalı hedef listesi + cihaz log'u
- [ ] Testler: dispatch tablosu, TOFU (ilk kayıt + uyuşmazlık), retry yalnız bağlantı
      hatasında; entegrasyon: compose'a test sshd konteyneri (`tests/fixtures/sshd/`) →
      gerçek ping işi uçtan uca

**Test geçidi:** pytest (entegrasyon dahil) yeşil; UI'dan 2 test konteynerine toplu ping →
ikisi de `success`, os bilgisi envanterde. → commit `feat(webui): job engine + ping`

## FAZ W4 — Deploy + Install  `[dağıtım]`

- [ ] **Deploy işi:** `mkdir -p /opt/hardenix` (700) → `linuxharden.sh` + `profiles/*.yml`
      SFTP push → uzakta `sha256sum` ile doğrula → `hardenix_version` envantere
      (script içindeki `VERSION` değişkeninden). Kaynak: repo kökü (compose volume:
      `../:/hardenix-src:ro`)
- [ ] **Install işi:** `sudo -n bash linuxharden.sh --install --yes` (timeout 900);
      çıktı log'a
- [ ] Cihaz detayına "hardenix durumu" bölümü: sürüm + son iş sonuçları
- [ ] Testler: push+sha256 (entegrasyon), install exit-code yorumu

**Test geçidi:** test konteynerine UI'dan deploy → `/opt/hardenix/linuxharden.sh` var,
hash doğru; install işi log üretiyor (konteynerde oscap kurulumu başarısızsa `failed`
olarak düzgün raporlanıyor). → commit `feat(webui): deploy + install jobs`

## FAZ W5 — Scan + Sonuç Toplama  `[değerin kalbi]`

- [ ] `worker/parsers.py`:
      - `parse_scan_json(path) -> ScanSummary(score, rules_pass, rules_fail, ...)`
        (test fixture: gerçek `scan_*.json` örneği)
      - `parse_cve_output(text) -> CveSummary(critical, high, medium, low)`
        (`--scan-cve` özet çıktısından)
      - `parse_lynis_report(path) -> LynisSummary(hardening_index, warnings, suggestions)`
        (`/var/log/lynis-report.dat` key=value formatı; fixture ile test)
- [ ] **Scan işi:** `--scan --format both --yes` → en yeni `scan_*.json` + `.html`
      SFTP pull → `reports/<device_id>/` → parse → `scan_results` satırı
- [ ] **Scan-CVE işi:** `--scan-cve --yes` → çıktı parse + varsa HTML pull → `scan_results`
- [ ] **Fix-CVE işi (admin):** `--fix-cve --yes` → ardından otomatik scan-cve zincirlenir
- [ ] **Lynis işi:** lynis kurulu değilse paket yöneticisiyle kur → `lynis audit system
      --quiet` → `/var/log/lynis-report.dat` SFTP pull → parse → `scan_results`
      (kind=lynis, score=hardening_index). OpenSCAP'ten bağımsız ikinci görüş
- [ ] Retention: yeni rapor yazılınca cihazın 10'dan eski rapor dosyaları silinir
- [ ] **Zafiyetli makine listesi:** cihaz listesine CVE sütunları (crit/high, son
      taramadan) + "sadece zafiyetli" filtresi; dashboard'da en riskli 10 cihaz
      (critical+high sıralı, cihaz detayına link)
- [ ] **Zaman çizelgesi:** cihaz detayında skor (compliance + lynis) ve CVE trend
      grafiği; dashboard'da filo trendi (tarih bazında ortalama skor + toplam CVE).
      Inline SVG ile — harici grafik kütüphanesi/CDN yok. Veri: `scan_results` geçmişi
- [ ] Cihaz detayı: skor geçmişi tablosu (son 20 `scan_results`), HTML rapor
      görüntüleme (`FileResponse`), CVE sayıları
- [ ] Dashboard (SQL agregasyon): cihaz sayısı (durum bazında), ortalama/min compliance
      skoru, toplam CVE (severity bazında), son 10 iş
- [ ] Testler: üç parser (fixture'larla), retention, dashboard + zafiyet listesi +
      trend sorguları

**Test geçidi:** pytest yeşil; test konteynerinde uçtan uca deploy→install→scan →
skor dashboard'da ve cihaz detayında; HTML rapor açılıyor; lynis işi hardening index
üretiyor; iki tarama sonrası trend grafiği iki nokta gösteriyor.
→ commit `feat(webui): scan collection + lynis + vulnerability views + trends`

## FAZ W6 — Apply/Unapply + Deadman/Confirm  `[riskli işlemler]`

- [ ] **Apply işi (admin):** parametreler `level (1|2)`, `deadman_min` (varsayılan 30,
      kapatılamaz) → `--apply --level N --deadman M --yes`; iş sihirbazında yazılı onay
      ("APPLY" yazdır) + audit log
- [ ] **Confirm akışı:** apply'ı `success` bitiren cihazlarda "Confirm" düğmesi →
      `--confirm` işi (interactive kuyruk). **Toplu confirm:** iş detayında
      "Confirm all successful" → başarılı hedeflere tek tıkla confirm işi
- [ ] (Ops.) Otomatik onay kuralı: `auto_confirm_min_score` parametresi — apply sonrası
      `--scan` skoru eşiği geçerse otomatik `--confirm` zincirlenir
- [ ] **Unapply işi (admin):** `--unapply --yes`; yazılı onay + audit
- [ ] `hardening_state` envanterde güncellenir (applied/confirmed/reverted)
- [ ] Testler: deadman parametresi her apply komutunda mevcut (komut üretimini test et),
      rol kontrolü (operator apply başlatamaz), toplu confirm hedef seçimi

**Test geçidi:** test VM'inde (konteyner değil — systemd gerekir) apply --deadman 5 →
confirm etmeden bekle → cihaz kendini geri aldı; ikinci apply → UI'dan confirm →
hardening kalıcı. → commit `feat(webui): apply/unapply with deadman+confirm`

## FAZ W7 — Key Rollout + Cilalar  `[filo hijyeni]`

- [ ] **Key-rollout işi (admin):** hedef credential (parolalı) ile bağlan → yönetim
      public key'ini `authorized_keys`'e ekle (idempotent) → cihazın `credential_id`'sini
      anahtarlı credential'a çevir → doğrulama ping'i
- [ ] Audit log ekranı (admin): sayfalı, kullanıcı/aksiyon filtreli
- [ ] Envanterde toplu etiketleme; iş sihirbazında "etikete göre seç"
- [ ] Testler: rollout idempotency (iki kez çalıştır → tek satır), credential geçişi

**Test geçidi:** parolalı test konteyneri → rollout → cihaz artık anahtarla erişiliyor,
ping yeşil. → commit `feat(webui): key rollout + audit UI`

## FAZ W8 — Ölçek Doğrulama + Dokümantasyon  `[1000 hedefi]`

- [ ] Yük testi: compose ile 100 sshd konteyneri (script: `tests/loadtest/spawn.sh`) →
      1000 hedefli sahte iş (100 konteynere 10'ar) → toplu ping+deploy+scan;
      ölçüm: kuyruk gecikmesi, DB kilitlenmesi yok, UI sayaçları akıcı
- [ ] `--scale worker=4` ile aynı test; süre ~4× iyileşme doğrula
- [ ] Ayar dokümantasyonu: worker sayısı/konkurens formülü, timeout'lar, retention
- [ ] `webui/README.md`: kurulum, .env, ilk admin, NOPASSWD sudo gereksinimi,
      HTTPS için reverse proxy (caddy/nginx) notu
- [ ] Ana `README.md` + `README_TR.md`'ye "Fleet Web UI" bölümü

**Test geçidi:** 100 konteyner yük testi hatasız; dokümanla sıfırdan kurulum
tekrarlanabilir. → commit `feat(webui): scale validation + docs`

---

## v2 Backlog (bilinçli erteleme)

- Zamanlanmış tarama (Celery Beat — `jobs.schedule` alanı hazır; trend v1'de var,
  otomatik besleme v2'de)
- E-posta/webhook bildirimi (kritik CVE, düşen skor)
- 5000+ cihaz / NAT arkası için pull-agent modu (DB+UI katmanı aynen kalır)
- LDAP/SSO entegrasyonu

## Notlar

- Script değişikliği gerekirse tek aday: `--version` çıktısı makine-okur formatta değilse
  eklemek (deploy sürüm tespiti için) — önce mevcut `VERSION` değişkenini grep'le
  okumayı dene, yetmezse küçük PR.
- `docker-compose.yml`'de repo kökü worker'a **read-only** mount edilir; deploy her zaman
  repo'daki güncel script'i basar → "script güncelle" işi = yeniden deploy.
- Parola tabanlı SSH'ta paramiko `password=` kullanır; `sshpass` gerekmez.
