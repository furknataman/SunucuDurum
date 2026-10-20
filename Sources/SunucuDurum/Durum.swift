import Foundation
import Observation

struct AgOrnek: Identifiable {
    let id = UUID()
    let tarih: Date
    let indirme: Double
    let yukleme: Double
}

@MainActor
@Observable
final class Durum {
    static let yenilemeAraligi: TimeInterval = 300

    private(set) var rapor: Rapor?
    private(set) var hata: String?
    private(set) var yenileniyor = false
    private(set) var sonGuncelleme: Date?
    private(set) var agGecmisi: [AgOrnek] = []
    private(set) var canliAg = false
    let macVPN = MacVPN()
    let ekranlar = Ekranlar()
    let kota = Kota()

    private var dongu: Task<Void, Never>?
    private var akis: CanliAgAkisi?
    private var oncekiOrnek: (zaman: Double, rx: Double, tx: Double)?

    var sorunlar: [String] { rapor?.sorunlar() ?? [] }

    var genelSeviye: Seviye {
        if hata != nil { return .kritik }
        guard rapor != nil else { return .iyi }
        return sorunlar.isEmpty ? .iyi : .uyari
    }

    func baslat() {
        guard dongu == nil else { return }
        macVPN.izlemeyiBaslat()
        ekranlar.baslat()
        kota.baslat()
        dongu = Task { [weak self] in
            while !Task.isCancelled {
                await self?.yenile()
                try? await Task.sleep(for: .seconds(Self.yenilemeAraligi))
            }
        }
    }

    func yenile() async {
        guard !yenileniyor else { return }
        yenileniyor = true
        defer { yenileniyor = false }
        do {
            let r = try await Task.detached(priority: .userInitiated) { try Toplayici.raporAl() }.value
            rapor = r
            hata = nil
            sonGuncelleme = .now
            if let ag = r.ag { ekle(AgOrnek(tarih: .now, indirme: ag.indirme, yukleme: ag.yukleme)) }
            gunluk.info("Veri alındı: \(r.konteynerler.count) konteyner, \(r.sorunlar().count) sorun")
        } catch {
            hata = error.localizedDescription
            gunluk.error("Veri alınamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Panel açıkken ağ grafiğini canlı besler.
    func canliAgBaslat() {
        guard akis == nil else { return }
        canliAg = true
        oncekiOrnek = nil
        let a = CanliAgAkisi()
        akis = a
        a.baslat({ [weak self] t, rx, tx in
            Task { @MainActor in self?.canliOrnek((t, rx, tx)) }
        }, bitti: { [weak self] in
            // Bağlantı koptuysa ve panel hâlâ açıksa birkaç saniye sonra yeniden dene.
            Task { @MainActor in
                guard let self, self.akis === a else { return }
                self.akis = nil
                try? await Task.sleep(for: .seconds(5))
                if self.canliAg { self.canliAg = false; self.canliAgBaslat() }
            }
        })
    }

    func canliAgDurdur() {
        akis?.durdur()
        akis = nil
        canliAg = false
    }

    private func canliOrnek(_ o: (zaman: Double, rx: Double, tx: Double)) {
        defer { oncekiOrnek = o }
        guard let e = oncekiOrnek, o.zaman > e.zaman, o.rx >= e.rx, o.tx >= e.tx else { return }
        let dt = o.zaman - e.zaman
        ekle(AgOrnek(tarih: .now, indirme: (o.rx - e.rx) / dt, yukleme: (o.tx - e.tx) / dt))
    }

    private func ekle(_ o: AgOrnek) {
        agGecmisi.append(o)
        if agGecmisi.count > 90 { agGecmisi.removeFirst(agGecmisi.count - 90) }
    }
}
