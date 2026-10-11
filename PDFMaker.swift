//  PDFMaker.swift
//  Rent receipts, deposit statements and reports as A4 PDF files for sharing.

import UIKit

/// Draws text, label-value pairs and tables down the page, starting new pages as needed.
final class PDFWriter {
    /// A4, upright or on its side for wide tables.
    static let portrait = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let landscape = CGRect(x: 0, y: 0, width: 842, height: 595)
    static let margin: CGFloat = 40

    private let context: UIGraphicsPDFRendererContext
    private let footer: String
    let page: CGRect
    private(set) var pageNumber = 0
    var y: CGFloat = PDFWriter.margin

    let left = PDFWriter.margin
    var right: CGFloat { page.width - PDFWriter.margin }
    var width: CGFloat { right - left }
    var bottom: CGFloat { page.height - PDFWriter.margin }

    init(context: UIGraphicsPDFRendererContext, footer: String, page: CGRect = PDFWriter.portrait) {
        self.context = context
        self.footer = footer
        self.page = page
        newPage()
    }

    func newPage() {
        context.beginPage()
        pageNumber += 1
        y = PDFWriter.margin
        let text = footer + L("  ·  Page \(pageNumber)", "  ·  Page \(pageNumber)")
        let attrs = PDFWriter.attributes(UIFont.systemFont(ofSize: 8), color: .gray, align: .center)
        PDFWriter.draw(text, in: CGRect(x: left, y: bottom + 14, width: width, height: 12), attrs: attrs)
    }

    /// Starts a new page if the next block would not fit.
    func ensure(_ height: CGFloat) {
        if y + height > bottom && y > PDFWriter.margin {
            newPage()
        }
    }

    func space(_ height: CGFloat) {
        y += height
    }

    // MARK: Text

    static func attributes(_ font: UIFont, color: UIColor = .black, align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static func height(_ text: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: attrs, context: nil)
        return ceil(rect.height)
    }

    static func draw(_ text: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any]) {
        guard !text.isEmpty else { return }
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }

    func text(_ s: String, font: UIFont, color: UIColor = .black, align: NSTextAlignment = .left, after: CGFloat = 4) {
        let attrs = PDFWriter.attributes(font, color: color, align: align)
        let h = PDFWriter.height(s, width: width, attrs: attrs)
        ensure(h)
        PDFWriter.draw(s, in: CGRect(x: left, y: y, width: width, height: h), attrs: attrs)
        y += h + after
    }

    /// A label on the left and its value on the right, for receipts and statements.
    func pair(_ label: String, _ value: String, bold: Bool = false) {
        let labelWidth: CGFloat = 175
        let labelAttrs = PDFWriter.attributes(UIFont.systemFont(ofSize: 11), color: .darkGray)
        let valueFont = bold ? UIFont.boldSystemFont(ofSize: 11) : UIFont.systemFont(ofSize: 11)
        let valueAttrs = PDFWriter.attributes(valueFont)
        let valueWidth = width - labelWidth
        let h = max(PDFWriter.height(label, width: labelWidth - 10, attrs: labelAttrs),
                    PDFWriter.height(value, width: valueWidth, attrs: valueAttrs))
        ensure(h)
        PDFWriter.draw(label, in: CGRect(x: left, y: y, width: labelWidth - 10, height: h), attrs: labelAttrs)
        PDFWriter.draw(value, in: CGRect(x: left + labelWidth, y: y, width: valueWidth, height: h), attrs: valueAttrs)
        y += h + 7
    }

    func rule(color: UIColor = .lightGray) {
        ensure(12)
        y += 4
        let path = UIBezierPath()
        path.move(to: CGPoint(x: left, y: y))
        path.addLine(to: CGPoint(x: right, y: y))
        path.lineWidth = 0.5
        color.setStroke()
        path.stroke()
        y += 8
    }

    // MARK: Tables

    static func isAmount(_ s: String) -> Bool {
        if s.hasPrefix("₹") || s.hasPrefix("-₹") { return true }
        return !s.isEmpty && s.allSatisfy { $0.isNumber || $0 == "," || $0 == "-" }
    }

    static func columnWidths(_ columns: [String], _ rows: [[String]], total: CGFloat) -> [CGFloat] {
        var weights: [CGFloat] = columns.map { CGFloat(min(max($0.count, 6), 20)) }
        for row in rows.prefix(300) {
            for (i, cell) in row.enumerated() where i < weights.count {
                weights[i] = max(weights[i], CGFloat(min(cell.count, 32)))
            }
        }
        let sum = max(1, weights.reduce(0, +))
        return weights.map { total * $0 / sum }
    }

    func table(columns: [String], rows: [[String]], totals: [String]?) {
        guard !columns.isEmpty else { return }
        let widths = PDFWriter.columnWidths(columns, rows, total: width)
        let rightAligned: [Bool] = columns.indices.map { i in
            rows.contains { i < $0.count && PDFWriter.isAmount($0[i]) }
        }
        let bodyFont = UIFont.systemFont(ofSize: 9)
        let boldFont = UIFont.boldSystemFont(ofSize: 9)

        tableHeader(columns, widths, rightAligned, boldFont)
        for (index, row) in rows.enumerated() {
            let h = rowHeight(row, widths, rightAligned, bodyFont)
            if y + h > bottom {
                newPage()
                tableHeader(columns, widths, rightAligned, boldFont)
            }
            if index % 2 == 1 {
                UIColor(white: 0.95, alpha: 1).setFill()
                UIRectFill(CGRect(x: left, y: y - 2, width: width, height: h + 4))
            }
            drawRow(row, widths, rightAligned, bodyFont, color: .black, height: h)
            y += h + 4
        }
        if let totals = totals {
            let h = rowHeight(totals, widths, rightAligned, boldFont)
            ensure(h + 12)
            rule(color: .gray)
            drawRow(totals, widths, rightAligned, boldFont, color: .black, height: h)
            y += h + 6
        }
    }

    private func tableHeader(_ columns: [String], _ widths: [CGFloat], _ rightAligned: [Bool], _ font: UIFont) {
        let h = rowHeight(columns, widths, rightAligned, font)
        drawRow(columns, widths, rightAligned, font, color: .darkGray, height: h)
        y += h + 2
        rule(color: .gray)
    }

    private func rowHeight(_ cells: [String], _ widths: [CGFloat], _ rightAligned: [Bool], _ font: UIFont) -> CGFloat {
        var h: CGFloat = PDFWriter.height("X", width: 100, attrs: PDFWriter.attributes(font))
        for (i, w) in widths.enumerated() where i < cells.count {
            let attrs = PDFWriter.attributes(font, align: rightAligned[i] ? .right : .left)
            h = max(h, PDFWriter.height(cells[i], width: w - 6, attrs: attrs))
        }
        return h
    }

    private func drawRow(_ cells: [String], _ widths: [CGFloat], _ rightAligned: [Bool], _ font: UIFont,
                         color: UIColor, height: CGFloat) {
        var x = left
        for (i, w) in widths.enumerated() {
            let cell = i < cells.count ? cells[i] : ""
            let attrs = PDFWriter.attributes(font, color: color, align: rightAligned[i] ? .right : .left)
            PDFWriter.draw(cell, in: CGRect(x: x + 3, y: y, width: w - 6, height: height), attrs: attrs)
            x += w
        }
    }
}

enum PDFMaker {
    static func safeName(_ name: String) -> String {
        let cleaned = name.map { "/\\:?*\"<>|".contains($0) ? "-" : $0 }
        let text = String(cleaned).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "RentBook" : text
    }

    /// Writes a PDF to a temporary file and returns its location.
    static func render(title: String, fileName: String, landscape: Bool = false, _ draw: (PDFWriter) -> Void) -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "RentBook"]
        let page = landscape ? PDFWriter.landscape : PDFWriter.portrait
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName(fileName) + ".pdf")
        let footer = L("Made with RentBook on ", "RentBook se banaya, ") + Fmt.dateTime(Date())
        do {
            try renderer.writePDF(to: url) { context in
                let writer = PDFWriter(context: context, footer: footer, page: page)
                draw(writer)
            }
            return url
        } catch {
            return nil
        }
    }

    private static func landlordLine(_ w: PDFWriter, _ s: AppSettings) {
        let parts = [s.landlordName, s.landlordPhone].filter { !$0.isEmpty }
        if !parts.isEmpty {
            w.text(L("Landlord: ", "Makaan malik: ") + parts.joined(separator: " · "), font: UIFont.systemFont(ofSize: 11), color: .darkGray)
        }
    }

    // MARK: Receipt

    static func receipt(tenant: Tenant, line: PaymentLine, place: String, settings: AppSettings) -> URL? {
        let p = line.payment
        let number = p.receiptNumber > 0 ? L("Receipt no. \(p.receiptNumber)", "Raseed no. \(p.receiptNumber)") : L("Receipt", "Raseed")
        let file = L("Receipt", "Raseed") + (p.receiptNumber > 0 ? " \(p.receiptNumber)" : "") + " " + tenant.name
        return render(title: L("Rent receipt", "Rent raseed"), fileName: file) { w in
            w.text(L("RENT RECEIPT", "RENT RASEED"), font: UIFont.boldSystemFont(ofSize: 22), after: 2)
            w.text(number + L("    Date: ", "    Tareekh: ") + Fmt.date(p.date), font: UIFont.systemFont(ofSize: 11), color: .darkGray)
            landlordLine(w, settings)
            w.rule()
            w.pair(L("Received from", "Kisse mila"), tenant.name, bold: true)
            if !place.isEmpty {
                w.pair("Property", place)
            }
            w.pair("Amount", Fmt.inr(p.amount), bold: true)
            w.pair(L("Amount in words", "Shabdon mein amount"), "Rupees " + Messages.rupeesInWords(p.amount) + " only")
            w.pair(L("Paid by", "Kaise diya"), p.method.label + (p.reference.isEmpty ? "" : " · Ref. " + p.reference))
            let covers = line.applications.map { $0.title + "  (" + Fmt.inr($0.amount) + ")" }
            if !covers.isEmpty {
                w.pair(L("Towards", "Kis cheez ka"), covers.joined(separator: "\n"))
            }
            if line.unapplied > 0 {
                w.pair(L("Kept as advance", "Advance mein rakha"), Fmt.inr(line.unapplied))
            }
            if line.balanceAfter > 0 {
                w.pair(L("Balance due after this payment", "Is payment ke baad baaki"), Fmt.inr(line.balanceAfter))
            } else if line.balanceAfter < 0 {
                w.pair(L("Paid in advance", "Advance diya hua"), Fmt.inr(-line.balanceAfter))
            } else {
                w.pair(L("Balance due", "Baaki"), L("Nil", "Kuch nahi"))
            }
            if !p.note.isEmpty {
                w.pair("Note", p.note)
            }
            w.rule()
            w.space(36)
            let signer = settings.landlordName.isEmpty ? "____________________" : settings.landlordName
            w.text(L("Received by: ", "Lene wale: ") + signer, font: UIFont.systemFont(ofSize: 11))
            w.space(8)
            w.text(L("This receipt was generated by RentBook.", "Yeh raseed RentBook se bani hai."), font: UIFont.italicSystemFont(ofSize: 9), color: .gray)
        }
    }

    // MARK: Deposit statement

    static func depositStatement(tenant: Tenant, place: String, settings: AppSettings) -> URL? {
        let entries = tenant.deposits.filter { !$0.isReversed }.sorted { $0.date < $1.date }
        var held = 0
        let rows: [[String]] = entries.map { e in
            let incoming = e.kind == .received || e.kind == .additional
            held += incoming ? e.amount : -e.amount
            return [Fmt.date(e.date), e.kind.label, e.reason,
                    incoming ? Fmt.inr(e.amount) : "", incoming ? "" : Fmt.inr(e.amount), Fmt.inr(held)]
        }
        let s = Ledger.deposit(of: tenant)
        return render(title: "Security deposit statement", fileName: "Deposit " + tenant.name) { w in
            w.text("SECURITY DEPOSIT STATEMENT", font: UIFont.boldSystemFont(ofSize: 18), after: 2)
            w.text(L("As of ", "Tareekh: ") + Fmt.date(Date()), font: UIFont.systemFont(ofSize: 11), color: .darkGray)
            landlordLine(w, settings)
            w.rule()
            w.pair("Tenant", tenant.name, bold: true)
            if !place.isEmpty {
                w.pair("Property", place)
            }
            if let start = tenant.startDate {
                w.pair(L("Tenancy", "Kirayedari"), Fmt.date(start) + L(" to ", " – ") + (tenant.endDate.map { Fmt.date($0) } ?? L("ongoing", "abhi chalu")))
            }
            w.space(8)
            if rows.isEmpty {
                w.text(L("No deposit entries.", "Koi deposit entry nahi."), font: UIFont.systemFont(ofSize: 11), color: .gray)
            } else {
                w.table(columns: [L("Date", "Tareekh"), "Entry", "Details", L("In", "Aaya"), L("Out", "Gaya"), L("Held", "Jama")], rows: rows,
                        totals: ["", L("Total", "Kul"), "", Fmt.inr(s.totalIn), Fmt.inr(s.deducted + s.refunded), Fmt.inr(s.held)])
            }
            w.space(10)
            w.pair(L("Received", "Mila"), Fmt.inr(s.totalIn))
            w.pair(L("Deducted", "Kata"), Fmt.inr(s.deducted))
            w.pair(L("Refunded", "Wapas diya"), Fmt.inr(s.refunded))
            w.pair(L("Held now", "Abhi jama"), Fmt.inr(s.held), bold: true)
        }
    }

    // MARK: Reports

    /// Wide tables (eight columns or more) are printed on the page's side.
    static func report(_ table: ReportTable, landlord: String) -> URL? {
        render(title: table.title, fileName: table.title + " " + DateMath.dayKey(Date()), landscape: table.columns.count >= 8) { w in
            drawTable(table, landlord: landlord, on: w)
        }
    }

    /// Several reports in one file, each starting on a new page.
    static func reports(_ tables: [ReportTable], title: String, subtitle: String, landlord: String) -> URL? {
        let wide = tables.contains { $0.columns.count >= 8 }
        return render(title: title, fileName: title + " " + DateMath.dayKey(Date()), landscape: wide) { w in
            w.text(title, font: UIFont.boldSystemFont(ofSize: 22), after: 4)
            if !subtitle.isEmpty {
                w.text(subtitle, font: UIFont.systemFont(ofSize: 11), color: .darkGray, after: 2)
            }
            if !landlord.isEmpty {
                w.text(landlord, font: UIFont.systemFont(ofSize: 11), color: .darkGray, after: 2)
            }
            w.space(10)
            for (i, table) in tables.enumerated() {
                w.text("\(i + 1). " + table.title, font: UIFont.systemFont(ofSize: 11))
            }
            for table in tables {
                w.newPage()
                drawTable(table, landlord: "", on: w)
            }
        }
    }

    private static func drawTable(_ table: ReportTable, landlord: String, on w: PDFWriter) {
        w.text(table.title, font: UIFont.boldSystemFont(ofSize: 18), after: 2)
        if !table.subtitle.isEmpty {
            w.text(table.subtitle, font: UIFont.systemFont(ofSize: 10), color: .darkGray, after: 2)
        }
        if !landlord.isEmpty {
            w.text(landlord, font: UIFont.systemFont(ofSize: 10), color: .darkGray, after: 2)
        }
        w.space(8)
        if table.rows.isEmpty {
            w.text(L("Nothing to show for these choices.", "In choices ke liye kuch nahi."), font: UIFont.systemFont(ofSize: 11), color: .gray)
        } else {
            w.table(columns: table.columns, rows: table.rows, totals: table.totals)
        }
        if !table.note.isEmpty {
            w.space(10)
            w.text(table.note, font: UIFont.systemFont(ofSize: 9), color: .darkGray)
        }
    }
}
