#!/bin/bash

DB_FILE="/root/users.db"
PORT_WEB=5000

touch "$DB_FILE"

# --- توابع سیستمی ---
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

restore_all() {
    while IFS='|' read -r user exp limit pass used status; do
        if ! id "$user" &>/dev/null; then
            useradd -m -s /usr/sbin/nologin -e "$exp" "$user"
            echo "$user:$pass" | chpasswd
            echo "$user hard maxlogins 1" >> /etc/security/limits.conf
            [ "$status" == "disabled" ] && usermod -L "$user"
        fi
    done < "$DB_FILE"
}

# --- پنل وب (پایتون) ---
run_web() {
    cat <<EOF > /root/web_panel.py
from flask import Flask, render_template_string, request, redirect, send_file
import subprocess, os

app = Flask(__name__)
DB_FILE = "$DB_FILE"

HTML = '''
<!DOCTYPE html>
<html dir="rtl"><head><meta charset="UTF-8"><title>SSH Pro Sync Panel</title>
<style>
    body { font-family: Tahoma; background: #f4f7f6; padding: 20px; }
    .container { max-width: 1000px; margin: auto; background: white; padding: 20px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; }
    th, td { border: 1px solid #eee; padding: 10px; text-align: center; }
    th { background: #2c3e50; color: white; }
    .btn { padding: 6px 12px; border-radius: 4px; border: none; cursor: pointer; color: white; text-decoration: none; font-size: 12px; margin: 2px; }
    .btn-add { background: #27ae60; font-size: 14px; }
    .btn-del { background: #e74c3c; } .btn-reset { background: #3498db; } .btn-toggle { background: #f39c12; }
    .upload-section { background: #e8f4fd; padding: 15px; border-radius: 8px; margin-top: 20px; border: 1px dashed #3498db; }
    input { padding: 8px; margin: 5px; border: 1px solid #ddd; border-radius: 4px; }
</style></head>
<body><div class="container">
    <h2>🚀 مدیریت کاربران و جابه‌جایی سرور</h2>
    <table>
        <tr><th>کاربر</th><th>انقضا</th><th>حجم</th><th>مصرف</th><th>باقی‌مانده</th><th>وضعیت</th><th>عملیات</th></tr>
        {% for u in users %}
        {% set limit_mb = u[2]|int * 1024 %}{% set rem = limit_mb - u[4]|int %}
        <tr>
            <td><b>{{ u[0] }}</b></td><td>{{ u[1] }}</td><td>{{ u[2] }} GB</td><td>{{ u[4] }} MB</td>
            <td style="color: {{ 'red' if rem <= 0 else 'green' }}">{{ rem if rem > 0 else 0 }} MB</td>
            <td>{{ '✅ فعال' if u[5] == 'active' else '❌ غیرفعال' if u[5] == 'disabled' else '⏰ منقضی' }}</td>
            <td>
                <a href="/reset/{{ u[0] }}" class="btn btn-reset">ریست حجم</a>
                <a href="/toggle/{{ u[0] }}" class="btn btn-toggle">قطع/وصل</a>
                <a href="/delete/{{ u[0] }}" class="btn btn-del">حذف</a>
            </td>
        </tr>{% endfor %}
    </table>
    <hr>
    <form action="/save" method="post">
        <input type="text" name="u" placeholder="نام کاربری" required>
        <input type="text" name="p" placeholder="رمز" required>
        <input type="number" name="d" placeholder="روز" required>
        <input type="number" name="v" placeholder="حجم (GB)" required>
        <button type="submit" class="btn btn-add">ذخیره کاربر جدید / ویرایش</button>
    </form>
    
    <div class="upload-section">
        <h3>🔄 جابه‌جایی سرور (بک‌آپ و ریستور)</h3>
        <a href="/backup_file" class="btn btn-reset" style="padding: 10px;">📥 ۱. دانلود فایل بک‌آپ (users.db)</a>
        <br><br>
        <form action="/upload" method="post" enctype="multipart/form-data">
            <label><b>۲. آپلود فایل در سرور جدید:</b></label>
            <input type="file" name="file" accept=".db" required>
            <button type="submit" class="btn btn-toggle" style="background: #8e44ad;">⬆️ آپلود و بازیابی کاربران</button>
        </form>
    </div>
</div></body></html>
'''

@app.route('/')
def index():
    if not os.path.exists(DB_FILE): return "Database not found"
    with open(DB_FILE, "r") as f: users = [l.strip().split('|') for l in f if l.strip()]
    return render_template_string(HTML, users=users)

@app.route('/save', methods=['POST'])
def save():
    subprocess.run(["/root/ssh-pro.sh", "add_api", request.form['u'], request.form['p'], request.form['d'], request.form['v']])
    return redirect('/')

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']
    if file:
        file.save(DB_FILE)
        subprocess.run(["/root/ssh-pro.sh", "restore"])
        return "✅ فایل با موفقیت آپلود شد و تمام کاربران در این سرور ساخته شدند. <a href='/'>بازگشت به پنل</a>"

@app.route('/backup_file')
def backup_file(): return send_file(DB_FILE, as_attachment=True)

@app.route('/delete/<u_str>')
def delete(u_str): subprocess.run(["/root/ssh-pro.sh", "del_api", u_str]); return redirect('/')

@app.route('/reset/<u_str>')
def reset(u_str): subprocess.run(["/root/ssh-pro.sh", "reset_api", u_str]); return redirect('/')

@app.route('/toggle/<u_str>')
def toggle(u_str): subprocess.run(["/root/ssh-pro.sh", "toggle_api", u_str]); return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$PORT_WEB)
EOF
    pkill -f web_panel.py
    nohup python3 /root/web_panel.py > /dev/null 2>&1 &
}

# --- مدیریت دستورات ---
case $1 in
    cron) check_status ;;
    add_api)
        sed -i "/^$2|/d" "$DB_FILE"
        userdel -f "$2" 2>/dev/null
        exp_date=$(date -d "+$4 days" +%Y-%m-%d)
        useradd -m -s /usr/sbin/nologin -e "$exp_date" "$2"
        echo "$2:$3" | chpasswd
        echo "$2 hard maxlogins 1" >> /etc/security/limits.conf
        echo "$2|$exp_date|$5|$3|0|active" >> "$DB_FILE"
        ;;
    del_api) sed -i "/^$2|/d" "$DB_FILE"; userdel -f "$2" 2>/dev/null ;;
    reset_api) sed -i "/^$2|/s/|[0-9]*|active/|0|active/; /^$2|/s/|[0-9]*|expired/|0|active/" "$DB_FILE"; usermod -U "$2" 2>/dev/null ;;
    toggle_api)
        line=$(grep "^$2|" "$DB_FILE")
        if [[ "$line" == *"|active" ]]; then
            sed -i "/^$2|/s/|active/|disabled/" "$DB_FILE"
            skill -u "$2" 2>/dev/null; usermod -L "$2" 2>/dev/null
        else
            sed -i "/^$2|/s/|disabled/|active/; /^$2|/s/|expired/|active/" "$DB_FILE"
            usermod -U "$2" 2>/dev/null
        fi ;;
    restore) restore_all ;;
    *) run_web; echo "🚀 پنل اجرا شد: http://YOUR_IP:5000" ;;
esac
