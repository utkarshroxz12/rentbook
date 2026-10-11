//  CoreFormula.swift
//  The dashboard at the top of every rent records worksheet. Each item is worked out from
//  the worksheet's column totals with a small formula, such as ACCOUNT - TDS, and items can
//  use each other by name, such as {Actual rent} * 12. Foundation only.

import Foundation

/// One item on the worksheet dashboard.
struct SheetTile: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var formula = ""
    /// Shown in rupees, or as a plain number such as a count of tenants.
    var isMoney = true
}

extension SheetTile {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        title = c.v(.title, title)
        formula = c.v(.formula, formula)
        isMoney = c.v(.isMoney, isMoney)
    }

    /// The name other formulas use for this item, without regard to case.
    var key: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A value formulas can use: the total of one worksheet column.
struct SheetField: Identifiable, Hashable {
    var code: String
    var label: String
    var isMoney = true
    var id: String { code }
}

enum FormulaProblem: Error, Equatable {
    case empty
    case unknownName(String)
    case unknownItem(String)
    case loop(String)
    case misplaced(String)
    case missingBracket
    case divideByZero

    var message: String {
        switch self {
        case .empty:
            return L("Type a formula, for example CASH + ACCOUNT - TDS.", "Formula likhein, jaise CASH + ACCOUNT - TDS.")
        case .unknownName(let name):
            return L("There is no value called ", "Is naam ki koi value nahi: ") + name
        case .unknownItem(let name):
            return L("There is no item called {", "Is naam ka koi item nahi: {") + name + "}"
        case .loop(let name):
            return L("{" + name + "} leads back to this item.", "{" + name + "} ghoom kar isi item par aata hai.")
        case .misplaced(let text):
            if text.isEmpty { return L("The formula ends too soon.", "Formula adhoora hai.") }
            return L("Check the formula near ", "Formula dekhein, yahan: ") + text
        case .missingBracket:
            return L("A bracket is not closed.", "Ek bracket band nahi hua.")
        case .divideByZero:
            return L("It divides by zero.", "Zero se bhaag ho raha hai.")
        }
    }
}

enum SheetFormula {
    /// The values a formula can use, with what each one is.
    static var fields: [SheetField] {
        [SheetField(code: "CASH", label: L("Cash rent after increment", "Badhotri ke baad cash rent")),
         SheetField(code: "ACCOUNT", label: L("Account rent after increment", "Badhotri ke baad account rent")),
         SheetField(code: "TDS", label: L("TDS on the account rent after increment", "Badhotri ke baad account rent par TDS")),
         SheetField(code: "GST", label: L("GST on the account rent after increment", "Badhotri ke baad account rent par GST")),
         SheetField(code: "CURRENT_ACCOUNT", label: L("Current rent in account", "Account mein abhi ka rent")),
         SheetField(code: "TOTAL_CURRENT", label: L("Total current rent", "Kul abhi ka rent")),
         SheetField(code: "OLD_CASH", label: L("Rent in cash, as first paid", "Cash mein rent, pehle jaisa")),
         SheetField(code: "OLD_ACCOUNT", label: L("Rent in account, as first paid", "Account mein rent, pehle jaisa")),
         SheetField(code: "OLD_TDS", label: L("TDS, as first paid", "TDS, pehle jaisa")),
         SheetField(code: "OLD_GST", label: L("GST, as first paid", "GST, pehle jaisa")),
         SheetField(code: "FINAL_ACCOUNT", label: L("Final rent in account", "Account mein final rent")),
         SheetField(code: "CASH_PLUS_FINAL", label: L("Cash + final rent", "Cash + final rent")),
         SheetField(code: "RENT", label: L("Rent amount", "Rent amount")),
         SheetField(code: "TENANTS", label: L("Number of tenants", "Tenants ki ginti"), isMoney: false),
         SheetField(code: "MISSED_MONTHS", label: L("Months since missed increments", "Chhooti badhotri ke mahine"), isMoney: false)]
    }

    static func values(_ s: SheetSums) -> [String: Double] {
        var v: [String: Double] = [:]
        v["CASH"] = Double(s.cash)
        v["ACCOUNT"] = Double(s.account)
        v["TDS"] = Double(s.tds)
        v["GST"] = Double(s.gst)
        v["CURRENT_ACCOUNT"] = Double(s.currentAccount)
        v["TOTAL_CURRENT"] = Double(s.totalCurrent)
        v["OLD_CASH"] = Double(s.oldCash)
        v["OLD_ACCOUNT"] = Double(s.oldAccount)
        v["OLD_TDS"] = Double(s.oldTDS)
        v["OLD_GST"] = Double(s.oldGST)
        v["FINAL_ACCOUNT"] = Double(s.finalAccount)
        v["CASH_PLUS_FINAL"] = Double(s.cashPlusFinal)
        v["RENT"] = Double(s.rent)
        v["TENANTS"] = Double(s.tenants)
        v["MISSED_MONTHS"] = Double(s.missedMonths)
        return v
    }

    /// The seven standard items, used until the dashboard is changed.
    static let defaultTiles: [SheetTile] = [
        standard(1, "Rent before TDS", "ACCOUNT"),
        standard(2, "Rent after TDS", "ACCOUNT - TDS"),
        standard(3, "TDS", "TDS"),
        standard(4, "GST", "GST"),
        standard(5, "Cash", "CASH"),
        standard(6, "Rent with GST", "ACCOUNT - TDS + GST"),
        standard(7, "Actual rent", "CASH + ACCOUNT - TDS"),
    ]

    private static func standard(_ n: Int, _ title: String, _ formula: String) -> SheetTile {
        let id = UUID(uuidString: "5E7D0B1A-2C3D-4E5F-8A9B-00000000000" + String(n)) ?? UUID()
        return SheetTile(id: id, title: title, formula: formula, isMoney: true)
    }

    // MARK: Working out

    /// The value of a dashboard item. An item cannot use itself, directly or through others.
    static func value(of tile: SheetTile, values: [String: Double], tiles: [SheetTile]) -> Result<Double, FormulaProblem> {
        evaluate(tile.formula, values: values, tiles: tiles, visiting: [tile.key])
    }

    /// Works out a formula: numbers, + - * / (also × and ÷), brackets, a % after a number
    /// (18% is 0.18), value names such as CASH in any case, and {item name} for another item.
    static func evaluate(_ formula: String, values: [String: Double], tiles: [SheetTile],
                         visiting: Set<String> = []) -> Result<Double, FormulaProblem> {
        let text = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        let list: [FormulaToken]
        switch tokens(text) {
        case .success(let found): list = found
        case .failure(let problem): return .failure(problem)
        }
        var parser = FormulaParser(tokens: list) { token in
            switch token {
            case .name(let name):
                if let v = values[name] { return .success(v) }
                return .failure(.unknownName(name))
            case .item(let name):
                let key = name.lowercased()
                if visiting.contains(key) { return .failure(.loop(name)) }
                guard let other = tiles.first(where: { $0.key == key }) else { return .failure(.unknownItem(name)) }
                return SheetFormula.evaluate(other.formula, values: values, tiles: tiles, visiting: visiting.union([key]))
            default:
                return .failure(.misplaced(token.text))
            }
        }
        do {
            let result = try parser.expression()
            if parser.at < list.count {
                return .failure(.misplaced(list[parser.at].text))
            }
            guard result.isFinite else { return .failure(.divideByZero) }
            return .success(result)
        } catch let problem as FormulaProblem {
            return .failure(problem)
        } catch {
            return .failure(.misplaced(""))
        }
    }

    /// The dashboard as a table, for the worksheet's PDF and Excel files.
    static func table(_ sheet: RentSheet, tiles: [SheetTile], asOf: Date = Date()) -> ReportTable {
        let totals = SheetFormula.values(RentSheets.sums(sheet, asOf: asOf))
        let rows: [[String]] = tiles.map { tile in
            let result = SheetFormula.value(of: tile, values: totals, tiles: tiles)
            let shown = SheetFormula.display(result, isMoney: tile.isMoney)
            return [tile.title, tile.formula, shown]
        }
        return ReportTable(title: L("Dashboard", "Dashboard"), subtitle: sheet.name,
                           columns: [L("Item", "Item"), L("Formula", "Formula"), L("Value", "Value")], rows: rows)
    }

    /// "₹12,500", "3" or "—" when the formula has a problem.
    static func display(_ result: Result<Double, FormulaProblem>, isMoney: Bool) -> String {
        guard case .success(let v) = result, v.isFinite, abs(v) < 1e13 else { return "—" }
        return isMoney ? Fmt.inr(Int(v.rounded())) : Fmt.number(v)
    }

    /// Changes {old name} to {new name} in a formula, after an item is renamed.
    static func renaming(_ formula: String, from old: String, to new: String) -> String {
        let oldKey = old.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !oldKey.isEmpty else { return formula }
        var out = ""
        var rest = Substring(formula)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let inside = rest[rest.index(after: open)..<close]
            if inside.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == oldKey {
                out += "{" + new.trimmingCharacters(in: .whitespacesAndNewlines) + "}"
            } else {
                out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    // MARK: Reading a formula

    static func tokens(_ text: String) -> Result<[FormulaToken], FormulaProblem> {
        var out: [FormulaToken] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if (c.isASCII && c.isNumber) || c == "." {
                var j = i
                var digits = ""
                while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." || chars[j] == "," {
                    if chars[j] != "," { digits.append(chars[j]) }
                    j += 1
                }
                guard let v = Double(digits) else { return .failure(.misplaced(String(chars[i..<j]))) }
                out.append(.number(v))
                i = j
                continue
            }
            if c.isLetter || c == "_" {
                var j = i
                var name = ""
                while j < chars.count, chars[j].isLetter || (chars[j].isASCII && chars[j].isNumber) || chars[j] == "_" {
                    name.append(chars[j])
                    j += 1
                }
                out.append(.name(name.uppercased()))
                i = j
                continue
            }
            switch c {
            case "{":
                guard let close = chars[(i + 1)...].firstIndex(of: "}") else { return .failure(.missingBracket) }
                let name = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(.item(name))
                i = close + 1
                continue
            case "+":
                out.append(.add)
            case "-", "−", "–":
                out.append(.subtract)
            case "*", "×":
                out.append(.multiply)
            case "/", "÷":
                out.append(.divide)
            case "(":
                out.append(.open)
            case ")":
                out.append(.close)
            case "%":
                out.append(.percent)
            default:
                return .failure(.misplaced(String(c)))
            }
            i += 1
        }
        return .success(out)
    }
}

enum FormulaToken: Equatable {
    case number(Double)
    case name(String)
    case item(String)
    case add, subtract, multiply, divide, open, close, percent

    var text: String {
        switch self {
        case .number(let v): return Fmt.number(v)
        case .name(let name): return name
        case .item(let name): return "{" + name + "}"
        case .add: return "+"
        case .subtract: return "-"
        case .multiply: return "×"
        case .divide: return "÷"
        case .open: return "("
        case .close: return ")"
        case .percent: return "%"
        }
    }
}

/// Reads tokens with the usual order: brackets, then × and ÷, then + and -.
struct FormulaParser {
    let tokens: [FormulaToken]
    var at = 0
    let lookup: (FormulaToken) -> Result<Double, FormulaProblem>

    init(tokens: [FormulaToken], lookup: @escaping (FormulaToken) -> Result<Double, FormulaProblem>) {
        self.tokens = tokens
        self.lookup = lookup
    }

    private var next: FormulaToken? {
        at < tokens.count ? tokens[at] : nil
    }

    mutating func expression() throws -> Double {
        var value = try term()
        while let t = next, t == .add || t == .subtract {
            at += 1
            let right = try term()
            value = t == .add ? value + right : value - right
        }
        return value
    }

    mutating func term() throws -> Double {
        var value = try signed()
        while let t = next, t == .multiply || t == .divide {
            at += 1
            let right = try signed()
            if t == .multiply {
                value *= right
            } else {
                guard right != 0 else { throw FormulaProblem.divideByZero }
                value /= right
            }
        }
        return value
    }

    mutating func signed() throws -> Double {
        if let t = next, t == .add || t == .subtract {
            at += 1
            let value = try signed()
            return t == .subtract ? -value : value
        }
        var value = try primary()
        while next == .percent {
            at += 1
            value /= 100
        }
        return value
    }

    mutating func primary() throws -> Double {
        guard let t = next else { throw FormulaProblem.misplaced("") }
        at += 1
        switch t {
        case .number(let v):
            return v
        case .name, .item:
            return try lookup(t).get()
        case .open:
            let value = try expression()
            guard next == .close else { throw FormulaProblem.missingBracket }
            at += 1
            return value
        default:
            throw FormulaProblem.misplaced(t.text)
        }
    }
}
