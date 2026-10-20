// Bu dosya MonitorControl'ün Model/Display.swift (swBrightness, gamma tablosu) ve Support/DisplayManager.swift
// (gamma etkinlik penceresi) dosyalarından türetilmiştir.
// Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others — MIT Lisansı
// (https://github.com/MonitorControl/MonitorControl/blob/main/License.txt)

import AppKit
import CoreGraphics

/// Yazılımsal karartma: ekranın gamma tablosunu (renk aktarım tablosu) ölçekler.
/// MonitorControl'ün varsayılan yolu budur (gölge pencere yalnızca sanal ekranlarda ya da "avoidGamma" seçiliyken kullanılır).
/// Uygulama kapanınca ya da çökünce macOS gamma tablolarını kendiliğinden ColorSync ayarlarına döndürür.
@MainActor
enum YazilimParlakligi {
    private struct Tablo {
        var kirmizi = [CGGammaValue](repeating: 0, count: 256)
        var yesil = [CGGammaValue](repeating: 0, count: 256)
        var mavi = [CGGammaValue](repeating: 0, count: 256)
        var sayi: UInt32 = 0
        var tepe: Float = 1
    }

    /// Ekranın karartılmamış (varsayılan) tablosu.
    private static var varsayilan: [CGDirectDisplayID: Tablo] = [:]
    /// Ekran başına son uygulanan yazılımsal parlaklık (0…1).
    private static var uygulanan: [CGDirectDisplayID: Double] = [:]
    private static var girisimSayisi = 0

    /// Bütün ekranları ColorSync ayarlarına döndürür (karartma kalkar). Açılışta, ekran düzeni değişince ve çıkışta çağrılır.
    static func sifirla() {
        CGDisplayRestoreColorSyncSettings()
        varsayilan = [:]
        uygulanan = [:]
    }

    /// Display.swUpdateDefaultGammaTable: tablo karartmasızken alınmalı.
    static func varsayilaniAl(_ ekran: CGDirectDisplayID) {
        var t = Tablo()
        guard CGGetDisplayTransferByTable(ekran, 256, &t.kirmizi, &t.yesil, &t.mavi, &t.sayi) == .success else { return }
        t.tepe = max(t.kirmizi.max() ?? 0, t.yesil.max() ?? 0, t.mavi.max() ?? 0)
        varsayilan[ekran] = t
    }

    static func deger(_ ekran: CGDirectDisplayID) -> Double { uygulanan[ekran] ?? 1 }

    /// Display.setSwBrightness (yumuşak geçişsiz yol).
    static func ayarla(_ ekran: CGDirectDisplayID, _ deger: Double) {
        let v = min(max(deger, 0), 1)
        uygulanan[ekran] = v
        guard let t = varsayilan[ekran] else { return }
        let k = Float(donustur(v))
        EtkinlikPenceresi.tasi(ekran)
        CGSetDisplayTransferByTable(ekran, t.sayi, t.kirmizi.map { $0 * k }, t.yesil.map { $0 * k }, t.mavi.map { $0 * k })
        EtkinlikPenceresi.kipirdat()
    }

    /// Display.checkGammaInterference: başka bir uygulama (f.lux vb.) gamma tablosunu değiştirdiyse bizimkini geri basar.
    /// ponytail: MonitorControl üç girişimden sonra gölge pencereye geçmeyi soran bir uyarı gösterir; burada yalnızca günlüğe yazılır.
    static func girisimiDenetle(_ ekran: CGDirectDisplayID) {
        guard girisimSayisi < 3, let beklenen = uygulanan[ekran], abs(okunan(ekran) - beklenen) > 0.02 else { return }
        girisimSayisi += 1
        ayarla(ekran, 1)
        if girisimSayisi == 3 {
            gunluk.error("Gamma tablosunu başka bir uygulama değiştiriyor (f.lux vb.); yazılımsal karartma onunla çakışabilir")
        }
    }

    /// Display.getSwBrightness: şu anki tablonun tepe değerinden geri hesaplanan parlaklık.
    private static func okunan(_ ekran: CGDirectDisplayID) -> Double {
        guard let t = varsayilan[ekran], t.tepe > 0 else { return 1 }
        var g = Tablo()
        guard CGGetDisplayTransferByTable(ekran, 256, &g.kirmizi, &g.yesil, &g.mavi, &g.sayi) == .success else { return 1 }
        let oran = Double(max(g.kirmizi.max() ?? 0, g.yesil.max() ?? 0, g.mavi.max() ?? 0) / t.tepe)
        return (donustur(oran, ters: true) * 256).rounded() / 256
    }

    /// Display.swBrightnessTransform: ekran hiç tamamen kararmasın diye taban %15 ("allowZeroSwBrightness" kapalı, varsayılan).
    private static func donustur(_ v: Double, ters: Bool = false) -> Double {
        let taban = 0.15
        return ters ? (v - taban) / (1 - taban) : v * (1 - taban) + taban
    }
}

/// DisplayManager.gammaActivityEnforcer: Apple Silicon'da gamma değişikliği ekranda hareket olmadan görünmez;
/// neredeyse saydam 1×1 bir pencere ilgili ekrana taşınıp saydamlığı oynatılarak ekran tazelenir.
@MainActor
private enum EtkinlikPenceresi {
    private static let pencere: NSWindow = {
        let p = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [], backing: .buffered, defer: false)
        p.title = "Sunucu Durum Gamma Etkinlik Penceresi"
        p.isMovableByWindowBackground = false
        p.backgroundColor = .black
        p.alphaValue = 0.01
        p.ignoresMouseEvents = true
        p.level = .screenSaver
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.stationary, .canJoinAllSpaces]
        p.orderFrontRegardless()
        return p
    }()

    static func tasi(_ ekran: CGDirectDisplayID) {
        if let s = NSScreen.screens.first(where: { $0.ekranKimligi == ekran }) { pencere.setFrameOrigin(s.frame.origin) }
        pencere.orderFrontRegardless()
    }

    static func kipirdat() {
        pencere.alphaValue = pencere.alphaValue == 0.01 ? 0.02 : 0.01
    }
}
