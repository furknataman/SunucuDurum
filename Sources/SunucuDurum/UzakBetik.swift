import Foundation

// Sunucuda `bash -s` ile çalışan uzak betik. YALNIZCA okur: hiçbir dosya yazmaz, kurulum ya da ayar değişikliği yapmaz.
// AdGuard şifresi sunucuda kalır; çıktıya hiç yazılmaz.
enum UzakBetik {
    /// Ayar JSON + base64 olarak betiğe argüman verilir; alan alan metin birleştirmesi yapılmaz.
    static func metin(_ ayar: Ayar) -> String {
        let json = (try? JSONEncoder().encode(ayar)) ?? Data()
        return sablon.replacingOccurrences(of: "__AYAR__", with: json.base64EncodedString())
    }

    private static let sablon = #"""
# Sunucuda `bash -s` ile çalışır. Yalnızca okur; hiçbir şey yazmaz/kurmaz.
exec python3 - "__AYAR__" <<'PY'
import base64, json, os, shlex, subprocess, sys, time, glob

cfg = json.loads(base64.b64decode(sys.argv[1]))

def sh(cmd, timeout=6):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""

def safe(f, default=None):
    try:
        return f()
    except Exception:
        return default

def net():
    for line in open("/proc/net/dev"):
        if line.strip().startswith(cfg["agArayuzu"] + ":"):
            p = line.split(":", 1)[1].split()
            return int(p[0]), int(p[8])
    return None

def cpu():
    p = [int(x) for x in open("/proc/stat").readline().split()[1:]]
    return sum(p), p[3] + p[4]

t0 = time.monotonic(); n0 = safe(net); c0 = safe(cpu)
time.sleep(1.0)
now = int(time.time())
out = {"zaman": now}

def sistem():
    l1, l5, l15 = open("/proc/loadavg").read().split()[:3]
    mem = {}
    for line in open("/proc/meminfo"):
        k, v = line.split(":"); mem[k] = int(v.split()[0]) * 1024
    st = os.statvfs("/")
    toplam = st.f_blocks * st.f_frsize; bos = st.f_bavail * st.f_frsize
    kullanilan = (st.f_blocks - st.f_bfree) * st.f_frsize
    up = float(open("/proc/uptime").read().split()[0])
    c1 = safe(cpu)
    kullanim = (1 - (c1[1] - c0[1]) / (c1[0] - c0[0])) * 100 if c0 and c1 and c1[0] > c0[0] else None
    return {"cpu": kullanim, "yuk1": float(l1), "yuk5": float(l5), "yuk15": float(l15), "cekirdek": os.cpu_count(),
            "ramToplam": mem["MemTotal"], "ramKullanilan": mem["MemTotal"] - mem["MemAvailable"],
            "diskToplam": toplam, "diskKullanilan": kullanilan, "diskBos": bos,
            "acikKalma": int(up)}
out["sistem"] = safe(sistem)

def konteynerler():
    r = []
    for line in sh("""docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}'""").splitlines():
        ad, durum, metin, proje, servis = (line.split("|", 4) + ["", "", ""])[:5]
        saglik = "healthy" if "(healthy)" in metin else "unhealthy" if "(unhealthy)" in metin else "starting" if "(health: starting)" in metin else None
        r.append({"ad": ad, "durum": durum, "metin": metin, "saglik": saglik,
                  "proje": proje or None, "servis": servis or None})
    return r
out["konteynerler"] = safe(konteynerler, [])

def servis(s):
    r = safe(lambda: subprocess.run(["systemctl", "is-active", s], capture_output=True, text=True, timeout=4).stdout.strip())
    return {"ad": s, "durum": r or "bilinmiyor"}
out["servisler"] = [servis(s) for s in [x["ad"] for x in cfg["servisler"]]]

def vpn():
    adlar = {}; ad = None
    for line in open("/etc/wireguard/" + cfg["vpn"]["arayuz"] + ".conf"):
        s = line.strip()
        if s.startswith("[Peer]"): ad = None
        elif s.startswith("# ") and ad is None: ad = s[2:].split()[0] if s[2:].split() else None
        elif s.startswith("PublicKey"): adlar[s.split("=", 1)[1].strip()] = ad or "?"
    hs = {}
    for line in sh("wg show " + shlex.quote(cfg["vpn"]["arayuz"]) + " latest-handshakes").splitlines():
        p = line.split()
        if len(p) == 2: hs[p[0]] = int(p[1])
    return [{"ad": a, "sonGorulme": (hs.get(k) or None)} for k, a in adlar.items()]
out["vpn"] = safe(vpn, [])

def adguard():
    a = cfg["adguard"]
    calisiyor = bool(sh("dig +short +time=2 +tries=1 @" + shlex.quote(a["adres"]) + " " + shlex.quote(a["testAlanAdi"]), 5).strip())
    sorgu = engel = None
    sifre = ""
    for line in safe(lambda: open(a["sifreDosyasi"]).read().splitlines(), []):
        if line.startswith("sifre: "): sifre = line[7:].strip()
    if sifre:
        r = safe(lambda: subprocess.run(["curl", "-s", "-m", "4", "-K", "-", "http://%s:%d/control/stats" % (a["adres"], a["port"])],
                                        input=f'user = "admin:{sifre}"\n', capture_output=True, text=True, timeout=6).stdout)
        d = safe(lambda: json.loads(r))
        if d: sorgu, engel = d.get("num_dns_queries"), d.get("num_blocked_filtering")
    return {"calisiyor": calisiyor, "sorgu": sorgu, "engellenen": engel}
out["adguard"] = safe(adguard)

def yedekler():
    r = []
    for y in cfg["yedekler"]:
        ad, d, pat = y["ad"], y["klasor"], y["desen"]
        f = [os.path.getmtime(x) for x in glob.glob(os.path.join(d, pat))]
        r.append({"ad": ad, "zaman": int(max(f)) if f else None})
    return r
out["yedekler"] = safe(yedekler, [])

def saglik():
    f = sorted(glob.glob(os.path.join(cfg["saglikKlasoru"], "*.md")), key=os.path.getmtime)
    if not f: return None
    metin = open(f[-1]).read()
    govde = [x.strip() for x in metin.splitlines() if x.strip() and not x.startswith("#")]
    return {"ad": os.path.basename(f[-1])[:-3], "zaman": int(os.path.getmtime(f[-1])),
            "tamam": "yolunda" in metin and "hata yok" in metin, "ozet": govde[0] if govde else ""}
out["saglikRaporu"] = safe(saglik)

def gorevler():
    import sqlite3
    d = cfg["gorevKlasoru"].rstrip("/") + "/"
    adlar = {j["id"]: j.get("name") or j["id"] for j in json.load(open(d + "jobs.json")).get("jobs", [])}
    db = sqlite3.connect("file:" + d + "executions.db?mode=ro", uri=True, timeout=2)
    return [adlar.get(r[0], r[0]) for r in db.execute("select job_id from executions where status in ('claimed','running') order by claimed_at")]
out["gorevler"] = safe(gorevler, [])

n1 = safe(net); dt = time.monotonic() - t0
out["ag"] = {"arayuz": cfg["agArayuzu"], "indirme": (n1[0] - n0[0]) / dt, "yukleme": (n1[1] - n0[1]) / dt} if n0 and n1 else None
print(json.dumps(out, ensure_ascii=False))
PY
"""#
}
