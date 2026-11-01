# Audit Zombie Worker Pasca-Patch PHP2Shell & CVE-2026-115560

Repo referensi dan alat uji forensik untuk artikel: **"Audit Pasca-Patch PHP2Shell: Mengapa Long-Running Worker Tetap Rentan"** oleh [Nextmend](https://nextmend.dev).

## Gambaran Masalah
Setelah insiden kritis PHP2Shell (CVE-2026-109618 & CVE-2026-109619) dan kerentanan susulan pada `session.upload_progress` (CVE-2026-115560), banyak tim engineering menjalankan `apt-get upgrade` atau memperbarui image Docker mereka.

Namun, di lingkungan produksi dengan **long-running workers** (seperti PHP-FPM pool, Laravel Horizon, PM2, dan worker queue):
1. **Linux Inode Semantics:** Menimpa binary atau `.so` library di disk tidak mematikan proses aktif. Kernel Linux mempertahankan memory-mapped pages dari inode yang sudah di-unlink selama proses masih berjalan (`/proc/PID/maps` menandainya sebagai `(deleted)`).
2. **False Sense of Security:** Security scanner yang hanya mengecek `dpkg -l` melaporkan status "patched", padahal proses di RAM masih mengeksekusi instruksi dari binary yang rentan.
3. **Exploit Susulan CVE-2026-115560:** Penyerang tetap dapat mengirim request multipart dengan header upload progress untuk mengeksploitasi memory corruption pada worker zombie yang belum di-reload.

## Struktur Repositori
- `scripts/audit-zombie-maps.sh`: Script forensik untuk mendeteksi deleted shared libraries di `/proc/PID/maps` dan open file descriptor di Linux.
- `tests/test-cve-2026-115560-zombie.php`: Skrip uji dan simulasi siklus hidup worker zombie vs worker refreshed serta verifikasi proteksi `session.upload_progress`.

## Cara Menjalankan Uji Forensik
```bash
# Menjalankan simulasi integritas memori & uji celah CVE-2026-115560
php tests/test-cve-2026-115560-zombie.php

# Menjalankan pemindaian /proc/PID/maps
bash scripts/audit-zombie-maps.sh
```

## Solusi Graceful Reload (Zero Downtime)
- **PHP-FPM:** `sudo systemctl reload php8.4-fpm` (atau `kill -USR2 $MASTER_PID`)
- **Laravel Horizon:** `php artisan horizon:terminate`
- **PM2:** `pm2 reload all`
- **Docker / K8s:** Pasang immutable SHA256 digest tag dan lakukan rolling update bertahap.
