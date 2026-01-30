# 🚀 پنل مدیریت پیشرفته SSH (نصب سریع)

برای نصب کامل پیش‌نیازها و فعال‌سازی پنل مدیریت فقط کافیست دستور زیر را کپی و در ترمینال اجرا کنید:

```bash
sudo apt update && sudo apt install -y python3 python3-flask bc vnstat curl && ufw allow 5000/tcp && ufw allow 443/tcp && curl -Ls [https://raw.githubusercontent.com/rima0222/ssh-management/main/install.sh](https://raw.githubusercontent.com/rima0222/ssh-management/main/install.sh) | bash
