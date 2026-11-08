# Nomi

iOS expense tracker (SwiftUI + SwiftData + CloudKit), no backend. India-focused:
email/UPI ingestion, CSV/XLSX import, rules, budgets, reports.

## Layout

One app target, five local Swift packages:

- `NomiCore` — SwiftData models, contracts, pure support code. No dependencies.
- `NomiPreview` — in-memory fakes of every `NomiCore` contract, for SwiftUI
  previews and UI tests. Depends on `NomiCore`.
- `NomiIngest` — mail (IMAP) and file (CSV/XLSX) ingestion, the write pipeline.
  Depends on `NomiCore`.
- `NomiUI` — every screen. Depends on `NomiCore` and `NomiPreview` only — never
  `NomiIngest`.
- `NomiApp` — composition root, wires real services to the UI. Depends on
  `NomiCore`, `NomiIngest` and `NomiUI`, not `NomiPreview`.

`project.yml` (XcodeGen) generates the Xcode project; `.xcodeproj` is never
committed.

## Build

```sh
brew install xcodegen
xcodegen generate
xcodebuild build -scheme Nomi -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'
```

## Test

```sh
for pkg in NomiCore NomiPreview NomiIngest NomiUI NomiApp; do
  (cd Packages/$pkg && swift test)
done
```

CI (`.github/workflows/ci.yml`) runs on `macos-14` for every pull request and
for each push to `main`. It runs the Xcode build for the iOS Simulator, then
`swift test` in all five packages. A branch pushed with no open pull request
does not run CI; open the PR (a draft is enough).
