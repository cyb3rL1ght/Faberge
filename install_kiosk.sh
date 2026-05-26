#!/bin/bash
#===============================================================================
# Скрипт установки киоска меню для столовой «Фаберже»
# Версия: 1.0
# ОС: Ubuntu Server 24.04
# Описание: Автоматическая установка и настройка системы отображения меню
#           на двух мониторах с разным разрешением
#===============================================================================

set -e

#================================================================================
# НАСТРОЙКИ (МОЖНО МЕНЯТЬ ПОД СЕБЯ)
#================================================================================

# Разрешения экранов
SCREEN_0_W=1280   # Ширина левого экрана
SCREEN_0_H=1024   # Высота левого экрана
SCREEN_1_W=1920   # Ширина правого экрана
SCREEN_1_H=1080   # Высота правого экрана

# Путь к конфигурации Nginx
NGINX_CONF="/etc/nginx/sites-available/faberge.conf"

# URL репозитория
REPO_URL="https://github.com/cyb3rL1ght/Faberge"
REPO_DIR="$HOME/Faberge"

# Корневая директория веб-сервера
WEB_ROOT="/var/www/faberge"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#================================================================================
# ФУНКЦИИ
#================================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Этот скрипт необходимо запускать от имени root (через sudo)"
        log_error "Пример: sudo ./install_kiosk.sh"
        exit 1
    fi
    log_success "Проверка прав root пройдена"
}

get_user_info() {
    # Получаем имя пользователя, от которого запущен скрипт через sudo
    KIOSK_USER="${SUDO_USER:-$USER}"
    KIOSK_HOME=$(eval echo ~$KIOSK_USER)
    
    log_info "Пользователь киоска: $KIOSK_USER"
    log_info "Домашняя директория: $KIOSK_HOME"
}

update_system() {
    log_info "Обновление списков пакетов..."
    apt update -qq
    
    log_info "Обновление установленных пакетов..."
    apt upgrade -y -qq
    
    log_success "Система обновлена"
}

install_packages() {
    log_info "Установка необходимых пакетов..."
    
    apt install -y -qq nginx xorg openbox \
        unclutter wmctrl curl net-tools network-manager \
        nano iputils-ping dnsutils git xdotool
    
    log_success "Пакеты установлены"
}

install_chromium() {
    log_info "Установка Chromium..."
    
    # Пробуем установить через snap сначала
    if command -v snap >/dev/null 2>&1; then
        snap install chromium
    else
        # Если snap недоступен, устанавливаем через apt
        log_warning "Snap не найден, устанавливаем Chromium через apt..."
        apt install -y -qq chromium-browser
    fi
    
    log_success "Chromium установлен"
}

configure_nginx() {
    log_info "Настройка Nginx..."
    
    # Включаем и запускаем Nginx
    systemctl enable nginx
    systemctl restart nginx
    
    # Создаем директорию для веб-файлов
    mkdir -p "$WEB_ROOT"
    
    # Создаем конфигурационный файл Nginx
    if [ ! -f "$NGINX_CONF" ]; then
        cat > "$NGINX_CONF" << 'NGINX_EOF'
server {
    listen 80;
    server_name _;

    # Корневая директория сайта
    root /var/www/faberge;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX_EOF
        
        log_info "Конфигурация Nginx создана: $NGINX_CONF"
    else
        log_warning "Конфигурация Nginx уже существует"
    fi
    
    # Создаем символическую ссылку в sites-enabled
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/faberge.conf 2>/dev/null || true
    
    # Удаляем дефолтную конфигурацию если есть
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Проверяем конфигурацию и перезапускаем Nginx
    if nginx -t; then
        systemctl restart nginx
        log_success "Nginx настроен и перезапущен"
    else
        log_error "Ошибка в конфигурации Nginx"
        exit 1
    fi
}

clone_repository() {
    log_info "Клонирование репозитория..."
    
    # Клонируем репозиторий в домашнюю директорию пользователя
    if [ ! -d "$REPO_DIR" ]; then
        su - "$KIOSK_USER" -c "git clone $REPO_URL $REPO_DIR"
        log_success "Репозиторий склонирован в $REPO_DIR"
    else
        log_warning "Репозиторий уже существует"
        # Обновляем репозиторий
        su - "$KIOSK_USER" -c "cd $REPO_DIR && git pull"
        log_success "Репозиторий обновлен"
    fi
    
    # Копируем файлы из репозитория в веб-директорию
    log_info "Копирование файлов в веб-директорию..."
    cp -r "$REPO_DIR"/* "$WEB_ROOT"/ 2>/dev/null || true
    cp -r "$REPO_DIR"/.[!.]* "$WEB_ROOT"/ 2>/dev/null || true
    
    # Устанавливаем правильные права доступа
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"
    
    log_success "Файлы скопированы в $WEB_ROOT"
}

configure_xwrapper() {
    log_info "Настройка Xwrapper.config..."
    
    # Разрешаем запуск X любому пользователю
    echo "allowed_users=anybody" > /etc/X11/Xwrapper.config
    
    log_success "Xwrapper.config настроен"
}

configure_autologin() {
    log_info "Настройка автологина для пользователя $KIOSK_USER..."
    
    # Создаем директорию для override файла systemd
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    
    # Создаем файл автологина
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF
    
    # Перезагружаем systemd и включаем службу
    systemctl daemon-reload
    systemctl enable getty@tty1.service
    
    log_success "Автологин настроен"
}

configure_profile() {
    log_info "Настройка автозапуска startx в .profile..."
    
    # Проверяем, есть ли уже запись в .profile
    if ! grep -q "exec startx" "$KIOSK_HOME/.profile" 2>/dev/null; then
        cat >> "$KIOSK_HOME/.profile" << 'PROFILE_EOF'

# Автозапуск графической сессии киоска на TTY1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx
fi
PROFILE_EOF
        
        log_success ".profile обновлен"
    else
        log_warning "Запись автозапуска уже существует в .profile"
    fi
    
    # Возвращаем права на .profile
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.profile"
}

configure_xinitrc() {
    log_info "Настройка .xinitrc..."
    
    XINITRC_FILE="$KIOSK_HOME/.xinitrc"
    
    # Создаем файл .xinitrc
    cat > "$XINITRC_FILE" << XINITRC_EOF
#!/bin/bash
# Базовые настройки дисплея
xset s off -dpms
xset s noblank

# Прячем курсор
which unclutter && unclutter -idle 0.1 -root &

# Openbox
openbox-session &
sleep 2

# === ЛЕВОЕ окно (Монитор 1) ===
chromium \\
  --kiosk \\
  --app=http://localhost/menu-left.html \\
  --user-data-dir=\$HOME/.config/chromium_1 \\
  --no-first-run --noerrdialogs --disable-infobars \\
  --disable-session-crashed-bubble --disable-translate --disable-pinch \\
  --overscroll-history-navigation=0 \\
  --incognito --disable-cache --disk-cache-dir=/dev/null --disk-cache-size=1 \\
  --autoplay-policy=no-user-gesture-required &

sleep 1

# === ПРАВОЕ окно (Монитор 2) ===
chromium \\
  --kiosk \\
  --app=http://localhost/menu-right.html \\
  --user-data-dir=\$HOME/.config/chromium_2 \\
  --no-first-run --noerrdialogs --disable-infobars \\
  --disable-session-crashed-bubble --disable-translate --disable-pinch \\
  --overscroll-history-navigation=0 \\
  --incognito --disable-cache --disk-cache-dir=/dev/null --disk-cache-size=1 \\
  --autoplay-policy=no-user-gesture-required &

sleep 6

# Позиционируем окна через wmctrl
# Левый экран: Menu_Left
wmctrl -r "Menu_Left" -e 0,0,0,$SCREEN_0_W,$SCREEN_0_H 2>/dev/null || true

# Правый экран: Menu_Right (начинается после левого экрана)
wmctrl -r "Menu_Right" -e 0,$SCREEN_0_W,0,$SCREEN_1_W,$SCREEN_1_H 2>/dev/null || true

wait
XINITRC_EOF
    
    # Делаем файл исполняемым
    chmod +x "$XINITRC_FILE"
    
    # Устанавливаем правильные права
    chown "$KIOSK_USER:$KIOSK_USER" "$XINITRC_FILE"
    
    log_success ".xinitrc настроен"
}


print_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
    echo "==============================================================================="
    echo ""
    echo "Что было сделано:"
    echo "  ✓ Система обновлена"
    echo "  ✓ Установлены все необходимые пакеты (nginx, xorg, openbox, chromium)"
    echo "  ✓ Склонирован репозиторий: $REPO_URL"
    echo "  ✓ Файлы скопированы в: $WEB_ROOT"
    echo "  ✓ Настроен Nginx"
    echo "  ✓ Настроен автологин для пользователя: $KIOSK_USER"
    echo "  ✓ Настроен автозапуск графической сессии"
    echo ""
    echo "Настройки дисплеев:"
    echo "  • Левый монитор: ${SCREEN_0_W}x${SCREEN_0_H}"
    echo "  • Правый монитор: ${SCREEN_1_W}x${SCREEN_1_H}"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo -e "${YELLOW}СЛЕДУЮЩИЕ ШАГИ:${NC}"
    echo "-------------------------------------------------------------------------------"
    echo "1. Перезагрузите систему командой: sudo reboot"
    echo ""
    echo "2. После перезагрузки система автоматически:"
    echo "   - Выполнит вход под пользователем: $KIOSK_USER"
    echo "   - Запустит графическую сессию"
    echo "   - Откроет два окна Chromium в режиме киоска:"
    echo "     * Левый экран: http://localhost/menu-left.html"
    echo "     * Правый экран: http://localhost/menu-right.html"
    echo ""
    echo "3. Для проверки работы веб-сервера откройте в браузере:"
    echo "   http://localhost/"
    echo ""
    echo "4. Файлы меню находятся в: $WEB_ROOT"
    echo "   Для редактирования меню отредактируйте файл: $WEB_ROOT/menu.csv"
    echo ""
    echo "5. Для настройки расположения мониторов используйте команду:"
    echo "   DISPLAY=:0 xrandr"
    echo "   Пример настройки: xrandr --output HDMI-1 --mode 1280x1024 --pos 0x0 \\"
    echo "                     --output HDMI-2 --mode 1920x1080 --pos 1280x0"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo -e "${YELLOW}ПОЛЕЗНЫЕ КОМАНДЫ:${NC}"
    echo "-------------------------------------------------------------------------------"
    echo "• Перезапустить Nginx: sudo systemctl restart nginx"
    echo "• Статус Nginx: sudo systemctl status nginx"
    echo "• Просмотр логов Nginx: sudo tail -f /var/log/nginx/error.log"
    echo "• Перезапустить графическую сессию: pkill xinit && startx"
    echo "• Выйти из графической сессии: Ctrl+Alt+Backspace"
    echo "• Переключиться на консоль: Ctrl+Alt+F2 (F3, F4...)"
    echo "• Вернуться в графику: Ctrl+Alt+F1"
    echo ""
    echo "==============================================================================="
}

#================================================================================
# ОСНОВНОЙ СЦЕНАРИЙ
#================================================================================

main() {
    echo ""
    echo "==============================================================================="
    echo "  Установка киоска меню для столовой «Фаберже»"
    echo "  Ubuntu Server 24.04"
    echo "==============================================================================="
    echo ""
    
    # Проверка прав root
    check_root
    
    # Получение информации о пользователе
    get_user_info
    
    # Обновление системы
    update_system
    
    # Установка пакетов
    install_packages
    
    # Установка Chromium
    install_chromium
    
    # Настройка Nginx
    configure_nginx
    
    # Клонирование репозитория
    clone_repository
    
    # Настройка Xwrapper
    configure_xwrapper
    
    # Настройка автологина
    configure_autologin
    
    # Настройка .profile
    configure_profile
    
    # Настройка .xinitrc
    configure_xinitrc
    
    # Вывод итоговой информации
    print_summary
}

# Запуск основной функции
main
