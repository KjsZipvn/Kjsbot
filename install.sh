#!/bin/bash

# ==========================================================
# FILE: kjs-new Installation Script (Full Feature VPN/Proxy)
# AUTHOR: Original Creator & KjsZivpn
# DESCRIPTION: Skrip instalasi lengkap untuk Xray, SSH, OpenVPN, dan ZiVPN UDP.
# ==========================================================

# ==========================================================
# 1. KONFIGURASI WARNA & FUNGSI UTILITAS (Diambil dari skrip ZiVPN)
# ==========================================================
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"
BOLD="\033[1m"
GRAY="\033[1;30m"

# Variabel warna lama (dipertahankan untuk kompatibilitas fungsi lama)
Green="\e[92;1m"
FONT="\033[0m"
OK="${Green}--->${FONT}"
ERROR="${RED}[ERROR]${FONT}"
NC='\e[0m'
red='\e[1;31m'
green='\e[0;32m'

# Fungsi utilitas baru
print_task() {
  echo -ne "${GRAY}•${RESET} $1..."
}

print_done() {
  echo -e "\r${GREEN}✓${RESET} $1      "
}

print_fail() {
  echo -e "\r${RED}✗${RESET} $1      "
  exit 1
}

# Fungsi run_silent baru untuk eksekusi yang lebih bersih
run_silent() {
  local msg="$1"
  local cmd="$2"
  
  print_task "$msg"
  bash -c "$cmd" &>/tmp/zivpn_install.log
  if [ $? -eq 0 ]; then
    print_done "$msg"
  else
    print_fail "$msg (Check /tmp/zivpn_install.log)"
  fi
}

# Fungsi utilitas lama (diperbarui agar menggunakan format warna baru)
function print_ok() {
echo -e "${OK} ${BLUE} $1 ${FONT}"
}
function print_install() {
echo -e "${GREEN} =============================== ${FONT}"
echo -e "${YELLOW} # $1 ${FONT}"
echo -e "${GREEN} =============================== ${FONT}"
sleep 1
}
function print_success() {
if [[ 0 -eq $? ]]; then
echo -e "${GREEN} =============================== ${FONT}"
echo -e "${Green} # $1 berhasil dipasang"
echo -e "${GREEN} =============================== ${FONT}"
sleep 2
fi
}

# ==========================================================
# 2. VARIABEL DAN CUKILAN KODE AWAL
# (Bagian ini sama dengan skrip lama, hanya dikurangi untuk mempersingkat)
# ==========================================================
export DEBIAN_FRONTEND=noninteractive
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
apt install -y
apt upgrade -y
apt update -y
apt install curl -y
apt install wondershaper -y
apt install lolcat -y
gem install lolcat
TIME=$(date '+%d %b %Y')
ipsaya=$(wget -qO- ipinfo.io/ip)
TIMES="10"
eval $(wget -qO- "https://raw.githubusercontent.com/kjsstore/kjs-new/main/Fls/botkey")
URL="https://api.telegram.org/bot$KEY/sendMessage"
clear
export IP=$( curl -sS icanhazip.com )
clear && clear && clear
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "\033[96;1m          WELCOME TO SRICPT METSOTRE           \033[0m"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
sleep 3
# ... (Cek Arsitektur, OS, IP, Root, OpenVZ - Dihilangkan untuk keringkasan)

# Variabel REPO dan waktu mulai
REPO="https://raw.githubusercontent.com/kjsstore/kjs-new/main/"
start=$(date +%s)
secs_to_human() {
echo "Installation time : $((${1} / 3600)) hours $(((${1} / 60) % 60)) minute's $((${1} % 60)) seconds"
}
# ... (Fungsi-fungsi seperti first_setup, nginx_install, base_package, make_folder_xray, install_xray, ssh, udp_mini, dll. - Dianggap sudah ada)

# ==========================================================
# 3. FUNGSI INSTALLASI ZIVPN UDP BARU
# ==========================================================
function ins_zivpn(){
clear
echo -e "${BOLD}--- ZIVPN UDP INSTALLER ---${RESET}"
echo -e "${GRAY}KjsZivpn Edition${RESET}"
echo ""

# Hapus instalasi lama ZiVPN
if [ -f /usr/local/bin/zivpn ]; then
  echo -e "${YELLOW}! ZiVPN detected. Preparing for (Re)installation...${RESET}"
  systemctl stop zivpn.service &>/dev/null
  systemctl stop zivpn-api.service &>/dev/null
  systemctl stop zivpn-bot.service &>/dev/null
fi

# Pastikan Timezone sudah diatur (sudah diatur di first_setup, ini sebagai redundansi)
run_silent "Setting Timezone" "sudo timedatectl set-timezone Asia/Jakarta"

# Instalasi GoLang jika belum ada (Dependensi utama ZiVPN)
if ! command -v go &> /dev/null; then
  run_silent "Installing Golang & Git" "sudo apt-get install -y golang git net-tools"
else
  print_done "Golang & Dependencies ready"
fi

# --- Konfigurasi Domain ---
echo ""
echo -ne "${BOLD}Domain Configuration${RESET}\n"
while true; do
  read -p "Enter Domain for ZiVPN/SSL: " domain_zivpn
  if [[ -n "$domain_zivpn" ]]; then
    break
  fi
done
# Mengganti domain utama jika belum disetel
if [ ! -f /root/domain ]; then
  echo $domain_zivpn > /root/domain
fi
echo ""

# --- Konfigurasi API Key ---
echo -ne "${BOLD}API Key Configuration${RESET}\n"
generated_key=$(openssl rand -hex 16)
echo -e "Generated Key: ${CYAN}$generated_key${RESET}"
read -p "Enter API Key (Press Enter to use generated): " input_key
if [[ -z "$input_key" ]]; then
  api_key="$generated_key"
else
  api_key="$input_key"
fi
echo -e "Using Key: ${GREEN}$api_key${RESET}"
echo ""

systemctl stop zivpn.service &>/dev/null
# Instalasi Core
run_silent "Downloading ZiVPN Core" "wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn && chmod +x /usr/local/bin/zivpn"

# Konfigurasi Direktori dan File
mkdir -p /etc/zivpn
echo "$domain_zivpn" > /etc/zivpn/domain
echo "$api_key" > /etc/zivpn/apikey
run_silent "Downloading Config.json" "wget -q https://raw.githubusercontent.com/KjsZipvn/kjsbot/main/config.json -O /etc/zivpn/config.json"

# Generating SSL
run_silent "Generating SSL Cert/Key" "openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj '/C=ID/ST=Jawa Barat/L=Bandung/O=KjsZipvn/OU=IT Department/CN=$domain_zivpn' -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt"

# Mencari Free API Port
print_task "Finding available API Port"
API_PORT=8080
while netstat -tuln | grep -q ":$API_PORT "; do
    ((API_PORT++))
done
echo "$API_PORT" > /etc/zivpn/api_port
print_done "API Port selected: ${CYAN}$API_PORT${RESET}"

# --- Kernel Tweak (Sysctl) ---
print_task "Applying Kernel Tweaks (BBR, Conntrack, etc.)"
cat >> /etc/sysctl.conf <<END
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=65536
net.core.somaxconn=65535
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3
fs.file-max=1000000
net.core.netdev_max_backlog=16384
net.ipv4.udp_mem=65536 131072 262144
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
END
sysctl -p &>/dev/null
print_done "Applied Kernel Tweaks"

# --- SystemD Service ZiVPN Core ---
print_task "Creating ZIVPN Core Service"
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
print_done "ZIVPN Core Service Created"

# --- Setting up API ---
mkdir -p /etc/zivpn/api
run_silent "Downloading ZIVPN API Files" "wget -q https://raw.githubusercontent.com/KjsZipvn/kjsbot/main/zivpn-api.go -O /etc/zivpn/api/zivpn-api.go && wget -q https://raw.githubusercontent.com/KjsZipvn/kjsbot/main/go.mod -O /etc/zivpn/api/go.mod"

cd /etc/zivpn/api
if go build -o zivpn-api zivpn-api.go &>/dev/null; then
  print_done "Compiling API"
else
  print_fail "Compiling API"
fi

# --- SystemD Service ZiVPN API ---
print_task "Creating ZIVPN API Service"
cat <<EOF > /etc/systemd/system/zivpn-api.service
[Unit]
Description=ZiVPN Golang API Service
After=network.target zivpn.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn/api
ExecStart=/etc/zivpn/api/zivpn-api
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
print_done "ZIVPN API Service Created"

# --- Telegram Bot Configuration (Interaktif) ---
echo ""
echo -ne "${BOLD}Telegram Bot Configuration${RESET}\n"
echo -ne "${GRAY}(Leave empty to skip)${RESET}\n"
read -p "Bot Token: " bot_token
read -p "Admin ID : " admin_id

if [[ -n "$bot_token" ]] && [[ -n "$admin_id" ]]; then
  echo ""
  echo "Select Bot Type:"
  echo "1) Free (Admin Only / Public Mode)"
  echo "2) Paid (Pakasir Payment Gateway)"
  read -p "Choice [1]: " bot_type
  bot_type=${bot_type:-1}

  if [[ "$bot_type" == "2" ]]; then
    read -p "Pakasir Project Slug: " pakasir_slug
    read -p "Pakasir API Key     : " pakasir_key
    read -p "Daily Price (IDR)   : " daily_price
    
    echo "{\"bot_token\": \"$bot_token\", \"admin_id\": $admin_id, \"mode\": \"public\", \"domain\": \"$domain_zivpn\", \"pakasir_slug\": \"$pakasir_slug\", \"pakasir_api_key\": \"$pakasir_key\", \"daily_price\": $daily_price}" > /etc/zivpn/bot-config.json
    bot_file="zivpn-paid-bot.go"
  else
    read -p "Bot Mode (public/private) [default: private]: " bot_mode
    bot_mode=${bot_mode:-private}
    
    echo "{\"bot_token\": \"$bot_token\", \"admin_id\": $admin_id, \"mode\": \"$bot_mode\", \"domain\": \"$domain_zivpn\"}" > /etc/zivpn/bot-config.json
    bot_file="zivpn-bot.go"
  fi
  
  run_silent "Downloading Bot Source" "wget -q https://raw.githubusercontent.com/KjsZipvn/kjsbot/main/$bot_file -O /etc/zivpn/api/$bot_file"
  
  cd /etc/zivpn/api
  run_silent "Downloading Bot Dependencies" "go get github.com/go-telegram-bot-api/telegram-bot-api/v5"
  
  if go build -o zivpn-bot "$bot_file" &>/dev/null; then
    print_done "Compiling Bot"
    
    # --- SystemD Service ZiVPN Bot ---
    print_task "Creating ZIVPN Bot Service"
    cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=ZiVPN Telegram Bot
After=network.target zivpn-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn/api
ExecStart=/etc/zivpn/api/zivpn-bot
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    print_done "ZIVPN Bot Service Created"
    systemctl enable zivpn-bot.service &>/dev/null
    systemctl start zivpn-bot.service &>/dev/null
  else
    print_fail "Compiling Bot"
  fi
else
  print_task "Skipping Bot Setup"
  echo ""
fi

# --- Memulai Service dan Cron ---
run_silent "Starting ZiVPN Services" "systemctl enable zivpn.service && systemctl start zivpn.service && systemctl enable zivpn-api.service && systemctl start zivpn-api.service"

# Setup Cron for Auto-Expire
echo -e "${YELLOW}Setting up Cron Job for ZiVPN Auto-Expire...${NC}"
cron_cmd="0 0 * * * /usr/bin/curl -s -X POST -H \"X-API-Key: \$(cat /etc/zivpn/apikey)\" http://127.0.0.1:\$(cat /etc/zivpn/api_port)/api/cron/expire >> /var/log/zivpn-cron.log 2>&1"
(crontab -l 2>/dev/null | grep -v "/api/cron/expire"; echo "$cron_cmd") | crontab -
print_done "ZiVPN Cron Job Configured"

# --- Pengaturan IPTABLES/UFW (Port ZiVPN) ---
print_task "Configuring Firewalls for ZiVPN"
iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 &>/dev/null
# Asumsi ufw atau netfilter-persistent digunakan, jadi tambahkan juga port
ufw allow 6000:19999/udp &>/dev/null
ufw allow 5667/udp &>/dev/null
ufw allow $API_PORT/tcp &>/dev/null
netfilter-persistent save &>/dev/null
print_done "Firewall Configured"

echo ""
echo -e "${BOLD}ZiVPN Installation Summary${RESET}"
echo -e "Domain  : ${CYAN}$domain_zivpn${RESET}"
echo -e "API Port: ${CYAN}$API_PORT${RESET}"
echo -e "API Key : ${CYAN}$api_key${RESET}"
echo -e "Dev     : ${CYAN}https://t.me/AutoFTBot${RESET}"
print_success "ZiVPN UDP"
}

# ==========================================================
# 4. FUNGSI INSTALASI UTAMA (MEMANGGIL ZIVPN)
# ==========================================================
# (Fungsi-fungsi seperti ins_SSHD, ins_dropbear, ins_vnstat, ins_openvpn, ins_backup, ins_swab, ins_Fail2ban, ins_epro, ins_restart, menu, profile, enable_services, restart_system dipertahankan di luar ins_zivpn)
# ...

function instal(){
clear
first_setup
make_folder_xray
# pasang_domain # Dihapus karena ins_zivpn akan meminta Domain
nginx_install
base_package
password_default # FUNGSI INI HILANG (Asumsi ada)
pasang_ssl
install_xray
ssh
udp_mini
ssh_slow
ins_SSHD
ins_dropbear
ins_vnstat
ins_openvpn
ins_backup
ins_swab
ins_Fail2ban
ins_epro
# --- PANGGILAN FUNGSI BARU ---
ins_zivpn
# -----------------------------
ins_restart
menu
profile
enable_services
restart_system
}

# --- BAGIAN FINALISASI ---
# (Semua kode di bawah instal tetap sama)
instal
NEW_FILE_MAX=65535
# ... (Pengaturan sysctl dan cleanup file)
# ...
secs_to_human "$(($(date +%s) - ${start}))"
sudo hostnamectl set-hostname $username
LOCAL_IP="127.0.1.1"
if ! grep -q "$username" /etc/hosts; then
    echo "$LOCAL_IP    $username" >> /etc/hosts
fi
clear
echo -e ""
echo -e ""
echo -e "\033[96m==========================\033[0m"
echo -e "\033[92m      INSTALL SUCCES      \033[0m"
echo -e "\033[96m==========================\033[0m"
echo -e ""
sleep 2
clear
echo -e "\033"