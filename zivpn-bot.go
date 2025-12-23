package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

// ==========================================
// Konstanta & Konfigurasi File Path
// ==========================================

const (
	// Base Directory untuk semua konfigurasi ZiVPN
	ConfigDir     = "/etc/zivpn"
	BotConfigFile = ConfigDir + "/bot-config.json"
	ApiPortFile   = ConfigDir + "/api_port"
	ApiKeyFile    = ConfigDir + "/apikey"
	DomainFile    = ConfigDir + "/domain"
	// PortFile tidak digunakan karena port dibaca dari ApiPortFile
)

// ==========================================
// Variabel Global
// ==========================================

var (
	// ApiUrl akan diisi saat startup berdasarkan ApiPortFile
	ApiUrl = "http://127.0.0.1:8080/api" // Default fallback
	// ApiKey akan diisi saat startup berdasarkan ApiKeyFile
	ApiKey = ""
)

// ==========================================
// Struktur Data
// ==========================================

type BotConfig struct {
	BotToken string `json:"bot_token"`
	AdminID  int64  `json:"admin_id"`
	Mode     string `json:"mode"`   // "public" or "private"
	Domain   string `json:"domain"` // Domain dari setup
}

type IpInfo struct {
	City  string `json:"city"`
	Isp   string `json:"isp"`
	Query string `json:"query"` // IP Address
}

type UserData struct {
	Password string `json:"password"`
	Expired  string `json:"expired"`
	Status   string `json:"status"`
	IpLimit  int    `json:"ip_limit"`
}

// ==========================================
// State Global
// ==========================================

var userStates = make(map[int64]string)
var tempUserData = make(map[int64]map[string]string)
var lastMessageIDs = make(map[int64]int)

// ==========================================
// Main Entry Point
// ==========================================

func main() {
	log.Println("Starting ZiVPN Telegram Bot...")

	// 1. Setup API Key and URL
	setupAPIConfig()

	// 2. Load Bot Configuration
	config, err := loadConfig()
	if err != nil {
		log.Fatalf("FATAL: Gagal memuat konfigurasi bot dari %s: %v", BotConfigFile, err)
	}

	// 3. Initialize Bot
	bot, err := tgbotapi.NewBotAPI(config.BotToken)
	if err != nil {
		log.Panicf("FATAL: Gagal inisialisasi Bot API: %v", err)
	}

	bot.Debug = false
	log.Printf("Authorized on account %s. AdminID: %d. Mode: %s.", bot.Self.UserName, config.AdminID, config.Mode)

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	// 4. Main Loop
	for update := range updates {
		if update.Message != nil {
			// Menggunakan goroutine agar bot tidak terblokir saat memproses request
			go handleMessage(bot, update.Message, &config)
		} else if update.CallbackQuery != nil {
			go handleCallback(bot, update.CallbackQuery, &config)
		}
	}
}

// setupAPIConfig membaca file API Key dan Port, lalu mengupdate variabel global ApiKey dan ApiUrl
func setupAPIConfig() {
	// Load API Key
	if keyBytes, err := os.ReadFile(ApiKeyFile); err == nil {
		ApiKey = strings.TrimSpace(string(keyBytes))
		log.Printf("INFO: API Key loaded successfully.")
	} else {
		log.Printf("WARNING: Gagal membaca API Key dari %s: %v. Menggunakan default/kosong.", ApiKeyFile, err)
	}

	// Load API Port
	if portBytes, err := os.ReadFile(ApiPortFile); err == nil {
		port := strings.TrimSpace(string(portBytes))
		// Validasi port
		if _, portErr := strconv.Atoi(port); portErr == nil {
			ApiUrl = fmt.Sprintf("http://127.0.0.1:%s/api", port)
			log.Printf("INFO: API URL set to %s", ApiUrl)
		} else {
			log.Printf("WARNING: Port API tidak valid: %v. Menggunakan default: %s", portErr, ApiUrl)
		}
	} else {
		log.Printf("WARNING: Gagal membaca API Port dari %s: %v. Menggunakan default: %s", ApiPortFile, err)
	}
}

// ==========================================
// Telegram Event Handlers
// ==========================================

func handleMessage(bot *tgbotapi.BotAPI, msg *tgbotapi.Message, config *BotConfig) {
	// Cek akses sebelum melakukan operasi apapun
	if !isAllowed(config, msg.From.ID) {
		replyError(bot, msg.Chat.ID, "⛔ Akses Ditolak. Bot ini Private.")
		return
	}

	// Handle Document Upload (Restore)
	if msg.Document != nil && msg.From.ID == config.AdminID {
		if state, exists := userStates[msg.From.ID]; exists && state == "waiting_restore_file" {
			processRestoreFile(bot, msg, config)
			return
		}
	}

	// Handle State (User Input)
	if state, exists := userStates[msg.From.ID]; exists {
		handleState(bot, msg, state, config)
		return
	}

	// Handle Commands
	if msg.IsCommand() {
		switch msg.Command() {
		case "start":
			showMainMenu(bot, msg.Chat.ID, config)
		default:
			replyError(bot, msg.Chat.ID, "Perintah tidak dikenal. Ketik /start untuk menu.")
		}
	}
}

func handleCallback(bot *tgbotapi.BotAPI, query *tgbotapi.CallbackQuery, config *BotConfig) {
	chatID := query.Message.Chat.ID
	userID := query.From.ID

	// Khusus untuk toggle_mode, hanya Admin yang boleh
	if query.Data == "toggle_mode" && userID != config.AdminID {
		bot.Request(tgbotapi.NewCallback(query.ID, "Akses Ditolak"))
		return
	}

	// Hapus state/temp data sebelum menjalankan aksi callback baru (kecuali pagination)
	if !strings.HasPrefix(query.Data, "page_") {
		delete(userStates, userID)
		delete(tempUserData, userID)
	}

	switch {
	// --- Menu Navigation ---
	case query.Data == "menu_create":
		startCreateUser(bot, chatID, userID)
	case query.Data == "menu_delete":
		showUserSelection(bot, chatID, 1, "delete")
	case query.Data == "menu_renew":
		showUserSelection(bot, chatID, 1, "renew")
	case query.Data == "menu_list":
		if userID == config.AdminID {
			listUsers(bot, chatID)
		}
	case query.Data == "menu_info":
		if userID == config.AdminID {
			systemInfo(bot, chatID, config)
		}
	case query.Data == "menu_backup_restore":
		if userID == config.AdminID {
			showBackupRestoreMenu(bot, chatID)
		}
	case query.Data == "menu_backup_action":
		if userID == config.AdminID {
			performBackup(bot, chatID)
		}
	case query.Data == "menu_restore_action":
		if userID == config.AdminID {
			startRestore(bot, chatID, userID)
		}
	case query.Data == "cancel":
		cancelOperation(bot, chatID, userID, config)

	// --- Pagination ---
	case strings.HasPrefix(query.Data, "page_"):
		handlePagination(bot, chatID, query.Data)

	// --- Action Selection & Confirmation ---
	case strings.HasPrefix(query.Data, "select_renew:"):
		startRenewUser(bot, chatID, userID, query.Data)
	case strings.HasPrefix(query.Data, "select_delete:"):
		confirmDeleteUser(bot, chatID, query.Data)
	case strings.HasPrefix(query.Data, "confirm_delete:"):
		username := strings.TrimPrefix(query.Data, "confirm_delete:")
		deleteUser(bot, chatID, username, config)

	// --- Admin Actions ---
	case query.Data == "toggle_mode":
		toggleMode(bot, chatID, userID, config)
	}

	// Always respond to callback queries to remove the 'loading' state
	bot.Request(tgbotapi.NewCallback(query.ID, ""))
}

func handleState(bot *tgbotapi.BotAPI, msg *tgbotapi.Message, state string, config *BotConfig) {
	userID := msg.From.ID
	text := strings.TrimSpace(msg.Text)
	chatID := msg.Chat.ID

	// Hapus pesan pengguna yang berisi input sensitif/state
	deleteMessage(bot, chatID, msg.MessageID)

	switch state {
	case "create_username":
		if !validateUsername(bot, chatID, text) {
			return
		}
		tempUserData[userID]["username"] = text
		userStates[userID] = "create_days"
		sendMessage(bot, chatID, "⏳ Masukkan Durasi (hari) untuk akun ini (1-9999):")

	case "create_days":
		days, ok := validateNumber(bot, chatID, text, 1, 9999, "Durasi")
		if !ok {
			return
		}
		
		// Panggil createUser di goroutine untuk tidak memblokir bot
		go createUser(bot, chatID, tempUserData[userID]["username"], days, config)
		resetState(userID)

	case "renew_days":
		days, ok := validateNumber(bot, chatID, text, 1, 9999, "Durasi")
		if !ok {
			return
		}
		
		// Panggil renewUser di goroutine
		go renewUser(bot, chatID, tempUserData[userID]["username"], days, config)
		resetState(userID)

	default:
		// State tidak dikenal, reset
		resetState(userID)
		replyError(bot, chatID, "Sesi interaksi berakhir. Silakan ulangi dari menu utama.")
		showMainMenu(bot, chatID, config)
	}
}

// ==========================================
// Feature Implementation
// ==========================================

func createUser(bot *tgbotapi.BotAPI, chatID int64, username string, days int, config *BotConfig) {
	res, err := apiCall("POST", "/user/create", map[string]interface{}{
		"password": username,
		"days":     days,
	})

	if err != nil {
		log.Printf("ERROR: API create user failed: %v", err)
		replyError(bot, chatID, "❌ Gagal Terhubung ke API ZiVPN: "+err.Error())
		return
	}

	if success, ok := res["success"].(bool); ok && success {
		if data, ok := res["data"].(map[string]interface{}); ok {
			sendAccountInfo(bot, chatID, data, config)
		} else {
			replyError(bot, chatID, "❌ Error: Respon API tidak valid.")
		}
	} else {
		msg := "❌ Gagal membuat akun."
		if message, ok := res["message"].(string); ok {
			msg += fmt.Sprintf(" Pesan: %s", message)
		}
		replyError(bot, chatID, msg)
		showMainMenu(bot, chatID, config)
	}
}

func renewUser(bot *tgbotapi.BotAPI, chatID int64, username string, days int, config *BotConfig) {
	res, err := apiCall("POST", "/user/renew", map[string]interface{}{
		"password": username,
		"days":     days,
	})

	if err != nil {
		log.Printf("ERROR: API renew user failed: %v", err)
		replyError(bot, chatID, "❌ Gagal Terhubung ke API ZiVPN: "+err.Error())
		return
	}

	if success, ok := res["success"].(bool); ok && success {
		if data, ok := res["data"].(map[string]interface{}); ok {
			sendAccountInfo(bot, chatID, data, config)
		} else {
			replyError(bot, chatID, "❌ Error: Respon API tidak valid.")
		}
	} else {
		msg := "❌ Gagal memperpanjang akun."
		if message, ok := res["message"].(string); ok {
			msg += fmt.Sprintf(" Pesan: %s", message)
		}
		replyError(bot, chatID, msg)
		showMainMenu(bot, chatID, config)
	}
}

func deleteUser(bot *tgbotapi.BotAPI, chatID int64, username string, config *BotConfig) {
	res, err := apiCall("POST", "/user/delete", map[string]interface{}{
		"password": username,
	})

	if err != nil {
		log.Printf("ERROR: API delete user failed: %v", err)
		replyError(bot, chatID, "❌ Gagal Terhubung ke API ZiVPN: "+err.Error())
		return
	}

	if success, ok := res["success"].(bool); ok && success {
		deleteLastMessage(bot, chatID)
		sendMessage(bot, chatID, fmt.Sprintf("✅ Password `%s` berhasil dihapus.", username))
		showMainMenu(bot, chatID, config)
	} else {
		msg := "❌ Gagal menghapus akun."
		if message, ok := res["message"].(string); ok {
			msg += fmt.Sprintf(" Pesan: %s", message)
		}
		replyError(bot, chatID, msg)
		showMainMenu(bot, chatID, config)
	}
}

// ... Fungsi listUsers, systemInfo, showBackupRestoreMenu, handlePagination, dsb. (Diasumsikan sudah benar, fokus pada perubahan besar) ...

func performBackup(bot *tgbotapi.BotAPI, chatID int64) {
	// Menghapus pesan 'loading' sebelumnya jika ada
	deleteLastMessage(bot, chatID)
	
	msgID := sendMessage(bot, chatID, "⏳ Sedang membuat backup. Mohon tunggu...")

	// Files to backup: Konfigurasi penting ZiVPN dan Bot
	files := []string{
		ConfigDir + "/config.json",  // Konfigurasi ZiVPN (contoh)
		ConfigDir + "/users.json",   // Data user (contoh)
		ConfigDir + "/domain",       // Domain
		BotConfigFile,               // Konfigurasi Bot
		ApiKeyFile,                  // API Key
		ApiPortFile,                 // API Port
	}

	buf := new(bytes.Buffer)
	zipWriter := zip.NewWriter(buf)

	for _, filePath := range files {
		// Gunakan os.Stat untuk pengecekan existence dan error yang lebih baik
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			log.Printf("WARNING: File tidak ditemukan saat backup: %s", filePath)
			continue
		} else if err != nil {
			log.Printf("ERROR: Gagal stat file %s: %v", filePath, err)
			continue
		}

		f, err := os.Open(filePath)
		if err != nil {
			log.Printf("ERROR: Gagal membuka file %s untuk backup: %v", filePath, err)
			continue
		}
		
		// Gunakan hanya nama dasar file untuk mencegah directory traversal di dalam zip
		header := filepath.Base(filePath)
		
		w, err := zipWriter.Create(header)
		if err != nil {
			f.Close()
			log.Printf("ERROR: Gagal membuat header zip untuk %s: %v", header, err)
			continue
		}

		if _, err := io.Copy(w, f); err != nil {
			f.Close()
			log.Printf("ERROR: Gagal menyalin file %s ke zip: %v", header, err)
			continue
		}
		f.Close()
	}

	if err := zipWriter.Close(); err != nil {
		log.Printf("ERROR: Gagal menutup zip writer: %v", err)
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ Gagal menyelesaikan proses backup (Zip Error).")
		return
	}

	fileName := fmt.Sprintf("zivpn-backup-%s.zip", time.Now().Format("20060102-150405"))

	// Tulis ke temp file
	tmpFile := filepath.Join(os.TempDir(), fileName)
	if err := os.WriteFile(tmpFile, buf.Bytes(), 0644); err != nil {
		log.Printf("ERROR: Gagal menulis file backup sementara: %v", err)
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ Gagal membuat file backup.")
		return
	}
	defer os.Remove(tmpFile) // Pastikan file dihapus setelah selesai

	doc := tgbotapi.NewDocument(chatID, tgbotapi.FilePath(tmpFile))
	doc.Caption = "✅ Backup Data ZiVPN"

	// Hapus pesan 'sedang membuat backup...'
	deleteMessage(bot, chatID, msgID)
	
	if _, err := bot.Send(doc); err != nil {
		log.Printf("ERROR: Gagal mengirim dokumen backup: %v", err)
		replyError(bot, chatID, "❌ Gagal mengirim file backup ke Telegram.")
	}
}

func processRestoreFile(bot *tgbotapi.BotAPI, msg *tgbotapi.Message, config *BotConfig) {
	chatID := msg.Chat.ID
	userID := msg.From.ID
	
	resetState(userID)
	msgID := sendMessage(bot, chatID, "⏳ Sedang memproses file restore. Mohon tunggu...")
	
	// Validasi MIME type jika perlu, tapi fokus pada file ZIP

	// Download file
	file, err := bot.GetFile(tgbotapi.FileConfig{FileID: msg.Document.FileID})
	if err != nil {
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ Gagal mengunduh file.")
		log.Printf("ERROR: Gagal get file info: %v", err)
		return
	}

	// Menggunakan link file secara langsung
	fileUrl := file.Link(config.BotToken)
	resp, err := http.Get(fileUrl)
	if err != nil {
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ Gagal mengunduh file content.")
		log.Printf("ERROR: Gagal HTTP GET file content: %v", err)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ Gagal membaca file yang diunduh.")
		return
	}

	// Unzip
	zipReader, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		deleteMessage(bot, chatID, msgID)
		replyError(bot, chatID, "❌ File bukan format ZIP yang valid.")
		return
	}

	// Daftar file yang diizinkan untuk di-restore (WHITELIST)
	validFiles := map[string]bool{
		"config.json":     true,
		"users.json":      true,
		"domain":          true,
		"bot-config.json": true,
		"apikey":          true,
		"api_port":        true,
	}

	for _, f := range zipReader.File {
		// 1. Amankan dari Directory Traversal
		fileName := filepath.Base(f.Name) // Ambil hanya nama file, buang path
		
		if !validFiles[fileName] {
			log.Printf("WARNING: Mencoba restore file tidak diizinkan: %s", f.Name)
			continue
		}

		rc, err := f.Open()
		if err != nil {
			log.Printf("ERROR: Gagal membuka file zip: %s, %v", f.Name, err)
			continue
		}
		
		dstPath := filepath.Join(ConfigDir, fileName) // Pastikan path tujuan adalah ConfigDir
		
		dst, err := os.Create(dstPath)
		if err != nil {
			rc.Close()
			log.Printf("ERROR: Gagal membuat file tujuan %s: %v", dstPath, err)
			continue
		}

		if _, err := io.Copy(dst, rc); err != nil {
			log.Printf("ERROR: Gagal menyalin data ke file %s: %v", dstPath, err)
		}
		
		dst.Close()
		rc.Close()
	}
	
	// Hapus pesan 'sedang memproses...'
	deleteMessage(bot, chatID, msgID)
	
	// Restart Services
	msgSuccess := tgbotapi.NewMessage(chatID, "✅ Restore Berhasil!\n⏳ Sedang me-restart Service ZiVPN, API, dan Bot...")
	bot.Send(msgSuccess)
	
	// Jalankan restart di latar belakang dan pastikan semua service di-restart
	go func() {
		// Fungsi pembantu untuk restart
		restartService := func(service string) {
			cmd := exec.Command("systemctl", "restart", service)
			output, err := cmd.CombinedOutput()
			if err != nil {
				log.Printf("ERROR: Gagal restart %s: %v. Output: %s", service, err, string(output))
				// Tidak perlu reply error ke user karena proses restore sudah sukses di sisi bot
			} else {
				log.Printf("INFO: Service %s berhasil direstart.", service)
			}
		}
		
		restartService("zivpn-api") // API harus restart duluan untuk membaca config baru
		time.Sleep(1 * time.Second)
		restartService("zivpn")     // Layanan VPN utama
		
		// Terakhir, restart bot itu sendiri untuk memuat bot-config.json yang baru
		time.Sleep(2 * time.Second) 
		restartService("zivpn-bot")
		
		// Tidak bisa menampilkan menu utama setelah restart bot, karena bot akan mati
	}()
}

// ==========================================
// UI & Helpers
// ==========================================

// Fungsi showMainMenu, getMainMenuKeyboard, sendAccountInfo, dll.

func showMainMenu(bot *tgbotapi.BotAPI, chatID int64, config *BotConfig) {
	ipInfo, _ := getIpInfo()
	domain := config.Domain
	if domain == "" {
		// Coba baca lagi dari file domain
		if domainBytes, err := os.ReadFile(DomainFile); err == nil {
			domain = strings.TrimSpace(string(domainBytes))
		}
		if domain == "" {
			domain = "_(Belum Dikonfigurasi)_"
		}
	}

	// Menggunakan format Markdown yang lebih kaya
	msgText := fmt.Sprintf("✨ *SELAMAT DATANG DI ZIVPN UDP BOT* ✨\n\n"+
		"╔═══════ 🇮🇩 *INFO SERVER* ═══════\n"+
		"║\n"+
		"╠═ 🌐 *Domain* : `%s`\n"+
		"╠═ 🏙️ *Kota* : `%s`\n"+
		"╠═ 📡 *ISP* : `%s`\n"+
		"║\n"+
		"╚═════════════════════════\n\n"+
		"👇 *Pilih Menu Transaksi Anda* 👇",
		domain, ipInfo.City, ipInfo.Isp)

	msg := tgbotapi.NewMessage(chatID, msgText)
	msg.ParseMode = "Markdown"
	msg.ReplyMarkup = getMainMenuKeyboard(config, chatID)
	sendAndTrack(bot, msg)
}

func sendAccountInfo(bot *tgbotapi.BotAPI, chatID int64, data map[string]interface{}, config *BotConfig) {
	ipInfo, _ := getIpInfo()
	domain := config.Domain
	if domain == "" {
		// Coba baca lagi dari file domain
		if domainBytes, err := os.ReadFile(DomainFile); err == nil {
			domain = strings.TrimSpace(string(domainBytes))
		}
		if domain == "" {
			domain = "_(Belum Dikonfigurasi)_"
		}
	}
	
	// Pastikan data string/interface dikonversi dengan aman
	password, _ := data["password"].(string)
	expired, _ := data["expired"].(string)
	
	// Menggunakan format yang lebih visual dengan emoji dan penekanan (Bold)
	msg := fmt.Sprintf("🔑 *DETAIL AKUN ZIVPN UDP*\n\n"+
		"╔═══════ 🔰 *INFORMASI AKUN* ═══════\n"+
		"║\n"+
		"╠═ 🔓 *Password* : `%s`\n"+
		"╠═ 📅 *Expired* : `%s`\n"+
		"║\n"+
		"╚════════════════════════════\n\n"+
		"╔═══════ 🌐 *INFORMASI SERVER* ═══════\n"+
		"║\n"+
		"╠═ 🌐 *Domain* : `%s`\n"+
		"╠═ 🏙️ *Kota* : `%s`\n"+
		"╠═ 📡 *ISP* : `%s`\n"+
		"╠═ 📍 *IP ISP* : `%s`\n"+
		"║\n"+
		"╚════════════════════════════\n\n"+
		"🚀 *Akun siap digunakan!* Harap jaga kerahasiaan password Anda.",
		password,
		expired,
		domain,
		ipInfo.City,
		ipInfo.Isp,
		ipInfo.Query,
	)

	reply := tgbotapi.NewMessage(chatID, msg)
	reply.ParseMode = "Markdown"
	deleteLastMessage(bot, chatID)
	bot.Send(reply)
	showMainMenu(bot, chatID, config)
}

// sendMessage mengirim pesan dan mengembalikan ID pesan
func sendMessage(bot *tgbotapi.BotAPI, chatID int64, text string) int {
	msg := tgbotapi.NewMessage(chatID, text)
	msg.ParseMode = "Markdown"
	if sentMsg, err := bot.Send(msg); err == nil {
		return sentMsg.MessageID
	}
	return 0
}

// replyError mengirim pesan error
func replyError(bot *tgbotapi.BotAPI, chatID int64, text string) {
	sendMessage(bot, chatID, "🚨 ERROR: "+text)
}

// sendAndTrack mengirim pesan dan mencatat ID-nya untuk dihapus nanti
func sendAndTrack(bot *tgbotapi.BotAPI, msg tgbotapi.Chattable) {
	if sentMsg, err := bot.Send(msg); err == nil {
		lastMessageIDs[sentMsg.Chat.ID] = sentMsg.MessageID
	}
}

// deleteLastMessage menghapus pesan terakhir yang dikirim bot
func deleteLastMessage(bot *tgbotapi.BotAPI, chatID int64) {
	if msgID, exists := lastMessageIDs[chatID]; exists {
		deleteMessage(bot, chatID, msgID)
		delete(lastMessageIDs, chatID)
	}
}

// deleteMessage menghapus pesan spesifik
func deleteMessage(bot *tgbotapi.BotAPI, chatID int64, messageID int) {
	if messageID != 0 {
		deleteConfig := tgbotapi.NewDeleteMessage(chatID, messageID)
		if _, err := bot.Request(deleteConfig); err != nil {
			// Log error jika gagal menghapus (misal, pesan terlalu lama)
			log.Printf("WARNING: Gagal menghapus pesan ID %d di chat %d: %v", messageID, chatID, err)
		}
	}
}

// resetState menghapus state dan data sementara pengguna
func resetState(userID int64) {
	delete(userStates, userID)
	delete(tempUserData, userID)
}

// ==========================================
// Validation & Config Helpers
// ==========================================

func validateUsername(bot *tgbotapi.BotAPI, chatID int64, text string) bool {
	if len(text) < 3 || len(text) > 20 {
		sendMessage(bot, chatID, "❌ Password harus **3-20 karakter**. Coba lagi:")
		return false
	}
	// Regex yang lebih ketat: hanya huruf, angka, - dan _
	if !regexp.MustCompile(`^[a-zA-Z0-9_-]+$`).MatchString(text) {
		sendMessage(bot, chatID, "❌ Password hanya boleh **huruf (A-Z, a-z), angka (0-9), strip (-), dan underscore (_)**. Coba lagi:")
		return false
	}
	return true
}

func validateNumber(bot *tgbotapi.BotAPI, chatID int64, text string, min, max int, fieldName string) (int, bool) {
	val, err := strconv.Atoi(text)
	if err != nil || val < min || val > max {
		sendMessage(bot, chatID, fmt.Sprintf("❌ %s harus angka positif **(%d-%d)**. Coba lagi:", fieldName, min, max))
		return 0, false
	}
	return val, true
}

func isAllowed(config *BotConfig, userID int64) bool {
	// Mode "public" diizinkan untuk semua, mode "private" hanya untuk AdminID
	return config.Mode == "public" || userID == config.AdminID
}

func saveConfig(config *BotConfig) error {
	data, err := json.MarshalIndent(config, "", "  ") // Menggunakan 2 spasi indent
	if err != nil {
		return err
	}
	// os.WriteFile adalah alias untuk ioutil.WriteFile, lebih modern
	return os.WriteFile(BotConfigFile, data, 0644)
}

func loadConfig() (BotConfig, error) {
	var config BotConfig
	
	// Gunakan os.ReadFile, lebih modern dari ioutil.ReadFile
	file, err := os.ReadFile(BotConfigFile)
	if err != nil {
		return config, err
	}
	
	if err = json.Unmarshal(file, &config); err != nil {
		return config, err
	}

	// Pastikan Domain dibaca, baik dari config atau file domain
	if config.Domain == "" {
		if domainBytes, err := os.ReadFile(DomainFile); err == nil {
			config.Domain = strings.TrimSpace(string(domainBytes))
		}
	}

	return config, nil
}

// ==========================================
// API Client
// ==========================================

func apiCall(method, endpoint string, payload interface{}) (map[string]interface{}, error) {
	if ApiKey == "" {
		return nil, fmt.Errorf("API Key belum dimuat. Cek file %s", ApiKeyFile)
	}
	
	var reqBody []byte
	var err error

	if payload != nil {
		reqBody, err = json.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("gagal marshal payload: %w", err)
		}
	}

	client := &http.Client{Timeout: 10 * time.Second} // Tambahkan timeout
	req, err := http.NewRequest(method, ApiUrl+endpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, fmt.Errorf("gagal membuat request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", ApiKey)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request API gagal: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("respon API status code %d. Body: %s", resp.StatusCode, string(body))
	}

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("gagal unmarshal respon API: %w", err)
	}

	return result, nil
}

func getIpInfo() (IpInfo, error) {
	// Timeout untuk permintaan eksternal
	client := http.Client{Timeout: 5 * time.Second} 
	resp, err := client.Get("http://ip-api.com/json/")
	if err != nil {
		log.Printf("ERROR: Gagal fetching IP info: %v", err)
		// Return IpInfo kosong dengan error
		return IpInfo{City: "N/A", Isp: "N/A", Query: "N/A"}, err
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return IpInfo{City: "N/A", Isp: "N/A", Query: "N/A"}, fmt.Errorf("status code ip-api: %d", resp.StatusCode)
	}

	var info IpInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return IpInfo{City: "N/A", Isp: "N/A", Query: "N/A"}, err
	}
	return info, nil
}

// getUsers dan showUserSelection (dihilangkan untuk fokus pada perbaikan utama)
// ...