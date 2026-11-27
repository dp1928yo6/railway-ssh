# جعبه‌یٔ SSH روی Railway — root + کلید + ورود مستقیم

این پوشه یک سرویس آمادهٔ Railway است: یک کانتینر Debian که `sshd` را روی پورت **۲۲ داخلی** بالا می‌آورد،
ورود `root` با **کلید SSH** را می‌پذیرد و اطلاعات اتصال واقعی (دامنه و پورت Railway) را روی صفحهٔ ورود نشان می‌دهد.
هیچ چیزی روی سیستم خودت نصب نمی‌شود؛ هر پکیجی هم که لازم داشتی داخل خود سرور با `apt-get install` نصب می‌کنی.

---

## ۱) مهم: دربارهٔ پورت ۲۲

داخل کانتینر `sshd` روی پورت ۲۲ گوش می‌دهد و TCP Proxy هم به همان ۲۲ وصل می‌شود، اما
**Railway پورت عمومی را خودش تولید می‌کند و قابل انتخاب نیست** (دامنه را هم فقط می‌توانی با CNAME عوض کنی، پورت نه).
یعنی آدرس اتصال چیزی شبیه این می‌شود:

```
ssh -p 41234 root@roundhouse.proxy.rlwy.net
```

این پورت **ثابت** می‌ماند (تا وقتی TCP Proxy را حذف نکنی)، ولی عددش ۲۲ نیست. برای اینکه دستور اتصال «دقیقاً» مثل
`ssh myserver` باشد، از فایل `~/.ssh/config` استفاده می‌کنیم (بخش ۶). اگر واقعاً پورت ۲۲ روی یک دامنه می‌خواهی،
باید سروری با IP عمومی (VPS) یا یک Reverse Proxy روی VPS داشته باشی؛ Railway چنین امکانی نمی‌دهد.

---

## ۲) فایل‌های پروژه

| فایل | کار |
|---|---|
| `Dockerfile` | ایمیج Debian + `openssh-server` |
| `sshd_config` | تنظیمات sshd (فقط کلید، ورود root مجاز) |
| `entrypoint.sh` | کلید میزبان پایدار، نصب کلیدهای تو از متغیرها، ساخت بنر اتصال، اجرای sshd |
| `railway.json` | بیلد با Dockerfile و ری‌استارت خودکار |
| `.gitattributes` | جلوگیری از خراب شدن اسکریپت‌ها در ویندوز (CRLF) |
| `.dockerignore` / `.gitignore` | فایل‌های اضافی وارد ایمیج و ریپو نشوند |

---

## ۳) پیش‌نیاز

- حساب Railway (قابلیت TCP Proxy باید در پلن و پروژهٔ تو فعال باشد؛ در Settings → Networking دیده می‌شود).
- یک ریپوی GitHub.
- روی ویندوز: `ssh` و `ssh-keygen` از قبل نصب‌اند (Windows 10/11 → OpenSSH Client).
  اگر نبود: Settings → Apps → Optional Features → OpenSSH Client.

---

## ۴) ساخت کلید روی سیستم خودت (ویندوز CMD)

```cmd
ssh-keygen -t ed25519 -C "railway-root" -f %USERPROFILE%\.ssh\railway_root
type %USERPROFILE%\.ssh\railway_root.pub
```

خط چاپ‌شده (که با `ssh-ed25519` شروع می‌شود) را کپی کن — این «کلید عمومی» است و در متغیر `AUTHORIZED_KEYS` می‌گذاریم.
فایل `railway_root` (بدون `.pub`) کلید خصوصی است و **فقط** روی سیستم خودت می‌ماند؛ آن را جایی آپلود نکن.

روی لینوکس/مک همین است:

```bash
ssh-keygen -t ed25519 -C "railway-root" -f ~/.ssh/railway_root
cat ~/.ssh/railway_root.pub
```

---

## ۵) دیپلوی روی Railway

1. Railway → **New Project** → **Deploy from GitHub repo** → ریپو را انتخاب کن.
   `Dockerfile` در ریشه است، پس نیازی به تنظیم Root Directory نیست
   (اگر Builder خودکار تشخیص داده نشد: Settings → Build → Builder = Dockerfile).
2. تب **Variables** → متغیر زیر را اضافه کن:

   | نام | مقدار |
   |---|---|
   | `AUTHORIZED_KEYS` | همان یک خط کلید عمومی (`ssh-ed25519 AAAA... railway-root`) |

   برای چند کلید، هر کلید در یک خط جدا (Railway اجازهٔ مقدار چندخطی می‌دهد) یا به‌جای آن
   `AUTHORIZED_KEYS_B64` را با محتوای base64 فایل `authorized_keys` پر کن.
3. **Settings → Networking → Public Networking → TCP Proxy** → پورت مقصد (Target Port) را `22` بگذار.
   Railway یک دامنه و پورت عمومی می‌دهد؛ همان‌ها را یادداشت کن.
4. یک بار **Redeploy** بزن تا متغیرهای `RAILWAY_TCP_PROXY_DOMAIN` و `RAILWAY_TCP_PROXY_PORT` هم به کانتینر برسند.

اگر پورت ۲۲ به‌عنوان Target Port پذیرفته نشد، در متغیرها `SSH_PORT=2222` بگذار و Target Port را هم `2222` کن.

---

## ۶) اتصال از CMD

```cmd
ssh -p 41234 root@roundhouse.proxy.rlwy.net -i %USERPROFILE%\.ssh\railway_root
```

بار اول `yes` را بزن. بعد از ورود، پرامپت `root@...` و بنر اطلاعات اتصال را می‌بینی.

### ورود مستقیم و همیشگی: `ssh railway`

فایل `%USERPROFILE%\.ssh\config` را بساز (یا باز کن) و این را اضافه کن — پورت و دامنه را از Railway کپی کن:

```
Host railway
    HostName roundhouse.proxy.rlwy.net
    Port 41234
    User root
    IdentityFile ~/.ssh/railway_root
    ServerAliveInterval 30
```

از این به بعد فقط:

```cmd
ssh railway
```

و با `scp -P 41234 ...` یا `sftp` هم با همان نام کار می‌کند: `scp file.txt railway:/root/`.

---

## ۷) متغیرهای محیطی

| متغیر | پیش‌فرض | کار |
|---|---|---|
| `AUTHORIZED_KEYS` | — | کلید(های) عمومی مجاز؛ چندخطی یا با `\n` |
| `AUTHORIZED_KEYS_B64` | — | همان محتوا به‌صورت base64 |
| `ROOT_PASSWORD` | خالی | اگر پر شود، ورود با رمز هم فعال می‌شود (کم‌ترین حالت) |
| `SSH_PORT` | `22` | پورت داخلی sshd (باید با Target Port پروکسی یکی باشد) |
| `DATA_DIR` | `/data` | محل نگهداری کلید میزبان و کلید موقت |
| `AUTO_GENERATE_KEY` | `1` | اگر هیچ کلیدی ندهی، یک کلید موقت می‌سازد و در صفحهٔ ورود نشان می‌دهد |

### بدون هیچ کلیدی هم می‌شود (کلید موقت)

اگر `AUTHORIZED_KEYS` را خالی بگذاری، سرور یک کلید موقت می‌سازد و **متن کلید خصوصی** را پایین بنر ورود چاپ می‌کند.
با آن یک بار وارد شو، بعد کلید خودت را در `AUTHORIZED_KEYS` بگذار و Redeploy کن؛ از آن به بعد کلید موقت نمایش داده نمی‌شود.
این مسیر برای وقتی است که فقط با گوشی به Railway دسترسی داری.

---

## ۸) Volume برای پایداری (اختیاری ولی توصیه‌شده)

بدون Volume، هر ری‌استارت Railway کلید میزبان عوض می‌شود و کلاینت هشدار
`REMOTE HOST IDENTIFICATION HAS CHANGED` می‌دهد. یک Volume بساز و به مسیر `/data` وصل کن
(Railway → service → **Volumes** → Mount Path = `/data`). کلید میزبان و کلید موقت همان‌جا می‌مانند.

---

## ۹) کارهایی که داخل سرور می‌کنی

همه‌چیز با کاربر root است، پس نصب هر پکیجی یک دستور است:

```bash
apt-get update && apt-get install -y python3 python3-pip git htop tmux
```

پکیج‌هایی که از قبل نصب‌اند: `openssh-server`, `bash`, `curl`, `wget`, `git`, `nano`, `vim-tiny`, `less`,
`tmux`, `htop`, `procps`, `psmisc`, `unzip`, `zip`, `iproute2`, `iputils-ping`, `net-tools`, `dnsutils`,
`python3`, `python3-pip`, `sudo`.

`pip install` هم مستقیم کار می‌کند (متغیر `PIP_BREAK_SYSTEM_PACKAGES=1` در ایمیج تنظیم شده):

```bash
pip install requests
```

پس عملاً هیچ‌چیز روی سیستم خودت لازم نیست؛ هر ابزاری خواستی داخل سرور با `apt-get` یا `pip` نصب می‌شود.

---

## ۱۰) عیب‌یابی

| خطا | دلیل / راه‌حل |
|---|---|
| `Permission denied (publickey)` | کلید عمومی در `AUTHORIZED_KEYS` نیست یا ناقص/شکسته کپی شده؛ باید یک خط کامل با `ssh-ed25519` شروع شود. اگر `AUTO_GENERATE_KEY=0` و هیچ کلیدی ندادی، ورود ممکن نیست. |
| `Connection refused` / `Connection timed out` | TCP Proxy ساخته نشده، Target Port اشتباه است، یا سرویس Down است (Logs را ببین). |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | کلید میزبان عوض شده (بدون Volume). راه‌حل: Volume روی `/data`، یا `ssh-keygen -R "[host]:port"` روی سیستم خودت. |
| بعد از ورود، بنر دامنه ندارد | متغیرهای `RAILWAY_TCP_PROXY_*` هنوز به کانتینر نرسیده‌اند؛ پروکسی را بساز و Redeploy کن. |
| ورود با رمز کار نمی‌کند | `ROOT_PASSWORD` تنظیم نشده (پیش‌فرض: فقط کلید). |
| تغییرات کد اعمال نمی‌شود | Railway از commit جدید می‌سازد؛ push کن و Redeploy بزن. |

Logهای سرویس در Railway → service → **Logs** است و هر ورود/رد sshd همان‌جا دیده می‌شود
(`Accepted publickey for root ...`).

---

## ۱۱) نکات امنیتی

- پیش‌فرض: **فقط کلید**، `PermitRootLogin prohibit-password`، `PasswordAuthentication no`.
- کلید خصوصی را هرگز کامیت نکن (`.gitignore` جلوی `.env` و کلیدها را می‌گیرد، ولی خودت هم دقت کن).
- `ROOT_PASSWORD` را فقط وقتی فعال کن که لازم داری؛ رمز کوتاه روی اینترنت سریع کرک می‌شود.
- `AUTO_GENERATE_KEY` را بعد از گذاشتن کلید خودت روی `0` بگذار تا کلید موقت اصلاً ساخته نشود.
- سرویس فقط یک replica داشته باشد (`railway.json` همین را تنظیم کرده)؛ SSH روی چند نمونه بی‌معنی است.
