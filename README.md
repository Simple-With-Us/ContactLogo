# ContactLogo

**Brand icons for your address book.**  ContactLogo looks for business contacts
and suggests matching logos for you to review.  Approved updates can replace a
grey monogram with a recognizable brand mark.

**Site:** [ContactLogo.com](https://contactlogo.com)
**Repo:** [Simple-With-Us/ContactLogo](https://github.com/Simple-With-Us/ContactLogo)
**From:** [Simple With Us](https://simplewithus.com/)

Three shells, one engine:

| Product | What it is |
| --- | --- |
| **ContactLogo for macOS** | Native app. Full contact scan, review queue, try-another, apply, undo. |
| **ContactLogo for iOS** | Native app. Same engine on-device, three-bucket review. |
| **ContactLogo Web** | Import a `.vcf`, Google CSV, Google Contacts, or the device picker → review → download.  Installable PWA.  No account. |

ContactLogo is the only product.  **BadgeBook** and **Crest** were working
names and are retired.  `jaywedgeworth22/BadgeBook` redirects here.
`jaywedgeworth22/crest` is a legacy archive.  Catalog, phone, and iconic-mark
matching from Crest, plus BadgeBook's native kit and review-first contract,
live in `ContactLogoKit` and `web/`.  Frozen originals are in `backups/`.
Product history is in [docs/CONTACTLOGO.md](docs/CONTACTLOGO.md).

## Why it exists

- Your address book is full of businesses: pharmacies, banks, airlines, apps.
  They all render as identical grey initials.
- Automatic logo matching is easy to get *almost* right — and embarrassing when
  wrong. ContactLogo is built around a **review-first** flow with confidence
  tiers and per-contact overrides, not blind automation.

## Status

Matching engine plus working web review app and native shells.  The rule set
was distilled from a real-world battle test against a 14,000-contact address
book — see [docs/MATCHING-ENGINE.md](docs/MATCHING-ENGINE.md).

## Run

Web (primary runnable app):

```bash
cd web
npm install
npm test
npm run dev
```

Then open the printed local URL.  Optional: set `VITE_GOOGLE_CONTACTS_CLIENT_ID`
or paste a client id in Settings for Google Contacts import.

Native engine and CLI (macOS):

```bash
swift test
swift run contactlogo scan
```

macOS / iOS SwiftUI apps live in `Apps/`.  Open those sources in Xcode with
Contacts permission.  The CLI is the dogfood driver for AddressBook writes.

## Repository layout

```
Sources/ContactLogoKit/   Shared matching engine (Swift, macOS + iOS)
Sources/contactlogo/      CLI dogfood driver
Apps/ContactLogoMac/      macOS SwiftUI app
Apps/ContactLogoiOS/      iOS SwiftUI app
web/                      Web app (import → review → download)
vendor/crest/             git subtree of Crest (not a second product)
backups/badgebook/        Frozen BadgeBook snapshot (pre-combine)
backups/crest/            Frozen Crest snapshot (public-release commit)
docs/                     Vision, architecture, matching rules, product history
```

CLI scan dumps (`.contactlogo/`, `.badgebook/`, `scan.json`, `match-results.json`,
`review.html`) are gitignored.  They can contain AddressBook identifiers and
must never be committed.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
