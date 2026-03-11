# AS/400 Finance Portal
### Automated Legacy Migration & Data Viewer — IBM iSeries → Linux

[![Platform](https://img.shields.io/badge/Platform-Linux%20%28Ubuntu%2FDebian%29-blue?style=flat-square)](https://ubuntu.com/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-yellow?style=flat-square)](https://python.org)
[![Database](https://img.shields.io/badge/Database-PostgreSQL-336791?style=flat-square)](https://postgresql.org)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

---

A **single-script solution** for infrastructure teams to migrate all data from an IBM AS/400 (iSeries) server to a modern Linux platform — with a built-in web portal for browsing, searching, and exporting data.

> Built for finance departments that need to extract legacy data for audits, government cases, or system decommissioning — **no programming knowledge required.**

---

## 📸 What It Looks Like

```
┌─────────────────────────────────────────────────────────┐
│   AS/400 Finance Portal  ◈   DB READY ●   10:45 AM IST  │
├─────────────────────────────────────────────────────────┤
│  [ CONNECT & MIGRATE ]  [ DATA VIEWER ]  [ SETUP GUIDE ]│
├──────────────────────────┬──────────────────────────────┤
│  AS/400 IP Address       │  WORKFLOW                    │
│  Username / Password     │  ① Enter credentials        │
│  Library Name            │  ② Test connection     ✔    │
│                          │  ③ Discover tables     ✔    │
│  [ TEST CONNECTION ]     │  ④ Migrate data        ✔    │
│  [ START MIGRATION ]     │  ⑤ View & export            │
└──────────────────────────┴──────────────────────────────┘
```

---

## ✨ Features

- **One-command install** — installs Python, PostgreSQL, and all dependencies automatically
- **Guided connection wizard** — prompts for AS/400 IP, username, password, and library name
- **Full automatic migration** — discovers and migrates every table in the specified library
- **Live progress dashboard** — real-time log, progress bar, row count, and error tracking
- **Web data viewer** — browse all migrated tables in a browser from any computer on the network
- **One-click export** — download any table as CSV or Excel (`.xlsx`)
- **Auto-start on reboot** — registers as a systemd service
- **Audit-ready** — migration log saved to `/var/log/as400_migration.log`
- **Secure** — AS/400 password never stored after migration; `config.json` excluded from git

---

## 🗂️ Data Supported

The portal migrates **all tables** from any AS/400 library. Typical finance data includes:

| Data Type | AS/400 Source | Migrated To |
|---|---|---|
| Financial Transactions | DB2/400 Physical Files | PostgreSQL tables |
| Invoices (AR/AP) | DB2/400 Physical Files | PostgreSQL tables |
| Inventory & Assets | DB2/400 Physical Files | PostgreSQL tables |
| Payroll Records | DB2/400 Physical Files | PostgreSQL tables |
| Any other table | DB2/400 Physical Files | PostgreSQL tables |

---

## 🖥️ System Requirements

**Linux Server (where this runs):**
- Ubuntu 20.04 / 22.04 or Debian 11 / 12
- Minimum 2 GB RAM, 20 GB free disk
- Network access to the AS/400 server
- Root / sudo access

**AS/400 Server:**
- IBM iSeries / AS/400 running OS/400 or IBM i (any version)
- User account with `*ALLOBJ` or `*SECADM` authority
- Ports 449, 8471, 9470–9475 open toward the Linux server

---

## 🚀 Quick Start

### Step 1 — Download the script

```bash
wget https://raw.githubusercontent.com/YOUR-USERNAME/as400-finance-portal/main/as400_migrate.sh
```

Or clone the repository:

```bash
git clone https://github.com/YOUR-USERNAME/as400-finance-portal.git
cd as400-finance-portal
```

### Step 2 — Run (as root)

```bash
sudo bash as400_migrate.sh
```

### Step 3 — Answer the prompts

```
AS/400 IP Address              : 192.168.1.50
AS/400 Username (e.g. QSECOFR) : QSECOFR
AS/400 Password                : ••••••••
Library / Schema name          : FINLIB
AS/400 Port [default: 449]     :            ← press Enter for default
```

### Step 4 — Open the portal

Once the script completes, open any browser on the same network:

```
http://<YOUR-LINUX-SERVER-IP>:8000
```

Click **Test Connection → Start Migration → View Data**.

---

## 📋 How It Works

```
as400_migrate.sh
│
├── [1] Collects AS/400 credentials interactively
├── [2] Installs: Python 3, PostgreSQL, Python libs, IBM ODBC driver
├── [3] Creates local PostgreSQL database (finance_db)
├── [4] Writes portal application to /opt/as400-finance-portal/
├── [5] Registers systemd service (auto-start on reboot)
└── [6] Starts web portal at http://0.0.0.0:8000
         │
         ├── /api/test                  → Tests AS/400 ODBC connection
         ├── /api/migrate               → Runs full data migration
         ├── /api/migrate/status        → Live progress polling
         ├── /api/tables                → Lists all migrated tables
         ├── /api/table/{name}          → Returns table data (paginated)
         ├── /api/export/{name}/csv     → Downloads table as CSV
         └── /api/export/{name}/excel   → Downloads table as Excel
```

---

## 🔧 IBM iSeries ODBC Driver

The script attempts to download the IBM driver automatically. If it fails (e.g. due to network restrictions), install it manually:

**Ubuntu / Debian:**
```bash
wget https://public.dhe.ibm.com/software/ibmi/products/odbc/debs/dists/1.1.0/ibm-iaccess_1.1.0.23-0_amd64.deb
sudo dpkg -i ibm-iaccess_1.1.0.23-0_amd64.deb
sudo apt-get install -f
```

**RHEL / CentOS:**
```bash
wget https://public.dhe.ibm.com/software/ibmi/products/odbc/rpms/ibm-iaccess-1.1.0.23-0.x86_64.rpm
sudo rpm -ivh ibm-iaccess-1.1.0.23-0.x86_64.rpm
```

**Verify the driver is installed:**
```bash
odbcinst -q -d
# Expected output: [IBM i Access ODBC Driver]
```

---

## 🔥 Firewall / Network Requirements

Open the following ports **from the Linux server toward the AS/400**:

| Port | Protocol | Purpose |
|------|----------|---------|
| 449 | TCP | DDM/DRDA — main database port |
| 8471 | TCP | Signon server |
| 9470 | TCP | Central server |
| 9471 | TCP | Database server |
| 9472–9475 | TCP | Various iSeries services |

Test connectivity:
```bash
nc -zv <AS400_IP> 449
```

Open the portal port on the Linux server firewall:
```bash
sudo ufw allow 8000
```

---

## 📁 File Structure

After installation, files are placed at:

```
/opt/as400-finance-portal/
├── server.py       # FastAPI backend (AS/400 connection, migration, API)
├── ui.html         # Web browser interface (HTML/CSS/JS — no framework)
└── config.json     # Pre-filled connection settings (excluded from git)

/var/log/
└── as400_migration.log     # Full installation and migration log

/etc/systemd/system/
└── as400-portal.service    # Auto-start service definition
```

---

## 🛠️ Managing the Service

```bash
# Start
sudo systemctl start as400-portal

# Stop
sudo systemctl stop as400-portal

# Restart
sudo systemctl restart as400-portal

# Check status
sudo systemctl status as400-portal

# View live logs
sudo journalctl -u as400-portal -f
```

---

## 💾 Backup After Migration

> **Critical for government / legal cases** — take a backup immediately after migration completes.

```bash
# Full database backup
pg_dump -U financeadmin finance_db > finance_backup_$(date +%Y%m%d_%H%M%S).sql

# Restore if needed
psql -U financeadmin finance_db < finance_backup_YYYYMMDD.sql
```

Store the `.sql` file on an external drive or a secure network location.

---

## 🔍 Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `iSeries ODBC driver not found` | IBM driver not installed | Follow IBM ODBC Driver section above |
| `Cannot reach 192.168.x.x` | Network / firewall issue | Run `nc -zv <AS400_IP> 449` to diagnose |
| `Wrong username or password` | Invalid AS/400 credentials | Verify with your AS/400 administrator |
| `No tables found` | Wrong library name | Use **Browse Libraries** button in the portal |
| Portal not opening in browser | Firewall blocking port 8000 | Run `sudo ufw allow 8000` |
| `DB ERROR` shown in header | PostgreSQL not running | Run `sudo systemctl start postgresql` |

---

## 🔐 Security Notes

- `config.json` is listed in `.gitignore` and will **never** be committed to this repository
- The AS/400 password is used only at connection time and is not stored in the database
- All data stays on your local Linux server — nothing is sent externally
- The portal runs on your internal network only
- For production deployments, add HTTPS and authentication via an nginx reverse proxy

---

## 🧰 Technology Stack

| Component | Technology |
|---|---|
| Backend API | Python 3 + FastAPI |
| Web Server | Uvicorn (ASGI) |
| Database | PostgreSQL |
| AS/400 Connection | IBM iSeries Access ODBC + pyodbc |
| Data Processing | pandas + SQLAlchemy |
| Export | openpyxl / xlsxwriter |
| Frontend | Vanilla HTML / CSS / JavaScript |
| Service Manager | systemd |

---

## 🤝 Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss.

1. Fork the repository
2. Create your branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'Add my feature'`
4. Push: `git push origin feature/my-feature`
5. Open a Pull Request

---

## 📜 License

MIT License — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.

---

## 📞 Support

If you run into issues:
1. Check the **Setup Guide** tab inside the running web portal
2. Review the log: `cat /var/log/as400_migration.log`
3. Open a GitHub Issue and paste the relevant log lines

---

*Built for infrastructure teams managing legacy IBM AS/400 / iSeries systems.*
