import Foundation

/// Sunucuya özgü bütün bilgiler repo dışındaki bir JSON dosyasında durur:
/// `~/Library/Application Support/Sunucu Durum/ayar.json` (şema için `ayar.ornek.json`'a bak).
struct Ayar: Codable {
    struct Servis: Codable { let ad: String; let gorunenAd: String }
    struct Proje: Codable { let ad: String; let sembol: String; let onekler: [String] }
    struct Yedek: Codable { let ad: String; let klasor: String; let desen: String }
    struct VPN: Codable {
        let arayuz: String        // sunucudaki WireGuard arayüzü
        let tunel: String         // Mac'teki tünel adı
        let ayarDosyasi: String   // ev klasörüne göreli .conf yolu
    }
    struct AdGuard: Codable {
        let adres: String
        let port: Int
        let sifreDosyasi: String  // sunucuda kalır, çıktıya yazılmaz
        let testAlanAdi: String
    }

    let ad: String
    let ssh: String
    let adres: String
    let agArayuzu: String
    let servisler: [Servis]
    let projeler: [Proje]
    let yedekler: [Yedek]
    let saglikKlasoru: String
    let gorevKlasoru: String
    let vpn: VPN
    let adguard: AdGuard

    static var yol: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sunucu Durum/ayar.json")
    }

    static func yukle() throws -> Ayar {
        try JSONDecoder().decode(Ayar.self, from: Data(contentsOf: yol))
    }

    /// Yükleme sonucu bir kez hesaplanır; hata çökmeye değil, `Toplayici.raporAl()` içinde hata kartına gider.
    static let sonuc = Result { try yukle() }

    /// Yükleme başarısızsa boş bir varsayılan döner (arayüz yine açılır).
    static var mevcut: Ayar {
        if case let .success(a) = sonuc { return a }
        return Ayar(ad: "Sunucu", ssh: "", adres: "", agArayuzu: "", servisler: [], projeler: [], yedekler: [],
                    saglikKlasoru: "", gorevKlasoru: "",
                    vpn: VPN(arayuz: "", tunel: "", ayarDosyasi: ""),
                    adguard: AdGuard(adres: "", port: 0, sifreDosyasi: "", testAlanAdi: ""))
    }
}
