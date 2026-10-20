import Foundation
import Observation

/// Mac'in kendi WireGuard tüneli (adı ayardan gelir). Tünel NetworkExtension tabanlıdır; `scutil --nc` ile yönetilir (sudo gerekmez).
@MainActor
@Observable
final class MacVPN {
    enum Hal: Equatable {
        case bilinmiyor, kuruluDegil, tunelYok, kapali, baglaniyor, bagli, kesiliyor
    }

    nonisolated static let tunel = Ayar.mevcut.vpn.tunel
    nonisolated static let uygulamaYolu = "/Applications/WireGuard.app"
    nonisolated static let ayarDosyasi = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(Ayar.mevcut.vpn.ayarDosyasi)
    static let adGuardPaneli = URL(string: "http://\(Ayar.mevcut.adguard.adres):\(Ayar.mevcut.adguard.port)")!
    static let magaza = URL(string: "macappstore://apps.apple.com/app/wireguard/id1451685025")!

    private(set) var hal: Hal = .bilinmiyor
    private(set) var adres: String?
    private(set) var hata: String?
    private(set) var ayarDosyasiVar = false

    var bagli: Bool { hal == .bagli }
    /// Anahtarın açık görünmesi gereken haller.
    var acik: Bool { hal == .bagli || hal == .baglaniyor }
    var mesgul: Bool { hal == .baglaniyor || hal == .kesiliyor }

    private var izleme: Task<Void, Never>?
    private var gecis: Task<Void, Never>?
    /// Anahtardan başlatılan geçişin hedefi; `scutil start/stop` döndükten sonra durum bir süre eski halde görünür.
    private var hedef: Hal?

    /// `-vpnDeneme kuruluDegil|tunelYok|kapali|baglaniyor|bagli` ile arayüz durumları elle denenebilir.
    private let deneme = UserDefaults.standard.string(forKey: "vpnDeneme")

    func yenile() async {
        if let d = deneme { uygula(deneme: d); return }
        let o = await Task.detached(priority: .utility) { Self.oku() }.value
        if let h = hedef {
            if o.hal == h { hedef = nil }
            else if o.hal == (h == .bagli ? .kapali : .bagli) { return }   // geçiş henüz yansımadı
        }
        hal = o.hal
        adres = o.adres
        ayarDosyasiVar = o.ayarVar
    }

    func degistir(ac: Bool) {
        guard hal == .kapali || hal == .bagli || hal == .baglaniyor else { return }
        hata = nil
        hal = ac ? .baglaniyor : .kesiliyor
        if deneme != nil { return }
        gecis?.cancel()
        hedef = ac ? .bagli : .kapali
        gecis = Task { [weak self] in
            let komut = ac ? "start" : "stop"
            let c = await Task.detached(priority: .userInitiated) { Self.calistir("/usr/sbin/scutil", ["--nc", komut, Self.tunel]) }.value
            guard let self, !Task.isCancelled else { return }
            if c.kod != 0 {
                let m = c.cikti.trimmingCharacters(in: .whitespacesAndNewlines)
                self.hata = m.isEmpty ? (ac ? "Tünel başlatılamadı." : "Tünel durdurulamadı.") : String(m.prefix(120))
                self.hedef = nil
            }
            // Hedef duruma ulaşana kadar (en çok ~20 sn) sık aralıkla yeniden oku.
            for _ in 0..<20 where self.hedef != nil {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                await self.yenile()
            }
            self.hedef = nil
            await self.yenile()
        }
    }

    func magazayiAc() { Self.calistir("/usr/bin/open", [Self.magaza.absoluteString], bekle: false) }

    func ayarDosyasiniAc() {
        hata = nil
        // WireGuard .conf dosyasını doğrudan açmayı kabul etmez; uygulamayı açıp dosyayı Finder'da gösteririz.
        Self.calistir("/usr/bin/open", ["-a", "WireGuard"], bekle: false)
        Self.calistir("/usr/bin/open", ["-R", Self.ayarDosyasi.path], bekle: false)
    }

    /// Menü çubuğu etiketi panel kapalıyken de güncel kalsın diye arada bir okur.
    func izlemeyiBaslat() {
        guard izleme == nil else { return }
        izleme = Task { [weak self] in
            while !Task.isCancelled {
                await self?.yenile()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func uygula(deneme d: String) {
        switch d {
        case "kuruluDegil": hal = .kuruluDegil
        case "tunelYok": hal = .tunelYok
        case "baglaniyor": hal = .baglaniyor
        case "bagli": hal = .bagli; adres = "10.0.0.2"
        case "kesiliyor": hal = .kesiliyor
        default: hal = .kapali
        }
        ayarDosyasiVar = FileManager.default.fileExists(atPath: Self.ayarDosyasi.path)
    }

    // MARK: Arka plan işleri (ana iş parçacığı dışında çalışır)

    nonisolated private static func oku() -> (hal: Hal, adres: String?, ayarVar: Bool) {
        let ayarVar = FileManager.default.fileExists(atPath: ayarDosyasi.path)
        guard FileManager.default.fileExists(atPath: uygulamaYolu) else { return (.kuruluDegil, nil, ayarVar) }
        let liste = calistir("/usr/sbin/scutil", ["--nc", "list"])
        guard liste.cikti.contains("\"\(tunel)\"") else { return (.tunelYok, nil, ayarVar) }
        let d = calistir("/usr/sbin/scutil", ["--nc", "status", tunel])
        let ilk = d.cikti.split(separator: "\n").first.map(String.init) ?? ""
        let hal: Hal
        switch ilk.trimmingCharacters(in: .whitespaces) {
        case "Connected": hal = .bagli
        case "Connecting", "Reasserting": hal = .baglaniyor
        case "Disconnecting": hal = .kesiliyor
        default: hal = .kapali
        }
        return (hal, hal == .bagli ? adresBul(d.cikti) : nil, ayarVar)
    }

    /// Önce `scutil` çıktısındaki IPv4 adresine, olmazsa ayar dosyasındaki `Address` satırına bakar.
    nonisolated private static func adresBul(_ cikti: String) -> String? {
        let desen = #/Addresses\s*:\s*<array>\s*\{\s*0\s*:\s*(\d{1,3}(?:\.\d{1,3}){3})/#
        if let m = cikti.firstMatch(of: desen) { return String(m.1) }
        guard let metin = try? String(contentsOf: ayarDosyasi, encoding: .utf8) else { return nil }
        for satir in metin.split(whereSeparator: \.isNewline) {
            let s = satir.trimmingCharacters(in: .whitespaces)
            guard s.lowercased().hasPrefix("address"), let esit = s.firstIndex(of: "=") else { continue }
            let ilk = s[s.index(after: esit)...].split(separator: ",").first ?? ""
            return ilk.trimmingCharacters(in: .whitespaces).split(separator: "/").first.map(String.init)
        }
        return nil
    }

    @discardableResult
    nonisolated private static func calistir(_ yol: String, _ arg: [String], bekle: Bool = true) -> (kod: Int32, cikti: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = arg
        let boru = Pipe()
        p.standardOutput = boru
        p.standardError = boru
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        guard bekle else { return (0, "") }
        let veri = boru.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: veri, as: UTF8.self))
    }
}
