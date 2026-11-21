import Foundation

/// Single source of the product name (specs/00): the `app.name` key of the String
/// Catalog. Never hard-code the name anywhere else.
enum AppBrand {
    static var name: String { String(localized: "app.name") }
}
