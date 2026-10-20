import Foundation

// MARK: - Uzak betiğin JSON çıktısı

struct Rapor: Codable {
    let zaman: Int
    let sistem: Sistem?
    let konteynerler: [Konteyner]
    let servisler: [Servis]
    let vpn: [VPNEs]
    let adguard: AdGuard?
    let yedekler: [Yedek]
    let saglikRaporu: SaglikRaporu?
    let gorevler: [String]
    let ag: Ag?
}

struct Sistem: Codable {
    let cpu: Double?       // /proc/stat'tan ölçülen gerçek kullanım (%)
    let yuk1, yuk5, yuk15: Double
    let cekirdek: Int
    let ramToplam, ramKullanilan: Int64
    let diskToplam, diskKullanilan, diskBos: Int64
    let acikKalma: Int

    var cpuYuzde: Double { cpu ?? yuk1 / Double(max(cekirdek, 1)) * 100 }
    var ramYuzde: Double { Double(ramKullanilan) / Double(max(ramToplam, 1)) * 100 }
    /// df ile aynı hesap: kullanılan / (kullanılan + kullanılabilir)
    var diskYuzde: Double { Double(diskKullanilan) / Double(max(diskKullanilan + diskBos, 1)) * 100 }
}

struct Konteyner: Codable, Identifiable {
    let ad: String
    let durum: String      // running, exited, restarting, paused, dead, created
    let metin: String      // "Up 15 hours (healthy)"
    let saglik: String?    // healthy, unhealthy, starting
    let proje: String?     // compose proje etiketi (compose dışı konteynerde yok)
    let servis: String?    // compose servis etiketi
    var id: String { ad }

    /// "proje-web-1" → "web" (compose etiketinden), "proje-api" → "api"
    var kisaAd: String {
        if let p = proje, let s = servis, ad.hasPrefix("\(p)-\(s)-"), Int(ad.dropFirst(p.count + s.count + 2)) != nil { return s }
        let p = ad.split(separator: "-")
        return p.count > 1 ? String(p.last!) : ad
    }

    var seviye: Seviye {
        switch durum {
        case "running": return saglik == "unhealthy" ? .uyari : .iyi
        case "restarting", "paused", "created": return .uyari
        default: return .kritik
        }
    }

    var durumMetni: String {
        switch durum {
        case "running":
            switch saglik {
            case "healthy": return "Sağlıklı"
            case "unhealthy": return "Sağlıksız"
            case "starting": return "Başlatılıyor"
            default: return "Çalışıyor"
            }
        case "restarting": return "Yeniden başlatılıyor"
        case "paused": return "Duraklatıldı"
        case "created": return "Oluşturuldu"
        case "dead": return "Çöktü"
        default: return "Durdu"
        }
    }

    /// "Up 15 hours (healthy)" → "15 sa", "Exited (0) 3 days ago" → "3 gün önce"
    var sureMetni: String {
        var s = metin.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
        let onceMi = s.hasSuffix(" ago")
        s = s.replacingOccurrences(of: " ago", with: "")
        for onek in ["Up ", "Exited ", "Restarting ", "Created", "Dead"] where s.hasPrefix(onek) {
            s = String(s.dropFirst(onek.count))
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        let sozluk: [(String, String)] = [
            ("Less than a second", "1 sn"), ("About a minute", "1 dk"), ("About an hour", "1 sa"),
            ("About a day", "1 gün"), ("About a week", "1 hafta"), ("About a month", "1 ay"), ("About a year", "1 yıl"),
            ("an hour", "1 sa"), ("a minute", "1 dk"), ("a day", "1 gün"),
        ]
        for (en, tr) in sozluk where s == en { return onceMi ? "\(tr) önce" : tr }
        let birimler: [String: String] = [
            "second": "sn", "seconds": "sn", "minute": "dk", "minutes": "dk", "hour": "sa", "hours": "sa",
            "day": "gün", "days": "gün", "week": "hafta", "weeks": "hafta", "month": "ay", "months": "ay",
            "year": "yıl", "years": "yıl",
        ]
        let p = s.split(separator: " ")
        if p.count == 2, let b = birimler[String(p[1])] {
            let t = "\(p[0]) \(b)"
            return onceMi ? "\(t) önce" : t
        }
        return s
    }
}

struct Servis: Codable, Identifiable {
    let ad: String
    let durum: String
    var id: String { ad }
    var seviye: Seviye { durum == "active" ? .iyi : (durum == "activating" || durum == "reloading") ? .uyari : .kritik }
    var durumMetni: String {
        switch durum {
        case "active": return "Etkin"
        case "inactive": return "Etkin değil"
        case "failed": return "Hatalı"
        case "activating": return "Başlatılıyor"
        case "reloading": return "Yeniden yükleniyor"
        default: return "Bilinmiyor"
        }
    }
    var gorunenAd: String {
        Ayar.mevcut.servisler.first { $0.ad == ad }?.gorunenAd ?? ad
    }
}

struct VPNEs: Codable, Identifiable {
    let ad: String
    let sonGorulme: Int?
    var id: String { ad }
    func bagli(simdi: Date) -> Bool {
        guard let t = sonGorulme else { return false }
        return simdi.timeIntervalSince1970 - Double(t) < 180
    }
}

struct AdGuard: Codable {
    let calisiyor: Bool
    let sorgu: Int?
    let engellenen: Int?
}

struct Yedek: Codable, Identifiable {
    let ad: String
    let zaman: Int?
    var id: String { ad }
    func saatOnce(simdi: Date) -> Int? {
        guard let z = zaman else { return nil }
        return max(0, Int(simdi.timeIntervalSince1970 - Double(z)) / 3600)
    }
}

struct SaglikRaporu: Codable {
    let ad: String
    let zaman: Int
    let tamam: Bool
    let ozet: String
}

struct Ag: Codable {
    let arayuz: String
    let indirme: Double   // bayt/sn
    let yukleme: Double
}

// MARK: - Seviye

enum Seviye: Int, Comparable {
    case iyi, uyari, kritik
    static func < (a: Seviye, b: Seviye) -> Bool { a.rawValue < b.rawValue }

    static func yuzde(_ v: Double) -> Seviye { v < 70 ? .iyi : v < 90 ? .uyari : .kritik }
}

// MARK: - Projeler

struct Proje: Identifiable {
    let ad: String
    let sembol: String
    let konteynerler: [Konteyner]
    var id: String { ad }
    var seviye: Seviye { konteynerler.map(\.seviye).max() ?? .iyi }

    static var tanimlar: [Ayar.Proje] { Ayar.mevcut.projeler }

    static func grupla(_ liste: [Konteyner]) -> [Proje] {
        var kalan = liste
        var sonuc: [Proje] = []
        for t in tanimlar {
            // Önek konteyner adı ya da compose proje etiketi olabilir.
            let uyan = t.onekler.flatMap { o in liste.filter { $0.ad == o || $0.proje == o }.sorted { $0.ad < $1.ad } }
            kalan.removeAll { k in t.onekler.contains { k.ad == $0 || k.proje == $0 } }
            if !uyan.isEmpty { sonuc.append(Proje(ad: t.ad, sembol: t.sembol, konteynerler: uyan)) }
        }
        // Tanımsız compose projeleri kendi adıyla gruplanır.
        for p in Set(kalan.compactMap(\.proje)).sorted() {
            sonuc.append(Proje(ad: p, sembol: "shippingbox.fill", konteynerler: kalan.filter { $0.proje == p }))
            kalan.removeAll { $0.proje == p }
        }
        if !kalan.isEmpty { sonuc.append(Proje(ad: "Diğer", sembol: "shippingbox.fill", konteynerler: kalan)) }
        return sonuc
    }
}

// MARK: - Sorunlar

extension Rapor {
    func sorunlar(simdi: Date = .now) -> [String] {
        var s: [String] = []
        if let si = sistem {
            if si.ramYuzde >= 90 { s.append("RAM kullanımı %\(Int(si.ramYuzde))") }
            if si.diskYuzde >= 85 { s.append("Disk doluluğu %\(Int(si.diskYuzde))") }
            if si.cpuYuzde >= 90 { s.append("İşlemci yükü %\(Int(si.cpuYuzde))") }
        } else {
            s.append("Sistem bilgisi okunamadı")
        }
        for k in konteynerler where k.seviye != .iyi { s.append("\(k.ad): \(k.durumMetni.lowercased(with: Bicim.tr))") }
        for sv in servisler where sv.seviye != .iyi { s.append("\(sv.gorunenAd) servisi: \(sv.durumMetni.lowercased(with: Bicim.tr))") }
        if let h = saglikRaporu, !h.tamam { s.append("Sağlık raporu: \(h.ozet)") }
        if adguard?.calisiyor != true { s.append("AdGuard DNS yanıt vermiyor") }
        for y in yedekler {
            if let h = y.saatOnce(simdi: simdi) {
                if h > 26 { s.append("\(y.ad) yedeği \(h) saat önce alınmış") }
            } else {
                s.append("\(y.ad) yedeği bulunamadı")
            }
        }
        return s
    }
}

// MARK: - Biçimlendirme (Türkçe)

enum Bicim {
    static let tr = Locale(identifier: "tr_TR")

    static func sayi(_ v: Double, basamak: Int = 0) -> String {
        v.formatted(.number.precision(.fractionLength(basamak)).locale(tr))
    }

    static func tam(_ v: Int) -> String { v.formatted(.number.locale(tr)) }

    static func yuzde(_ v: Double) -> String { "%" + sayi(v) }

    static func bayt(_ b: Int64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 100 { return sayi(gb) + " GB" }
        if gb >= 1 { return sayi(gb, basamak: 1) + " GB" }
        return sayi(Double(b) / 1_048_576) + " MB"
    }

    static func hiz(_ bps: Double) -> String {
        switch bps {
        case ..<1024: return sayi(bps) + " B/sn"
        case ..<1_048_576: return sayi(bps / 1024, basamak: bps < 10_240 ? 1 : 0) + " KB/sn"
        default: return sayi(bps / 1_048_576, basamak: 1) + " MB/sn"
        }
    }

    /// Saniye cinsinden süre → "3 gün 4 sa", "5 sa 12 dk", "8 dk"
    static func sure(_ sn: Int) -> String {
        let g = sn / 86400, s = (sn % 86400) / 3600, d = (sn % 3600) / 60
        if g > 0 { return s > 0 ? "\(g) gün \(s) sa" : "\(g) gün" }
        if s > 0 { return d > 0 ? "\(s) sa \(d) dk" : "\(s) sa" }
        return "\(max(d, 1)) dk"
    }

    static func once(_ tarih: Date, simdi: Date = .now) -> String {
        let sn = Int(simdi.timeIntervalSince(tarih))
        if sn < 60 { return "az önce" }
        if sn < 3600 { return "\(sn / 60) dk önce" }
        if sn < 86400 { return "\(sn / 3600) sa önce" }
        return "\(sn / 86400) gün önce"
    }

    static func tarihSaat(_ t: Date) -> String {
        t.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(tr))
    }
}
