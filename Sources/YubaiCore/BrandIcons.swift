import Foundation

public struct BrandIcon: Decodable, Equatable, Sendable {
    public var slug: String
    public var name: String
    public var keywords: [String]
    public var license: String
}

/// The bundled catalog is the only name/keyword mapping, also used for credits.
public enum BrandIcons {
    private struct Catalog: Decodable { var icons: [BrandIcon] }
    public static let catalog: [BrandIcon] = {
        guard let url = Bundle.module.url(forResource: "brand-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return value.icons
    }()
    public static var licenses: [String] { Array(Set(catalog.map(\.license))).sorted() }

    public static func match(_ name: String) -> BrandIcon? {
        let name = normalize(name)
        guard !name.isEmpty else { return nil }
        // Prefer the most specific keyword, then an exact catalog name, then
        // catalog order. Latin fragments require word boundaries (API ≠ capital).
        var best: (icon: BrandIcon, length: Int, exact: Bool)?
        for icon in catalog {
            for word in icon.keywords {
                let key = normalize(word)
                guard !key.isEmpty, contains(name, keyword: key) else { continue }
                let exact = name == normalize(icon.name)
                if best == nil || key.count > best!.length || (key.count == best!.length && exact && !best!.exact) {
                    best = (icon, key.count, exact)
                }
            }
        }
        return best?.icon
    }
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func contains(_ name: String, keyword: String) -> Bool {
        guard name.contains(keyword) else { return false }
        let latin = keyword.unicodeScalars.allSatisfy { $0.value < 128 }
        guard latin else { return name.contains(keyword) }
        let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![a-z0-9])"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
