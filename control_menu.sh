#!/bin/bash

# ==========================================================
# FILE: control_menu.sh
# Dijalankan otomatis saat login SSH (melalui .bashrc)
# Fungsi: Menampilkan Status Lisensi, Server, dan Menu Kontrol
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

# --- Variabel Repositori Lisensi ---
REPO_OWNER="KjsZipvn"
REPO_NAME="Kjsbot"
IP_FILE_PATH="izin/ip" 
RAW_IP_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/$IP_FILE_PATH"

# --- Variabel Instalasi Bot ---
BOT_SERVICE_NAME="zivpn"
REPO_DIR="/root/$REPO_NAME" 
MENU_SH="$REPO_DIR/menu.sh" 
# Ambil Domain dari lokasi konfigurasi ZIVPN (lebih aman dari file domain)
DOMAIN_TERINSTAL=$(cat /etc/zivpn/domain 2>/dev/null) 

# --- Variabel Lisensi Default & IP ---
NAMA_USER="Tamu"
HARI_SISA="N/A"
LISENSI_STATUS="${RED}TIDAK DITEMUKAN / KADALUWARSA${NC}"
CURRENT_IP=$(curl -sS ipv4.icanhazip.com 2>/dev/null)

# --- Pengecekan Lisensi ---
IP_DATA=$(curl -sS $RAW_IP_URL 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$IP_DATA" ]; then
    # Cari baris yang mengandung IP saat ini dan dimulai dengan '###'
    MATCHING_LINE=$(echo "$IP_DATA" | grep "$CURRENT_IP" | grep '^###')

    if [ -n "$MATCHING_LINE" ]; then
        # Ambil bagian setelah '###', lalu pisahkan nama dan tanggal
        CLEAN_LINE=$(echo "$MATCHING_LINE" | cut -d'#' -f4 | xargs)
        NAMA_USER=$(echo "$CLEAN_LINE" | awk '{print $1}')
        TANGGAL_KEDALUWARSA=$(echo "$CLEAN_LINE" | awk '{print $2}')

        TANGGAL_SEKARANG_SEC=$(date +%s)
        # Gunakan 'date' untuk mengkonversi tanggal kedaluwarsa ke detik
        TANGGAL_KEDALUWARSA_SEC=$(date -d "$TANGGAL_KEDALUWARSA" +%s 2>/dev/null)

        if [ $? -eq 0 ]; then
            HARI_SISA=$(( (TANGGAL_KEDALUWARSA_SEC - TANGGAL_SEKARANG_SEC) / 86400 ))

            if [ "$HARI_SISA" -ge 0 ]; then
                LISENSI_STATUS="${OK}AKTIF ($HARI_SISA hari tersisa)"
            else
                LISENSI_STATUS="${RED}KADALUWARSA ($(echo $HARI_SISA | tr -d '-') hari lalu)"
            fi
        fi
    fi
fi

# --- Cek Status Bot ---
BOT_STATUS_MSG="${WARN}TIDAK AKTIF"
RESTART_CMD=""

# Cek Systemd Service (zivpn, zivpn-api, zivpn-bot)
STATUS_ZIVPN=$(systemctl is-active --quiet zivpn.service && echo "AKTIF" || echo "MATI")
STATUS_API=$(systemctl is-active --quiet zivpn-api.service && echo "AKTIF" || echo "MATI")
STATUS_BOT=$(systemctl is-active --quiet zivpn-bot.service 2>/dev/null && echo "AKTIF" || echo "MATI (Dilewati)")

# Menentukan pesan status keseluruhan
if [[ "$STATUS_ZIVPN" == "AKTIF" ]] && [[ "$STATUS_API" == "AKTIF" ]]; then
    BOT_STATUS_MSG="${OK}CORE & API AKTIF"
    RESTART_CMD="systemctl restart zivpn zivpn-api zivpn-bot"
else
    BOT_STATUS_MSG="${RED}CORE/API MATI"
    RESTART_CMD="systemctl start zivpn zivpn-api zivpn-bot"
fi

# ==========================================================
# TAMPILAN MENU
# ==========================================================
clear
echo -e "\n${CYAN}========================================================"
echo -e "   ✨ ZIVPN UDP TUNNEL CONTROL PANEL (Kjsbot) ✨"
echo -e "========================================================${NC}"
echo -e "🟢 ${WHITE}INFO SERVER:${NC}"
echo -e "${YELLOW}  • IP Publik  : ${WHITE}${CURRENT_IP}${NC}"
echo -e "${YELLOW}  • Domain Instl: ${WHITE}${DOMAIN_TERINSTAL:-N/A}${NC}" 
echo -e "${YELLOW}  • Waktu      : ${WHITE}$(date "+%Y-%m-%d %H:%M:%S")${NC}"
echo -e "--------------------------------------------------------"
echo -e "👑 ${WHITE}STATUS LISENSI:${NC}"
echo -e "${YELLOW}  • Terdaftar Untuk: ${WHITE}${NAMA_USER}${NC}"
echo -e "${YELLOW}  • Status     : ${LISENSI_STATUS}${NC}"
echo -e "--------------------------------------------------------"
echo -e "🤖 ${WHITE}KONTROL ZIVPN SERVICE:${NC}"
echo -e "${YELLOW}  • ZIVPN Core: ${STATUS_ZIVPN}${NC}  |  ${YELLOW}API: ${STATUS_API}${NC}  |  ${YELLOW}Bot: ${STATUS_BOT}${NC}"
echo -e "${YELLOW}  • Status Keseluruhan : ${BOT_STATUS_MSG}${NC}"
echo -e "--------------------------------------------------------"
echo -e "${WHITE}PERINTAH CEPAT:${NC}"

# 1. Akses Bot / Restart
if [ -n "$RESTART_CMD" ]; then
    echo -e "${CYAN}   1. $RESTART_CMD   -> Restart/Start Services Zivpn${NC}"
fi

# 2. Jalankan Menu.sh dari repositori
if [ -f "$MENU_SH" ]; then
    echo -e "${CYAN}   2. $MENU_SH -> Akses Menu Admin Lengkap${NC}"
else
    echo -e "${GRAY}   2. $MENU_SH -> (Menu Admin Lengkap tidak ditemukan di $REPO_DIR)${NC}"
fi

echo -e "${CYAN}   3. tail -f /tmp/zivpn_install.log -> Cek Log Instalasi Terakhir${NC}"
echo -e "${CYAN}   4. exit                 -> Keluar dari Terminal SSH${NC}"
echo -e "${CYAN}========================================================${NC}"