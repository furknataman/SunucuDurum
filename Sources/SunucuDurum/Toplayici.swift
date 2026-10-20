import Foundation
import os

let gunluk = Logger(subsystem: "com.solvy.sunucudurum", category: "veri")

enum ToplamaHatasi: LocalizedError {
    case ssh(kod: Int32, mesaj: String)
    case zamanAsimi
    case cozumleme(String)
    case ayarOkunamadi(String)

    var errorDescription: String? {
        switch self {
        case let .ssh(kod, mesaj):
            let m = mesaj.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "SSH bağlantısı başarısız (çıkış kodu \(kod))." : m
        case .zamanAsimi: return "Sunucu zamanında yanıt vermedi."
        case let .cozumleme(m): return "Sunucu yanıtı çözümlenemedi: \(m)"
        case let .ayarOkunamadi(yol): return "Ayar dosyası okunamadı: \(yol)"
        }
    }
}

enum Toplayici {
    /// Geliştirme için `-sunucu <ad>` argümanıyla değiştirilebilir (hata kartını denemek gibi).
    static let sunucu = UserDefaults.standard.string(forKey: "sunucu") ?? Ayar.mevcut.ssh

    /// `ssh <sunucu> 'bash -s'` çalıştırır, betiği stdin'den gönderir; stdout'u döndürür.
    static func ssh(komut: String, stdin: String?, zamanAsimi: TimeInterval) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5", sunucu, komut]
        let girdi = Pipe(), cikti = Pipe(), hata = Pipe()
        p.standardInput = girdi
        p.standardOutput = cikti
        p.standardError = hata
        try p.run()

        if let stdin { girdi.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? girdi.fileHandleForWriting.close()

        // Boru tıkanmasın diye çıktılar arka planda okunur.
        var veri = Data(), hataVeri = Data()
        let grup = DispatchGroup()
        grup.enter(); DispatchQueue.global().async { veri = cikti.fileHandleForReading.readDataToEndOfFile(); grup.leave() }
        grup.enter(); DispatchQueue.global().async { hataVeri = hata.fileHandleForReading.readDataToEndOfFile(); grup.leave() }

        if grup.wait(timeout: .now() + zamanAsimi) == .timedOut {
            p.terminate()
            _ = grup.wait(timeout: .now() + 2)
            throw ToplamaHatasi.zamanAsimi
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ToplamaHatasi.ssh(kod: p.terminationStatus, mesaj: String(decoding: hataVeri, as: UTF8.self))
        }
        return veri
    }

    static func raporAl() throws -> Rapor {
        guard case .success = Ayar.sonuc else { throw ToplamaHatasi.ayarOkunamadi(Ayar.yol.path) }
        let veri = try ssh(komut: "bash -s", stdin: UzakBetik.metin(Ayar.mevcut), zamanAsimi: 40)
        do {
            return try JSONDecoder().decode(Rapor.self, from: veri)
        } catch {
            throw ToplamaHatasi.cozumleme(String(describing: error).prefix(160).description)
        }
    }

}

/// Panel açıkken tek bir ssh oturumu üzerinden 2 sn'de bir ağ arayüzü sayaçlarını okur (salt okunur).
final class CanliAgAkisi {
    private var surec: Process?
    private var tampon = ""

    /// Her satır için (sunucu çalışma süresi, alınan bayt, gönderilen bayt) bildirir.
    func baslat(_ bildir: @escaping @Sendable (Double, Double, Double) -> Void, bitti: @escaping @Sendable () -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5", Toplayici.sunucu,
                       "while :; do read u _ < /proc/uptime; awk -v u=\"$u\" '/\(Ayar.mevcut.agArayuzu):/{sub(/.*:/,\"\"); print u, $1, $9}' /proc/net/dev; sleep 2; done"]
        let cikti = Pipe()
        p.standardOutput = cikti
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        cikti.fileHandleForReading.readabilityHandler = { [weak self] h in
            let veri = h.availableData
            guard !veri.isEmpty, let self else { h.readabilityHandler = nil; return }
            self.tampon += String(decoding: veri, as: UTF8.self)
            while let r = self.tampon.firstIndex(of: "\n") {
                let satir = self.tampon[..<r].split(separator: " ").compactMap { Double($0) }
                self.tampon.removeSubrange(...r)
                if satir.count == 3 { bildir(satir[0], satir[1], satir[2]) }
            }
        }
        p.terminationHandler = { _ in bitti() }
        do { try p.run(); surec = p } catch { bitti() }
    }

    func durdur() {
        surec?.terminationHandler = nil
        surec?.terminate()
        surec = nil
    }
}
