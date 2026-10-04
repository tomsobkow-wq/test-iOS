import Foundation
@testable import DocumentKit

/// Invented statements (no real data). One list of transactions is rendered in several bank styles,
/// so every parser can be checked against the exact truth.
struct TruthRow {
    let day: String          // yyyy-MM-dd
    let minor: Int
    let text: String
    let merchant: String?    // expected cleaned merchant, when known
    let category: String?    // expected category, when known
}

enum Fixtures {
    static let polishOpening = 500_000
    static let polish: [TruthRow] = [
        TruthRow(day: "2026-03-01", minor: 850_000, text: "WYNAGRODZENIE MARZEC ACME SP Z O O", merchant: nil, category: "income"),
        TruthRow(day: "2026-03-02", minor: -4_560, text: "PŁATNOŚĆ KARTĄ BIEDRONKA 1234 WARSZAWA", merchant: "Biedronka", category: "groceries"),
        TruthRow(day: "2026-03-03", minor: -5_299, text: "NETFLIX.COM", merchant: "Netflix", category: "subscriptions"),
        TruthRow(day: "2026-03-04", minor: -12_000, text: "WYPŁATA Z BANKOMATU PKO ATM WARSZAWA", merchant: nil, category: "cash"),
        TruthRow(day: "2026-03-05", minor: -240_000, text: "CZYNSZ ZA MARZEC WSPÓLNOTA MIESZKANIOWA", merchant: nil, category: "housing"),
        TruthRow(day: "2026-03-07", minor: -3_840, text: "PŁATNOŚĆ KARTĄ ŻABKA Z1234 KRAKÓW", merchant: "Żabka", category: "groceries"),
        TruthRow(day: "2026-03-09", minor: -2_900, text: "SPOTIFY P3A8", merchant: "Spotify", category: "subscriptions"),
        TruthRow(day: "2026-03-10", minor: -8_735, text: "PŁATNOŚĆ KARTĄ ORLEN STACJA 4521", merchant: "Orlen", category: "transport"),
        TruthRow(day: "2026-03-12", minor: -15_220, text: "PŁATNOŚĆ KARTĄ LIDL 0456", merchant: "Lidl", category: "groceries"),
        TruthRow(day: "2026-03-14", minor: -6_490, text: "UBER *TRIP HELP.UBER.COM", merchant: "Uber", category: "transport"),
        TruthRow(day: "2026-03-15", minor: -19_900, text: "ALLEGRO PAYMENT 7384929", merchant: "Allegro", category: "shopping"),
        TruthRow(day: "2026-03-18", minor: 4_500, text: "ZWROT ZA ZAMÓWIENIE ALLEGRO", merchant: "Allegro", category: "refund"),
        TruthRow(day: "2026-03-20", minor: -3_500, text: "OPŁATA ZA PROWADZENIE RACHUNKU", merchant: nil, category: "fees"),
        TruthRow(day: "2026-03-22", minor: -6_150, text: "PŁATNOŚĆ KARTĄ MCDONALDS 321 WARSZAWA", merchant: "McDonald's", category: "eating_out"),
        TruthRow(day: "2026-03-25", minor: -120_000, text: "PRZELEW NA RACHUNEK WŁASNY OSZCZĘDNOŚCI", merchant: nil, category: "savings"),
        TruthRow(day: "2026-03-28", minor: -4_999, text: "PLAY ABONAMENT", merchant: "Play", category: "utilities"),
        TruthRow(day: "2026-03-30", minor: -21_000, text: "ORANGE FAKTURA 55123", merchant: "Orange", category: "utilities"),
    ]

    static let englishOpening = 124_700
    static let english: [TruthRow] = [
        TruthRow(day: "2026-03-01", minor: 215_000, text: "SALARY ACME LTD", merchant: nil, category: "income"),
        TruthRow(day: "2026-03-02", minor: -1_250, text: "CARD PAYMENT TO TESCO STORES 3421", merchant: "Tesco", category: "groceries"),
        TruthRow(day: "2026-03-03", minor: -1_099, text: "NETFLIX.COM", merchant: "Netflix", category: "subscriptions"),
        TruthRow(day: "2026-03-04", minor: -80_000, text: "STANDING ORDER RENT MR J SMITH", merchant: nil, category: "housing"),
        TruthRow(day: "2026-03-06", minor: -2_640, text: "CARD PAYMENT TO SAINSBURY'S 0912", merchant: "Sainsbury's", category: "groceries"),
        TruthRow(day: "2026-03-08", minor: -450, text: "TFL TRAVEL CH", merchant: "TfL", category: "transport"),
        TruthRow(day: "2026-03-11", minor: -999, text: "SPOTIFY AB", merchant: "Spotify", category: "subscriptions"),
        TruthRow(day: "2026-03-13", minor: -4_580, text: "CARD PAYMENT TO AMAZON.CO.UK", merchant: "Amazon", category: "shopping"),
        TruthRow(day: "2026-03-15", minor: -2_000, text: "CASH WITHDRAWAL ATM HIGH STREET", merchant: nil, category: "cash"),
        TruthRow(day: "2026-03-17", minor: 1_999, text: "REFUND AMAZON.CO.UK", merchant: "Amazon", category: "refund"),
        TruthRow(day: "2026-03-21", minor: -1_720, text: "CARD PAYMENT TO PRET A MANGER", merchant: "Pret", category: "eating_out"),
        TruthRow(day: "2026-03-25", minor: -6_500, text: "DIRECT DEBIT BRITISH GAS", merchant: "Utility", category: "utilities"),
        TruthRow(day: "2026-03-29", minor: -1_800, text: "MONTHLY ACCOUNT FEE", merchant: nil, category: "fees"),
    ]

    // MARK: Number formatting

    static func pl(_ minor: Int, sign: Bool = true, currency: String? = nil) -> String {
        let absolute = abs(minor)
        let whole = absolute / 100
        var grouped = ""
        for (index, ch) in String(whole).reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped = " " + grouped }
            grouped = String(ch) + grouped
        }
        let text = String(format: "%@,%02d", grouped, absolute % 100)
        return (minor < 0 && sign ? "-" : "") + text + (currency.map { " " + $0 } ?? "")
    }

    static func en(_ minor: Int, sign: Bool = true) -> String {
        let absolute = abs(minor)
        var grouped = ""
        for (index, ch) in String(absolute / 100).reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped = "," + grouped }
            grouped = String(ch) + grouped
        }
        return (minor < 0 && sign ? "-" : "") + String(format: "%@.%02d", grouped, absolute % 100)
    }

    static func plain(_ minor: Int) -> String {
        (minor < 0 ? "-" : "") + String(format: "%d.%02d", abs(minor) / 100, abs(minor) % 100)
    }

    static func balances(opening: Int, _ rows: [TruthRow]) -> [Int] {
        var running = opening
        return rows.map { running += $0.minor; return running }
    }

    static func ddmmyyyy(_ iso: String) -> String { let p = iso.split(separator: "-"); return "\(p[2]).\(p[1]).\(p[0])" }
    static func mmddyyyy(_ iso: String) -> String { let p = iso.split(separator: "-"); return "\(p[1])/\(p[2])/\(p[0])" }
    static func ddMon(_ iso: String) -> String {
        let p = iso.split(separator: "-"); let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(p[2]) \(names[Int(p[1])! - 1])"
    }

    // MARK: Renderers

    /// mBank-like: preamble lines, `;`-separated, `#` headers, "1 234,56 PLN", running balance.
    static func mbankCSV() -> String {
        let bal = balances(opening: polishOpening, polish)
        var out = "mBank S.A. Bankowość Detaliczna\nSkrócony Wyciąg z Rachunku\n\n#Data operacji;#Opis operacji;#Rachunek;#Kategoria;#Kwota;#Saldo po operacji;\n"
        for (row, balance) in zip(polish, bal) {
            out += "\(row.day);\"\(row.text)\";\"Konto osobiste\";\"Inne\";\(pl(row.minor, currency: "PLN"));\(pl(balance, currency: "PLN"));\n"
        }
        return out
    }

    /// PKO-like: comma separated, everything quoted, dot decimals, two dates, newest first.
    static func pkoCSV() -> String {
        let bal = balances(opening: polishOpening, polish)
        var out = "\"Data operacji\",\"Data waluty\",\"Typ transakcji\",\"Kwota\",\"Waluta\",\"Saldo po transakcji\",\"Opis transakcji\"\n"
        for (row, balance) in zip(polish, bal).reversed() {
            out += "\"\(row.day)\",\"\(row.day)\",\"\(row.minor < 0 ? "Płatność kartą" : "Przelew przychodzący")\",\"\(plain(row.minor))\",\"PLN\",\"\(plain(balance))\",\"\(row.text)\"\n"
        }
        return out
    }

    /// ING-like: separate counterparty and title columns, dd-mm-yyyy dates, `;`-separated, extra noise columns.
    static func ingCSV() -> String {
        let bal = balances(opening: polishOpening, polish)
        var out = "Lista transakcji nr 03/2026\nINGBSKPW\n\n\"Data transakcji\";\"Data księgowania\";\"Dane kontrahenta\";\"Tytuł\";\"Nr rachunku\";\"Kwota transakcji (waluta rachunku)\";\"Kwota blokady/zwolnienie blokady\";\"Waluta\";\"Saldo po transakcji\"\n"
        for (row, balance) in zip(polish, bal) {
            let parts = row.text.split(separator: " ", maxSplits: 3).map(String.init)
            out += "\"\(ddmmyyyy(row.day).replacingOccurrences(of: ".", with: "-"))\";\"\(ddmmyyyy(row.day).replacingOccurrences(of: ".", with: "-"))\";\"\(parts.prefix(2).joined(separator: " "))\";\"\(row.text)\";\"'00000000\";\(pl(row.minor).replacingOccurrences(of: " ", with: ""));;\"PLN\";\(pl(balance).replacingOccurrences(of: " ", with: ""))\n"
        }
        return out
    }

    /// Revolut-like (English): comma separated, timestamps, dot decimals, GBP.
    static func revolutCSV() -> String {
        let bal = balances(opening: englishOpening, english)
        var out = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\n"
        for (row, balance) in zip(english, bal) {
            out += "\(row.minor < 0 ? "CARD_PAYMENT" : "TOPUP"),Current,\(row.day) 10:15:00,\(row.day) 10:15:09,\"\(row.text)\",\(plain(row.minor)),0.00,GBP,COMPLETED,\(plain(balance))\n"
        }
        return out
    }

    /// Chase-like (US): month-first dates, no balance column.
    static func chaseCSV() -> String {
        var out = "Transaction Date,Post Date,Description,Category,Type,Amount,Memo\n"
        for row in english.reversed() {
            out += "\(mmddyyyy(row.day)),\(mmddyyyy(row.day)),\"\(row.text)\",Shopping,\(row.minor < 0 ? "Sale" : "Payment"),\(plain(row.minor)),\n"
        }
        return out
    }

    /// Text from a Polish PDF: page noise, two dates per entry, signed amount then balance.
    static func polishPDFText() -> String {
        let bal = balances(opening: polishOpening, polish)
        var out = "Bank Polska S.A.\nWYCIĄG Z RACHUNKU\nza okres od 01.03.2026 do 31.03.2026\nNumer rachunku: PL61 1090 1014 0000 0712 1981 2874\nSaldo początkowe: \(pl(polishOpening)) PLN\nData operacji Data waluty Opis operacji Kwota Saldo\n"
        for (index, (row, balance)) in zip(polish, bal).enumerated() {
            out += "\(ddmmyyyy(row.day)) \(ddmmyyyy(row.day)) \(row.text) \(pl(row.minor)) \(pl(balance))\n"
            if index == 8 { out += "Strona 1 z 2\nWYCIĄG Z RACHUNKU\nData operacji Data waluty Opis operacji Kwota Saldo\n" }
        }
        out += "Saldo końcowe: \(pl(bal.last!)) PLN\nRazem uznania: 8 549,50 PLN\nStrona 2 z 2\n"
        return out
    }

    /// Text from a UK PDF: "02 Mar", no signs, amounts in paid-out/paid-in columns, then balance.
    static func ukPDFText() -> String {
        let bal = balances(opening: englishOpening, english)
        var out = "Example Bank plc\nYour statement\nStatement period 01 Mar 2026 to 31 Mar 2026\nOpening balance \(en(englishOpening))\nDate Description Paid out Paid in Balance\n"
        for (row, balance) in zip(english, bal) {
            out += "\(ddMon(row.day)) \(row.text) \(en(abs(row.minor))) \(en(balance))\n"
        }
        out += "Closing balance \(en(bal.last!))\nPage 1 of 1\n"
        return out
    }

    /// Text where the date, description and amounts sit on separate lines.
    static func multilinePDFText() -> String {
        let bal = balances(opening: polishOpening, polish)
        var out = "WYCIĄG\nOkres: 01.03.2026 - 31.03.2026\nSaldo początkowe \(pl(polishOpening)) PLN\n"
        for (row, balance) in zip(polish, bal) {
            out += "\(ddmmyyyy(row.day))\n\(row.text)\n\(pl(row.minor)) PLN \(pl(balance)) PLN\n"
        }
        out += "Saldo końcowe \(pl(bal.last!)) PLN\n"
        return out
    }
}
