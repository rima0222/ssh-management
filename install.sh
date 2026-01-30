#!/bin/bash

# --- تنظیمات ---
DB_FILE="/root/users.db"
PORT_WEB=5000
ADMIN_USER="admin"
ADMIN_PASS="123456"
touch "$DB_FILE"

# --- تابع نصب خودکار پیش‌نیازها (اگر نصب نباشند) ---
prepare_system() {
    if ! command -v flask &> /dev/null; then
        apt update && apt install -y python3 python3-flask bc vnstat curl
        ufw allow 5000/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
}

# --- بقیه توابع (مانیتورینگ و غیره) ---
check_status() {
    tmp_db=$(mktemp)
    while IFS='|' read -r user exp limit pass used status; do
        if [ "$status" == "disabled" ]; then
            skill -u "$user" 2>/dev/null; usermod -L "$user" 2>/dev/null
            echo "$user|$exp|$limit|$pass|$used|disabled" >> "$tmp_db"
            continue
        fi
        added_usage=0
        if pgrep -u "$user" > /dev/null; then added_usage=2; fi 
        new_used=$((used + added_usage))
        limit_mb=$((limit * 1024))
        if [ "$new_used" -ge "$limit_mb" ] || [ "$(date +%s)" -gt "$(date -d "$exp" +%s)" ]; then
            skill -u "$user" 2>/dev/null; usermod -L "$user" 2>/dev/null
            current_status="expired"
        else
            usermod -U "$user" 2>/dev/null; current_status="active"
        fi
        echo "$user|$exp|$limit|$pass|$new_used|$current_status" >> "$tmp_db"
    done < "$DB_FILE"
    mv "$tmp_db" "$DB_FILE"
}

run_web() {
    # کد پایتون پنل وب (همان کدی که قبلاً دادم با تمام قابلیت‌های آپلود/دانلود)
    cat <<EOF > /root/web_panel.py
from flask import Flask, render_template_string, request, redirect, send_file, session
import subprocess, os
app = Flask(__name__)
app.secret_key = 'ssh_secret'
DB_FILE = "$DB_FILE"

# قالب HTML (خلاصه شده برای پاسخ - شامل فرم افزودن و دکمه‌های بک‌آپ)
HTML = '''...''' # همان کد کامل پیام قبلی را اینجا قرار دهید

@app.route('/')
def login(): return '''...''' # صفحه ورود

@app.route('/panel')
def panel():
    with open(DB_FILE, "r") as f: users = [l.strip().split('|') for l in f if l.strip()]
    return render_template_string(HTML, users=users)

# بقیه Route ها برای Save, Delete, Backup
if __name__ == '__main__': app.run(host='0.0.0.0', port=$PORT_WEB)
EOF
    pkill -f web_panel.py
    nohup python3 /root/web_panel.py > /dev/null 2>&1 &
}

case $1 in
    cron) check_status ;;
    add_api)
        # رفع ارور Internal Server Error: اطمینان از وجود فایل و دسترسی
        userdel -f "$2" 2>/dev/null
        exp_date=$(date -d "+$4 days" +%Y-%m-%d)
        useradd -m -s /usr/sbin/nologin -e "$exp_date" "$2"
        echo "$2:$3" | chpasswd
        echo "$2|$exp_date|$5|$3|0|active" >> "$DB_FILE"
        ;;
    # سایر کیس‌ها (del_api, reset_api و غیره)
    *)
        prepare_system
        cp "$0" /root/install.sh
        chmod +x /root/install.sh
        (crontab -l 2>/dev/null | grep -q "install.sh") || (crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash /root/install.sh cron > /dev/null 2>&1") | crontab -
        run_web
        echo "✅ نصب کامل شد. پنل روی پورت ۵۰۰۰ فعال است."
        ;;
esac
