# RentBook

A private rent book for one landlord: properties and units, tenants, monthly rent,
payments, arrears, deposits, rent increases, agreements, expenses, reminders,
WhatsApp messages and reports. Amounts are in rupees; the financial year runs April to March.

Everything stays on the iPhone, with an automatic backup to an iCloud Drive folder you choose.
There are no accounts, no tenant logins and nothing is shared unless you share it.
Never commit tenant documents or exported backups to this repository.

## How it is built

`.github/workflows/main.yml` runs on every push to `main`:

1. **Check rent calculations** – compiles `Core*.swift` with `RentBookTests.swift` and runs the
   checks. If any check fails, the build stops.
2. **Build** – creates an Xcode project with XcodeGen and builds an unsigned app (iOS 16 or later).
3. **Package** – uploads `RentBook.ipa` as the `RentBook-ipa` artifact, to sign and install
   with your own certificate.

The version is 2.0; the build number is the workflow run number.

## Files

| Files | What they hold |
| --- | --- |
| `CoreModels.swift` | Data model, dates, rupee formatting |
| `CoreLedger.swift` | Charges, payment allocation, balances (all worked out from the records) |
| `CoreInsights.swift` | Rent increases, agreements, promises, occupancy, home screen figures |
| `CoreReports.swift` | Reports, CSV export |
| `CoreReminders.swift` | Which reminders to schedule |
| `CoreMessages.swift` | WhatsApp messages, amounts in words |
| `CoreBackup.swift` | Backup format, moving data from RentBook 1.0, sample data |
| `RentBookTests.swift` | Checks of the rent calculations (not part of the app) |
| `AppStore.swift` | Saving, iCloud Drive backup, restore, files, reminders |
| `RentBook.swift`, `AppLock.swift`, `UIComponents.swift`, `PDFMaker.swift` | App shell, Face ID lock, shared pieces, PDFs |
| `*Views.swift` | The screens |

## Versions

- **2.0** – Full rewrite: properties and units, part-month rent, billing frequencies, older dues,
  manual or oldest-first payment allocation, refunds, reversals with history, deposits and
  move-out settlement, approved rent increases, agreements with documents, WhatsApp messages,
  promises and follow-ups, expenses, 15 reports with PDF and CSV, Face ID lock, iCloud Drive
  backup. Data from 1.0 moves over automatically on first launch.
- **1.0** – Tenants, rent and payments.
