import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// One page of a character sheet PDF: the printed labels, and the filled-in boxes.
///
/// D&D Beyond's PDFs have no form (no AcroForm), but every value is still drawn in a named box
/// (a widget annotation such as `STR`, `MaxHP` or `spellName11`). The page's own text only has the labels.
public struct PDFSheetPage: Hashable, Sendable {
    /// 0-based page number.
    public var index: Int
    /// The page's printed text (labels such as "ARMOR CLASS" and "SAVING THROWS").
    public var text: String
    public var fields: [Field]

    public init(index: Int, text: String, fields: [Field]) {
        self.index = index
        self.text = text
        self.fields = fields
    }

    /// A filled-in box on the page.
    public struct Field: Hashable, Sendable {
        /// The box's name with spaces trimmed, e.g. "Wpn2 AtkBonus".
        public var name: String
        public var value: String
        /// Bottom-left corner and size, in PDF points (y grows upwards).
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(name: String, value: String, x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
            self.name = PDFSheetPage.normalizedName(name)
            self.value = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// The top edge (y grows upwards in PDF space).
        public var top: Double { y + height }
    }

    /// "Wpn2 AtkBonus  " → "Wpn2 AtkBonus", "CLASS  LEVEL" → "CLASS LEVEL".
    static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first non-empty value for a box name (case-insensitive).
    public func value(_ name: String) -> String? {
        let wanted = Self.normalizedName(name)
        for field in fields where field.name.caseInsensitiveCompare(wanted) == .orderedSame {
            let trimmed = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return field.value }
        }
        return nil
    }

    public func hasField(_ name: String) -> Bool {
        let wanted = Self.normalizedName(name)
        return fields.contains { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// Boxes named `prefix` followed by a number, e.g. "spellName12", as (number, field).
    public func numberedFields(_ prefix: String) -> [(number: Int, field: Field)] {
        fields.compactMap { field in
            guard field.name.count > prefix.count,
                  field.name.lowercased().hasPrefix(prefix.lowercased()),
                  let number = Int(field.name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
            else { return nil }
            return (number, field)
        }
    }

    /// Everything on the page as text: the labels, then "name: value" for every filled-in box.
    public var rawText: String {
        var lines = ["--- Page \(index + 1) ---", text.trimmingCharacters(in: .whitespacesAndNewlines), "--- Fields ---"]
        for field in fields where !field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("[\(field.name)] \(field.value)")
        }
        return lines.joined(separator: "\n")
    }
}

public enum PDFSheetError: Error, Equatable, Sendable {
    /// The file isn't a PDF, or is locked.
    case unreadable
    /// The PDF opened but has no filled-in boxes, so it isn't a D&D Beyond character sheet.
    case noValues
}

#if canImport(PDFKit)
/// Reads a character sheet PDF's pages with PDFKit. Everything happens on the device.
public enum PDFSheetReader {
    public static func pages(from data: Data) throws -> [PDFSheetPage] {
        guard let document = PDFDocument(data: data), !document.isLocked else { throw PDFSheetError.unreadable }
        return try pages(from: document)
    }

    public static func pages(from url: URL) throws -> [PDFSheetPage] {
        guard let document = PDFDocument(url: url), !document.isLocked else { throw PDFSheetError.unreadable }
        return try pages(from: document)
    }

    static func pages(from document: PDFDocument) throws -> [PDFSheetPage] {
        var pages: [PDFSheetPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var fields: [PDFSheetPage.Field] = []
            for annotation in page.annotations {
                guard let name = annotation.fieldName, !name.isEmpty else { continue }
                let value = annotation.widgetStringValue
                    ?? (annotation.value(forAnnotationKey: .widgetValue) as? String)
                    ?? ""
                let bounds = annotation.bounds
                fields.append(PDFSheetPage.Field(
                    name: name, value: value,
                    x: Double(bounds.minX), y: Double(bounds.minY),
                    width: Double(bounds.width), height: Double(bounds.height)
                ))
            }
            pages.append(PDFSheetPage(index: index, text: page.string ?? "", fields: fields))
        }
        guard pages.contains(where: { page in page.fields.contains { !$0.value.isEmpty } }) else {
            throw PDFSheetError.noValues
        }
        return pages
    }
}
#endif
