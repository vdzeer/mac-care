import Foundation

/// The apps speak English; dates and times still follow the region the user chose.
public enum AppLocale {
    public static var current: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(languageCode: "en")
        return Locale(components: components)
    }

    /// "yesterday", "2 hours ago": dates the way people say them.
    public static func relative(_ date: Date, to now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = current
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(current))
    }

    public static func dateAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(current))
    }
}
