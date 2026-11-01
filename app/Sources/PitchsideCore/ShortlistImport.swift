import Foundation

/// Imports a player list (FM's shortlist, or any FM table) from screenshots: text recognised on the
/// Mac (Vision) arrives as tokens with positions; they are grouped into table rows, read as
/// name / age / nation, and matched to players in the scan.
public enum ShortlistImport {
    /// One piece of recognised text. x, y: its left edge and vertical centre, 0–1 from the top left;
    /// h: its height (same units).
    public struct Token: Sendable, Codable {
        public let text: String
        public let x: Double, y: Double, h: Double
        /// Width, when known: lets a phrase that spans several cells be split into words in place.
        public let w: Double?
        public init(text: String, x: Double, y: Double, h: Double, w: Double? = nil) {
            self.text = text; self.x = x; self.y = y; self.h = h; self.w = w
        }
    }

    /// The Mac's text recognition returns phrases, sometimes across cells ("ENG M (C)", "20 Unknown").
    /// Split them into words, each placed along the phrase in proportion to its position in the text.
    static func words(_ tokens: [Token]) -> [Token] {
        tokens.flatMap { t -> [Token] in
            let parts = t.text.split(separator: " ")
            guard parts.count > 1 else { return [t] }
            let total = Double(max(1, t.text.count)), width = t.w ?? 0
            var out: [Token] = [], offset = 0
            for p in parts {
                let start = t.text.distance(from: t.text.startIndex, to: p.startIndex)
                out.append(Token(text: String(p), x: t.x + width * Double(start) / total, y: t.y, h: t.h, w: width * Double(p.count) / total))
                offset = start
            }
            _ = offset
            return out
        }
    }

    /// "ENG", or "ENGÙ"/"ENG," when a flag or mark is read with it → "ENG".
    static func nationCode(_ w: String) -> String? {
        guard w.count <= 5, let f = w.first, f.isUppercase else { return nil }
        let letters = String(w.filter { ("A"..."Z").contains($0) })
        return letters.count == 3 && w.prefix(3) == letters && Nations.byCode[letters] != nil ? letters : nil
    }

    /// A table row as read from the screen.
    public struct Line: Sendable, Hashable {
        public let name: String
        public let age: Int?
        public let nation: String?     // FM's three-letter code (ENG, ARG…)
        public let raw: String
    }

    public enum Confidence: Int, Sendable { case exact = 0, likely = 1, unsure = 2 }

    public struct Match: Sendable, Identifiable {
        public var id: String { line.raw }
        public let line: Line
        public let player: PlayerRow?
        public let confidence: Confidence
        public let alternatives: Int    // other players that also fit
    }

    // MARK: Rows

    /// FM's status chips in the first column ("FrA" free agent, "Lst" listed…) and table headers.
    static let chips: Set<String> = ["fra", "lst", "wnt", "bid", "loa", "trn", "unk", "inj", "sus", "int", "ret", "fut",
                                     "pre", "opt", "wdr", "rec", "ldp", "lon", "nfs", "cup", "new", "inf", "u21", "u23",
                                     "u18", "u19", "lst*", "bid*"]
    static let headers: Set<String> = ["inf", "name", "age", "nation", "club", "position", "value", "wage"]

    static func isAge(_ w: String) -> Bool { Int(w).map { (14...50).contains($0) } ?? false }
    static func isNation(_ w: String) -> Bool { nationCode(w) != nil }

    /// Groups tokens into table rows and reads each as name, age and nation. Rows are anchored on the
    /// nation codes (every row has one, at the row's centre line) or, without a Nation column, on the
    /// ages; every other piece of text joins the nearest row. Two-line cells (position + role) then
    /// can't spill into the next player's row.
    public static func lines(_ tokens: [Token]) -> [Line] {
        let toks = words(tokens.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        let nat = toks.filter { isNation($0.text) }, age = toks.filter { isAge($0.text) }
        var anchors: [Double] = []
        // Nation codes and ages both sit on a row's centre line; either one anchors the row.
        for y in (nat + age).map(\.y).sorted() {
            if let last = anchors.last, y - last < 0.004 { continue }
            anchors.append(y)
        }
        guard anchors.count >= 2 else { return linesByGap(toks) }
        let gaps = zip(anchors.dropFirst(), anchors).map { $0 - $1 }.sorted()
        let gap = gaps[gaps.count / 2]
        var rows = [[Token]](repeating: [], count: anchors.count)
        for t in toks {
            // Nearest anchor (anchors are sorted).
            var lo = 0, hi = anchors.count - 1
            while lo < hi { let mid = (lo + hi) / 2; if anchors[mid] < t.y { lo = mid + 1 } else { hi = mid } }
            let i = [lo - 1, lo].filter { $0 >= 0 }.min { abs(anchors[$0] - t.y) < abs(anchors[$1] - t.y) } ?? lo
            if abs(anchors[i] - t.y) <= gap * 0.45 { rows[i].append(t) }
        }
        return rows.compactMap { r in
            // Only the row's own line: the role line under the position is not part of the name.
            let line = r.filter { abs($0.y - (r.first { isNation($0.text) || isAge($0.text) }?.y ?? $0.y)) <= gap * 0.25 }
            return parse(line.sorted { $0.x < $1.x }.map(\.text).joined(separator: " "))
        }
    }

    /// Fallback without anchors: group by vertical position.
    static func linesByGap(_ toks: [Token]) -> [Line] {
        var rows: [[Token]] = []
        for t in toks.sorted(by: { $0.y < $1.y }) {
            if var last = rows.last, let ref = last.first, abs(t.y - ref.y) < max(ref.h, t.h) * 0.6 {
                last.append(t); rows[rows.count - 1] = last
            } else {
                rows.append([t])
            }
        }
        return rows.compactMap { parse($0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")) }
    }

    /// "FrA Ryan Shotton 38 ENG -" → name "Ryan Shotton", age 38, nation "ENG".
    public static func parse(_ raw: String) -> Line? {
        var words = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        // Leading checkbox marks, icons read as a single letter or symbol, and FM's status chip.
        while let w = words.first, (w.count <= 2 && w.allSatisfy { !$0.isLetter }) || w.count == 1
                || chips.contains(w.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeFirst()
        }
        let natIdx = words.firstIndex(where: isNation), ageIdx = words.firstIndex(where: isAge)
        // The name ends at the first of nation code and age (Player Database: name, nation…;
        // Shortlist: name, age, nation…). The age may be unreadable; the nation code is enough.
        guard let nameEnd = [natIdx, ageIdx].compactMap({ $0 }).min(), nameEnd > 0 else { return nil }
        let nameWords = words[..<nameEnd].filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !nameWords.isEmpty else { return nil }
        let name = nameWords.joined(separator: " ")
        if headers.contains(name.lowercased()) { return nil }
        // Position text ("ST (C)") or other cells misread as a row: real names have lower-case letters.
        guard name.contains(where: \.isLowercase) else { return nil }
        let nation = natIdx.flatMap { nationCode(words[$0]) }
        let age = words[nameEnd...].first(where: isAge).flatMap { Int($0) }
        return Line(name: name, age: age, nation: nation, raw: raw)
    }

    // MARK: Matching

    /// "Romário Vieira" → "romario vieira"; apostrophes and hyphens are ignored.
    public static func normalise(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .init(identifier: "en"))
        return folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined().split(separator: " ").joined(separator: " ")
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// An index of the scan's players by normalised name, for matching many lines quickly.
    public struct Index: Sendable {
        let byName: [String: [PlayerRow]]
        let bySurname: [String: [String]]
        let nations: [String: String]
        public init(_ rows: [PlayerRow]) {
            nations = Nations.resolved(for: Set(rows.compactMap { $0.person.nat }))
            var n = [String: [PlayerRow]](), s = [String: Set<String>]()
            for r in rows {
                let k = normalise(r.name)
                n[k, default: []].append(r)
                if let last = k.split(separator: " ").last { s[String(last), default: []].insert(k) }
            }
            byName = n
            bySurname = s.mapValues { Array($0) }
        }
    }

    public static func match(_ lines: [Line], index: Index) -> [Match] {
        var seenPlayers = Set<UInt32>(), seenLines = Set<String>()
        var out: [Match] = []
        for line in lines {
            let m = matchOne(line, index)
            // Overlapping screenshots repeat rows.
            if let p = m.player {
                guard seenPlayers.insert(p.id).inserted else { continue }
            } else {
                guard seenLines.insert("\(normalise(m.line.name))|\(line.age ?? -1)").inserted else { continue }
            }
            out.append(m)
        }
        return out
    }

    /// Icons and status chips can come out as stray words before the name ("A", "Pw", "ee FA"):
    /// try the name without up to three leading words, longest first, and keep the first that matches.
    static func matchOne(_ line: Line, _ idx: Index) -> Match {
        // Words run together ("BradArthur"): split at a lower→upper change, but not after Mc/Mac.
        let all = line.name.split(separator: " ").flatMap { w -> [String] in
            let chars = Array(w)
            guard chars.count > 5 else { return [String(w)] }
            for i in 2..<chars.count where chars[i].isUppercase && chars[i - 1].isLowercase {
                let head = String(chars[..<i])
                if head == "Mc" || head == "Mac" || head.hasSuffix("-") { continue }
                if i >= 3 { return [head, String(chars[i...])] }
            }
            return [String(w)]
        }
        var variants: [Line] = []
        // A flag icon can also come out as a short word after the name ("Zac Whittle Ss ENG").
        let tails = (all.last.map { $0.count <= 2 } ?? false) && all.count > 2 ? [0, 1] : [0]
        for tail in tails {
            let words = Array(all.dropLast(tail))
            for drop in 0...min(3, max(0, words.count - 2)) {
                variants.append(Line(name: words.dropFirst(drop).joined(separator: " "), age: line.age, nation: line.nation, raw: line.raw))
            }
        }
        var best: Match?
        for v in variants {
            let m = matchVariant(v, idx)
            if m.player != nil && m.confidence == .exact { return m }
            if m.player != nil && (best == nil || m.confidence.rawValue < best!.confidence.rawValue) { best = m }
        }
        return best ?? Match(line: variants.last ?? line, player: nil, confidence: .unsure, alternatives: 0)
    }

    static func matchVariant(_ line: Line, _ idx: Index) -> Match {
        let key = normalise(line.name)
        func narrow(_ c: [PlayerRow]) -> [PlayerRow] {
            var c = c
            if let age = line.age {
                let a = c.filter { abs($0.age - age) <= 1 }
                if !a.isEmpty { c = a }
            }
            if let code = line.nation, let country = idx.nations[code] {
                let n = c.filter { $0.person.nat == country }
                if !n.isEmpty { c = n }
            }
            if c.count > 1 {
                // Namesakes: the club printed in the same row, or "-" (no club) for a free agent.
                let raw = line.raw.lowercased()
                let byClub = c.filter { !$0.club.isEmpty && raw.contains($0.club.lowercased()) }
                if !byClub.isEmpty { c = byClub }
                // FM's "FrA" chip (free agent) or "-" in the Club column: the one without a club.
                else if line.raw.split(separator: " ").contains("FrA") || raw.split(separator: " ").contains("-") {
                    let free = c.filter { $0.club.isEmpty }
                    if !free.isEmpty { c = free }
                }
            }
            return c
        }
        if let exact = idx.byName[key] {
            let c = narrow(exact)
            let ageOK = line.age.map { a in c.first.map { abs($0.age - a) <= 1 } ?? false } ?? true
            let nationOK = line.nation.flatMap { idx.nations[$0] }.map { n in c.first?.person.nat == n } ?? false
            let conf: Confidence = c.count != 1 ? .unsure : ageOK ? .exact : nationOK ? .likely : .unsure
            return Match(line: line, player: c.first, confidence: conf, alternatives: max(0, c.count - 1))
        }
        // Small recognition slips: same surname or close spelling, and the age must fit. Only for a
        // full name: loose matching of a stray word ("Ss") finds some unrelated player.
        guard key.contains(" "), key.count >= 6 else { return Match(line: line, player: nil, confidence: .unsure, alternatives: 0) }
        var candidates: [String] = []
        if let last = key.split(separator: " ").last { candidates = idx.bySurname[String(last)] ?? [] }
        let close = candidates.filter { distance($0, key) <= 3 }
        var pool = close.flatMap { idx.byName[$0] ?? [] }
        if pool.isEmpty {
            // Surname misread: try every name with the same first letter and similar length.
            pool = idx.byName.filter { k, _ in k.first == key.first && abs(k.count - key.count) <= 2 && distance(k, key) <= 2 }
                .flatMap(\.value)
        }
        // Same first initial: "Ben Tomlinson" must not become Joe Tomlinson.
        pool = pool.filter { normalise($0.name).first == key.first }
        let country = line.nation.flatMap { idx.nations[$0] }
        let c = narrow(pool).filter { r in
            (line.age.map { abs(r.age - $0) <= 1 } ?? true) && (country.map { r.person.nat == $0 } ?? true)
        }
        guard let best = c.min(by: { distance(normalise($0.name), key) < distance(normalise($1.name), key) }) else {
            return Match(line: line, player: nil, confidence: .unsure, alternatives: 0)
        }
        return Match(line: line, player: best, confidence: c.count == 1 ? .likely : .unsure, alternatives: c.count - 1)
    }
}

/// FM's three-letter nation codes → the country names in the scan.
public enum Nations {
    static let table = """
    AFG Afghanistan|ALB Albania|ALG Algeria|AND Andorra|ANG Angola|ARG Argentina|ARM Armenia|AUS Australia|AUT Austria|\
    AZE Azerbaijan|BAH Bahamas|BAN Bangladesh|BRB Barbados|BLR Belarus|BEL Belgium|BLZ Belize|BEN Benin|BER Bermuda|\
    BOL Bolivia|BIH Bosnia & Herzegovina|BOT Botswana|BRA Brazil|BUL Bulgaria|BFA Burkina Faso|BDI Burundi|CPV Cape Verde|\
    CMR Cameroon|CAN Canada|CTA Central African Rep.|CHA Chad|CHI Chile|CHN China|COL Colombia|COM Comoros|CGO Congo|\
    COD DR Congo|CRC Costa Rica|CIV Ivory Coast|CRO Croatia|CUB Cuba|CUW Curaçao|CYP Cyprus|CZE Czechia|DEN Denmark|\
    DOM Dominican Republic|ECU Ecuador|EGY Egypt|SLV El Salvador|ENG England|EQG Eq. Guinea|ERI Eritrea|EST Estonia|\
    ETH Ethiopia|FRO Faroe Islands|FIJ Fiji|FIN Finland|FRA France|GAB Gabon|GAM The Gambia|GEO Georgia|GER Germany|GHA Ghana|\
    GIB Gibraltar|GRE Greece|GRN Grenada|GUA Guatemala|GUI Guinea|GNB Guinea-Bissau|GUY Guyana|HAI Haiti|HON Honduras|\
    HKG Hong Kong (China PR)|HUN Hungary|ISL Iceland|IND India|IDN Indonesia|IRN Iran|IRQ Iraq|IRL Ireland|ISR Israel|\
    ITA Italy|JAM Jamaica|JPN Japan|JOR Jordan|KAZ Kazakhstan|KEN Kenya|KOR South Korea|PRK North Korea|KOS Kosovo|\
    KUW Kuwait|KGZ Kyrgyzstan|LVA Latvia|LIB Lebanon|LBR Liberia|LBY Libya|LIE Liechtenstein|LTU Lithuania|LUX Luxembourg|\
    MAD Madagascar|MWI Malawi|MAS Malaysia|MLI Mali|MLT Malta|MTN Mauritania|MRI Mauritius|MEX Mexico|MDA Moldova|\
    MNE Montenegro|MAR Morocco|MOZ Mozambique|NAM Namibia|NED Netherlands|NZL New Zealand|NCA Nicaragua|NIG Niger|\
    NGA Nigeria|MKD North Macedonia|NIR N.Ireland|NOR Norway|OMA Oman|PAK Pakistan|PLE Palestine|PAN Panama|\
    PAR Paraguay|PER Peru|PHI Philippines|POL Poland|POR Portugal|PUR Puerto Rico|QAT Qatar|ROU Romania|RUS Russia|\
    RWA Rwanda|SKN St Kitts & Nevis|LCA St Lucia|VIN St Vincent|SMR San Marino|KSA Saudi Arabia|\
    SCO Scotland|SEN Senegal|SRB Serbia|SLE Sierra Leone|SIN Singapore|SVK Slovakia|SVN Slovenia|SOM Somalia|RSA South Africa|\
    SSD South Sudan|ESP Spain|SRI Sri Lanka|SDN Sudan|SUR Suriname|SWE Sweden|SUI Switzerland|SYR Syria|TAH Tahiti|\
    TJK Tajikistan|TAN Tanzania|THA Thailand|TOG Togo|TRI Trinidad & Tobago|TUN Tunisia|TUR Türkiye|TKM Turkmenistan|\
    UGA Uganda|UKR Ukraine|UAE U.A.E.|USA U.S.A.|URU Uruguay|UZB Uzbekistan|VEN Venezuela|VIE Vietnam|\
    WAL Wales|YEM Yemen|ZAM Zambia|ZIM Zimbabwe|MSR Montserrat|ATG Antigua & Barbuda|DMA Dominica|ARU Aruba|CAY Cayman Islands|\
    BOE Bonaire|GLP Guadeloupe|MTQ Martinique|GUF French Guiana|NCL New Caledonia|TPE Chinese Taipei (China PR)|STP São Tomé & Príncipe|\
    SEY Seychelles|LES Lesotho|SWZ Eswatini|DJI Djibouti|AIA Anguilla|BHR Bahrain|VGB British Virgin Is.|CAM Cambodia|\
    TLS East Timor|MAC Macau (China PR)|MDV Maldives|MYT Mayotte|MON Monaco|MNG Mongolia|REU Réunion|SXM Sint Maarten|\
    SMN St Martin|TCA Turks & Caicos Is.|VAN Vanuatu
    """
    /// Code → country; also tolerant of the scan using a slightly different name ("Turkey", "USA").
    public static let byCode: [String: String] = {
        var d = [String: String]()
        for item in table.split(separator: "|") {
            let parts = item.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
            if parts.count == 2 { d[String(parts[0])] = String(parts[1]) }
        }
        return d
    }()

    /// Re-keys the table to the spellings actually used in a scan (matching on folded names).
    public static func resolved(for scanNations: Set<String>) -> [String: String] {
        let folded = Dictionary(scanNations.map { (ShortlistImport.normalise($0), $0) }, uniquingKeysWith: { a, _ in a })
        var out = [String: String]()
        for (code, name) in byCode {
            if let exact = folded[ShortlistImport.normalise(name)] { out[code] = exact; continue }
            // "Republic of Ireland" vs "Ireland", "St. Kitts and Nevis" vs "Saint Kitts & Nevis"…
            let n = ShortlistImport.normalise(name)
            if let hit = folded.first(where: { $0.key.contains(n) || n.contains($0.key) }) { out[code] = hit.value }
        }
        return out
    }
}
