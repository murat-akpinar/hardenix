# hardenix — Test Prosedürü (FAZ 0)

Her fazdan sonra çalıştırılan tekrarlanabilir doğrulama. Amaç: değişikliklerin
mevcut davranışı bozmadığını ve yeni özelliğin çalıştığını hızlıca görmek.

## Test ortamı

- Temiz Ubuntu 24.04 VM (snapshot'tan dönülebilir).
- **Pristine baseline (referans): %65.2** (L2, 242 pass / 129 fail).
- Kurulum: `git clone -b <branch> ... && sudo bash linuxharden.sh --install`

## Statik kontrol (her commit öncesi)

```sh
bash -n linuxharden.sh        # syntax
shellcheck linuxharden.sh     # varsa
```

## Smoke test (çekirdek döngü — her faz)

```sh
sudo bash linuxharden.sh --scan                 # baseline skoru (~%65.2)
sudo bash linuxharden.sh --dry-run              # ne değişecek (uygulamaz)
sudo bash linuxharden.sh --apply --level 1 --yes  # uygula (yedek alır)   [*]
sudo bash linuxharden.sh --scan                 # skor yükselmeli (~%93)
sudo bash linuxharden.sh --unapply --yes        # geri al                 [*]
sudo bash linuxharden.sh --scan                 # baseline'a dönmeli (~%65)
```

`[*]` `--yes` FAZ 4'te gelecek; o zamana dek onay `printf 'y\n' | ...` ile verilir.

Uzaktan (SSH) apply/unapply, oturum kopsa da tamamlansın diye **nohup + remote poll**
ile çalıştırılır (sshd restart oturumu düşürebilir):

```sh
sudo bash -c 'printf "y\n" | nohup bash linuxharden.sh --apply --level 1 >/tmp/a.log 2>&1 &'
# sonra /tmp/a.log poll edilir; süreç bitince skor kontrol edilir
```

## Faz kabul kriterleri (her faz "Test geçidi")

- **FAZ 0** — smoke test çalışıyor; baseline %65.2 doğrulandı. ✅
- **FAZ 1** — servis koruması:
  - nginx kur+başlat → `--dry-run` → "nginx tespit edildi", 2 kural hariç (toplam 7). ✅
  - nginx durdur → `--dry-run` → tespit yok, 5 exclusion, nginx kuralları tekrar failing. ✅
  - (Apache için aynı: `apache2`/`httpd` aktifse `package_httpd_removed` +
    `service_httpd_disabled` hariç tutulur.)
- FAZ 2+ — ilgili fazın kendi geçidi (plan.md'de tanımlı).

## Notlar

- Test sonrası kutuyu temiz bırak: kurulan servisleri `apt-get purge` ile kaldır,
  hardening uygulandıysa `--unapply` ile geri al (ya da snapshot'a dön).
- `detect_active_services` etkileşimsiz modda (pipe/SSH) servis kurallarını **otomatik**
  hariç tutar; TTY'de kullanıcıya sorar.
