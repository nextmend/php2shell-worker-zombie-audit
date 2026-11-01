#!/usr/bin/env bash

# Audit Script: Deteksi Zombie Worker & Deleted Shared Libraries di Memory (/proc/PID/maps)
# Nextmend (https://nextmend.dev)

set -eo pipefail

echo "============================================================"
echo "  AUDIT MEMORI LINUX: DETEKSI DELETED SHARED LIBRARIES      "
echo "  Target: PHP-FPM, Laravel Horizon, PM2 & Background Worker "
echo "============================================================"
echo

OS="$(uname -s)"
echo "[i] Sistem Operasi terdeteksi: $OS"

FOUND_ZOMBIE=0

if [ "$OS" = "Linux" ]; then
    echo "[i] Memindai memory mapping di /proc/[0-9]*/maps..."
    
    # Mencari proses aktif yang masih menahan deleted inode (.so shared libraries atau binary)
    DELETED_MAPS=$(grep -s '(deleted)' /proc/[0-9]*/maps | grep -E '(php|node|pm2|horizon)' || true)

    if [ -n "$DELETED_MAPS" ]; then
        echo "🚨 PERINGATAN: Ditemukan proses worker yang menahan library/binary terhapus (deleted) di RAM!"
        echo
        echo "$DELETED_MAPS" | awk '{
            split($1, a, "/");
            pid = a[3];
            lib = $NF;
            print "   PID: " pid " | Memory Inode Terhapus: " lib
        }' | sort -u | head -n 15
        echo
        FOUND_ZOMBIE=1
    else
        echo "✅ Tidak ditemukan deleted shared libraries pada proses php/node/horizon."
    fi

    # Cross-check menggunakan lsof jika tersedia
    if command -v lsof >/dev/null 2>&1; then
        echo "[i] Memeriksa open file descriptors via 'lsof +L1'..."
        LSOF_CHECK=$(lsof -nP +L1 2>/dev/null | grep -E '(php|node)' || true)
        if [ -n "$LSOF_CHECK" ]; then
            echo "🚨 lsof mendeteksi file unlinked yang masih terbuka:"
            echo "$LSOF_CHECK" | awk '{print "   " $1 " (PID " $2 ") | Open deleted file: " $9}' | head -n 10
            FOUND_ZOMBIE=1
        fi
    fi
else
    echo "[i] Lingkungan non-Linux (macOS / Darwin)."
    echo "    Pemeriksaan /proc/PID/maps spesifik untuk kernel Linux."
    echo "    Menampilkan daftar proses worker lokal yang aktif:"
    ps aux | grep -E '(php-fpm|horizon|pm2|node)' | grep -v grep | awk '{print "   PID: " $2 " | " $11 " " $12}' || true
fi

echo
echo "------------------------------------------------------------"
if [ "$FOUND_ZOMBIE" -eq 1 ]; then
    echo "❌ KESIMPULAN: Zombie Worker terdeteksi di RAM!"
    echo "   File disk baru SUDAH TERPASANG, tetapi kernel masih memuat kode lama di memori."
    echo
    echo "   Rekomendasi Graceful Reload (Zero Downtime):"
    echo "   1. PHP-FPM Master Pool : sudo systemctl reload php8.4-fpm  (atau kill -USR2 \$MASTER_PID)"
    echo "   2. Laravel Horizon     : php artisan horizon:terminate"
    echo "   3. PM2 Cluster Engine  : pm2 reload all"
    echo "   4. Docker / Kubernetes : Recreate container dengan immutable image digest (sha256)"
    exit 1
else
    echo "✅ KESIMPULAN: Seluruh proses worker sinkron dengan binary di disk."
    exit 0
fi
