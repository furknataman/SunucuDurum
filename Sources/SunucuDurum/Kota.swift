// Claude ve Codex abonelik kotaları: kalan kullanım limitleri.
// Veri kaynakları ve istek biçimi için CodexBar © 2026 Peter Steinberger, MIT esas alınmıştır.
// Token yenilenmez; süresi dolmuşsa kullanıcıya ilgili aracı bir kez açması söylenir.
import Foundation
import Observation
import SwiftUI

// MARK: - Model

struct KotaSatiri: Identifiable {
    let ad: String
    let kullanilanYuzde: Double
    let sifirlanma: Date?
    var id: String { ad }

    var kalanYuzde: Int { Int((100 - kullanilanYuzde).rounded()).clamped(0, 100) }
}

struct KotaSaglayici: Identifiable {
    let ad: String
    var plan: String?
    var satirlar: [KotaSatiri] = []
    var hata: String?
    var id: String { ad }

    var baslik: String { plan.map { "\(ad) · \($0)" } ?? ad }
}

private extension Int {
    func clamped(_ a: Int, _ b: Int) -> Int { Swift.min(Swift.max(self, a), b) }
}

// MARK: - Çekme

@MainActor
@Observable
final class Kota {
    static let yenilemeAraligi: TimeInterval = 120

    private(set) var claude: KotaSaglayici?
    private(set) var codex: KotaSaglayici?

    var saglayicilar: [KotaSaglayici] { [claude, codex].compactMap { $0 } }

    private var dongu: Task<Void, Never>?
    private var yenileniyor = false
    private var claudeBekleme: Date?
    private var claudeSurum: String?

    func baslat() {
        guard dongu == nil else { return }
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
        async let c: Void = claudeCek()
        async let x: Void = codexCek()
        _ = await (c, x)
    }

    // MARK: Claude

    private struct ClaudeKimlik: Decodable {
        struct Oauth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
            let rateLimitTier: String?
        }
        let claudeAiOauth: Oauth?
    }

    private struct ClaudePencere: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    private struct ClaudeSinir: Decodable {
        struct Kapsam: Decodable {
            struct Model: Decodable { let displayName: String? }
            let model: Model?
        }
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Kapsam?
    }

    private struct ClaudeYanit: Decodable {
        let fiveHour: ClaudePencere?
        let sevenDay: ClaudePencere?
        let limits: [ClaudeSinir]?
    }

    private func claudeCek() async {
        if let b = claudeBekleme, b > .now { return }
        // Kayıt yoksa Claude Code kurulu değildir: kartta hiç görünmez.
        guard let metin = await komutCalistir("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let oauth = try? JSONDecoder().decode(ClaudeKimlik.self, from: Data(metin.utf8)).claudeAiOauth,
              let token = oauth.accessToken else {
            claude = nil
            return
        }
        var s = KotaSaglayici(ad: "Claude", plan: Self.claudePlani(oauth.subscriptionType, oauth.rateLimitTier),
                              satirlar: claude?.satirlar ?? [])
        let dolmusMetni = "Oturum süresi dolmuş; Claude Code'u bir kez açman yeterli."
        if let bitis = oauth.expiresAt, Date(timeIntervalSince1970: bitis / 1000) <= .now {
            s.satirlar = []; s.hata = dolmusMetni
            claude = s
            return
        }
        if claudeSurum == nil { claudeSurum = await claudeSurumuBul() }
        var istek = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        istek.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        istek.setValue("application/json", forHTTPHeaderField: "Accept")
        istek.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        istek.setValue("claude-cli/\(claudeSurum ?? "2.1.0") (external, cli)", forHTTPHeaderField: "User-Agent")
        do {
            let (veri, yanit) = try await URLSession.shared.data(for: istek)
            let kod = (yanit as? HTTPURLResponse)?.statusCode ?? 0
            switch kod {
            case 200:
                let y = try JSONDecoder.kota.decode(ClaudeYanit.self, from: veri)
                s.satirlar = Self.claudeSatirlari(y)
                s.hata = s.satirlar.isEmpty ? "Kullanım bilgisi bulunamadı." : nil
            case 401:
                s.satirlar = []; s.hata = dolmusMetni
            case 429:
                // Eski veri görünmeye devam eder; Retry-After kadar (yoksa 5 dk) yeniden denenmez.
                let sn = ((yanit as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")).flatMap { Double($0) } ?? 300
                claudeBekleme = Date().addingTimeInterval(max(sn, 1))
                return
            default:
                s.hata = "Claude kullanımı alınamadı (HTTP \(kod))."
            }
        } catch {
            s.hata = "Claude kullanımı alınamadı; bağlantı kurulamadı."
        }
        claude = s
    }

    private static func claudePlani(_ tur: String?, _ kademe: String?) -> String? {
        guard let tur, !tur.isEmpty else { return nil }
        var p = tur.prefix(1).uppercased() + tur.dropFirst()
        // "default_claude_max_20x" → "20x"
        if let son = kademe?.split(separator: "_").last, son.hasSuffix("x"), Int(son.dropLast()) != nil { p += " \(son)" }
        return p
    }

    private static func claudeSatirlari(_ y: ClaudeYanit) -> [KotaSatiri] {
        var l: [KotaSatiri] = []
        if let p = y.fiveHour, let u = p.utilization { l.append(KotaSatiri(ad: "5 saatlik oturum", kullanilanYuzde: u, sifirlanma: tarih(p.resetsAt))) }
        if let p = y.sevenDay, let u = p.utilization { l.append(KotaSatiri(ad: "Haftalık (tüm modeller)", kullanilanYuzde: u, sifirlanma: tarih(p.resetsAt))) }
        for s in y.limits ?? [] where s.kind == "weekly_scoped" {
            guard let u = s.percent, let ad = s.scope?.model?.displayName else { continue }
            l.append(KotaSatiri(ad: "Haftalık · \(ad)", kullanilanYuzde: u, sifirlanma: tarih(s.resetsAt)))
        }
        return l
    }

    private static func tarih(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Uygulama ömründe bir kez: `claude --version` çıktısının ilk kelimesi.
    private func claudeSurumuBul() async -> String? {
        let yerel = NSHomeDirectory() + "/.local/bin/claude"
        let cikti = FileManager.default.isExecutableFile(atPath: yerel)
            ? await komutCalistir(yerel, ["--version"])
            : await komutCalistir("/usr/bin/env", ["claude", "--version"])
        return cikti?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    // MARK: Codex

    private struct CodexKimlik: Decodable {
        struct Tokenlar: Decodable {
            let accessToken: String?
            let accountId: String?
        }
        let tokens: Tokenlar?
    }

    private struct CodexPencere: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Int?
        let resetAt: Double?
    }

    private struct CodexYanit: Decodable {
        struct Sinir: Decodable {
            let primaryWindow: CodexPencere?
            let secondaryWindow: CodexPencere?
        }
        let planType: String?
        let rateLimit: Sinir?
    }

    private func codexCek() async {
        let dizin = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.codex"
        // Dosya yoksa Codex kurulu değildir: kartta hiç görünmez.
        guard let veri = await Task.detached(operation: { FileManager.default.contents(atPath: dizin + "/auth.json") }).value,
              let t = try? JSONDecoder.kota.decode(CodexKimlik.self, from: veri).tokens,
              let token = t.accessToken, let hesap = t.accountId else {
            codex = nil
            return
        }
        var s = KotaSaglayici(ad: "Codex", plan: codex?.plan, satirlar: codex?.satirlar ?? [])
        var istek = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 15)
        istek.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        istek.setValue(hesap, forHTTPHeaderField: "ChatGPT-Account-Id")
        istek.setValue("SunucuDurum", forHTTPHeaderField: "User-Agent")
        istek.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (cevap, yanit) = try await URLSession.shared.data(for: istek)
            let kod = (yanit as? HTTPURLResponse)?.statusCode ?? 0
            switch kod {
            case 200:
                let y = try JSONDecoder.kota.decode(CodexYanit.self, from: cevap)
                s.plan = y.planType.flatMap { $0.isEmpty ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
                s.satirlar = [y.rateLimit?.primaryWindow, y.rateLimit?.secondaryWindow].compactMap { Self.codexSatiri($0) }
                s.hata = s.satirlar.isEmpty ? "Kullanım bilgisi bulunamadı." : nil
            case 401:
                s.satirlar = []; s.hata = "Oturum süresi dolmuş; Terminal'de codex'i bir kez çalıştırman yeterli."
            default:
                s.hata = "Codex kullanımı alınamadı (HTTP \(kod))."
            }
        } catch {
            s.hata = "Codex kullanımı alınamadı; bağlantı kurulamadı."
        }
        codex = s
    }

    private static func codexSatiri(_ p: CodexPencere?) -> KotaSatiri? {
        guard let p, let u = p.usedPercent else { return nil }
        let sn = p.limitWindowSeconds ?? 0
        let ad: String
        switch sn {
        case 18000: ad = "5 saatlik oturum"
        case 604800: ad = "Haftalık"
        case ..<172800: ad = "\(max(sn / 3600, 1)) saatlik"
        default: ad = "\(sn / 86400) günlük"
        }
        return KotaSatiri(ad: ad, kullanilanYuzde: u, sifirlanma: p.resetAt.map { Date(timeIntervalSince1970: $0) })
    }
}

private extension JSONDecoder {
    static var kota: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

/// Arka planda çalıştırır; başarısızsa ya da çıkış kodu 0 değilse nil. Çıktı asla loglanmaz.
private func komutCalistir(_ yol: String, _ argumanlar: [String]) async -> String? {
    await Task.detached(priority: .utility) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = argumanlar
        let cikis = Pipe()
        p.standardOutput = cikis
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // Anahtar Zinciri penceresinde ya da kilitte takılırsa kota yenilemesi sonsuza dek beklemesin.
        let sinir = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: sinir)
        let veri = cikis.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        sinir.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: veri, as: UTF8.self)
    }.value
}

// MARK: - Biçim

extension Bicim {
    /// "2 sa 14 dk sonra yenilenir" (24 saatten az) ya da "24 Eki Cum 05:59'da yenilenir".
    static func yenilenme(_ t: Date, simdi: Date = .now) -> String {
        let sn = Int(t.timeIntervalSince(simdi))
        if sn <= 0 { return "Yenilenme zamanı geldi" }
        if sn < 86400 { return "\(sure(sn)) sonra yenilenir" }
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = "d MMM EEE HH:mm"
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        let dakika = c.minute ?? 0
        return "\(f.string(from: t))'\(ekDa(dakika != 0 ? dakika : c.hour ?? 0)) yenilenir"
    }

    /// Okunuşta son sayıya göre bulunma eki: 59 (dokuz) → "da", 30 → "da", 40 → "ta", 5 → "te".
    private static func ekDa(_ n: Int) -> String {
        let tekler = ["da", "de", "de", "te", "te", "te", "da", "de", "de", "da"]   // 0 sıfır, 1 bir, 2 iki, 3 üç, 4 dört, 5 beş, 6 altı, 7 yedi, 8 sekiz, 9 dokuz
        let onlar = ["", "da", "de", "da", "ta", "de"]                               // on, yirmi, otuz, kırk, elli
        if n % 10 != 0 || n == 0 { return tekler[n % 10] }
        return onlar[n / 10]
    }
}

// MARK: - Kart

struct KotaKarti: View {
    let kota: Kota

    var body: some View {
        Kart(baslik: "YAPAY ZEKÂ KULLANIMI", sembol: "chart.bar.fill", renk: Tema.mor) {
            // Sıfırlanma metinleri dakikalar içinde değiştiği için yarım dakikada bir yenilenir.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(kota.saglayicilar) { s in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(s.baslik).font(Tema.yazi(12, .semibold))
                            ForEach(s.satirlar) { KotaSatirGorunumu(satir: $0, simdi: ctx.date) }
                            if let h = s.hata {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.turuncu)
                                    Text(h).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(Tema.yazi(11))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct KotaSatirGorunumu: View {
    let satir: KotaSatiri
    let simdi: Date

    private var renk: Color {
        switch satir.kalanYuzde {
        case 50...: Tema.yesil
        case 20..<50: Tema.turuncu
        default: Tema.kirmizi
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(satir.ad).font(Tema.yazi(12))
                Spacer(minLength: 8)
                Text("%\(satir.kalanYuzde) kaldı").font(Tema.yazi(12, .semibold)).monospacedDigit().foregroundStyle(renk)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.iz)
                    Capsule().fill(renk).frame(width: g.size.width * CGFloat(satir.kalanYuzde) / 100)
                }
            }
            .frame(height: 5)
            if let t = satir.sifirlanma {
                Text(Bicim.yenilenme(t, simdi: simdi)).font(Tema.yazi(11)).foregroundStyle(Tema.ikincil)
            }
        }
    }
}
