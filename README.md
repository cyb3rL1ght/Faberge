# Kiosk Menu System for "Faberge" Canteen

## 📖 Overview

This is a digital kiosk menu system designed for the "Faberge" canteen. It displays an interactive menu on two monitors simultaneously:
- **Left Monitor**: Shows salads, main dishes (split into two columns), and **COMBO** offers
- **Right Monitor**: Shows soups, sides, drinks, and **SET** offers (Набор 1, 2, 3)

The system runs in kiosk mode using Chromium browsers controlled by Openbox window manager on Ubuntu Server.

---

## 🏗️ Architecture

### Frontend Components

| File | Description |
|------|-------------|
| `menu-left.html` | Left monitor page with salads, mains, and combo cards |
| `menu-right.html` | Right monitor page with soups, sides, drinks, and set cards |
| `styles.css` | Centralized styling with CSS variables for easy customization |
| `scripts.js` | Menu logic, CSV parsing, and dynamic card generation |
| `menu.csv` | Menu data source (items, categories, prices, combo/set assignments) |

### Backend & Infrastructure

| Component | Purpose |
|-----------|---------|
| **Nginx** | Serves static HTML/CSS/JS files from `/var/www/faberge` |
| **Chromium** | Runs in kiosk mode displaying the menu pages |
| **Openbox** | Lightweight window manager for positioning browser windows |
| **hostapd + dnsmasq** | Wi-Fi hotspot for customer access |
| **systemd** | Manages autologin and service startup |

---

## ⚙️ Configuration Variables

### CSS Variables (`styles.css`)

All visual parameters are configurable via CSS custom properties in the `:root` section:

#### Card Styling
```css
--card-text-color: #1F233C;        /* Text color for all cards */
--card-border-color: #1F233C;      /* Border color for cards */
--card-label-bg-color: #1F233C;    /* Background for side labels (КОМБО/НАБОР) */
```

#### Item Names
```css
--item-name-color: #1F233C;        /* Color of dish names */
--item-name-font-size: 2.2vh;      /* Font size of dish names */
```

#### Prices
```css
--item-price-color: #D63031;       /* Color of prices */
--item-price-font-size: 3vh;       /* Price font size in regular menu items */
--combo-price-font-size: 7vh;      /* Price font size in COMBO cards */
--set-price-font-size: 7vh;        /* Price font size in SET cards */
```

#### Layout
```css
--item-vertical-padding: 0.5vh;    /* Vertical spacing between menu items */
--menu-grid-gap: 2vh;              /* Gap between menu columns */
--column-padding: 2vh 2.5vh;       /* Internal padding of columns */
```

#### Working Hours
```css
--working-hours-text: "Пн–Пт: 11:00–16:00 | Сб: 11:00–15:00";
--working-hours-color: #ffffff;
--working-hours-font-size: 2.2vh;
```

---

## 📦 Installation

### Prerequisites

- Ubuntu Server 24.04 LTS
- Two monitors connected to the system
- Wi-Fi adapter supporting AP mode (for hotspot functionality)
- Root/sudo access

### Quick Install

Run the installation script with sudo:

```bash
sudo bash install_kiosk.sh
```

The script will:
1. Update the system and install required packages (nginx, Xorg, Openbox, Chromium, hostapd, dnsmasq)
2. Configure nginx to serve files from `/var/www/faberge`
3. Set up autologin for the kiosk user on TTY1
4. Configure automatic X session start with dual-monitor support
5. Set up Wi-Fi hotspot with predefined SSID and password
6. Create systemd services for network and hotspot management

### Manual Installation Steps

If you prefer manual setup:

#### 1. Install Dependencies
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx xorg openbox unclutter wmctrl curl net-tools \
    network-manager nano iputils-ping dnsutils git wireless-tools \
    hostapd dnsmasq
sudo snap install chromium
```

#### 2. Deploy Web Files
```bash
sudo mkdir -p /var/www/faberge
sudo cp menu-left.html menu-right.html styles.css scripts.js menu.csv /var/www/faberge/
sudo chown -R www-data:www-data /var/www/faberge
```

#### 3. Configure Nginx
Create `/etc/nginx/sites-available/faberge.conf`:
```nginx
server {
    listen 80;
    server_name _;
    root /var/www/faberge;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
}
```
Enable the site:
```bash
sudo ln -sf /etc/nginx/sites-available/faberge.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
```

#### 4. Configure Autologin
Create `/etc/systemd/system/getty@tty1.service.d/autologin.conf`:
```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin <YOUR_USER> --noclear %I $TERM
```

#### 5. Configure X Session
Add to `~/.profile`:
```bash
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
```

Create `~/.xinitrc` with dual-monitor Chromium setup (see `install_kiosk.sh` for full example).

---

## 🍽️ Menu Data Format (`menu.csv`)

The menu is defined in a CSV file with the following structure:

```csv
цель;Категория;Наименование;Порция;Цена
комбо;Салаты;ОЛИВЬЕ;1/100;180
набор 1;Салаты;МОРКОВЬ С ЧЕСНОКОМ;1/100;120
;Салаты;ВИНЕГРЕТ;1/100;120
```

### Column Descriptions

| Column | Description | Example Values |
|--------|-------------|----------------|
| **цель** | Assignment to combo/set or empty for regular menu | `комбо`, `набор 1`, `набор 2`, `набор 3`, or empty |
| **Категория** | Menu category | `Салаты`, `Первые блюда`, `Вторые блюда`, `Гарниры`, `Напитки` |
| **Наименование** | Dish name | `ОЛИВЬЕ`, `БОРЩ`, `ШНИЦЕЛЬ` |
| **Порция** | Portion size | `1/100`, `1/350`, `1 ст.` |
| **Цена** | Price in rubles | `180`, `250`, `90` |

### Combo/Set Logic

- Items marked with `комбо` in the first column are grouped into a **COMBO** card displayed on the left monitor
- Items marked with `набор 1`, `набор 2`, or `набор 3` are grouped into corresponding **SET** cards on the right monitor
- The total price for each combo/set is calculated automatically as the sum of all included items
- Regular menu items (empty first column) appear in their respective category columns

---

## 🎨 Customization Guide

### Changing Colors

Edit the CSS variables in `styles.css`:

```css
:root {
  --price: #d63031;              /* Accent color for prices */
  --card-text-color: #1F233C;    /* Main text color in cards */
  --item-name-color: #1F233C;    /* Dish name color */
}
```

### Adjusting Font Sizes

Modify these variables to control typography:

```css
--item-name-font-size: 2.2vh;    /* Dish names */
--item-price-font-size: 3vh;     /* Regular menu prices */
--combo-price-font-size: 7vh;    /* COMBO card prices */
--set-price-font-size: 7vh;      /* SET card prices */
--working-hours-font-size: 2.2vh; /* Working hours text */
```

### Modifying Combo/Set Prices Independently

You can now set different font sizes for COMBO and SET cards:

```css
/* Larger price font for combos */
--combo-price-font-size: 8vh;

/* Smaller price font for sets */
--set-price-font-size: 6vh;
```

### Updating Working Hours

Change the working hours display by modifying the CSS variable:

```css
--working-hours-text: "Пн–Пт: 09:00–18:00 | Сб: 10:00–16:00";
```

Or update directly in the HTML files if needed.

### Adding New Menu Categories

1. Add new category names to `menu.csv`
2. Create corresponding container elements in HTML files
3. Update the category detection logic in `scripts.js`

---

## 🔧 Troubleshooting

### Common Issues

#### Monitors Not Displaying Correctly
- Check that both monitors are detected: `xrandr`
- Verify screen resolution settings in `.xinitrc`
- Ensure window titles match: `<title>Menu_Left</title>` and `<title>Menu_Right</title>`

#### Wi-Fi Hotspot Not Working
- Verify Wi-Fi interface name: `ip link`
- Update `WIFI_IFACE` in `install_kiosk.sh`
- Check hostapd status: `sudo systemctl status hostapd`

#### Menu Not Loading
- Ensure nginx is running: `sudo systemctl status nginx`
- Check file permissions in `/var/www/faberge`
- Verify CSV format (semicolon-separated, UTF-8 encoding)

#### Browser Crashes
- Clear Chromium cache directories: `~/.config/chromium_1`, `~/.config/chromium_2`
- Check system resources (RAM, CPU)
- Review Chromium logs: `journalctl -u chromium`

### Logs and Diagnostics

```bash
# Nginx logs
sudo tail -f /var/log/nginx/error.log

# Systemd service status
sudo systemctl status nginx hostapd dnsmasq

# X session logs
cat ~/.xsession-errors

# Network configuration
ip addr show
netplan get all
```

---

## 🛠️ Maintenance

### Updating Menu

Simply edit `menu.csv` and refresh the browser (Ctrl+R) or wait for auto-refresh (every 5 minutes).

### Backup Configuration

```bash
# Backup important configs
sudo cp /etc/nginx/sites-available/faberge.conf ~/backup/
sudo cp /etc/hostapd/hostapd.conf ~/backup/
sudo cp /etc/dnsmasq.conf ~/backup/
cp ~/.xinitrc ~/backup/
```

### System Updates

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

---

## 📋 Technical Specifications

### Hardware Requirements
- **CPU**: Dual-core processor or better
- **RAM**: Minimum 4GB (8GB recommended)
- **Storage**: 16GB minimum
- **Graphics**: Support for dual monitors
- **Network**: Ethernet + Wi-Fi adapter with AP support

### Software Stack
- **OS**: Ubuntu Server 24.04 LTS
- **Web Server**: Nginx 1.24+
- **Browser**: Chromium (snap package)
- **Window Manager**: Openbox
- **Hotspot**: hostapd + dnsmasq

### Network Configuration
- **Hotspot SSID**: FABERGE_WIFI (customizable)
- **Hotspot Password**: A_123456A (customizable)
- **Subnet**: 192.168.50.0/24
- **DHCP Range**: 192.168.50.10 – 192.168.50.50

---

## 📄 License

This project is proprietary software developed for "Faberge" canteen. All rights reserved.

---

## 👥 Support

For technical support or customization requests, contact the development team.

---

**Last Updated**: 2024
**Version**: 1.0
