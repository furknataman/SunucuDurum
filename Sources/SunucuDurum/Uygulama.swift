import AppKit
import ServiceManagement
import SwiftUI

struct SunucuDurumApp: App {
    @NSApplicationDelegateAdaptor(UygulamaTemsilcisi.self) private var temsilci

    var body: some Scene {
        MenuBarExtra {
            Panel().environment(temsilci.durum)
        } label: {
            MenuEtiketi(durum: temsilci.durum)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menü çubuğu ikonu: tek renkli template `server.rack` (menü çubuğunun temasına kendiliğinden uyar);
/// durum, ikonun sağ alt köşesindeki renkli noktayla (bkz. `MenuNoktasi`) gösterilir.
struct MenuEtiketi: View {
    let durum: Durum

    var body: some View {
        let sayi = durum.hata == nil ? durum.sorunlar.count : 0
        HStack(spacing: 3) {
            Image(nsImage: MenuEtiketi.ikon)
            if durum.macVPN.bagli {
                Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
            }
            if sayi > 0 { Text("\(sayi)").monospacedDigit() }
        }
    }
}

extension MenuEtiketi {
    /// Vektörel SF Symbol, template: Retina'da keskin, menü çubuğunun rengine uyar.
    static let ikon: NSImage = {
        let ayar = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium, scale: .medium)
            .applying(.preferringMonochrome())
        let r = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Sunucu durumu")?
            .withSymbolConfiguration(ayar) ?? NSImage()
        r.isTemplate = true
        return r
    }()
}

/// MenuBarExtra'nın oluşturduğu durum çubuğu düğmesine küçük renkli bir nokta katmanı ekler.
@MainActor
enum MenuNoktasi {
    private static weak var dugme: NSStatusBarButton?
    private static var nokta: CALayer?
    private static let cap: CGFloat = 6

    static func guncelle(renk: NSColor?, nabiz: Bool) {
        if dugme == nil { dugme = bul() }
        guard let d = dugme else { return }
        d.wantsLayer = true
        guard let katman = d.layer else { return }
        let n: CALayer
        if let mevcut = nokta { n = mevcut } else {
            n = CALayer()
            n.cornerRadius = cap / 2
            n.zPosition = 10
            katman.addSublayer(n)
            nokta = n
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = d.cell?.imageRect(forBounds: d.bounds) ?? d.bounds
        let y = d.isFlipped ? r.maxY - cap + 2 : r.minY - 2
        n.frame = CGRect(x: r.maxX - cap + 3, y: y, width: cap, height: cap)
        n.contentsScale = d.window?.backingScaleFactor ?? 2
        n.backgroundColor = renk?.cgColor
        n.isHidden = renk == nil
        CATransaction.commit()

        if nabiz, n.animation(forKey: "nabiz") == nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.25; a.duration = 0.5
            a.autoreverses = true; a.repeatCount = .infinity
            n.add(a, forKey: "nabiz")
        } else if !nabiz {
            n.removeAnimation(forKey: "nabiz")
        }
    }

    private static func bul() -> NSStatusBarButton? {
        for w in NSApp.windows where String(describing: type(of: w)).contains("StatusBar") {
            if let b = ara(w.contentView) { return b }
        }
        return nil
    }

    private static func ara(_ v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let b = v as? NSStatusBarButton { return b }
        for alt in v.subviews { if let b = ara(alt) { return b } }
        return nil
    }
}

@MainActor
final class UygulamaTemsilcisi: NSObject, NSApplicationDelegate {
    let durum = Durum()
    private var onizlemePenceresi: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        durum.baslat()
        noktayiIzle()
        if CommandLine.arguments.contains("--preview") {
            onizlemeAc()
        } else {
            GirisOgesi.kaydet()
        }
    }

    /// Durum değiştikçe menü çubuğundaki noktayı günceller.
    private func noktayiIzle() {
        withObservationTracking {
            noktayiGuncelle()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.noktayiIzle() }
        }
        // Etiket genişliği (uyarı sayısı) değişince düzen oturduktan sonra konumu tazele.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.noktayiGuncelle() }
    }

    private func noktayiGuncelle() {
        let renk: NSColor? = durum.rapor == nil && durum.hata == nil ? nil : NSColor(durum.genelSeviye.renk)
        MenuNoktasi.guncelle(renk: renk, nabiz: durum.yenileniyor)
    }

    /// `--preview`: paneli normal bir pencerede gösterir (ekran görüntüsü / geliştirme için).
    private func onizlemeAc() {
        let gorunum = NSHostingView(rootView: Panel(canliAgKullan: true).environment(durum))
        let p = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Sunucu Durum — Önizleme"
        p.contentView = gorunum
        if CommandLine.arguments.contains("--aydinlik") { p.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--karanlik") { p.appearance = NSAppearance(named: .darkAqua) }
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        onizlemePenceresi = p
    }
}

enum GirisOgesi {
    static let ajanYolu = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.solvy.sunucudurum.plist")

    /// Girişte otomatik açılma: önce SMAppService, olmazsa LaunchAgent.
    static func kaydet() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let servis = SMAppService.mainApp
        if servis.status != .enabled {
            do { try servis.register() } catch {
                gunluk.error("SMAppService kaydı başarısız: \(error.localizedDescription, privacy: .public)")
            }
        }
        gunluk.info("Giriş öğesi durumu: \(servis.status.rawValue)")
        if servis.status == .enabled {
            try? FileManager.default.removeItem(at: ajanYolu)
        } else if !FileManager.default.fileExists(atPath: ajanYolu.path) {
            launchAgentYaz()
        }
    }

    private static func launchAgentYaz() {
        let plist: [String: Any] = [
            "Label": "com.solvy.sunucudurum",
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(at: ajanYolu.deletingLastPathComponent(), withIntermediateDirectories: true)
            let veri = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try veri.write(to: ajanYolu)
            gunluk.info("LaunchAgent yazıldı")
        } catch {
            gunluk.error("LaunchAgent yazılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }
}
