import Foundation

/// Offline name → domain table ported from `vendor/crest/src/lib/contacts.ts`.
/// Used when a contact has no usable website or work email. Homonyms still
/// go through the review-first confidence cap (MATCHING-ENGINE §4).
public enum CompanyCatalog {

    /// Lowercased, punctuation-stripped keys → registrable domain.
    static let domains: [String: String] = [
        "apple": "apple.com", "apple inc": "apple.com",
        "google": "google.com", "alphabet": "abc.xyz",
        "microsoft": "microsoft.com", "amazon": "amazon.com",
        "meta": "meta.com", "facebook": "facebook.com", "instagram": "instagram.com",
        "tesla": "tesla.com", "nvidia": "nvidia.com",
        "netflix": "netflix.com", "spotify": "spotify.com",
        "adobe": "adobe.com", "salesforce": "salesforce.com",
        "oracle": "oracle.com", "ibm": "ibm.com", "intel": "intel.com",
        "cisco": "cisco.com", "stripe": "stripe.com", "paypal": "paypal.com",
        "visa": "visa.com", "mastercard": "mastercard.com",
        "american express": "americanexpress.com", "amex": "americanexpress.com",
        "chase": "chase.com", "jpmorgan": "jpmorganchase.com",
        "jp morgan": "jpmorganchase.com", "jpmorgan chase": "jpmorganchase.com",
        "bank of america": "bankofamerica.com",
        "wells fargo": "wellsfargo.com",
        "citi": "citi.com", "citibank": "citi.com", "citigroup": "citi.com",
        "geico": "geico.com",
        "state farm": "statefarm.com", "state farm insurance": "statefarm.com",
        "allstate": "allstate.com", "allstate insurance": "allstate.com",
        "usaa": "usaa.com", "usaa insurance": "usaa.com",
        "verizon": "verizon.com",
        "at&t": "att.com", "att": "att.com",
        "t-mobile": "t-mobile.com", "tmobile": "t-mobile.com",
        "united airlines": "united.com", "united": "united.com",
        "american airlines": "aa.com",
        "delta": "delta.com", "delta air lines": "delta.com", "delta airlines": "delta.com",
        "southwest": "southwest.com", "southwest airlines": "southwest.com",
        "jetblue": "jetblue.com", "alaska airlines": "alaskaair.com",
        "fedex": "fedex.com", "ups": "ups.com", "usps": "usps.com",
        "the home depot": "homedepot.com", "home depot": "homedepot.com",
        "lowes": "lowes.com", "lowe's": "lowes.com",
        "costco": "costco.com", "walmart": "walmart.com", "target": "target.com",
        "starbucks": "starbucks.com",
        "mcdonalds": "mcdonalds.com", "mcdonald's": "mcdonalds.com",
        "uber": "uber.com", "lyft": "lyft.com", "doordash": "doordash.com",
        "airbnb": "airbnb.com", "nike": "nike.com",
        "samsung": "samsung.com", "sony": "sony.com",
        "ford": "ford.com", "bmw": "bmw.com",
        "centerpoint energy": "centerpointenergy.com", "centerpoint": "centerpointenergy.com",
        "x ai": "x.ai", "xai": "x.ai",
        "square": "squareup.com",
        "capital one": "capitalone.com", "discover": "discover.com",
        "intuit": "intuit.com", "turbotax": "turbotax.intuit.com",
        "quickbooks": "quickbooks.intuit.com",
        "h&r": "hrblock.com", "h&r block": "hrblock.com", "h and r block": "hrblock.com",
        "edward jones": "edwardjones.com",
        "charles schwab": "schwab.com", "td ameritrade": "tdameritrade.com",
        "etrade": "etrade.com", "robinhood": "robinhood.com", "coinbase": "coinbase.com",
        "american tower": "americantower.com", "crown castle": "crowncastle.com",
        "waste management": "wm.com",
        "republic": "republicservices.com", "republic services": "republicservices.com",
        "waste connections": "wasteconnections.com",
        "texas instruments": "ti.com", "qualcomm": "qualcomm.com",
        "broadcom": "broadcom.com", "amd": "amd.com",
        "advanced micro devices": "amd.com",
        "palantir": "palantir.com", "snowflake": "snowflake.com",
        "databricks": "databricks.com", "servicenow": "servicenow.com",
        "workday": "workday.com", "autodesk": "autodesk.com",
        "electronic arts": "ea.com", "activision": "activision.com",
        "take-two": "take2games.com", "roblox": "roblox.com", "unity": "unity.com",
        "epic games": "epicgames.com", "valve": "valvesoftware.com",
        "steam": "steampowered.com",
        "comcast": "xfinity.com", "xfinity": "xfinity.com", "spectrum": "spectrum.com",
        "progressive": "progressive.com", "liberty mutual": "libertymutual.com",
        "farmers": "farmers.com", "nationwide": "nationwide.com",
        "root insurance": "rootinsurance.com",
        "heb": "heb.com", "h-e-b": "heb.com",
        "kroger": "kroger.com", "randalls": "randalls.com", "safeway": "safeway.com",
        "publix": "publix.com", "walgreens": "walgreens.com", "cvs": "cvs.com",
        "best buy": "bestbuy.com", "macy's": "macys.com", "macys": "macys.com",
        "hertz": "hertz.com", "enterprise": "enterprise.com", "avis": "avis.com",
        "hilton": "hilton.com", "marriott": "marriott.com", "hyatt": "hyatt.com",
        "fidelity": "fidelity.com", "vanguard": "vanguard.com", "schwab": "schwab.com",
        "trader joes": "traderjoes.com", "trader joe's": "traderjoes.com",
        "aldi": "aldi.us", "whole foods": "wholefoodsmarket.com", "whole foods market": "wholefoodsmarket.com",
        "kaiser": "kp.org", "kaiser permanente": "kp.org", "quest": "questdiagnostics.com", "quest diagnostics": "questdiagnostics.com",
        "labcorp": "labcorp.com", "enterprise rent-a-car": "enterprise.com",
        "shell": "shell.com", "chevron": "chevron.com",
        "exxon": "exxon.com", "exxonmobil": "exxonmobil.com", "bp": "bp.com", "7 eleven": "7-eleven.com", "7-eleven": "7-eleven.com",
        "wawa": "wawa.com", "bucees": "buc-ees.com", "buc ees": "buc-ees.com", "buc-ees": "buc-ees.com",
        "reliant": "reliant.com", "pg&e": "pge.com",
        "duke energy": "duke-energy.com", "amtrak": "amtrak.com",
        "txt": "texasbytexas.com", "texas by texas": "texasbytexas.com",
        "gcx": "raise.com", "raise": "raise.com",

        // Food & Restaurants
        "chick-fil-a": "chick-fil-a.com", "chick fil a": "chick-fil-a.com",
        "wendys": "wendys.com", "wendy's": "wendys.com",
        "burger king": "bk.com", "taco bell": "tacobell.com",
        "subway": "subway.com", "chipotle": "chipotle.com",
        "panera": "panerabread.com", "panera bread": "panerabread.com",
        "dominos": "dominos.com", "domino's": "dominos.com",
        "pizza hut": "pizzahut.com",
        "papa johns": "papajohns.com", "papa john's": "papajohns.com",
        "dunkin": "dunkindonuts.com", "dunkin donuts": "dunkindonuts.com",
        "dutch bros": "dutchbros.com", "five guys": "fiveguys.com",
        "in-n-out": "in-n-out.com", "in n out": "in-n-out.com",
        "panda express": "pandaexpress.com", "olive garden": "olivegarden.com",
        "buffalo wild wings": "buffalowildwings.com", "texas roadhouse": "texasroadhouse.com",
        "chilis": "chilis.com", "chili's": "chilis.com",
        "applebees": "applebees.com", "applebee's": "applebees.com",
        "outback": "outback.com", "outback steakhouse": "outback.com",
        "red lobster": "redlobster.com", "ihop": "ihop.com",
        "dennys": "dennys.com", "denny's": "dennys.com",
        "cracker barrel": "crackerbarrel.com", "waffle house": "wafflehouse.com",
        "sonic": "sonicdrivein.com", "sonic drive-in": "sonicdrivein.com",
        "whataburger": "whataburger.com", "shake shack": "shakeshack.com",
        "sweetgreen": "sweetgreen.com", "cava": "cava.com",
        "crumbl": "crumblcookies.com", "crumbl cookies": "crumblcookies.com",

        // Retail & Groceries
        "chewy": "chewy.com", "ikea": "ikea.com", "wayfair": "wayfair.com",
        "nordstrom": "nordstrom.com", "kohls": "kohls.com", "kohl's": "kohls.com",
        "gap": "gap.com", "old navy": "oldnavy.com", "lululemon": "lululemon.com",
        "sephora": "sephora.com", "ulta": "ulta.com",
        "petco": "petco.com", "petsmart": "petsmart.com", "menards": "menards.com",
        "ace hardware": "acehardware.com",
        "williams sonoma": "williams-sonoma.com", "williams-sonoma": "williams-sonoma.com",
        "pottery barn": "potterybarn.com",
        "crate & barrel": "crateandbarrel.com", "crate and barrel": "crateandbarrel.com",
        "sprouts": "sprouts.com", "sprouts farmers market": "sprouts.com",
        "albertsons": "albertsons.com", "meijer": "meijer.com",
        "wegmans": "wegmans.com", "hy-vee": "hy-vee.com", "hy vee": "hy-vee.com",
        "winco": "wincofoods.com", "sams club": "samsclub.com", "sam's club": "samsclub.com",
        "bjs": "bjs.com", "bj's": "bjs.com",
        "dollar general": "dollargeneral.com", "dollar tree": "dollartree.com",
        "tj maxx": "tjx.com", "marshalls": "marshalls.com", "homegoods": "homegoods.com",
        "ross": "rossstores.com", "burlington": "burlington.com",
        "bath & body works": "bathandbodyworks.com", "bath and body works": "bathandbodyworks.com",
        "dick's sporting goods": "dickssportinggoods.com", "dicks sporting goods": "dickssportinggoods.com",
        "academy sports": "academy.com", "bass pro shops": "basspro.com",
        "cabelas": "cabelas.com", "cabela's": "cabelas.com", "rei": "rei.com",
        "autozone": "autozone.com", "o'reilly auto parts": "oreillyauto.com", "oreilly auto parts": "oreillyauto.com",
        "advance auto parts": "advanceautoparts.com",

        // Banks & Financial
        "us bank": "usbank.com", "pnc": "pnc.com", "pnc bank": "pnc.com",
        "truist": "truist.com", "td bank": "td.com",
        "bmo": "bmo.com", "bmo harris": "bmo.com",
        "morgan stanley": "morganstanley.com", "goldman sachs": "goldmansachs.com",
        "raymond james": "raymondjames.com", "ameriprise": "ameriprise.com",
        "lpl financial": "lpl.com", "northwestern mutual": "northwesternmutual.com",
        "new york life": "newyorklife.com", "massmutual": "massmutual.com",
        "prudential": "prudential.com", "metlife": "metlife.com",
        "lincoln financial": "lincolnfinancial.com", "principal": "principal.com", "principal financial": "principal.com",
        "ally": "ally.com", "ally bank": "ally.com", "sofi": "sofi.com", "synchrony": "synchrony.com",

        // Insurance & Healthcare
        "travelers": "travelers.com", "american family": "amfam.com", "american family insurance": "amfam.com",
        "auto-owners": "auto-owners.com", "auto owners": "auto-owners.com",
        "erie insurance": "erieinsurance.com", "chubb": "chubb.com",
        "the hartford": "thehartford.com", "hartford": "thehartford.com",
        "aetna": "aetna.com", "cigna": "cigna.com", "humana": "humana.com",
        "unitedhealthcare": "uhc.com", "uhc": "uhc.com",
        "blue cross": "bcbs.com", "blue cross blue shield": "bcbs.com", "bcbs": "bcbs.com",
        "anthem": "anthem.com", "centene": "centene.com",

        // Travel, Rental & Hotels
        "budget": "budget.com", "budget rent a car": "budget.com",
        "national car rental": "nationalcar.com", "national": "nationalcar.com",
        "alamo": "alamo.com", "alamo rent a car": "alamo.com",
        "thrifty": "thrifty.com", "dollar rent a car": "dollar.com",
        "spirit": "spirit.com", "spirit airlines": "spirit.com",
        "allegiant": "allegiantair.com", "allegiant air": "allegiantair.com",
        "sun country": "suncountry.com", "hawaiian airlines": "hawaiianairlines.com",
        "air canada": "aircanada.com", "british airways": "britishairways.com",
        "lufthansa": "lufthansa.com", "emirates": "emirates.com", "dhl": "dhl.com",
        "wyndham": "wyndhamhotels.com", "choice hotels": "choicehotels.com",
        "best western": "bestwestern.com", "ihg": "ihg.com", "holiday inn": "holidayinn.com",
        "sheraton": "sheraton.com", "westin": "westin.com",
        "four seasons": "fourseasons.com", "ritz carlton": "ritzcarlton.com", "ritz-carlton": "ritzcarlton.com",

        // Auto Brands
        "toyota": "toyota.com", "honda": "honda.com",
        "chevrolet": "chevrolet.com", "chevy": "chevrolet.com",
        "nissan": "nissanusa.com", "jeep": "jeep.com", "ram": "ramtrucks.com",
        "subaru": "subaru.com", "hyundai": "hyundaiusa.com", "kia": "kia.com",
        "gmc": "gmc.com", "dodge": "dodge.com", "volkswagen": "vw.com", "vw": "vw.com",
        "mercedes": "mbusa.com", "mercedes-benz": "mbusa.com", "mercedes benz": "mbusa.com",
        "audi": "audiusa.com", "lexus": "lexus.com", "mazda": "mazdausa.com",
        "volvo": "volvocars.com", "porsche": "porsche.com", "chrysler": "chrysler.com",
        "buick": "buick.com", "cadillac": "cadillac.com", "acura": "acura.com",
        "infiniti": "infinitiusa.com", "lincoln": "lincoln.com", "rivian": "rivian.com", "lucid": "lucidmotors.com",

        // Tech, Media & Services
        "shopify": "shopify.com", "etsy": "etsy.com", "slack": "slack.com",
        "zoom": "zoom.us", "zillow": "zillow.com", "redfin": "redfin.com",
        "ebay": "ebay.com", "linkedin": "linkedin.com", "snapchat": "snapchat.com",
        "pinterest": "pinterest.com", "reddit": "reddit.com", "discord": "discord.com",
        "twitch": "twitch.tv", "hulu": "hulu.com",
        "disney plus": "disneyplus.com", "disney+": "disneyplus.com",
        "paramount plus": "paramountplus.com", "paramount+": "paramountplus.com",
        "peacock": "peacocktv.com", "hbo": "max.com", "max": "max.com",
        "roku": "roku.com", "sonos": "sonos.com", "garmin": "garmin.com",
        "dji": "dji.com", "gopro": "gopro.com", "dropbox": "dropbox.com", "box": "box.com",
        "notion": "notion.so", "figma": "figma.com", "canva": "canva.com",
        "github": "github.com", "gitlab": "gitlab.com",
        "atlassian": "atlassian.com", "jira": "atlassian.com", "trello": "trello.com",
        "asana": "asana.com", "monday": "monday.com", "hubspot": "hubspot.com",
        "mailchimp": "mailchimp.com", "squarespace": "squarespace.com",
        "wix": "wix.com", "godaddy": "godaddy.com", "cloudflare": "cloudflare.com",
        "craigslist": "craigslist.org", "offerup": "offerup.com",
        "carvana": "carvana.com", "carmax": "carmax.com",

        // Utilities & Telecom
        "cox": "cox.com", "optimum": "optimum.com", "frontier": "frontier.com",
        "centurylink": "centurylink.com", "windstream": "windstream.com",
        "directv": "directv.com", "dish": "dish.com", "dish network": "dish.com",
        "coned": "coned.com", "con edison": "coned.com", "national grid": "nationalgridus.com",
        "eversource": "eversource.com", "xcel energy": "xcelenergy.com",
        "entergy": "entergy.com", "southern": "southerncompany.com", "southern company": "southerncompany.com",
        "dominion energy": "dominionenergy.com", "nextera": "nexteraenergy.com",
        "fpl": "fpl.com", "florida power & light": "fpl.com"
    ]

    /// R8.3 `CATALOG_TAIL_OK` — a location or sub-brand tail after a known
    /// brand ("Walgreens Mason Rd", "H-E-B Pharmacy").  Trade words such as
    /// "dental" are deliberately absent, so "Delta Dental" never reduces to
    /// delta.com.
    static func isAllowedTail(_ tail: String) -> Bool {
        WordLists.isCatalogTailOK(tail)
    }

    public static func domain(forName raw: String) -> String? {
        let key = NameNormalizer.companyKey(raw)
        guard !key.isEmpty else { return nil }
        if let d = domains[key] { return d }
        let nospace = key.replacingOccurrences(of: " ", with: "")
        if let d = domains[nospace] { return d }

        let words = key.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        for i in stride(from: words.count - 1, through: 1, by: -1) {
            let head = words[..<i].joined(separator: " ")
            let tail = words[i...].joined(separator: " ")
            let hit = domains[head] ?? domains[head.replacingOccurrences(of: " ", with: "")]
            if let hit, isAllowedTail(tail) {
                return hit
            }
        }
        return nil
    }
}
