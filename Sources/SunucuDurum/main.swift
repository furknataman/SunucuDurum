import Foundation

if CommandLine.arguments.contains("--dump") {
    exit(Dokum.calistir())
}
SunucuDurumApp.main()

/// `--dump`: veriyi sunucudan alır, çözümler ve okunur biçimde yazdırır.
enum Dokum {
    static func calistir() -> Int32 {
        let r: Rapor
        do { r = try Toplayici.raporAl() } catch {
            FileHandle.standardError.write(Data("HATA: \(error.localizedDescription)\n".utf8))
            return 1
        }
        let simdi = Date()
        var o: [String] = []
        o.append("\(Ayar.mevcut.ad) · \(Bicim.tarihSaat(Date(timeIntervalSince1970: Double(r.zaman))))")
        if let s = r.sistem {
            o.append("Açık kalma: \(Bicim.sure(s.acikKalma))")
            o.append("İşlemci: \(Bicim.yuzde(s.cpuYuzde)) (yük \(Bicim.sayi(s.yuk1, basamak: 2)) / \(s.cekirdek) çekirdek)")
            o.append("RAM: \(Bicim.yuzde(s.ramYuzde)) (\(Bicim.bayt(s.ramKullanilan)) / \(Bicim.bayt(s.ramToplam)))")
            o.append("Disk: \(Bicim.yuzde(s.diskYuzde)) (\(Bicim.bayt(s.diskKullanilan)) / \(Bicim.bayt(s.diskKullanilan + s.diskBos)))")
        }
        if let a = r.ag { o.append("Ağ (\(a.arayuz)): ↓ \(Bicim.hiz(a.indirme))  ↑ \(Bicim.hiz(a.yukleme))") }
        o.append("Projeler:")
        for p in Proje.grupla(r.konteynerler) {
            let k = p.konteynerler.map { "\($0.ad) [\($0.durumMetni), \($0.sureMetni)]" }.joined(separator: ", ")
            o.append("  \(p.ad): \(k)")
        }
        o.append("Servisler: " + r.servisler.map { "\($0.gorunenAd) \($0.durumMetni.lowercased(with: Bicim.tr))" }.joined(separator: ", "))
        o.append("Yedekler: " + r.yedekler.map { y in "\(y.ad) " + (y.saatOnce(simdi: simdi).map { "\($0) saat önce" } ?? "yok") }.joined(separator: ", "))
        o.append("VPN: " + r.vpn.map { e in
            e.bagli(simdi: simdi) ? "\(e.ad) bağlı"
                : e.sonGorulme.map { "\(e.ad) son görülme \(Bicim.once(Date(timeIntervalSince1970: Double($0)), simdi: simdi))" } ?? "\(e.ad) hiç bağlanmadı"
        }.joined(separator: ", "))
        if let a = r.adguard {
            o.append("AdGuard: DNS \(a.calisiyor ? "yanıt veriyor" : "yanıt vermiyor"), \(a.sorgu.map(Bicim.tam) ?? "?") sorgu, \(a.engellenen.map(Bicim.tam) ?? "?") engellendi (24 saat)")
        }
        o.append("Çalışan görevler: " + (r.gorevler.isEmpty ? "yok" : r.gorevler.joined(separator: ", ")))
        if let s = r.saglikRaporu { o.append("Son sağlık raporu: \(s.ad) (\(Bicim.tarihSaat(Date(timeIntervalSince1970: Double(s.zaman)))))") }
        let sorunlar = r.sorunlar(simdi: simdi)
        o.append(sorunlar.isEmpty ? "Durum: her şey yolunda" : "Uyarılar (\(sorunlar.count)): " + sorunlar.joined(separator: "; "))
        print(o.joined(separator: "\n"))
        return 0
    }
}
