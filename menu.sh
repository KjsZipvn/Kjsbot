#!/bin/bash

# ==========================================================
# KONFIGURASI DAN CHECK LISENSI OTOMATIS
# Disesuaikan untuk Repo: KjsZipvn/Kjsbot dan ZIVPN UDP Tunnel
# ==========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
INFO="${CYAN}[*]${NC}"
WARN="${YELLOW}[!]${NC}"
OK="${GREEN}[+]${NC}"
ERROR="${RED}[X]${NC}"

# Variabel Repositori Lisensi (DISESUAIKAN KE REPO TERBARU)
REPO_OWNER="KjsZipvn"
REPO_NAME="Kjsbot"
IP_FILE_PATH="izin/ip" 
RAW_IP_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/$IP_FILE_PATH"

# Variabel Bot Service (Asumsi Instalasi ZIVPN)
BOT_SERVICE_NAME="zivpn"
BOT_SCREEN_NAME="zivpn_bot" 

# Variabel Lisensi Default
NAMA_USER="Tamu"
HARI_SISA="N/A"
LISENSI_STATUS="${RED}TIDAK DITEMUKAN / KADALUWARSA${NC}"
CURRENT_IP=$(curl -sS ipv4.icanhazip.com 2>/dev/null)
# Ambil Domain dari config.json (file konfigurasi ZIVPN)
DOMAIN_TERINSTAL=$(grep 'Domain' /root/config.json 2>/dev/null | awk -F '"' '{print $4}') 

# --- Pengecekan Lisensi ---
IP_DATA=$(curl -sS $RAW_IP_URL 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$IP_DATA" ]; then
    MATCHING_LINE=$(echo "$IP_DATA" | grep "$CURRENT_IP" | grep '^###')

    if [ -n "$MATCHING_LINE" ]; then
        CLEAN_LINE=$(echo "$MATCHING_LINE" | cut -d'#' -f4 | xargs)
        NAMA_USER=$(echo "$CLEAN_LINE" | awk '{print $1}')
        TANGGAL_KEDALUWARSA=$(echo "$CLEAN_LINE" | awk '{print $2}')

        TANGGAL_SEKARANG_SEC=$(date +%s)
        TANGGAL_KEDALUWARSA_SEC=$(date -d "$TANGGAL_KEDALUWARSA" +%s 2>/dev/null)

        if [ $? -eq 0 ]; then
            HARI_SISA=$(( (TANGGAL_KEDALUWARSA_SEC - TANGGAL_SEKARANG_SEC) / 86400 ))

            if [ "$HARI_SISA" -ge 0 ]; then
                LISENSI_STATUS="${OK}AKTIF ($HARI_SISA hari tersisa)"
            else
                LISENSI_STATUS="${RED}KADALUWARSA (${HARI_SISA} hari lalu)"
            fi
        fi
    fi
fi

# --- Cek Status Bot ---
BOT_STATUS_MSG="${WARN}TIDAK DIKENAL"
RESTART_CMD=""

# 1. Cek jika Bot berjalan sebagai Systemd Service
if command -v systemctl &> /dev/null && systemctl is-active --quiet $BOT_SERVICE_NAME; then
    BOT_STATUS_MSG="${OK}AKTIF (Systemd Service: $BOT_SERVICE_NAME)"
    RESTART_CMD="systemctl restart $BOT_SERVICE_NAME"
# 2. Cek jika Bot berjalan di Screen
elif screen -ls | grep -q $BOT_SCREEN_NAME; then
    BOT_STATUS_MSG="${OK}AKTIF (Screen: $BOT_SCREEN_NAME)"
    RESTART_CMD="screen -r $BOT_SCREEN_NAME"
fi

# ==========================================================
# TAMPILAN MENU
# ==========================================================
clear
echo -e "\n${CYAN}========================================================"
echo -e "   ✨ ZIVPN UDP TUNNEL CONTROL PANEL ✨"
echo -e "      (Powered by $REPO_OWNER/$REPO_NAME)${NC}"
echo -e "========================================================${NC}"
echo -e "🟢 ${WHITE}INFO SERVER:${NC}"
echo -e "${YELLOW}  • IP Publik  : ${WHITE}${CURRENT_IP}${NC}"
echo -e "${YELLOW}  • Domain Instl: ${WHITE}${DOMAIN_TERINSTAL:-N/A}${NC}" 
echo -e "${YELLOW}  • Hostname   : ${WHITE}$(hostname)${NC}"
echo -e "${YELLOW}  • Waktu      : ${WHITE}$(date "+%Y-%m-%d %H:%M:%S")${NC}"
echo -e "--------------------------------------------------------"
echo -e "👑 ${WHITE}STATUS LISENSI:${NC}"
echo -e "${YELLOW}  • Terdaftar Untuk: ${WHITE}${NAMA_USER}${NC}"
echo -e "${YELLOW}  • Status     : ${LISENSI_STATUS}${NC}"
echo -e "--------------------------------------------------------"
echo -e "🤖 ${WHITE}KONTROL BOT ZIVPN:${NC}"
echo -e "${YELLOW}  • Status     : ${BOT_STATUS_MSG}${NC}"
echo -e "--------------------------------------------------------"
echo -e "${WHITE}PERINTAH CEPAT:${NC}"

# Tampilkan perintah kontrol sesuai cara bot berjalan
if [ -n "$RESTART_CMD" ]; then
    # Jika bot terdeteksi berjalan sebagai service atau screen, berikan opsi kontrol
    echo -e "${CYAN}   1. $RESTART_CMD   -> Akses/Restart Service${NC}"
    echo -e "${CYAN}   2. screen -r ${BOT_SCREEN_NAME} -> Akses Konsol Screen${NC}"
else
    # Jika bot tidak terdeteksi berjalan, berikan perintah untuk menjalankan manual
    echo -e "${CYAN}   1. screen -S ${BOT_SCREEN_NAME} /root/zivpn-bot.go -> Start Bot Manual${NC}"
fi

echo -e "${CYAN}   3. nano /root/config.json -> Edit Konfigurasi Bot${NC}"
echo -e "${CYAN}   4. exit                 -> Keluar dari Terminal SSH${NC}"
echo -e "${CYAN}========================================================${NC}"