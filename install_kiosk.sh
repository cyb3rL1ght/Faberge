#!/bin/bash
# ============================================================================
# Скрипт автоматической настройки Kiosk-системы на Ubuntu Server 24.04
#
# Что делает:
#   1. Ставит нужные пакеты (nginx, Xorg, Openbox, Chromium, hostapd и т.д.)
#   2. Настраивает nginx на раздачу страниц из /var/www/faberge
#   3. Делает автологин пользователя в TTY1 и автозапуск графики
#   4. Запускает ДВА окна Chromium в kiosk-режиме на двух мониторах
#   5. Поднимает Wi-Fi точку доступа (hotspot)
#
# Запуск:  sudo bash setup-kiosk.sh
# ============================================================================

set -e   # прерывать скрипт при любой ошибке

# ========================== НАСТРОЙКИ (меняйте под себя) ====================
KIOSK_USER="${SUDO_USER:-$USER}"                 # пользователь киоска
KIOSK_HOME=$(eval echo ~"$KIOSK_USER")           # его домашняя папка
NGINX_CONF="/etc/nginx/sites-available/faberge.conf"
WEB_ROOT="/var/www/faberge"

# Разрешения экранов (левый и правый мониторы)
SCREEN_0_W=1280
SCREEN_0_H=1024
SCREEN_1_W=1920
SCREEN_1_H=1080

# Wi-Fi точка доступа
WIFI_IFACE="wlxf4f26d1bce7d"   # ← ОБЯЗАТЕЛЬНО ПОМЕНЯЙТЕ на своё (ip link)
SSID="FABERGE_WIFI"
WIFI_PASS="A_123456A"
WIFI_IP="192.168.50.1"
WIFI_NETMASK="24"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.50"
# ============================================================================

# --------------------------- Вспомогательные функции ------------------------
log_info()  { echo -e "\n\033[1;32m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERR]\033[0m   $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Скрипт нужно запускать через sudo:  sudo bash $0"
        exit 1
    fi
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log_error "Запустите от обычного пользователя через sudo (не от root напрямую)."
        log_error "Иначе KIOSK_USER будет root, и автологин сломается."
        exit 1
    fi
}
# ----------------------------------------------------------------------------

# ============================ 1. ОБНОВЛЕНИЕ И ПАКЕТЫ ========================
install_packages() {
    log_info "Обновление системы и установка пакетов..."
    apt update
    apt upgrade -y
    apt install -y \
        nginx xorg openbox unclutter wmctrl \
        curl net-tools network-manager nano \
        iputils-ping dnsutils git wireless-tools \
        hostapd dnsmasq

    # snap-пакеты
    if ! command -v snap >/dev/null 2>&1; then
        apt install -y snapd
    fi
    snap install chromium || log_warn "Chromium уже установлен или snap недоступен"
}
# ============================================================================

# ============================ 2. НАСТРОЙКА NGINX ============================
setup_nginx() {
    log_info "Настройка nginx (корень: $WEB_ROOT)..."
    mkdir -p "$WEB_ROOT"

    cat > "$NGINX_CONF" <<NGINX
server {
    listen 80;
    server_name _;

    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINX

    # Включаем наш конфиг, выключаем дефолтный
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    systemctl enable nginx
    nginx -t && systemctl restart nginx
}
# ============================================================================

# ============================ 3. РАЗРЕШАЕМ X-ОБЫЧНЫМ ЮЗЕРАМ ================
setup_xwrapper() {
    log_info "Настраиваем /etc/X11/Xwrapper.config (allowed_users=anybody)..."
    echo "allowed_users=anybody" > /etc/X11/Xwrapper.config
}
# ============================================================================

# ============================ 4. АВТОЛОГИН В TTY1 ===========================
setup_autologin() {
    log_info "Настраиваем автологин пользователя '$KIOSK_USER' на TTY1..."
    mkdir -p /etc/systemd/system/getty@tty1.service.d

    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

    systemctl daemon-reload
    systemctl enable getty@tty1.service
}
# ============================================================================

# ============================ 5. АВТОЗАПУСК X В .profile ====================
setup_profile() {
    log_info "Добавляем автозапуск startx в $KIOSK_HOME/.profile..."

    # Добавляем блок только если его ещё нет
    if ! grep -q "exec startx" "$KIOSK_HOME/.profile" 2>/dev/null; then
        cat >> "$KIOSK_HOME/.profile" <<'EOF'

# --- Автозапуск графической сессии киоска на TTY1 ---
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF
    else
        log_warn "Блок 'exec startx' уже есть в .profile — пропускаем"
    fi
}
# ============================================================================

# ============================ 6. СОЗДАЁМ .xinitrc ===========================
setup_xinitrc() {
    log_info "Создаём $KIOSK_HOME/.xinitrc (два Chromium на два экрана)..."

    # ВАЖНО: здесь НЕ используем кавычки у 'EOF', чтобы переменные
    # SCREEN_0_W и т.д. подставились прямо в файл.
    cat > "$KIOSK_HOME/.xinitrc" <<EOF
#!/bin/bash
# --------------------------------------------------
# Базовые настройки дисплея: выключаем скринсейвер и DPMS
# --------------------------------------------------
xset s off -dpms
xset s noblank

# Прячем курсор мыши (если unclutter установлен)
which unclutter && unclutter -idle 0.1 -root &

# Запускаем оконный менеджер Openbox
openbox-session &

# Функция умного ожидания окна по его заголовку
wait_for_window() {
    local title="\$1"
    local timeout=15
    local count=0
    
    echo "⏳ Ожидание окна: \$title..."
    
    while ! wmctrl -l | grep -qi "\$title"; do
        sleep 0.1
        count=\$((count + 1))
        if [ "\$count" -ge \$((timeout * 10)) ]; then
            echo "❌ Ошибка: Окно '\$title' не появилось за \$timeout сек."
            return 1
        fi
    done
    echo "✅ Окно '\$title' найдено!"
    return 0
}

# --------------------------------------------------
# ЛЕВОЕ окно Chromium (левый монитор)
# --------------------------------------------------
chromium \\
    --kiosk \\
    --app=http://localhost/menu-left.html \\
    --user-data-dir=\$HOME/.config/chromium_1 \\
    --no-first-run --noerrdialogs --disable-infobars \\
    --disable-session-crashed-bubble --disable-translate --disable-pinch \\
    --overscroll-history-navigation=0 \\
    --incognito --disable-cache --disk-cache-dir=/dev/null --disk-cache-size=1 \\
    --autoplay-policy=no-user-gesture-required &

if wait_for_window "Menu_Left"; then
    wmctrl -r "Menu_Left" -e 0,0,0,${SCREEN_0_W},${SCREEN_0_H} 2>/dev/null || true
fi

# --------------------------------------------------
# ПРАВОЕ окно Chromium (правый монитор)
# --------------------------------------------------
chromium \\
    --kiosk \\
    --app=http://localhost/menu-right.html \\
    --user-data-dir=\$HOME/.config/chromium_2 \\
    --no-first-run --noerrdialogs --disable-infobars \\
    --disable-session-crashed-bubble --disable-translate --disable-pinch \\
    --overscroll-history-navigation=0 \\
    --incognito --disable-cache --disk-cache-dir=/dev/null --disk-cache-size=1 \\
    --autoplay-policy=no-user-gesture-required &

if wait_for_window "Menu_Right"; then
    wmctrl -r "Menu_Right" -e 0,${SCREEN_0_W},0,${SCREEN_1_W},${SCREEN_1_H} 2>/dev/null || true
fi

wait
EOF

    chmod +x "$KIOSK_HOME/.xinitrc"
    chown "$KIOSK_USER":"$KIOSK_USER" "$KIOSK_HOME/.xinitrc"
}
# ============================================================================

# ============================ 7. НАСТРОЙКА NETPLAN ==========================
setup_netplan() {
    log_info "Настраиваем Netplan: отключаем DHCP на Wi-Fi интерфейсе $WIFI_IFACE..."

    cat > /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $WIFI_IFACE:
      dhcp4: false
      optional: true
EOF

    netplan apply || log_warn "netplan apply вернул ошибку (интерфейс может быть ещё не поднят)"
}
# ============================================================================

# ============================ 8. НАСТРОЙКА HOSTAPD (точка доступа) ==========
setup_hostapd() {
    log_info "Настраиваем hostapd (Wi-Fi точка доступа $SSID)..."

    cat > /etc/hostapd/hostapd.conf <<EOF
interface=$WIFI_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    if ! grep -q "^DAEMON_CONF=" /etc/default/hostapd; then
        echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
    fi

    systemctl unmask hostapd
    systemctl enable hostapd
}
# ============================================================================

# ============================ 9. НАСТРОЙКА DNSMASQ (DHCP для клиентов) ======
setup_dnsmasq() {
    log_info "Настраиваем dnsmasq (раздача IP клиентам Wi-Fi)..."

    if [ -f /etc/dnsmasq.conf ] && [ ! -f /etc/dnsmasq.conf.orig ]; then
        mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
    fi

    cat > /etc/dnsmasq.conf <<EOF
interface=$WIFI_IFACE
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h
port=0
EOF

    systemctl enable dnsmasq
}
# ============================================================================

# ============================ 10. СИСТЕМНЫЙ СЕРВИС HOTSPOT ==================
setup_hotspot_service() {
    log_info "Создаём systemd-сервис hotspot.service..."

    cat > /usr/local/bin/share-wifi-ip.sh <<EOF
#!/bin/bash
sleep 5
ip addr add ${WIFI_IP}/${WIFI_NETMASK} dev ${WIFI_IFACE} 2>/dev/null || true
systemctl restart hostapd dnsmasq
EOF
    chmod +x /usr/local/bin/share-wifi-ip.sh

    cat > /etc/systemd/system/hotspot.service <<'EOF'
[Unit]
Description=Force Static IP for USB Wi-Fi Hotspot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/share-wifi-ip.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hotspot.service
}
# ============================================================================

# ============================ 11. ФИНАЛЬНЫЕ ШТРИХИ ==========================
finalize() {
    log_info "Отключаем systemd-networkd-wait-online (часто мешает при Wi-Fi)..."
    systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

    log_info "Готово! Что дальше:"
    echo "  1. Положите ваши HTML-страницы в $WEB_ROOT"
    echo "     (menu-left.html с <title>Menu_Left</title>,"
    echo "      menu-right.html с <title>Menu_Right</title>)"
    echo "  2. Перезагрузите сервер:  sudo reboot"
    echo "  3. После ребута пользователь '$KIOSK_USER' автоматически"
    echo "     залогинится в TTY1 и запустит два Chromium на два экрана."
}
# ============================================================================

# ============================ ЗАПУСК ВСЕХ ШАГОВ =============================
main() {
    check_root
    install_packages
    setup_nginx
    setup_xwrapper
    setup_autologin
    setup_profile
    setup_xinitrc
    setup_netplan
    setup_hostapd
    setup_dnsmasq
    setup_hotspot_service
    finalize
}

main "$@"
