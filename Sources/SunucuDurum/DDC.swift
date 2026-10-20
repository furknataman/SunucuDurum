// Bu dosya MonitorControl'ün Support/Arm64DDC.swift dosyasından türetilmiştir.
// Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others — MIT Lisansı
// (https://github.com/MonitorControl/MonitorControl/blob/main/License.txt)

import AppKit
import CoreGraphics
import IOKit

// Apple Silicon'da harici ekranla I²C (DDC/CI) konuşmayı sağlayan özel IOKit/CoreDisplay işlevleri.
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ ayirici: CFAllocator?, _ servis: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ servis: CFTypeRef, _ cip: UInt32, _ konum: UInt32, _ tampon: UnsafeMutableRawPointer, _ boyut: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ servis: CFTypeRef, _ cip: UInt32, _ adres: UInt32, _ tampon: UnsafeMutableRawPointer, _ boyut: UInt32) -> IOReturn
@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
private func CoreDisplay_DisplayCreateInfoDictionary(_ ekran: CGDirectDisplayID) -> Unmanaged<CFDictionary>?

/// Harici ekranların parlaklığını (VCP 0x10) DDC/CI ile okur/yazar.
/// Bütün I²C trafiği tek seri kuyrukta yürür; çağıranlar `async` arayüzle beklediği için ana iş parçacığı hiç bloklanmaz.
final class DDC: @unchecked Sendable {
    static let ortak = DDC()

    private static let cipAdresi: UInt8 = 0x37    // DisplayPort cihazlarıyla çalışır
    private static let veriAdresi: UInt8 = 0x51
    static let parlaklik: UInt8 = 0x10

    private let kuyruk = DispatchQueue(label: "com.solvy.sunucudurum.ddc", qos: .userInitiated)
    /// Ekran → IOAVService eşleşmesi; yalnızca `kuyruk` üzerinde okunup yazılır. `nil`: yeniden kurulmalı.
    private var servisler: [CGDirectDisplayID: CFTypeRef]?
    /// Ekran başına bekleyen son yazma değeri: hızlı tuş/kaydırıcı hareketinde yalnızca en güncel değer gönderilir.
    private var bekleyen: [CGDirectDisplayID: UInt16] = [:]
    private let kilit = NSLock()

    /// Ekran düzeni değişince (bağlama/çıkarma, uyku) eşleşmeler geçersizdir.
    func gecersizKil() { kuyruk.async { self.servisler = nil } }

    func servisVar(_ ekran: CGDirectDisplayID) async -> Bool {
        await kuyrukta { self.servis(ekran) != nil }
    }

    /// (güncel, en çok) değer; okunamazsa `nil`.
    func oku(_ ekran: CGDirectDisplayID, komut: UInt8 = parlaklik) async -> (deger: UInt16, enCok: UInt16)? {
        await kuyrukta {
            guard let s = self.servis(ekran) else { return nil }
            var gonder: [UInt8] = [komut]
            var yanit = [UInt8](repeating: 0, count: 11)
            guard Self.iletisim(s, gonder: &gonder, yanit: &yanit) else { return nil }
            return (UInt16(yanit[8]) << 8 | UInt16(yanit[9]), UInt16(yanit[6]) << 8 | UInt16(yanit[7]))
        }
    }

    /// Yazar; daha yeni bir değer bu yazmayı geride bıraktıysa `nil` döner (o değeri sonraki iş gönderir).
    func yaz(_ ekran: CGDirectDisplayID, _ deger: UInt16, komut: UInt8 = parlaklik) async -> Bool? {
        kilit.withLock { bekleyen[ekran] = deger }
        return await kuyrukta {
            guard let d = self.kilit.withLock({ self.bekleyen.removeValue(forKey: ekran) }) else { return nil }
            guard let s = self.servis(ekran) else { return false }
            var gonder: [UInt8] = [komut, UInt8(d >> 8), UInt8(d & 0xFF)]
            var yanit: [UInt8] = []
            return Self.iletisim(s, gonder: &gonder, yanit: &yanit)
        }
    }

    private func kuyrukta<T>(_ islem: @escaping () -> T) async -> T {
        await withCheckedContinuation { devam in kuyruk.async { devam.resume(returning: islem()) } }
    }

    // MARK: Kuyruk içi

    private func servis(_ ekran: CGDirectDisplayID) -> CFTypeRef? {
        if servisler == nil { servisler = Self.eslestir() }
        return servisler?[ekran]
    }

    /// Arm64DDC.performDDCCommunication: aynı paket, sağlama, gecikme ve deneme sayıları.
    private static func iletisim(_ servis: CFTypeRef, gonder: inout [UInt8], yanit: inout [UInt8]) -> Bool {
        var paket: [UInt8] = [UInt8(0x80 | (gonder.count + 1)), UInt8(gonder.count)] + gonder + [0]
        paket[paket.count - 1] = sagla(gonder.count == 1 ? cipAdresi << 1 : cipAdresi << 1 ^ veriAdresi, paket, paket.count - 2)
        var basarili = false
        for _ in 0..<5 {
            for _ in 0..<2 {
                usleep(10_000)
                basarili = IOAVServiceWriteI2C(servis, UInt32(cipAdresi), UInt32(veriAdresi), &paket, UInt32(paket.count)) == 0
            }
            if !yanit.isEmpty {
                basarili = false    // okumada başarı yalnız geçerli yanıtla sayılır
                usleep(50_000)
                if IOAVServiceReadI2C(servis, UInt32(cipAdresi), 0, &yanit, UInt32(yanit.count)) == 0 {
                    basarili = sagla(0x50, yanit, yanit.count - 2) == yanit[yanit.count - 1]
                }
            }
            if basarili { return true }
            usleep(20_000)
        }
        return false
    }

    private static func sagla(_ baslangic: UInt8, _ veri: [UInt8], _ son: Int) -> UInt8 {
        veri[0...son].reduce(baslangic, ^)
    }

    // MARK: IOAVService ↔ CGDirectDisplayID eşleştirmesi (Arm64DDC.getServiceMatches)

    private struct Aday {
        var edid = "", konum = "", ad = ""
        var seri: Int64 = 0
        var sira = 0
        var servis: CFTypeRef?
    }

    private static func eslestir() -> [CGDirectDisplayID: CFTypeRef] {
        var sayi: UInt32 = 0
        var kimlikler = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &kimlikler, &sayi) == .success else { return [:] }
        let harici = kimlikler.prefix(Int(sayi)).filter { CGDisplayIsBuiltin($0) == 0 }
        let adaylar = adaylariTopla()
        // Puanı en yüksek eşleşmeden başlayarak her ekranı ve her çerçeve arabelleğini bir kez kullan.
        var puanli: [(ekran: CGDirectDisplayID, aday: Aday, puan: Int)] = []
        for e in harici { for a in adaylar { puanli.append((e, a, puan(e, a))) } }
        var sonuc: [CGDirectDisplayID: CFTypeRef] = [:]
        var alinanSira = Set<Int>()
        for p in stride(from: 20, to: 0, by: -1) {
            for c in puanli where c.puan == p && sonuc[c.ekran] == nil && !alinanSira.contains(c.aday.sira) {
                guard let s = c.aday.servis else { continue }
                sonuc[c.ekran] = s
                alinanSira.insert(c.aday.sira)
            }
        }
        return sonuc
    }

    private static func ozellik(_ g: io_service_t, _ ad: String) -> Any? {
        IORegistryEntryCreateCFProperty(g, ad as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// IORegistry'de her çerçeve arabelleğini (AppleCLCD2 / IOMobileFramebufferShim) ardından gelen DCPAVServiceProxy ile eşler.
    private static func adaylariTopla() -> [Aday] {
        let kok = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(kok) }
        var gezgin = io_iterator_t()
        guard IORegistryEntryCreateIterator(kok, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &gezgin) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(gezgin) }
        var sonuc: [Aday] = []
        var a = Aday()
        var sira = 0
        var ad = [CChar](repeating: 0, count: 128)
        while case let g = IOIteratorNext(gezgin), g != IO_OBJECT_NULL {
            defer { IOObjectRelease(g) }
            guard IORegistryEntryGetName(g, &ad) == KERN_SUCCESS else { continue }
            let n = String(cString: ad)
            if n == "AppleCLCD2" || n == "IOMobileFramebufferShim" {
                sira += 1
                a = Aday(sira: sira)
                a.edid = ozellik(g, "EDID UUID") as? String ?? ""
                var yol = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(g, kIOServicePlane, &yol) == KERN_SUCCESS { a.konum = String(cString: yol) }
                if let ozn = ozellik(g, "DisplayAttributes") as? NSDictionary, let u = ozn["ProductAttributes"] as? NSDictionary {
                    a.ad = u["ProductName"] as? String ?? ""
                    a.seri = u["SerialNumber"] as? Int64 ?? 0
                }
            } else if n == "DCPAVServiceProxy" {
                if ozellik(g, "Location") as? String == "External" {
                    a.servis = IOAVServiceCreateWithService(kCFAllocatorDefault, g)?.takeRetainedValue()
                }
                sonuc.append(a)
            }
        }
        return sonuc
    }

    /// Arm64DDC.ioregMatchScore: EDID UUID parçaları (+1'er), IODisplayLocation (+10), ürün adı (+1), seri (+1).
    private static func puan(_ ekran: CGDirectDisplayID, _ a: Aday) -> Int {
        guard let s = CoreDisplay_DisplayCreateInfoDictionary(ekran)?.takeRetainedValue() as NSDictionary? else { return 0 }
        var p = 0
        if let yil = s["DisplayYearOfManufacture"] as? Int64, let hafta = s["DisplayWeekOfManufacture"] as? Int64,
           let uretici = s["DisplayVendorID"] as? Int64, let urun = s["DisplayProductID"] as? Int64,
           let dikey = s["DisplayVerticalImageSize"] as? Int64, let yatay = s["DisplayHorizontalImageSize"] as? Int64 {
            let bayt = { (v: Int64) in UInt8(max(0, min(v, 255))) }
            let u = UInt16(max(0, min(urun, 65535)))
            let anahtarlar: [(deger: String, yer: Int)] = [
                (String(format: "%04X", UInt16(max(0, min(uretici, 65535)))), 0),
                (String(format: "%02X%02X", UInt8(u & 0xFF), UInt8(u >> 8)), 4),
                (String(format: "%02X%02X", bayt(hafta), bayt(yil - 1990)), 19),
                (String(format: "%02X%02X", bayt(yatay / 10), bayt(dikey / 10)), 30),
            ]
            for k in anahtarlar where k.deger != "0000" && k.deger == String(a.edid.prefix(k.yer + 4).suffix(4)) { p += 1 }
        }
        if !a.konum.isEmpty, s["IODisplayLocation"] as? String == a.konum { p += 10 }
        if !a.ad.isEmpty, let adlar = s["DisplayProductName"] as? [String: String],
           let ad = adlar["en_US"] ?? adlar.first?.value, ad.lowercased() == a.ad.lowercased() { p += 1 }
        if a.seri != 0, s["DisplaySerialNumber"] as? Int64 == a.seri { p += 1 }
        return p
    }
}
