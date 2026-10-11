//  CoreExcel.swift
//  Writes Excel workbooks (.xlsx) without any library: a few XML parts packed in a
//  ZIP archive. Amounts become real numbers, so they can be added up in Excel.
//  Foundation only.

import Foundation

enum XLSXCell: Hashable {
    case text(String)
    case boldText(String)
    /// Rupees, shown with separators (1,23,456).
    case number(Int)
    case boldNumber(Int)
    /// A count, reading or flat number, shown as it is (1204).
    case plain(Double)
    case boldPlain(Double)
}

struct XLSXSheet {
    var name: String
    var rows: [[XLSXCell]]
    var widths: [Double] = []
}

enum Excel {
    /// A sheet from a report table: a bold heading row, the rows, and a bold totals row.
    /// Rupee amounts and whole numbers become numbers.
    static func sheet(_ table: ReportTable, name: String? = nil) -> XLSXSheet {
        var rows: [[XLSXCell]] = []
        if !table.title.isEmpty {
            rows.append([.boldText(table.title)])
        }
        if !table.subtitle.isEmpty {
            rows.append([.text(table.subtitle)])
        }
        if !rows.isEmpty {
            rows.append([])
        }
        rows.append(table.columns.map { XLSXCell.boldText($0) })
        for row in table.rows {
            rows.append(row.map { cell($0, bold: false) })
        }
        if let totals = table.totals {
            rows.append(totals.map { cell($0, bold: true) })
        }
        if !table.note.isEmpty {
            rows.append([])
            for line in table.note.split(separator: "\n") {
                rows.append([.text(String(line))])
            }
        }
        var widths: [Double] = table.columns.map { Double(min(max($0.count, 8), 30)) }
        for row in table.rows.prefix(300) {
            for (i, text) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], Double(min(text.count, 40)))
            }
        }
        return XLSXSheet(name: name ?? table.title, rows: rows, widths: widths.map { $0 + 2 })
    }

    static func cell(_ text: String, bold: Bool) -> XLSXCell {
        if let n = number(text) {
            return bold ? .boldNumber(n) : .number(n)
        }
        if let v = plainNumber(text) {
            return bold ? .boldPlain(v) : .plain(v)
        }
        return bold ? .boldText(text) : .text(text)
    }

    /// Rupee amounts: "₹1,23,456" → 123456, "-₹500" → -500. Anything else is not an amount.
    static func number(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }
        guard s.hasPrefix("₹") else { return nil }
        s.removeFirst()
        let digits = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits.count <= 15, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(digits) else { return nil }
        return negative ? -value : value
    }

    /// Plain numbers such as "42", "1204" or "1520.5". Text with commas, or with a leading
    /// zero such as a phone number or a code, stays text.
    static func plainNumber(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !s.isEmpty, s.count <= 12, parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        if parts[0].count > 1 && parts[0].hasPrefix("0") { return nil }
        guard let value = Double(s), value.isFinite else { return nil }
        return negative ? -value : value
    }

    /// A number as Excel stores it.
    static func numberText(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    // MARK: Workbook

    static func workbook(_ sheets: [XLSXSheet]) -> Data {
        let list = sheets.isEmpty ? [XLSXSheet(name: "Sheet1", rows: [])] : sheets
        var names: [String] = []
        for sheet in list {
            names.append(uniqueName(sheet.name, taken: names))
        }
        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", Data(contentTypes(list.count).utf8)))
        files.append(("_rels/.rels", Data(rootRels.utf8)))
        files.append(("xl/workbook.xml", Data(workbookXML(names).utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(workbookRels(list.count).utf8)))
        files.append(("xl/styles.xml", Data(styles.utf8)))
        for (i, sheet) in list.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml", Data(sheetXML(sheet).utf8)))
        }
        return Zip.archive(files)
    }

    /// Sheet names: at most 31 characters, none of : \ / ? * [ ], and unique.
    static func uniqueName(_ raw: String, taken: [String]) -> String {
        let banned = Set(":\\/?*[]")
        var base = String(raw.filter { !banned.contains($0) && !$0.isNewline })
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "'")))
        // Excel keeps "History" for itself.
        if base.isEmpty || base.lowercased() == "history" { base = base.isEmpty ? "Sheet" : base + " 1" }
        base = String(base.prefix(31))
        var name = base
        var n = 2
        while taken.contains(where: { $0.lowercased() == name.lowercased() }) {
            let suffix = " (\(n))"
            name = String(base.prefix(31 - suffix.count)) + suffix
            n += 1
        }
        return name
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // XML 1.0 allows tab, newline and carriage return, but no other control characters.
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func columnName(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + r))) + name
            n = (n - 1) / 26
        }
        return name
    }

    static func sheetXML(_ sheet: XLSXSheet) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if !sheet.widths.isEmpty {
            xml += "<cols>"
            for (i, w) in sheet.widths.enumerated() {
                xml += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(Int(w.rounded()))\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            let rowNumber = r + 1
            xml += "<row r=\"\(rowNumber)\">"
            for (c, cell) in row.enumerated() {
                let ref = columnName(c) + String(rowNumber)
                switch cell {
                case .text(let t):
                    if !t.isEmpty {
                        xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(t))</t></is></c>"
                    }
                case .boldText(let t):
                    xml += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">\(escape(t))</t></is></c>"
                case .number(let n):
                    xml += "<c r=\"\(ref)\" s=\"2\"><v>\(n)</v></c>"
                case .boldNumber(let n):
                    xml += "<c r=\"\(ref)\" s=\"3\"><v>\(n)</v></c>"
                case .plain(let v):
                    xml += "<c r=\"\(ref)\"><v>\(numberText(v))</v></c>"
                case .boldPlain(let v):
                    xml += "<c r=\"\(ref)\" s=\"1\"><v>\(numberText(v))</v></c>"
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    static func contentTypes(_ count: Int) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for i in 1...max(1, count) {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "</Types>"
        return xml
    }

    static let rootRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        + "</Relationships>"

    static func workbookXML(_ names: [String]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
        xml += "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
        for (i, name) in names.enumerated() {
            xml += "<sheet name=\"\(escape(name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        xml += "</sheets></workbook>"
        return xml
    }

    static func workbookRels(_ count: Int) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1...max(1, count) {
            xml += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(max(1, count) + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "</Relationships>"
        return xml
    }

    /// Normal text, bold text, a number with thousands separators, and the same in bold.
    static let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
        + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"4\">"
        + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        + "<xf numFmtId=\"3\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "<xf numFmtId=\"3\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyNumberFormat=\"1\"/>"
        + "</cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"
}

/// A ZIP archive with stored (uncompressed) entries, which is all an .xlsx file needs.
enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    static func archive(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        // 1 January 1980, the earliest date a ZIP file can hold.
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1
        for (name, content) in files {
            let nameBytes = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(out.count)
            out.append(le32(0x04034b50))
            out.append(le16(20))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(UInt32(content.count)))
            out.append(le32(UInt32(content.count)))
            out.append(le16(UInt16(nameBytes.count)))
            out.append(le16(0))
            out.append(nameBytes)
            out.append(content)

            central.append(le32(0x02014b50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(UInt32(content.count)))
            central.append(le32(UInt32(content.count)))
            central.append(le16(UInt16(nameBytes.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(files.count)))
        out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    static func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
}
