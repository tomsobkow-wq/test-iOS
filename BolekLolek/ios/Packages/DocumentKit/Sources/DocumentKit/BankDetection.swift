import Foundation

public enum BankDetector {
    private static let banks: [(needles: [String], name: String, dayOrder: DayOrder)] = [
        (["pko bank polski", "pkobp", "pko bp"], "PKO BP", .dayFirst), (["mbank"], "mBank", .dayFirst),
        (["ing bank slaski", "ing bank"], "ING Bank Śląski", .dayFirst), (["santander bank polska", "santander"], "Santander", .dayFirst),
        (["pekao", "bank polska kasa opieki"], "Bank Pekao", .dayFirst), (["bank millennium", "millennium"], "Bank Millennium", .dayFirst),
        (["alior bank", "alior"], "Alior Bank", .dayFirst), (["bnp paribas"], "BNP Paribas", .dayFirst), (["credit agricole"], "Credit Agricole", .dayFirst),
        (["velobank", "velo bank"], "VeloBank", .dayFirst), (["nest bank"], "Nest Bank", .dayFirst), (["citi handlowy"], "Citi Handlowy", .dayFirst),
        (["revolut"], "Revolut", .dayFirst), (["transferwise", "wise payments", " wise "], "Wise", .dayFirst),
        (["monzo"], "Monzo", .dayFirst), (["starling bank"], "Starling", .dayFirst), (["barclays"], "Barclays", .dayFirst),
        (["hsbc"], "HSBC", .dayFirst), (["lloyds"], "Lloyds", .dayFirst), (["natwest"], "NatWest", .dayFirst),
        (["jpmorgan chase", "chase.com", "chase bank"], "Chase", .monthFirst), (["bank of america"], "Bank of America", .monthFirst),
        (["wells fargo"], "Wells Fargo", .monthFirst), (["capital one"], "Capital One", .monthFirst), (["american express"], "American Express", .monthFirst),
        (["citibank"], "Citibank", .monthFirst),
    ]

    /// Some banks never print their name in a CSV export, but their header row is distinctive.
    private static let headerSignatures: [(signature: String, name: String, dayOrder: DayOrder)] = [
        ("type,product,started date", "Revolut", .dayFirst),
        ("transferwise id", "Wise", .dayFirst),
        ("transaction id,date,time,type,name", "Monzo", .dayFirst),
        ("transaction date,post date,description,category,type,amount", "Chase", .monthFirst),
        ("#data operacji;#opis operacji;#rachunek;#kategoria", "mBank", .dayFirst),
        ("data transakcji;data ksiegowania;dane kontrahenta", "ING Bank Śląski", .dayFirst),
        ("\"data operacji\",\"data waluty\",\"typ transakcji\"", "PKO BP", .dayFirst),
    ]

    public static func detect(_ text: String) -> (name: String, dayOrder: DayOrder)? {
        let head = " " + String(text.prefix(6000)).folded + " "
        for bank in banks where bank.needles.contains(where: { head.contains($0) }) { return (bank.name, bank.dayOrder) }
        let compact = head.replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: ", ", with: ",")
        for entry in headerSignatures where compact.contains(entry.signature) { return (entry.name, entry.dayOrder) }
        return nil
    }
}
