#!/bin/bash
# =============================================================================
#  AS/400 → Linux Finance Portal
#  ALL-IN-ONE INSTALLER + MIGRATOR
#
#  USAGE (run as root on your Linux server):
#    sudo bash as400_migrate.sh
#
#  This script will:
#    1. Install all required software automatically
#    2. Ask you for AS/400 IP address and login credentials
#    3. Connect to AS/400 and migrate ALL data
#    4. Launch a web portal so your CFO can view and export data
# =============================================================================

set -e

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'
OK="${G}✔${N}"; FAIL="${R}✘${N}"; INFO="${C}▸${N}"

PORTAL_DIR="/opt/as400-finance-portal"
LOG_FILE="/var/log/as400_migration.log"
PG_DB="finance_db"
PG_USER="financeadmin"
PG_PASS="FinPortal$(date +%Y)!"

# ── Logging ───────────────────────────────────────────────────────────────────
mkdir -p "$(dirname $LOG_FILE)"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo -e "${INFO} $1"; }
ok()   { echo -e "${OK}  $1"; }
warn() { echo -e "${Y}⚠  $1${N}"; }
die()  { echo -e "${FAIL} ${R}ERROR: $1${N}"; exit 1; }

# =============================================================================
#  BANNER
# =============================================================================
clear
echo -e "${C}${B}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════════════════════╗
  ║                                                                  ║
  ║      AS/400  →  Linux  Finance  Portal                          ║
  ║      Automated Migration & Data Viewer                           ║
  ║                                                                  ║
  ║      For Infrastructure Teams — No Programming Required          ║
  ║                                                                  ║
  ╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"
echo -e "  This script will install everything needed and migrate your"
echo -e "  AS/400 finance data to this Linux server automatically.\n"
echo -e "  ${Y}Log file: $LOG_FILE${N}\n"

# =============================================================================
#  CHECK ROOT
# =============================================================================
if [ "$EUID" -ne 0 ]; then
    die "Please run with sudo:  sudo bash $0"
fi

# =============================================================================
#  DETECT OS
# =============================================================================
log "Detecting Linux distribution..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    die "Cannot detect OS. Please use Ubuntu 20.04/22.04 or Debian 11/12."
fi
ok "Detected: $PRETTY_NAME"

# =============================================================================
#  STEP 1 — COLLECT AS/400 CREDENTIALS
# =============================================================================
echo ""
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}${B}  STEP 1 OF 5 — AS/400 CONNECTION DETAILS${N}"
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  Please enter your AS/400 server details."
echo -e "  ${Y}(These will only be used locally — never sent anywhere)${N}\n"

while true; do
    read -p "  AS/400 IP Address          : " AS400_IP
    [[ -n "$AS400_IP" ]] && break
    echo -e "  ${R}IP address cannot be empty.${N}"
done

read -p "  AS/400 Username (e.g. QSECOFR) : " AS400_USER
while true; do
    read -s -p "  AS/400 Password                : " AS400_PASS
    echo ""
    [[ -n "$AS400_PASS" ]] && break
    echo -e "  ${R}Password cannot be empty.${N}"
done

read -p "  Library / Schema name (e.g. FINLIB) : " AS400_LIB
AS400_LIB=${AS400_LIB:-FINLIB}

read -p "  AS/400 Port [default: 449]   : " AS400_PORT
AS400_PORT=${AS400_PORT:-449}

echo ""
echo -e "  ${Y}Settings saved:${N}"
echo -e "  ┌──────────────────────────────────────────┐"
echo -e "  │  IP       : $AS400_IP"
echo -e "  │  Username : $AS400_USER"
echo -e "  │  Library  : $AS400_LIB"
echo -e "  │  Port     : $AS400_PORT"
echo -e "  └──────────────────────────────────────────┘"
echo ""
read -p "  Continue with these settings? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# =============================================================================
#  STEP 2 — INSTALL SYSTEM SOFTWARE
# =============================================================================
echo ""
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}${B}  STEP 2 OF 5 — INSTALLING SOFTWARE${N}"
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

log "Updating package lists..."
apt-get update -qq 2>/dev/null || yum update -y -q 2>/dev/null || true
ok "Package lists updated"

log "Installing Python 3, pip, PostgreSQL..."
if command -v apt-get &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        python3 python3-pip python3-venv \
        postgresql postgresql-contrib \
        unixodbc unixodbc-dev \
        curl wget net-tools \
        libpq-dev gcc python3-dev 2>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y -q python3 python3-pip postgresql postgresql-server \
        unixODBC unixODBC-devel curl wget 2>/dev/null
fi
ok "System packages installed"

log "Starting PostgreSQL service..."
systemctl start postgresql 2>/dev/null || service postgresql start 2>/dev/null || true
systemctl enable postgresql 2>/dev/null || true
sleep 2
ok "PostgreSQL running"

log "Creating finance database and user..."
sudo -u postgres psql -c "CREATE DATABASE $PG_DB;" 2>/dev/null || true
sudo -u postgres psql -c "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$PG_USER') THEN
    CREATE USER $PG_USER WITH PASSWORD '$PG_PASS';
  ELSE
    ALTER USER $PG_USER WITH PASSWORD '$PG_PASS';
  END IF;
END \$\$;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $PG_DB TO $PG_USER;" 2>/dev/null || true
sudo -u postgres psql -d "$PG_DB" -c "GRANT ALL ON SCHEMA public TO $PG_USER;" 2>/dev/null || true
ok "PostgreSQL database '$PG_DB' ready"

log "Installing Python libraries (this may take 2–3 minutes)..."
pip3 install --break-system-packages -q \
    fastapi uvicorn[standard] psycopg2-binary \
    pandas sqlalchemy openpyxl xlsxwriter \
    python-multipart pyodbc 2>/dev/null || \
pip3 install -q \
    fastapi uvicorn[standard] psycopg2-binary \
    pandas sqlalchemy openpyxl xlsxwriter \
    python-multipart pyodbc 2>/dev/null || true
ok "Python libraries installed"

# ── Try to install IBM iSeries ODBC driver ────────────────────────────────────
log "Attempting to install IBM iSeries ODBC driver..."
ARCH=$(uname -m)
IBM_DEB="ibm-iaccess_1.1.0.23-0_amd64.deb"
IBM_URL="https://public.dhe.ibm.com/software/ibmi/products/odbc/debs/dists/1.1.0/$IBM_DEB"

ODBC_OK=false
if command -v apt-get &>/dev/null; then
    if wget -q --timeout=30 -O "/tmp/$IBM_DEB" "$IBM_URL" 2>/dev/null; then
        dpkg -i "/tmp/$IBM_DEB" 2>/dev/null && apt-get install -f -y -qq 2>/dev/null && ODBC_OK=true
        rm -f "/tmp/$IBM_DEB"
    fi
fi

if [ "$ODBC_OK" = true ]; then
    ok "IBM iSeries ODBC driver installed"
else
    warn "IBM iSeries ODBC driver could not be downloaded automatically."
    warn "The portal will still work but you may need to install it manually."
    warn "See the web portal's Setup Guide tab for instructions."
fi

# =============================================================================
#  STEP 3 — WRITE APPLICATION FILES
# =============================================================================
echo ""
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}${B}  STEP 3 OF 5 — CREATING PORTAL APPLICATION${N}"
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

mkdir -p "$PORTAL_DIR"
log "Writing application to $PORTAL_DIR ..."

# ── Write config ──────────────────────────────────────────────────────────────
cat > "$PORTAL_DIR/config.json" << CFGEOF
{
  "as400_ip":   "$AS400_IP",
  "as400_user": "$AS400_USER",
  "as400_lib":  "$AS400_LIB",
  "as400_port": "$AS400_PORT",
  "pg_host":    "localhost",
  "pg_db":      "$PG_DB",
  "pg_user":    "$PG_USER",
  "pg_pass":    "$PG_PASS"
}
CFGEOF

# ── Write Python backend ───────────────────────────────────────────────────────
cat > "$PORTAL_DIR/server.py" << 'PYEOF'
#!/usr/bin/env python3
"""
AS/400 Finance Portal — Backend Server
Handles connection testing, live migration, data viewing, and export.
"""
import os, io, json, logging, threading, traceback
from datetime import datetime
from pathlib import Path

import psycopg2, psycopg2.extras
import pandas as pd
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger(__name__)

# ── Load config written by the installer ──────────────────────────────────────
CFG_FILE = Path(__file__).parent / "config.json"
CFG = json.loads(CFG_FILE.read_text()) if CFG_FILE.exists() else {}

PG = dict(
    host=CFG.get("pg_host", "localhost"),
    database=CFG.get("pg_db", "finance_db"),
    user=CFG.get("pg_user", "financeadmin"),
    password=CFG.get("pg_pass", "FinPortal2024!")
)

app = FastAPI(title="AS/400 Finance Portal")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ── Migration state (in-memory, live updates) ─────────────────────────────────
MIG = dict(running=False, done=False, error=None, progress=0,
           current="", log=[], tables_done=[], tables_failed=[], total_rows=0)

# ─────────────────────────────────────────────────────────────────────────────
def pg():
    return psycopg2.connect(**PG)

def pg_engine():
    from sqlalchemy import create_engine
    u = PG
    return create_engine(f"postgresql://{u['user']}:{u['password']}@{u['host']}/{u['database']}")

def mlog(msg, lvl="INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    MIG["log"].append(f"[{ts}] {msg}")
    log.info(msg)

# ─────────────────────────────────────────────────────────────────────────────
# AS/400 ODBC CONNECT
# ─────────────────────────────────────────────────────────────────────────────
def as400_connect(ip, user, pwd):
    try:
        import pyodbc
    except ImportError:
        raise RuntimeError("pyodbc not installed. Run: pip3 install pyodbc")

    DRIVERS = [
        "IBM i Access ODBC Driver",
        "iSeries Access ODBC Driver",
        "IBM iSeries Access for Windows - ODBC Driver",
    ]
    available = pyodbc.drivers()
    drv = next((d for d in DRIVERS if d in available), None)
    if not drv:
        raise RuntimeError(
            f"IBM iSeries ODBC driver not found. Available drivers: {available or ['none']}. "
            "Please install 'ibm-iaccess' — see Setup Guide tab."
        )
    cs = f"DRIVER={{{drv}}};SYSTEM={ip};UID={user};PWD={pwd};TRANSLATE=1;"
    return pyodbc.connect(cs, timeout=20)

# ─────────────────────────────────────────────────────────────────────────────
# API — TEST CONNECTION
# ─────────────────────────────────────────────────────────────────────────────
@app.post("/api/test")
async def test_connection(body: dict):
    ip   = body.get("ip",   CFG.get("as400_ip","")).strip()
    user = body.get("user", CFG.get("as400_user","")).strip()
    pwd  = body.get("pwd",  "").strip()

    if not ip or not user or not pwd:
        raise HTTPException(400, "IP, username and password required")
    try:
        conn = as400_connect(ip, user, pwd)
        cur  = conn.cursor()
        cur.execute("SELECT CURRENT_SERVER FROM SYSIBM.SYSDUMMY1")
        srv = cur.fetchone()[0]
        conn.close()
        return {"ok": True, "server": srv, "msg": f"Connected to {srv}"}
    except Exception as e:
        err = str(e)
        if "password" in err.lower() or "1017" in err:
            hint = "Wrong username or password"
        elif "connect" in err.lower() or "timeout" in err.lower():
            hint = f"Cannot reach {ip} — check network/firewall (port {body.get('port',449)})"
        elif "driver" in err.lower():
            hint = err
        else:
            hint = err
        return JSONResponse({"ok": False, "msg": hint})

# ─────────────────────────────────────────────────────────────────────────────
# API — LIST LIBRARIES
# ─────────────────────────────────────────────────────────────────────────────
@app.post("/api/libraries")
async def list_libraries(body: dict):
    ip   = body.get("ip",   CFG.get("as400_ip",""))
    user = body.get("user", CFG.get("as400_user",""))
    pwd  = body.get("pwd","")
    try:
        conn = as400_connect(ip, user, pwd)
        cur  = conn.cursor()
        cur.execute("""
            SELECT SCHEMA_NAME FROM QSYS2.SYSSCHEMAS
            WHERE SCHEMA_NAME NOT LIKE 'Q%'
              AND SCHEMA_NAME NOT IN ('SYSIBM','SYSCAT','SYSSTAT','SYSTOOLS','SYSPROC')
            ORDER BY SCHEMA_NAME
        """)
        libs = [r[0] for r in cur.fetchall()]
        conn.close()
        return {"libs": libs}
    except Exception as e:
        raise HTTPException(500, str(e))

# ─────────────────────────────────────────────────────────────────────────────
# API — START MIGRATION
# ─────────────────────────────────────────────────────────────────────────────
@app.post("/api/migrate")
async def start_migration(body: dict):
    if MIG["running"]:
        raise HTTPException(409, "Migration already running")

    ip      = body.get("ip",   CFG.get("as400_ip",""))
    user    = body.get("user", CFG.get("as400_user",""))
    pwd     = body.get("pwd","")
    library = body.get("lib",  CFG.get("as400_lib",""))

    for k in ("log","tables_done","tables_failed"):
        MIG[k] = []
    MIG.update(running=True, done=False, error=None,
               progress=0, current="", total_rows=0)

    def run():
        try:
            _migrate(ip, user, pwd, library)
        except Exception as e:
            MIG["error"] = str(e)
            mlog(f"FATAL: {e}", "ERROR")
        finally:
            MIG["running"] = False
            MIG["done"]    = True

    threading.Thread(target=run, daemon=True).start()
    return {"msg": "Migration started"}

def _migrate(ip, user, pwd, library):
    mlog(f"Connecting to AS/400 {ip} …")
    as400 = as400_connect(ip, user, pwd)
    mlog("AS/400 connected ✔")
    mlog("Connecting to local PostgreSQL …")
    engine = pg_engine()
    mlog("PostgreSQL connected ✔")

    # Discover tables
    mlog(f"Scanning library {library} for tables …")
    cur = as400.cursor()
    cur.execute(f"""
        SELECT TABLE_NAME
        FROM QSYS2.SYSTABLES
        WHERE TABLE_SCHEMA='{library}' AND TABLE_TYPE='T'
        ORDER BY TABLE_NAME
    """)
    tables = [r[0] for r in cur.fetchall()]
    total  = len(tables)
    mlog(f"Found {total} tables")

    if total == 0:
        mlog("⚠ No tables found — check library name", "WARN")
        return

    for i, tbl in enumerate(tables):
        MIG["current"]  = f"{library}.{tbl}"
        MIG["progress"] = int(i / total * 95)
        mlog(f"[{i+1}/{total}] Reading {library}.{tbl} …")
        try:
            df = pd.read_sql(f'SELECT * FROM {library}.{tbl}', as400)
            rows = len(df)
            if rows == 0:
                mlog(f"  (empty table, skipped)")
                continue
            # Clean column names for PostgreSQL
            df.columns = [
                c.strip().lower()
                 .replace(' ','_').replace('-','_')
                 .replace('/','_').replace('.','_')[:63]
                for c in df.columns
            ]
            pg_name = f"{library.lower()}_{tbl.lower()}"[:63]
            df.to_sql(pg_name, engine, if_exists='replace',
                      index=False, method='multi', chunksize=500)
            MIG["total_rows"] += rows
            MIG["tables_done"].append({"pg": pg_name, "src": f"{library}.{tbl}", "rows": rows})
            mlog(f"  ✔ {rows:,} rows → {pg_name}")
        except Exception as e:
            MIG["tables_failed"].append({"name": tbl, "err": str(e)})
            mlog(f"  ✘ {tbl}: {e}", "WARN")

    as400.close()
    MIG["progress"] = 100
    mlog(f"")
    mlog(f"Migration complete!")
    mlog(f"  Tables migrated : {len(MIG['tables_done'])}")
    mlog(f"  Total rows      : {MIG['total_rows']:,}")
    mlog(f"  Errors          : {len(MIG['tables_failed'])}")
    mlog(f"")
    mlog(f"Open the Data Viewer tab to browse and export data.")

@app.get("/api/migrate/status")
async def migration_status():
    return MIG

# ─────────────────────────────────────────────────────────────────────────────
# API — DATA VIEWER
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/api/tables")
async def list_tables():
    try:
        conn = pg()
        cur  = conn.cursor()
        cur.execute("""
            SELECT table_name,
                   pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS sz
            FROM information_schema.tables
            WHERE table_schema='public' ORDER BY table_name
        """)
        rows = [{"name": r[0], "size": r[1]} for r in cur.fetchall()]
        conn.close()
        return {"tables": rows}
    except Exception as e:
        raise HTTPException(500, str(e))

@app.get("/api/table/{name}")
async def get_table(name: str, limit: int = 500, offset: int = 0):
    try:
        conn = pg()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(f'SELECT COUNT(*) AS n FROM "{name}"')
        total = cur.fetchone()["n"]
        cur.execute(f'SELECT * FROM "{name}" LIMIT %s OFFSET %s', (limit, offset))
        rows = []
        for r in cur.fetchall():
            row = {}
            for k, v in dict(r).items():
                row[k] = v.isoformat() if hasattr(v, 'isoformat') else ("" if v is None else str(v))
            rows.append(row)
        cur.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name=%s AND table_schema='public'
            ORDER BY ordinal_position
        """, (name,))
        cols = [r["column_name"] for r in cur.fetchall()]
        conn.close()
        return {"name": name, "total": total, "cols": cols, "rows": rows}
    except Exception as e:
        raise HTTPException(500, str(e))

@app.get("/api/export/{name}/csv")
async def export_csv(name: str):
    conn = pg()
    df   = pd.read_sql(f'SELECT * FROM "{name}"', conn); conn.close()
    buf  = io.StringIO(); df.to_csv(buf, index=False); buf.seek(0)
    fn   = f"{name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    return StreamingResponse(buf, media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={fn}"})

@app.get("/api/export/{name}/excel")
async def export_excel(name: str):
    conn = pg()
    df   = pd.read_sql(f'SELECT * FROM "{name}"', conn); conn.close()
    buf  = io.BytesIO()
    with pd.ExcelWriter(buf, engine='xlsxwriter') as w:
        df.to_excel(w, index=False, sheet_name=name[:31])
    buf.seek(0)
    fn = f"{name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    return StreamingResponse(buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={fn}"})

# ─────────────────────────────────────────────────────────────────────────────
# SERVE HTML UI (embedded inline)
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/", response_class=HTMLResponse)
async def ui():
    html = (Path(__file__).parent / "ui.html").read_text()
    return html

if __name__ == "__main__":
    h = "0.0.0.0"
    p = 8000
    print(f"\n{'='*60}")
    print(f"  AS/400 Finance Portal — Running")
    print(f"  Open browser:  http://localhost:{p}")
    print(f"{'='*60}\n")
    uvicorn.run("server:app", host=h, port=p, reload=False)
PYEOF

ok "Backend server written"

# ── Write HTML UI ─────────────────────────────────────────────────────────────
cat > "$PORTAL_DIR/ui.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>AS/400 Finance Portal</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@300;400;500;700&display=swap" rel="stylesheet"/>
<style>
:root{--bg:#03070B;--sur:#070F18;--bdr:#0C1C2C;--acc:#00D4FF;--grn:#00FF9C;--red:#FF4060;--gld:#FFB800;--mut:#1E3A4A;--txt:#9ABCCC;--wht:#D8EEFF}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:var(--bg);color:var(--txt);font-family:'IBM Plex Mono',monospace;font-size:13px}
body::before{content:'';position:fixed;inset:0;pointer-events:none;background-image:linear-gradient(#0C1C2C44 1px,transparent 1px),linear-gradient(90deg,#0C1C2C44 1px,transparent 1px);background-size:32px 32px;z-index:0}
#app{position:relative;z-index:1;min-height:100vh;display:flex;flex-direction:column}

/* header */
header{height:56px;display:flex;align-items:center;justify-content:space-between;padding:0 28px;border-bottom:1px solid var(--bdr);background:linear-gradient(180deg,#050C14,var(--sur));position:sticky;top:0;z-index:100}
.logo{display:flex;align-items:center;gap:12px}
.logo-box{width:34px;height:34px;border:1.5px solid var(--acc);display:flex;align-items:center;justify-content:center;color:var(--acc);font-size:15px;box-shadow:0 0 10px #00D4FF30}
.logo-title{font-size:12px;font-weight:700;letter-spacing:.2em;color:var(--wht)}
.logo-sub{font-size:9px;letter-spacing:.18em;color:var(--mut);margin-top:1px}
.hdr-r{display:flex;align-items:center;gap:18px}
.dot{width:7px;height:7px;border-radius:50%;background:var(--red);box-shadow:0 0 6px var(--red);animation:blink 2.5s infinite}
.dot.on{background:var(--grn);box-shadow:0 0 6px var(--grn)}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
.clk{font-size:10px;color:var(--mut);letter-spacing:.1em}

/* tabs */
.tabs{display:flex;gap:2px;padding:10px 28px 0;background:var(--sur);border-bottom:1px solid var(--bdr)}
.tab{padding:9px 18px;font-size:10px;letter-spacing:.15em;border:1px solid transparent;border-bottom:none;background:transparent;color:var(--mut);cursor:pointer;font-family:inherit;border-radius:3px 3px 0 0;transition:all .2s}
.tab.on{border-color:var(--bdr);background:var(--bg);color:var(--acc)}
.tab:not(.on):hover{color:var(--txt)}

main{flex:1;padding:24px 28px}

/* cards */
.card{border:1px solid var(--bdr);background:var(--sur);border-radius:2px;padding:20px;margin-bottom:16px}
.ctitle{font-size:9px;letter-spacing:.2em;color:var(--acc);margin-bottom:16px;display:flex;align-items:center;gap:8px}
.ctitle::before{content:'';display:block;width:3px;height:12px;background:var(--acc)}

/* forms */
.fg{display:flex;flex-direction:column;gap:5px;margin-bottom:12px}
.fg label{font-size:9px;letter-spacing:.15em;color:var(--mut)}
.fg input{background:#020509;border:1px solid var(--bdr);color:var(--txt);padding:9px 12px;font-size:12px;font-family:inherit;border-radius:2px;outline:none;transition:border-color .2s}
.fg input:focus{border-color:#00D4FF55}
.fg input::placeholder{color:var(--mut)}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.row3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}

/* buttons */
.btn{padding:9px 20px;font-size:10px;letter-spacing:.15em;border:1px solid;cursor:pointer;font-family:inherit;border-radius:2px;transition:all .2s}
.ba{border-color:var(--acc);color:var(--acc);background:#00D4FF0A}.ba:hover{background:#00D4FF18}
.bg{border-color:var(--grn);color:var(--grn);background:#00FF9C0A}.bg:hover{background:#00FF9C18}
.br{border-color:var(--gld);color:var(--gld);background:#FFB8000A}.br:hover{background:#FFB80018}
.btn:disabled{opacity:.3;cursor:not-allowed}

/* alerts */
.al{padding:11px 14px;border-radius:2px;font-size:11px;letter-spacing:.06em;line-height:1.7;margin:10px 0}
.ai{border:1px solid #00D4FF33;background:#00D4FF08;color:var(--acc)}
.as{border:1px solid #00FF9C44;background:#00FF9C08;color:var(--grn)}
.ae{border:1px solid #FF406044;background:#FF406008;color:var(--red)}
.aw{border:1px solid #FFB80044;background:#FFB80008;color:var(--gld)}

/* progress */
.pb-wrap{margin:14px 0}
.pb-lbl{display:flex;justify-content:space-between;font-size:10px;color:var(--mut);margin-bottom:5px;letter-spacing:.1em}
.pb{height:3px;background:var(--bdr);border-radius:2px;overflow:hidden}
.pb-fill{height:100%;background:linear-gradient(90deg,var(--acc),var(--grn));transition:width .4s;border-radius:2px}

/* log */
.logbox{background:#020406;border:1px solid var(--bdr);border-radius:2px;padding:14px;height:220px;overflow-y:auto;font-size:11px;line-height:2}
.ll{color:#3A6070}.lk{color:var(--grn)}.le{color:var(--red)}.lw{color:var(--gld)}

/* stats */
.sg{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:14px 0}
.sb{border:1px solid var(--bdr);background:var(--bg);padding:14px;border-radius:2px;text-align:center}
.sv{font-size:26px;font-weight:700;color:var(--wht);letter-spacing:.04em}
.sl{font-size:9px;letter-spacing:.15em;color:var(--mut);margin-top:3px}

/* layout helpers */
.two{display:grid;grid-template-columns:1fr 1fr;gap:20px}
.sidebar{display:flex;flex-direction:column;gap:0}

/* table list */
.tlist{max-height:300px;overflow-y:auto;margin-bottom:12px}
.ti{display:flex;align-items:center;justify-content:space-between;padding:9px 12px;border:1px solid var(--bdr);background:var(--bg);cursor:pointer;transition:all .15s;margin-bottom:2px;border-radius:2px}
.ti:hover,.ti.on{border-color:#00D4FF44;background:#00D4FF07}
.tn{font-size:11px;color:var(--acc);letter-spacing:.06em}
.tm{font-size:9px;color:var(--mut);margin-top:2px}

/* data table */
.dt-wrap{overflow:auto;border:1px solid var(--bdr);border-radius:2px;max-height:420px}
.dt{border-collapse:collapse;width:100%;font-size:11px}
.dt thead tr{background:#040A10;position:sticky;top:0}
.dt th{padding:9px 12px;text-align:left;letter-spacing:.12em;font-size:9px;color:var(--acc);white-space:nowrap;border-right:1px solid var(--bdr);border-bottom:1px solid #00D4FF22}
.dt td{padding:8px 12px;border-bottom:1px solid #07111A;border-right:1px solid #07111A;color:#7AACBC;white-space:nowrap;max-width:180px;overflow:hidden;text-overflow:ellipsis}
.dt tr:hover td{background:#00D4FF05}
.dt tr:nth-child(even) td{background:#050C14}

/* export bar */
.ebar{display:flex;gap:8px;align-items:center;padding:10px 0;flex-wrap:wrap}
.ecount{font-size:10px;color:var(--mut);letter-spacing:.1em;margin-left:auto}

/* steps */
.steps{display:flex;flex-direction:column;gap:6px}
.step{display:flex;align-items:flex-start;gap:12px;padding:12px;border:1px solid var(--bdr);background:var(--bg);border-radius:2px;transition:border-color .2s}
.step.done{border-color:#00FF9C33}.step.act{border-color:#00D4FF44;background:#00D4FF05}
.snum{width:26px;height:26px;border-radius:50%;border:1.5px solid var(--mut);color:var(--mut);display:flex;align-items:center;justify-content:center;font-size:10px;flex-shrink:0}
.step.done .snum{border-color:var(--grn);color:var(--grn)}.step.act .snum{border-color:var(--acc);color:var(--acc)}
.st{font-size:11px;color:var(--wht);letter-spacing:.06em;margin-bottom:2px}
.sd{font-size:10px;color:var(--mut);letter-spacing:.04em}

/* code block */
.code{background:#020406;border:1px solid var(--bdr);padding:14px;border-radius:2px;font-size:11px;color:#5AE09A;line-height:2;margin:10px 0;overflow-x:auto}

/* toast */
#toast{position:fixed;top:18px;right:22px;z-index:9999;padding:11px 20px;border-radius:2px;font-size:11px;letter-spacing:.1em;display:none}
@keyframes si{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:translateY(0)}}
</style>
</head>
<body>
<div id="app">

<header>
  <div class="logo">
    <div class="logo-box">◈</div>
    <div>
      <div class="logo-title">AS/400 FINANCE PORTAL</div>
      <div class="logo-sub">LEGACY MIGRATION SYSTEM — LINUX PLATFORM</div>
    </div>
  </div>
  <div class="hdr-r">
    <div style="display:flex;align-items:center;gap:7px">
      <div class="dot" id="dbdot"></div>
      <span id="dbst" style="font-size:10px;color:var(--red);letter-spacing:.1em">CHECKING DB...</span>
    </div>
    <div class="clk" id="clk"></div>
  </div>
</header>

<div class="tabs">
  <button class="tab on" onclick="tab('mig')">⬡ CONNECT &amp; MIGRATE</button>
  <button class="tab"    onclick="tab('view')">◈ DATA VIEWER</button>
  <button class="tab"    onclick="tab('guide')">◎ SETUP GUIDE</button>
</div>

<main>

<!-- ══ TAB: MIGRATE ══════════════════════════════════════════════════════════ -->
<div id="t-mig">
<div class="two">

  <!-- LEFT -->
  <div>
    <div class="card">
      <div class="ctitle">AS/400 CONNECTION</div>

      <!-- Pre-filled from config, password must be re-entered -->
      <div id="prefilled-notice" class="al ai" style="margin-bottom:14px">
        ▸ IP address, username and library were pre-filled from your installation.<br>
        &nbsp;&nbsp;Enter your AS/400 password to continue.
      </div>

      <div class="row2">
        <div class="fg"><label>AS/400 IP ADDRESS</label><input id="ip" placeholder="192.168.1.50"/></div>
        <div class="fg"><label>PORT</label><input id="port" value="449"/></div>
      </div>
      <div class="row2">
        <div class="fg"><label>USERNAME</label><input id="usr" placeholder="QSECOFR"/></div>
        <div class="fg"><label>PASSWORD</label><input id="pwd" type="password" placeholder="••••••••"/></div>
      </div>
      <div class="fg"><label>LIBRARY / SCHEMA NAME</label><input id="lib" placeholder="FINLIB"/></div>

      <div style="display:flex;gap:10px;margin-top:4px">
        <button class="btn ba" onclick="doTest()" id="btnTest">▶ TEST CONNECTION</button>
        <button class="btn bg" onclick="doLibs()" id="btnLibs" style="display:none">◉ BROWSE LIBRARIES</button>
      </div>
      <div id="testRes"></div>
    </div>

    <div class="card">
      <div class="ctitle">START MIGRATION</div>
      <p style="font-size:11px;color:var(--mut);line-height:1.9;margin-bottom:14px">
        Once connected, click the button below to migrate <strong style="color:var(--wht)">ALL tables</strong>
        from the AS/400 library into the local PostgreSQL database.<br>
        This may take several minutes depending on data size.
      </p>
      <div style="display:flex;gap:10px;flex-wrap:wrap">
        <button class="btn bg" id="btnMig" onclick="doMigrate()" disabled>⬇ START FULL MIGRATION</button>
        <button class="btn br" id="btnGoView" onclick="tab('view')" style="display:none">◈ VIEW MIGRATED DATA →</button>
      </div>
    </div>
  </div>

  <!-- RIGHT -->
  <div>
    <div class="card">
      <div class="ctitle">WORKFLOW</div>
      <div class="steps">
        <div class="step act" id="s1"><div class="snum">1</div><div><div class="st">ENTER CREDENTIALS</div><div class="sd">AS/400 IP, username, password, library name</div></div></div>
        <div class="step"     id="s2"><div class="snum">2</div><div><div class="st">TEST CONNECTION</div><div class="sd">Verify TCP/ODBC connection to IBM iSeries</div></div></div>
        <div class="step"     id="s3"><div class="snum">3</div><div><div class="st">DISCOVER TABLES</div><div class="sd">Scan AS/400 library for all data tables</div></div></div>
        <div class="step"     id="s4"><div class="snum">4</div><div><div class="st">MIGRATE DATA</div><div class="sd">Copy all rows from AS/400 DB2 → PostgreSQL</div></div></div>
        <div class="step"     id="s5"><div class="snum">5</div><div><div class="st">VIEW &amp; EXPORT</div><div class="sd">Browse data, export CSV/Excel for CFO</div></div></div>
      </div>
    </div>

    <div class="card" id="progCard" style="display:none">
      <div class="ctitle">LIVE MIGRATION PROGRESS</div>
      <div class="pb-wrap">
        <div class="pb-lbl"><span id="plbl">Preparing...</span><span id="ppct">0%</span></div>
        <div class="pb"><div class="pb-fill" id="pfill" style="width:0%"></div></div>
      </div>
      <div class="sg">
        <div class="sb"><div class="sv" id="stTbl">0</div><div class="sl">TABLES DONE</div></div>
        <div class="sb"><div class="sv" id="stRow">0</div><div class="sl">ROWS MIGRATED</div></div>
        <div class="sb"><div class="sv" id="stErr">0</div><div class="sl">ERRORS</div></div>
      </div>
      <div class="ctitle" style="margin-bottom:8px">MIGRATION LOG</div>
      <div class="logbox" id="mlog"></div>
    </div>
  </div>

</div>
</div><!-- /t-mig -->

<!-- ══ TAB: VIEWER ═══════════════════════════════════════════════════════════ -->
<div id="t-view" style="display:none">
<div style="display:grid;grid-template-columns:260px 1fr;gap:18px">

  <div>
    <div class="card">
      <div class="ctitle">TABLES IN DATABASE</div>
      <div class="fg" style="margin-bottom:10px">
        <input id="tsearch" placeholder="Search tables..." oninput="filterT()"/>
      </div>
      <div class="tlist" id="tlist"><div style="color:var(--mut);font-size:11px;padding:16px;text-align:center">Loading...</div></div>
      <button class="btn ba" style="width:100%" onclick="loadTables()">↺ REFRESH</button>
    </div>
  </div>

  <div>
    <div class="card" id="datapanel">
      <div style="padding:50px;text-align:center;color:var(--mut);letter-spacing:.1em">
        SELECT A TABLE ON THE LEFT TO VIEW DATA
      </div>
    </div>
  </div>

</div>
</div><!-- /t-view -->

<!-- ══ TAB: GUIDE ════════════════════════════════════════════════════════════ -->
<div id="t-guide" style="display:none">
<div style="max-width:760px">
<div class="card">
  <div class="ctitle">INFRASTRUCTURE SETUP — WHAT TO DO IF CONNECTION FAILS</div>

  <div class="al aw" style="margin-bottom:18px">
    ⚠ If "TEST CONNECTION" shows "ODBC driver not found" — follow Step 1 below.
  </div>

  <div style="font-size:9px;letter-spacing:.18em;color:var(--gld);margin-bottom:8px">STEP 1 — INSTALL IBM iSERIES ODBC DRIVER (one time only)</div>
  <div class="code">
    # Ubuntu / Debian:<br>
    wget https://public.dhe.ibm.com/software/ibmi/products/odbc/debs/dists/1.1.0/ibm-iaccess_1.1.0.23-0_amd64.deb<br>
    sudo dpkg -i ibm-iaccess_1.1.0.23-0_amd64.deb<br>
    sudo apt-get install -f<br><br>
    # Verify:<br>
    odbcinst -q -d &nbsp;&nbsp;# should show: [IBM i Access ODBC Driver]
  </div>

  <div style="font-size:9px;letter-spacing:.18em;color:var(--gld);margin:16px 0 8px">STEP 2 — CHECK FIREWALL / NETWORK (ports AS/400 needs)</div>
  <div class="code">
    # Test if port 449 is open from this Linux server to AS/400:<br>
    nc -zv YOUR_AS400_IP 449<br><br>
    # Ports to open in firewall/switch between Linux ↔ AS/400:<br>
    # 449, 8471, 9470, 9471, 9472, 9473, 9474, 9475
  </div>

  <div style="font-size:9px;letter-spacing:.18em;color:var(--gld);margin:16px 0 8px">STEP 3 — BACKUP AFTER MIGRATION (IMPORTANT for government case)</div>
  <div class="code">
    pg_dump -U financeadmin finance_db > finance_backup_$(date +%Y%m%d).sql<br><br>
    # Store this .sql file on an external drive or secure network share
  </div>

  <div style="font-size:9px;letter-spacing:.18em;color:var(--gld);margin:16px 0 8px">STEP 4 — SHARE WITH CFO (browser access)</div>
  <div class="code">
    # Find this server's IP:<br>
    ip addr show | grep "inet "<br><br>
    # CFO opens browser on any computer on the same network:<br>
    http://&lt;THIS-SERVER-IP&gt;:8000<br><br>
    # If firewall blocks it:<br>
    sudo ufw allow 8000
  </div>

  <div style="font-size:9px;letter-spacing:.18em;color:var(--gld);margin:16px 0 8px">RESTART PORTAL AFTER SERVER REBOOT</div>
  <div class="code">
    cd /opt/as400-finance-portal<br>
    python3 server.py
  </div>
</div>
</div>
</div><!-- /t-guide -->

</main>
</div><!-- /app -->

<div id="toast"></div>

<script>
// ── pre-fill from config ─────────────────────────────────────────────────────
fetch('/api/config').then(r=>r.json()).then(c=>{
  if(c.ip)  document.getElementById('ip').value  = c.ip;
  if(c.usr) document.getElementById('usr').value = c.usr;
  if(c.lib) document.getElementById('lib').value = c.lib;
}).catch(()=>{});

// ── clock ────────────────────────────────────────────────────────────────────
setInterval(()=>{
  document.getElementById('clk').textContent =
    new Date().toLocaleString('en-IN',{timeZone:'Asia/Kolkata'}).replace(',',' |');
},1000);

// ── DB health ────────────────────────────────────────────────────────────────
async function chkDB(){
  try{
    const r=await fetch('/api/tables');
    if(r.ok){
      document.getElementById('dbdot').className='dot on';
      const st=document.getElementById('dbst');
      st.style.color='var(--grn)'; st.textContent='DB READY';
    }
  }catch(e){
    document.getElementById('dbdot').className='dot';
    document.getElementById('dbst').textContent='DB ERROR';
  }
}
setInterval(chkDB,8000); chkDB();

// ── tabs ─────────────────────────────────────────────────────────────────────
function tab(t){
  ['mig','view','guide'].forEach((n,i)=>{
    document.getElementById('t-'+n).style.display = n===t?'':'none';
    document.querySelectorAll('.tab')[i].className = 'tab'+(n===t?' on':'');
  });
  if(t==='view') loadTables();
}

// ── toast ────────────────────────────────────────────────────────────────────
function toast(msg,type='info'){
  const c={info:'#00D4FF',success:'#00FF9C',error:'#FF4060',warn:'#FFB800'};
  const el=document.getElementById('toast');
  el.style.cssText=`display:block;animation:si .25s ease;border:1px solid ${c[type]}44;background:${c[type]}10;color:${c[type]}`;
  el.textContent=msg;
  setTimeout(()=>el.style.display='none',3500);
}

// ── step helpers ─────────────────────────────────────────────────────────────
function step(n,s){ document.getElementById('s'+n).className='step '+(s==='done'?'done':s==='act'?'act':''); }

// ── connection test ───────────────────────────────────────────────────────────
let connOK=false;
async function doTest(){
  const btn=document.getElementById('btnTest');
  const res=document.getElementById('testRes');
  btn.disabled=true; btn.textContent='▶ CONNECTING...';
  res.innerHTML='<div class="al ai">Connecting — this can take up to 20 seconds...</div>';
  step(2,'act');
  try{
    const r=await fetch('/api/test',{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        ip:  document.getElementById('ip').value,
        user:document.getElementById('usr').value,
        pwd: document.getElementById('pwd').value,
        port:document.getElementById('port').value
      })});
    const d=await r.json();
    if(d.ok){
      res.innerHTML=`<div class="al as">✔ ${d.msg}</div>`;
      connOK=true;
      step(2,'done'); step(3,'done'); step(4,'act');
      document.getElementById('btnMig').disabled=false;
      document.getElementById('btnLibs').style.display='';
      toast('Connected to AS/400!','success');
    }else{
      const extra = d.msg.includes('driver') ?
        '<br><small>→ See the Setup Guide tab to install the IBM ODBC driver.</small>' : '';
      res.innerHTML=`<div class="al ae">✘ ${d.msg}${extra}</div>`;
      step(2,'');
      toast('Connection failed','error');
    }
  }catch(e){
    res.innerHTML=`<div class="al ae">Server error: ${e.message}</div>`;
  }
  btn.disabled=false; btn.textContent='▶ TEST CONNECTION';
}

// ── list libraries ────────────────────────────────────────────────────────────
async function doLibs(){
  try{
    const r=await fetch('/api/libraries',{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        ip:  document.getElementById('ip').value,
        user:document.getElementById('usr').value,
        pwd: document.getElementById('pwd').value
      })});
    const d=await r.json();
    if(d.libs && d.libs.length){
      const list=d.libs.join(' &nbsp;|&nbsp; ');
      document.getElementById('testRes').innerHTML+=
        `<div class="al ai" style="margin-top:8px">Available libraries: <strong style="color:var(--wht)">${list}</strong></div>`;
    }
  }catch(e){ toast('Could not list libraries: '+e.message,'warn'); }
}

// ── migration ─────────────────────────────────────────────────────────────────
let poll;
async function doMigrate(){
  if(!connOK){ toast('Test connection first!','warn'); return; }
  document.getElementById('btnMig').disabled=true;
  document.getElementById('progCard').style.display='';
  step(4,'act');
  try{
    await fetch('/api/migrate',{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        ip:  document.getElementById('ip').value,
        user:document.getElementById('usr').value,
        pwd: document.getElementById('pwd').value,
        lib: document.getElementById('lib').value
      })});
    toast('Migration started!','info');
    poll=setInterval(pollMig,1500);
  }catch(e){
    toast('Failed: '+e.message,'error');
    document.getElementById('btnMig').disabled=false;
  }
}

async function pollMig(){
  try{
    const s=await (await fetch('/api/migrate/status')).json();
    document.getElementById('pfill').style.width=s.progress+'%';
    document.getElementById('ppct').textContent=s.progress+'%';
    document.getElementById('plbl').textContent=
      s.current ? 'Migrating: '+s.current : (s.done ? 'Complete!' : 'Preparing...');
    document.getElementById('stTbl').textContent=s.tables_done.length;
    document.getElementById('stRow').textContent=(s.total_rows||0).toLocaleString();
    document.getElementById('stErr').textContent=s.tables_failed.length;

    const lb=document.getElementById('mlog');
    lb.innerHTML=s.log.slice(-80).map(l=>{
      const c=l.includes('✔')||l.includes('complete')?'lk':l.includes('✘')||l.includes('FATAL')?'le':l.includes('WARN')?'lw':'ll';
      return `<div class="${c}">${l}</div>`;
    }).join('');
    lb.scrollTop=lb.scrollHeight;

    if(s.done){
      clearInterval(poll);
      step(4,'done'); step(5,'done');
      document.getElementById('btnGoView').style.display='';
      document.getElementById('btnMig').disabled=false;
      toast(`Done! ${s.tables_done.length} tables, ${(s.total_rows||0).toLocaleString()} rows.`,'success');
    }
    if(s.error){ clearInterval(poll); document.getElementById('btnMig').disabled=false; }
  }catch(e){}
}

// ── table viewer ──────────────────────────────────────────────────────────────
let allT=[], curT='';
async function loadTables(){
  try{
    const d=await (await fetch('/api/tables')).json();
    allT=d.tables||[];
    renderT(allT);
  }catch(e){
    document.getElementById('tlist').innerHTML=
      '<div class="al ae">Cannot reach server</div>';
  }
}
function filterT(){
  const q=document.getElementById('tsearch').value.toLowerCase();
  renderT(allT.filter(t=>t.name.toLowerCase().includes(q)));
}
function renderT(list){
  const el=document.getElementById('tlist');
  if(!list.length){
    el.innerHTML='<div style="color:var(--mut);font-size:11px;padding:16px;text-align:center">No tables found.<br>Run migration first.</div>';
    return;
  }
  el.innerHTML=list.map(t=>`
    <div class="ti${t.name===curT?' on':''}" onclick="loadData('${t.name}')">
      <div><div class="tn">${t.name}</div><div class="tm">${t.size||''}</div></div>
      <span style="color:var(--mut);font-size:11px">→</span>
    </div>`).join('');
}

async function loadData(name){
  curT=name; renderT(allT);
  const panel=document.getElementById('datapanel');
  panel.innerHTML='<div class="ctitle">LOADING...</div>';
  try{
    const d=await (await fetch(`/api/table/${encodeURIComponent(name)}?limit=500`)).json();
    renderData(d);
  }catch(e){
    panel.innerHTML=`<div class="al ae">Error: ${e.message}</div>`;
  }
}

function renderData(d){
  const panel=document.getElementById('datapanel');
  const th=d.cols.map(c=>`<th>${c.toUpperCase()}</th>`).join('');
  const tb=d.rows.map(r=>`<tr>${d.cols.map(c=>`<td title="${r[c]||''}">${r[c]||''}</td>`).join('')}</tr>`).join('');
  panel.innerHTML=`
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;flex-wrap:wrap;gap:8px">
      <div class="ctitle" style="margin:0">${d.name.toUpperCase()}</div>
      <span style="font-size:10px;color:var(--mut);letter-spacing:.1em">${d.total.toLocaleString()} TOTAL ROWS</span>
    </div>
    <div class="ebar">
      <button class="btn bg" onclick="exp('csv')">↓ EXPORT CSV</button>
      <button class="btn br" onclick="exp('excel')">↓ EXPORT EXCEL</button>
      <span class="ecount">Showing ${d.rows.length} of ${d.total.toLocaleString()}</span>
    </div>
    <div class="dt-wrap"><table class="dt"><thead><tr>${th}</tr></thead><tbody>${tb}</tbody></table></div>
    ${d.total>500?'<div style="font-size:10px;color:var(--mut);margin-top:8px;letter-spacing:.06em">Showing first 500 rows. Export to get all records.</div>':''}
  `;
}

function exp(fmt){
  if(!curT){ toast('Select a table first','warn'); return; }
  window.open(`/api/export/${encodeURIComponent(curT)}/${fmt}`,'_blank');
  toast(`Downloading ${curT}.${fmt==='csv'?'csv':'xlsx'}`,'success');
}

loadTables();
</script>
</body>
</html>
HTMLEOF

ok "Web interface written"

# ── Add /api/config endpoint so UI can pre-fill fields ────────────────────────
cat >> "$PORTAL_DIR/server.py" << 'CFGEP'

@app.get("/api/config")
async def get_config():
    return {
        "ip":  CFG.get("as400_ip",""),
        "usr": CFG.get("as400_user",""),
        "lib": CFG.get("as400_lib",""),
    }
CFGEP

# =============================================================================
#  STEP 4 — WRITE SYSTEMD SERVICE
# =============================================================================
echo ""
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}${B}  STEP 4 OF 5 — SETTING UP AUTO-START SERVICE${N}"
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

cat > /etc/systemd/system/as400-portal.service << SVCEOF
[Unit]
Description=AS/400 Finance Portal
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=$PORTAL_DIR
ExecStart=/usr/bin/python3 $PORTAL_DIR/server.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable as400-portal 2>/dev/null || true
ok "Service registered — portal will auto-start on server reboot"

# Open firewall if ufw is active
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow 8000/tcp >/dev/null 2>&1 || true
    ok "Firewall rule added for port 8000"
fi

# =============================================================================
#  STEP 5 — START THE PORTAL
# =============================================================================
echo ""
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${C}${B}  STEP 5 OF 5 — STARTING PORTAL${N}"
echo -e "${C}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR-SERVER-IP")

echo -e "${G}${B}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                                                              ║"
echo "  ║  ✔  Installation Complete!                                   ║"
echo "  ║                                                              ║"
echo "  ║  Open this URL in any browser on your network:              ║"
echo "  ║                                                              ║"
echo "  ║     http://${SERVER_IP}:8000"
echo "  ║                                                              ║"
echo "  ║  Your AS/400 credentials have been pre-filled.              ║"
echo "  ║  Just enter your password and click TEST CONNECTION.         ║"
echo "  ║                                                              ║"
echo "  ║  Log file: $LOG_FILE"
echo "  ║                                                              ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${N}"
echo "  Starting portal now... Press Ctrl+C to stop."
echo "  (It will auto-restart on next reboot via systemd)"
echo ""

cd "$PORTAL_DIR"
exec python3 server.py
