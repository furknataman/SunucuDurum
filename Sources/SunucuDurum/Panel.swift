import AppKit
import Charts
import SwiftUI

// MARK: - Tema (opak, yüksek kontrast)

enum Tema {
    private static func uyarlanir(_ koyu: UInt32, _ acik: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { g in
            let k = g.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: k ? koyu : acik)
        })
    }

    static let zemin = uyarlanir(0x0F1115, 0xF5F6F8)
    static let kart = uyarlanir(0x181B22, 0xFFFFFF)
    static let kenar = uyarlanir(0x262A33, 0xE3E5EA)
    static let cip = uyarlanir(0x22262F, 0xF0F1F4)
    static let iz = uyarlanir(0x2C313C, 0xE3E5EA)
    static let metin = uyarlanir(0xF2F4F7, 0x14171C)
    static let ikincil = uyarlanir(0xA3AAB8, 0x555C69)

    static let yesil = Color(nsColor: NSColor(hex: 0x30D158))
    static let turuncu = Color(nsColor: NSColor(hex: 0xFF9F0A))
    static let kirmizi = Color(nsColor: NSColor(hex: 0xFF453A))
    static let mavi = Color(nsColor: NSColor(hex: 0x0A84FF))
    static let mor = Color(nsColor: NSColor(hex: 0xBF5AF2))

    static func yazi(_ boyut: CGFloat, _ agirlik: Font.Weight = .regular) -> Font {
        .system(size: boyut, weight: agirlik)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Seviye {
    var renk: Color {
        switch self {
        case .iyi: Tema.yesil
        case .uyari: Tema.turuncu
        case .kritik: Tema.kirmizi
        }
    }
}

// MARK: - Ana panel

struct Panel: View {
    @Environment(Durum.self) private var durum
    var canliAgKullan = true

    var body: some View {
        VStack(spacing: 10) {
            Baslik()
            if let hata = durum.hata { HataKarti(mesaj: hata) }
            if let r = durum.rapor {
                Icerik(rapor: r)
                    .opacity(durum.hata == nil ? 1 : 0.45)
                    .saturation(durum.hata == nil ? 1 : 0.2)
                    .allowsHitTesting(durum.hata == nil)
            } else if durum.hata == nil {
                Yukleniyor()
            }
            Alt()
        }
        .padding(14)
        .frame(width: 420)
        .foregroundStyle(Tema.metin)
        .background(Tema.zemin)
        .animation(.smooth(duration: 0.45), value: durum.hata)
        .animation(.smooth(duration: 0.45), value: durum.rapor == nil)
        .onAppear { if canliAgKullan { durum.canliAgBaslat() } }
        .onDisappear { durum.canliAgDurdur() }
    }
}

private struct Icerik: View {
    let rapor: Rapor
    @Environment(Durum.self) private var durum

    var body: some View {
        VStack(spacing: 10) {
            if !durum.sorunlar.isEmpty { UyariKarti(sorunlar: durum.sorunlar) }
            if let s = rapor.sistem { Kaynaklar(sistem: s) }
            AgKarti(anlik: rapor.ag)
            ProjelerKarti(projeler: Proje.grupla(rapor.konteynerler), servisler: rapor.servisler)
            VPNKarti(esler: rapor.vpn, mac: durum.macVPN)
            HStack(alignment: .top, spacing: 10) {
                YedeklerKarti(yedekler: rapor.yedekler)
                AdGuardKarti(adguard: rapor.adguard)
            }
            .fixedSize(horizontal: false, vertical: true)
            GorevKarti(gorevler: rapor.gorevler)
            .fixedSize(horizontal: false, vertical: true)
            if let s = rapor.saglikRaporu {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(s.tamam ? Tema.yesil : Tema.kirmizi)
                    Text("Son sağlık raporu: \(Bicim.tarihSaat(Date(timeIntervalSince1970: Double(s.zaman))))")
                        .foregroundStyle(Tema.ikincil)
                    Spacer()
                }
                .font(Tema.yazi(11))
                .padding(.horizontal, 4)
                .help(s.ozet)
            }
        }
    }
}

// MARK: - Ortak parçalar

/// Koyu zemin + renkli nokta + açık metin.
private struct Cip: View {
    let renk: Color
    let metin: String
    var ek: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(renk).frame(width: 7, height: 7)
            Text(metin).font(Tema.yazi(11, .semibold)).foregroundStyle(Tema.metin)
            if let ek { Text(ek).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil) }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Tema.cip, in: Capsule())
        .overlay(Capsule().strokeBorder(Tema.kenar, lineWidth: 1))
    }
}

private struct Kart<Icerik: View>: View {
    let baslik: String
    let sembol: String
    var renk: Color = Tema.mavi
    var sag: AnyView? = nil
    @ViewBuilder let icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sembol).foregroundStyle(renk).font(Tema.yazi(11, .semibold))
                Text(baslik).font(Tema.yazi(11, .bold)).foregroundStyle(Tema.ikincil).kerning(0.4)
                Spacer(minLength: 0)
                if let sag { sag }
            }
            icerik
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kartZemini()
    }
}

extension View {
    func kartZemini(kenar: Color = Tema.kenar) -> some View {
        background(Tema.kart, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(kenar, lineWidth: 1))
    }
}

private struct DuzTus: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tema.yazi(12, .medium))
            .foregroundStyle(Tema.metin)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Tema.kart, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tema.kenar, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Başlık

private struct Baslik: View {
    @Environment(Durum.self) private var durum

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(durum.genelSeviye.renk).frame(width: 34, height: 34)
                Image(systemName: "server.rack").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Ayar.mevcut.ad).font(Tema.yazi(15, .semibold))
                    DurumHapi()
                }
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    Text(altBaslik(ctx.date)).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                }
            }
            Spacer()
            YenileTusu()
        }
        .padding(.horizontal, 2)
    }

    private func altBaslik(_ simdi: Date) -> String {
        var p = [Ayar.mevcut.adres]
        if let s = durum.rapor?.sistem { p.append("\(Bicim.sure(s.acikKalma)) açık") }
        if durum.yenileniyor && durum.sonGuncelleme == nil {
            p.append("Bağlanıyor…")
        } else if let t = durum.sonGuncelleme {
            p.append("Son güncelleme: \(Bicim.once(t, simdi: simdi))")
        }
        return p.joined(separator: " · ")
    }
}

private struct DurumHapi: View {
    @Environment(Durum.self) private var durum

    var body: some View {
        let (metin, renk): (String, Color) = {
            if durum.hata != nil { return ("Erişilemiyor", Tema.kirmizi) }
            if durum.rapor == nil { return ("Bekleniyor", Tema.ikincil) }
            let n = durum.sorunlar.count
            return n == 0 ? ("Her şey yolunda", Tema.yesil) : ("\(n) uyarı", Tema.turuncu)
        }()
        Cip(renk: renk, metin: metin)
    }
}

private struct YenileTusu: View {
    @Environment(Durum.self) private var durum
    @State private var aci = 0.0

    var body: some View {
        Button {
            Task { await durum.yenile() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.metin)
                .rotationEffect(.degrees(aci))
                .frame(width: 32, height: 32)
                .background(Tema.kart, in: Circle())
                .overlay(Circle().strokeBorder(Tema.kenar, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Yenile")
        .disabled(durum.yenileniyor)
        .onChange(of: durum.yenileniyor, initial: true) { _, yeni in
            if yeni {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { aci += 360 }
            } else {
                withAnimation(.spring(duration: 0.5)) { aci = (aci / 360).rounded(.up) * 360 }
            }
        }
    }
}

// MARK: - Durum kartları

private struct HataKarti: View {
    let mesaj: String
    @Environment(Durum.self) private var durum

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Tema.kirmizi)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sunucuya erişilemiyor").font(Tema.yazi(13, .semibold))
                Text(mesaj).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if let t = durum.sonGuncelleme {
                    Text("Aşağıdaki veriler \(Bicim.once(t)) alındı.").font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .kartZemini(kenar: Tema.kirmizi.opacity(0.6))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct UyariKarti: View {
    let sorunlar: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sorunlar, id: \.self) { s in
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.turuncu)
                    Text(s).foregroundStyle(Tema.metin)
                }
                .font(Tema.yazi(12))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kartZemini(kenar: Tema.turuncu.opacity(0.6))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

private struct Yukleniyor: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Sunucudan veri alınıyor…").font(Tema.yazi(12)).foregroundStyle(Tema.ikincil)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .kartZemini()
    }
}

// MARK: - Kaynaklar (halkalar)

private struct Kaynaklar: View {
    let sistem: Sistem

    var body: some View {
        HStack(spacing: 0) {
            Halka(baslik: "İşlemci", deger: sistem.cpuYuzde,
                  alt: "Yük \(Bicim.sayi(sistem.yuk1, basamak: 2)) / \(sistem.cekirdek)")
            Halka(baslik: "RAM", deger: sistem.ramYuzde,
                  alt: "\(Bicim.bayt(sistem.ramKullanilan)) / \(Bicim.bayt(sistem.ramToplam))")
            Halka(baslik: "Disk", deger: sistem.diskYuzde,
                  alt: "\(Bicim.bayt(sistem.diskKullanilan)) / \(Bicim.bayt(sistem.diskKullanilan + sistem.diskBos))")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .kartZemini()
    }
}

private struct Halka: View {
    let baslik: String
    let deger: Double
    let alt: String
    @State private var gosterilen = 0.0

    var body: some View {
        let renk = Seviye.yuzde(deger).renk
        let oran = max(0.004, min(gosterilen, 100) / 100)
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Tema.iz, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: oran)
                    .stroke(renk, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Bicim.yuzde(gosterilen))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Tema.metin)
                    .contentTransition(.numericText(value: gosterilen))
            }
            .frame(width: 70, height: 70)
            Text(baslik).font(Tema.yazi(12, .semibold))
            Text(alt).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil).monospacedDigit().lineLimit(1).minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.spring(duration: 1.2, bounce: 0.15).delay(0.05)) { gosterilen = deger } }
        .onChange(of: deger) { _, yeni in withAnimation(.spring(duration: 1.0, bounce: 0.15)) { gosterilen = yeni } }
    }
}

// MARK: - Ağ

private struct AgKarti: View {
    let anlik: Ag?
    @Environment(Durum.self) private var durum

    var body: some View {
        let son = durum.agGecmisi.last
        let indirme = son?.indirme ?? anlik?.indirme ?? 0
        let yukleme = son?.yukleme ?? anlik?.yukleme ?? 0
        Kart(baslik: "AĞ · ETH0", sembol: "network", renk: Tema.mavi, sag: AnyView(CanliIsareti(aktif: durum.canliAg))) {
            HStack(spacing: 18) {
                HizEtiketi(sembol: "arrow.down.circle.fill", renk: Tema.mavi, baslik: "İndirme", deger: indirme)
                HizEtiketi(sembol: "arrow.up.circle.fill", renk: Tema.mor, baslik: "Yükleme", deger: yukleme)
                Spacer(minLength: 0)
            }
            AgGrafigi(ornekler: durum.agGecmisi)
                .frame(height: 60)
        }
    }
}

private struct CanliIsareti: View {
    let aktif: Bool
    var body: some View {
        if aktif {
            HStack(spacing: 5) {
                Circle().fill(Tema.yesil).frame(width: 7, height: 7)
                    .phaseAnimator([1.0, 0.3]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.8) }
                Text("Canlı").font(Tema.yazi(11, .medium)).foregroundStyle(Tema.ikincil)
            }
        }
    }
}

private struct HizEtiketi: View {
    let sembol: String
    let renk: Color
    let baslik: String
    let deger: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: sembol).font(.system(size: 20)).foregroundStyle(renk)
            VStack(alignment: .leading, spacing: 1) {
                Text(baslik).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                Text(Bicim.hiz(deger))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: deger))
                    .animation(.smooth, value: deger)
            }
        }
    }
}

private struct AgGrafigi: View {
    let ornekler: [AgOrnek]

    var body: some View {
        if ornekler.count < 2 {
            Text(ornekler.isEmpty ? "Ölçüm bekleniyor…" : "Grafik için ikinci ölçüm bekleniyor…")
                .font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(ornekler) { o in
                    AreaMark(x: .value("Zaman", o.tarih), y: .value("Hız", o.indirme), series: .value("Yön", "İndirme"))
                        .foregroundStyle(LinearGradient(colors: [Tema.mavi.opacity(0.3), Tema.mavi.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Zaman", o.tarih), y: .value("Hız", o.indirme), series: .value("Yön", "İndirme"))
                        .foregroundStyle(Tema.mavi)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Zaman", o.tarih), y: .value("Hız", o.yukleme), series: .value("Yön", "Yükleme"))
                        .foregroundStyle(Tema.mor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(Tema.kenar)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(Bicim.hiz(d)).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil) }
                    }
                }
            }
            .chartLegend(.hidden)
            .animation(.smooth(duration: 0.6), value: ornekler.count)
        }
    }
}

// MARK: - Projeler

private struct ProjelerKarti: View {
    let projeler: [Proje]
    let servisler: [Servis]

    var body: some View {
        Kart(baslik: "PROJELER", sembol: "square.stack.3d.up.fill", renk: Tema.mor) {
            VStack(spacing: 8) {
                ForEach(projeler) { p in ProjeSatiri(proje: p) }
            }
            Rectangle().fill(Tema.kenar).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 6) {
                ForEach(servisler) { s in
                    Cip(renk: s.seviye.renk, metin: s.gorunenAd)
                        .help("\(s.ad): \(s.durumMetni)")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ProjeSatiri: View {
    let proje: Proje

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: proje.sembol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(proje.seviye.renk, in: RoundedRectangle(cornerRadius: 6))
            Text(proje.ad).font(Tema.yazi(13, .medium)).frame(width: 100, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                ForEach(proje.konteynerler) { k in
                    Cip(renk: k.seviye.renk, metin: k.kisaAd, ek: k.sureMetni)
                        .help("\(k.ad): \(k.durumMetni) · \(k.metin)")
                }
            }
            Spacer(minLength: 0)
        }
        .help(ozet)
    }

    private var ozet: String {
        let calisan = proje.konteynerler.filter { $0.durum == "running" }.count
        return "\(proje.ad): \(calisan)/\(proje.konteynerler.count) konteyner çalışıyor"
    }
}

// MARK: - Küçük kartlar

private struct Satir: View {
    let renk: Color
    let ad: String
    let deger: String
    var vurgulu = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(renk).frame(width: 7, height: 7)
            Text(ad).font(Tema.yazi(12, .medium))
            Spacer(minLength: 4)
            Text(deger).font(Tema.yazi(11, vurgulu ? .semibold : .regular))
                .foregroundStyle(vurgulu ? Tema.metin : Tema.ikincil)
        }
    }
}

private struct YedeklerKarti: View {
    let yedekler: [Yedek]

    var body: some View {
        Kart(baslik: "YEDEKLER", sembol: "externaldrive.fill.badge.timemachine", renk: Tema.mavi) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(yedekler) { y in
                    let saat = y.saatOnce(simdi: .now)
                    let eski = saat.map { $0 > 26 } ?? true
                    Satir(renk: saat == nil ? Tema.kirmizi : eski ? Tema.turuncu : Tema.yesil, ad: y.ad,
                          deger: saat.map { $0 == 0 ? "1 saatten yeni" : "\($0) saat önce" } ?? "Yok",
                          vurgulu: eski)
                }
            }
        }
    }
}

private struct VPNKarti: View {
    let esler: [VPNEs]
    let mac: MacVPN

    var body: some View {
        Kart(baslik: "VPN", sembol: "lock.shield.fill", renk: Tema.yesil) {
            VStack(alignment: .leading, spacing: 10) {
                macSatiri
                if let h = mac.hata {
                    Text(h).font(Tema.yazi(11)).foregroundStyle(Tema.kirmizi).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Tema.kenar).frame(height: 1)
                Text("EŞLER").font(Tema.yazi(11, .bold)).foregroundStyle(Tema.ikincil).kerning(0.4)
                VStack(alignment: .leading, spacing: 6) {
                    if esler.isEmpty { Text("Eş bulunamadı").font(Tema.yazi(11)).foregroundStyle(Tema.ikincil) }
                    ForEach(esler) { e in
                        let bagli = e.bagli(simdi: .now)
                        Satir(renk: bagli ? Tema.yesil : Tema.iz, ad: e.ad, deger: durumMetni(e, bagli: bagli), vurgulu: bagli)
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: mac.hal)
            .animation(.smooth(duration: 0.3), value: mac.hata)
        }
        .task {
            // Kart açıkken yerel tünel durumu (WireGuard uygulamasından yapılan değişiklikler dahil) canlı izlenir.
            while !Task.isCancelled {
                await mac.yenile()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private var macSatiri: some View {
        switch mac.hal {
        case .bilinmiyor:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Denetleniyor…").font(Tema.yazi(12)).foregroundStyle(Tema.ikincil)
            }
        case .kuruluDegil:
            eylemSatiri(baslik: "WireGuard kurulu değil", altMetin: "Bu Mac'in tüneli için uygulama gerekli.",
                        dugme: "App Store'da aç", sembol: "arrow.down.app.fill") { mac.magazayiAc() }
        case .tunelYok:
            if mac.ayarDosyasiVar {
                eylemSatiri(baslik: "Tünel içe aktarılmadı", altMetin: "WireGuard'da Import tunnel(s) from file… ile \(MacVPN.ayarDosyasi.lastPathComponent) dosyasını seç.",
                            dugme: "Ayar dosyasını içe aktar", sembol: "square.and.arrow.down.fill") { mac.ayarDosyasiniAc() }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tünel içe aktarılmadı").font(Tema.yazi(13, .semibold))
                    Text("İçe aktarılacak \(MacVPN.ayarDosyasi.lastPathComponent) dosyası bulunamadı: \(MacVPN.ayarDosyasi.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                        .font(Tema.yazi(11)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .kapali, .baglaniyor, .bagli, .kesiliyor:
            tunelSatiri
        }
    }

    private var tunelSatiri: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bu Mac").font(Tema.yazi(14, .semibold))
                    HStack(spacing: 6) {
                        if mac.mesgul { ProgressView().controlSize(.mini) }
                        else { Circle().fill(mac.bagli ? Tema.yesil : Tema.iz).frame(width: 7, height: 7) }
                        Text(durumMetni).font(Tema.yazi(12, mac.bagli ? .semibold : .regular))
                            .foregroundStyle(mac.bagli ? Tema.metin : Tema.ikincil)
                    }
                }
                Spacer(minLength: 8)
                Toggle("Bu Mac için VPN", isOn: Binding(get: { mac.acik }, set: { mac.degistir(ac: $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .tint(Tema.yesil)
                    .disabled(mac.hal == .kesiliyor)
            }
            if mac.bagli {
                Link(destination: MacVPN.adGuardPaneli) {
                    Label("AdGuard paneli", systemImage: "arrow.up.right.square")
                        .font(Tema.yazi(11, .medium))
                }
                .foregroundStyle(Tema.mavi)
                .transition(.opacity)
            }
        }
    }

    private var durumMetni: String {
        switch mac.hal {
        case .bagli: mac.adres.map { "Bağlı · \($0)" } ?? "Bağlı"
        case .baglaniyor: "Bağlanıyor…"
        case .kesiliyor: "Bağlantı kesiliyor…"
        default: "Kapalı"
        }
    }

    private func eylemSatiri(baslik: String, altMetin: String, dugme: String, sembol: String,
                             eylem: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(baslik).font(Tema.yazi(13, .semibold))
                Text(altMetin).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: eylem) { Label(dugme, systemImage: sembol) }
                .buttonStyle(DuzTus())
        }
    }

    private func durumMetni(_ e: VPNEs, bagli: Bool) -> String {
        if bagli { return "Bağlı" }
        guard let t = e.sonGorulme else { return "Hiç bağlanmadı" }
        return Bicim.once(Date(timeIntervalSince1970: Double(t)))
    }
}

private struct AdGuardKarti: View {
    let adguard: AdGuard?

    var body: some View {
        Kart(baslik: "ADGUARD · 24 SAAT", sembol: "shield.lefthalf.filled", renk: Tema.yesil) {
            if let a = adguard {
                VStack(alignment: .leading, spacing: 5) {
                    Satir(renk: a.calisiyor ? Tema.yesil : Tema.kirmizi, ad: "DNS", deger: a.calisiyor ? "Yanıt veriyor" : "Yanıt vermiyor",
                          vurgulu: !a.calisiyor)
                    if let q = a.sorgu, let b = a.engellenen {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Bicim.tam(q)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize()
                            Text("sorgu").font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Bicim.tam(b)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize()
                            Text("engellendi (\(Bicim.yuzde(q > 0 ? Double(b) / Double(q) * 100 : 0)))")
                                .font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                        }
                    } else {
                        Text("İstatistik alınamadı").font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
                    }
                }
            } else {
                Text("Bilgi alınamadı").font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
            }
        }
    }
}

private struct GorevKarti: View {
    let gorevler: [String]

    var body: some View {
        Kart(baslik: "ÇALIŞAN GÖREVLER", sembol: "sparkles", renk: Tema.turuncu) {
            VStack(alignment: .leading, spacing: 5) {
                if gorevler.isEmpty {
                    Text("Çalışan görev yok").font(Tema.yazi(12)).foregroundStyle(Tema.ikincil)
                } else {
                    ForEach(gorevler, id: \.self) { g in
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(g).font(Tema.yazi(12, .medium)).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alt çubuk

private struct Alt: View {
    var body: some View {
        HStack {
            Button {
                Terminal.baglan()
            } label: {
                Label("Terminal'de bağlan", systemImage: "terminal.fill")
            }
            .buttonStyle(DuzTus())
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "power")
            }
            .buttonStyle(DuzTus())
            .keyboardShortcut("q")
        }
    }
}

enum Terminal {
    static func baglan() {
        guard let url = URL(string: "ssh://\(Ayar.mevcut.ssh)") else { return }
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let ayar = NSWorkspace.OpenConfiguration()
            ayar.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: ayar)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
