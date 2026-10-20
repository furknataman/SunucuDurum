// Tuş yakalama, hedef ekran seçimi ve birleşik parlaklık MonitorControl'ün MediaKeyTapManager.swift,
// DisplayManager.swift, Model/OtherDisplay.swift, Model/Display.swift ve OSDUtils.swift dosyalarından türetilmiştir.
// Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others — MIT Lisansı
// (https://github.com/MonitorControl/MonitorControl/blob/main/License.txt)

import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// Harici ekranlar ve parlaklıkları. Klavye tuşları ve paneldeki kaydırıcı aynı modeli kullanır.
///
/// MonitorControl varsayılanı birebir: DDC'li ekranlarda "birleşik parlaklık" (ölçeğin alt yarısı yazılımsal karartma,
/// üst yarısı DDC 0…en çok); DDC'si olmayan ya da DDC'den okunamayan ekranlarda yalnızca yazılımsal karartma.
@MainActor
@Observable
final class Ekranlar {
    enum Mod: Equatable {
        case denetleniyor   // DDC henüz yoklanıyor
        case birlesik       // alt yarı yazılım, üst yarı DDC
        case yazilim        // yalnızca yazılımsal karartma
    }

    struct Ekran: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let ad: String
        let anahtar: String         // son değerin UserDefaults anahtarı (MonitorControl biçimi)
        var deger = 1.0             // 0…1; birleşik modda ölçeğin tamamı
        var enCok: UInt16 = 100
        var mod = Mod.denetleniyor
        var yanitYok = false
    }

    /// OtherDisplay.combinedBrightnessSwitchingValue: (0 + 8) / 16; altı yazılım, üstü DDC.
    static let gecis = 0.5

    private(set) var liste: [Ekran] = []
    private(set) var izinVar = AXIsProcessTrusted()

    @ObservationIgnored private let tuslar = ParlaklikTuslari()
    @ObservationIgnored private var yapilandirma: Task<Void, Never>?
    /// OtherDisplay.writeDDCLastSavedValue: aynı DDC değeri yeniden gönderilmez.
    @ObservationIgnored private var sonDDC: [CGDirectDisplayID: UInt16] = [:]
    private static weak var etkin: Ekranlar?

    func baslat() {
        guard Self.etkin == nil else { return }
        Self.etkin = self
        // Önceki çalışmadan (çökme dahil) kalmış karartma varsa temizlenir; değerler aşağıda kayıttan yeniden uygulanır.
        YazilimParlakligi.sifirla()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { YazilimParlakligi.sifirla() }
        }
        // Tek kayıt: bağlama/çıkarma ve uyanmada DDC eşleşmeleri geçersiz kılınır, liste yeniden kurulur.
        CGDisplayRegisterReconfigurationCallback({ _, bayrak, _ in
            guard !bayrak.contains(.beginConfigurationFlag) else { return }
            DDC.ortak.gecersizKil()
            Task { @MainActor in Ekranlar.etkin?.yenidenYapilandir() }
        }, nil)
        tazele()
        Task { [weak self] in
            // İzin verilene kadar bekler, sonra tuşları yakalamaya başlar (yeniden başlatma gerekmez).
            while !Task.isCancelled {
                guard let self else { return }
                let izin = AXIsProcessTrusted()
                if self.izinVar != izin { self.izinVar = izin }
                if izin, self.tuslar.kur(self) { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Gizlilik ve Güvenlik > Erişilebilirlik bölmesini açar. Sistem sorusu uygulamayı listeye ekler; yalnızca anahtarı açmak kalır.
    func izinAyariniAc() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// OtherDisplay.setDirectBrightness / Display.setDirectBrightness. Model hemen güncellenir,
    /// DDC yazması arka planda yapılır (hızlı değişimlerde en son değer kazanır).
    func ayarla(_ id: CGDirectDisplayID, _ deger: Double) {
        guard var e = liste.first(where: { $0.id == id }), e.mod != .denetleniyor else { return }
        YazilimParlakligi.girisimiDenetle(id)
        e.deger = min(max(deger, 0), 1)
        degistir(id) { $0.deger = e.deger }
        UserDefaults.standard.set(e.deger, forKey: e.anahtar)
        if e.mod == .birlesik {
            let oran = e.deger >= Self.gecis ? (e.deger - Self.gecis) / (1 - Self.gecis) : 0
            let ham = UInt16((oran * Double(e.enCok)).rounded())
            if sonDDC[id] != ham {
                sonDDC[id] = ham
                Task { [weak self] in
                    guard let basarili = await DDC.ortak.yaz(id, ham) else { return }
                    self?.degistir(id) { $0.yanitYok = !basarili }
                    // Başarısız yazma unutulur ki aynı değer bir sonraki basışta yeniden denensin.
                    if !basarili, self?.sonDDC[id] == ham { self?.sonDDC[id] = nil }
                }
            }
        }
        let yazilim = Self.yazilimBileseni(e)
        if YazilimParlakligi.deger(id) != yazilim { YazilimParlakligi.ayarla(id, yazilim) }
    }

    /// Parlaklık tuşu. Hedef, fare imlecinin bulunduğu ekrandır (MonitorControl varsayılanı).
    /// Hedef bilinen bir harici ekransa ayarlar ve `true` döner (olay yutulur); değilse olay macOS'a kalır.
    func tus(yukari: Bool, basili: Bool) -> Bool {
        let fare = NSEvent.mouseLocation
        // ponytail: yansıtılan (mirror) ekranlara aynı adım uygulanmaz; yalnızca imlecin bulunduğu ekran.
        guard let ekran = NSScreen.screens.first(where: { NSMouseInRect(fare, $0.frame, false) }),
              let id = ekran.ekranKimligi, let e = liste.first(where: { $0.id == id }), e.mod != .denetleniyor else { return false }
        guard basili else { return true }
        // Tap callback'i hemen dönsün; gamma, DDC ve gösterge işi bir sonraki döngüde yapılır.
        Task { @MainActor [weak self] in self?.adimAt(id, yukari: yukari) }
        return true
    }

    private func adimAt(_ id: CGDirectDisplayID, yukari: Bool) {
        guard let e = liste.first(where: { $0.id == id }), e.mod != .denetleniyor else { return }
        if e.mod == .birlesik {
            // OtherDisplay.stepBrightness: 16 kutulu gösterge.
            let yeni = Self.sonrakiDeger(e.deger, yukari: yukari)
            ayarla(id, yeni)
            OSD.goster(ekran: id, dolu: Int((yeni * 16).rounded()), toplam: 16)
        } else {
            // Display.stepBrightness: gösterge değer × 64 / 64 ile, yuvarlamasız.
            let yeni = Self.yazilimAdimi(e.deger, yukari: yukari)
            ayarla(id, yeni)
            OSD.goster(ekran: id, dolu: Int(yeni * 64 * 100), toplam: 64 * 100)
        }
    }

    /// OtherDisplay.calcNewValue (küçük adımsız dal): 1/16'lık gösterge kutularına hizalanarak bir adım.
    static func sonrakiDeger(_ v: Double, yukari: Bool) -> Double {
        let kutu = v * 16
        let uzaklik = abs(kutu.rounded(.towardZero) - kutu)
        var hedef = yukari ? kutu.rounded(.up) : kutu.rounded(.down)
        if uzaklik == 0 { hedef += yukari ? 1 : -1 }
        else if !yukari, uzaklik < 0.25 { hedef -= 1 }
        else if yukari, uzaklik > 0.75 { hedef += 1 }
        return min(max(hedef / 16, 0), 1)
    }

    /// Display.calcNewBrightness (küçük adımsız): yalnızca yazılım modundaki ekranlar için 1/16 adım.
    static func yazilimAdimi(_ v: Double, yukari: Bool) -> Double {
        let adim = (yukari ? 1.0 : -1.0) / 16
        return min(max(0, ((v + adim / 4) / adim).rounded(.up) * adim), 1)
    }

    /// Değerin yazılımsal karartmaya düşen kısmı (1 = karartma yok).
    private static func yazilimBileseni(_ e: Ekran) -> Double {
        switch e.mod {
        case .yazilim: e.deger
        case .birlesik: e.deger >= gecis ? 1 : e.deger / gecis
        case .denetleniyor: 1
        }
    }

    // MARK: Ekran listesi

    /// AppDelegate.displayReconfigured: karartma hemen kaldırılır (ColorSync'e dönülür), 1 sn sonra liste kurulup yeniden uygulanır.
    private func yenidenYapilandir() {
        YazilimParlakligi.sifirla()
        sonDDC = [:]
        yapilandirma?.cancel()
        yapilandirma = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.tazele()
        }
    }

    /// Harici ekran listesini kurar. Bilinen ekranların karartması yeniden uygulanır; yenilerin DDC'si yoklanır.
    private func tazele() {
        let eski = Dictionary(uniqueKeysWithValues: liste.map { ($0.id, $0) })
        liste = NSScreen.screens.compactMap { s in
            guard let id = s.ekranKimligi, CGDisplayIsBuiltin(id) == 0 else { return nil }
            return eski[id] ?? Ekran(id: id, ad: s.localizedName, anahtar: Self.anahtar(id, ad: s.localizedName))
        }
        for e in liste {
            YazilimParlakligi.varsayilaniAl(e.id)
            if eski[e.id] != nil {
                YazilimParlakligi.ayarla(e.id, Self.yazilimBileseni(e))
                continue
            }
            Task { [weak self] in
                let servis = await DDC.ortak.servisVar(e.id)
                let okunan = servis ? await DDC.ortak.oku(e.id) : nil
                self?.kur(e.id, okunan: okunan)
            }
        }
    }

    /// OtherDisplay.processCurrentDDCValue (ekrandan okunan değerle) ve Display.getBrightness (yazılım modu).
    private func kur(_ id: CGDirectDisplayID, okunan: (deger: UInt16, enCok: UInt16)?) {
        guard let i = liste.firstIndex(where: { $0.id == id }) else { return }
        let kayitli = UserDefaults.standard.object(forKey: liste[i].anahtar) as? Double
        if let o = okunan, o.enCok > 0 {
            let oran = min(Double(o.deger) / Double(o.enCok), 1)
            liste[i].mod = .birlesik
            liste[i].enCok = o.enCok
            // DDC 0'sa ölçeğin alt yarısındaki (karartmalı) kayıtlı değer geri yüklenir.
            // ponytail: MonitorControl açılışta (startupAction varsayılanı) karartmayı geri yüklemez, geçiş noktasından başlar.
            liste[i].deger = oran > 0 ? Self.gecis + oran * (1 - Self.gecis) : min(kayitli ?? Self.gecis, Self.gecis)
            sonDDC[id] = o.deger
        } else {
            liste[i].mod = .yazilim
            liste[i].deger = kayitli ?? 1
        }
        YazilimParlakligi.ayarla(id, Self.yazilimBileseni(liste[i]))
    }

    /// Display.prefsId biçimi: "value16(<boşluksuz ad><üretici><model>@<ekran kimliği>)".
    private static func anahtar(_ id: CGDirectDisplayID, ad: String) -> String {
        "value16(\(ad.filter { !$0.isWhitespace })\(CGDisplayVendorNumber(id))\(CGDisplayModelNumber(id))@\(id))"
    }

    private func degistir(_ id: CGDirectDisplayID, _ islem: (inout Ekran) -> Void) {
        guard let i = liste.firstIndex(where: { $0.id == id }) else { return }
        islem(&liste[i])
    }
}

extension NSScreen {
    var ekranKimligi: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

// MARK: - Tuş yakalama

/// Klavyenin parlaklık tuşlarını (NX_SYSDEFINED olayı, alt tür 8) yakalayan olay musluğu. Erişilebilirlik izni ister.
@MainActor
final class ParlaklikTuslari {
    private static let sistemOlayi: UInt32 = 14       // NX_SYSDEFINED
    private static let parlaklikArtir = 2             // NX_KEYTYPE_BRIGHTNESS_UP
    private static let parlaklikAzalt = 3             // NX_KEYTYPE_BRIGHTNESS_DOWN

    private var musluk: CFMachPort?
    private weak var ekranlar: Ekranlar?

    /// Musluğu ana çalışma döngüsüne ekler; izin yoksa `false` döner.
    func kur(_ e: Ekranlar) -> Bool {
        if musluk != nil { return true }
        ekranlar = e
        guard let m = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.sistemOlayi | CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, tur, olay, kullanici in
                guard let kullanici else { return Unmanaged.passUnretained(olay) }
                let ben = Unmanaged<ParlaklikTuslari>.fromOpaque(kullanici).takeUnretainedValue()
                return MainActor.assumeIsolated { ben.isle(tur, olay) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        musluk = m
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, m, 0), .commonModes)
        CGEvent.tapEnable(tap: m, enable: true)
        gunluk.info("Parlaklık tuşları yakalanıyor")
        return true
    }

    private func isle(_ tur: CGEventType, _ olay: CGEvent) -> Unmanaged<CGEvent>? {
        let gecir = Unmanaged.passUnretained(olay)
        // Sistem, yavaş kalan ya da kullanıcı girdisiyle kesilen musluğu kapatır; hemen yeniden açılmalı.
        if tur == .tapDisabledByTimeout || tur == .tapDisabledByUserInput {
            if let musluk { CGEvent.tapEnable(tap: musluk, enable: true) }
            return gecir
        }
        // Yeni Mac klavyelerinde parlaklık tuşları sistem olayı değil, normal tuş basışı olarak gelir
        // (MediaKeyTap functionKeyCodeToMediaKey: 144/145; F14/F15 harici Apple klavyeleri için, MonitorControl'de varsayılan açık).
        if tur == .keyDown {
            let yukari: Bool
            switch olay.getIntegerValueField(.keyboardEventKeycode) {
            case 144, 113: yukari = true     // parlaklık artır, F15
            case 145, 107: yukari = false    // parlaklık azalt, F14
            default: return gecir
            }
            guard olay.flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty,
                  let ekranlar, ekranlar.tus(yukari: yukari, basili: true) else { return gecir }
            return nil
        }
        guard tur.rawValue == Self.sistemOlayi, let ns = NSEvent(cgEvent: olay), ns.subtype.rawValue == 8 else { return gecir }
        let tus = (ns.data1 & 0xFFFF0000) >> 16
        guard tus == Self.parlaklikArtir || tus == Self.parlaklikAzalt else { return gecir }
        // ponytail: Control, Option ya da Command ile basışlar macOS'a bırakılır; MonitorControl da bunları
        // dahili ekrana ya da Ekranlar ayarına yönlendirir, macOS bunu kendisi yapar.
        guard ns.modifierFlags.intersection([.control, .option, .command]).isEmpty else { return gecir }
        let basili = (ns.data1 & 0xFF00) >> 8 == 0x0A    // 0x0A basıldı (tekrar dahil), 0x0B bırakıldı
        guard let ekranlar, ekranlar.tus(yukari: tus == Self.parlaklikArtir, basili: basili) else { return gecir }
        return nil
    }
}

// MARK: - Yerel parlaklık göstergesi (OSD)

/// macOS'un OSDUIHelper hizmetinin, kullandığımız tek yöntemi.
@objc protocol OSDUIHelperProtocol {
    @objc(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:)
    func showImage(_ resim: Int64, onDisplayID: UInt32, priority: UInt32, msecUntilFade: UInt32,
                   filledChiclets: UInt32, totalChiclets: UInt32, locked: Bool)
}

/// macOS'un kendi parlaklık göstergesi (MonitorControl OSDUtils.swift'in macOS 26–27 yolu: XPC ile OSDUIHelper).
/// ponytail: macOS 28 ve sonrası için OSDManager yolu yok; gösterge çıkmazsa yalnızca görsel geri bildirim eksik kalır.
@MainActor
enum OSD {
    private static var baglanti: NSXPCConnection?

    static func goster(ekran: CGDirectDisplayID, dolu: Int, toplam: Int) {
        let b = baglanti ?? {
            let b = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
            b.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
            b.interruptionHandler = { [weak b] in b?.invalidate() }
            b.invalidationHandler = { Task { @MainActor in OSD.baglanti = nil } }
            b.resume()
            return b
        }()
        baglanti = b
        let vekil = b.remoteObjectProxyWithErrorHandler { _ in } as? OSDUIHelperProtocol
        vekil?.showImage(1, onDisplayID: ekran, priority: 0x1F4, msecUntilFade: 1000,
                         filledChiclets: UInt32(max(0, min(dolu, toplam))), totalChiclets: UInt32(toplam), locked: false)
    }
}
