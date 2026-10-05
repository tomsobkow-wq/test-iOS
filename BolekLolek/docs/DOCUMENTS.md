# Documents and bank statements (Lolek): design and measurements

Package: `ios/Packages/DocumentKit`. All of it runs on the phone; Bolek (cloud) never gets documents (tools are `tier: .lolek`).

## Principle: a 4B model does not read the document

Qwen3.5 4B is weak at long text and bad at arithmetic. So code does the reading and the maths, and the model only phrases results.

| Step | Done by | Notes |
|---|---|---|
| Read the file | code | PDF text (PDFKit), scans/photos by Apple Vision OCR (Polish + English), CSV with Windows-1250/ISO-8859-2 decoding |
| Is it a bank statement? | code | CSV header recognition (PL/EN synonyms) or text parsing of PDF/OCR lines; checked by **reconciliation** (opening balance + transactions = closing balance, or running-balance steps) |
| Signs (debit/credit) | code | explicit sign, brackets, DR/CR, otherwise from the running balance, otherwise keywords |
| Totals, categories, merchants, recurring payments | code | `StatementAnalyzer`, exact |
| Summary on upload | code (statements), one model call (text documents) | statement summary is written from the numbers, instant |
| Which question maps to which query | code first (`DocumentPlanner`), model only if unsure | the 4B model skipped tools or invented numbers when left to choose |
| Phrasing the answer | model | |
| Checking the answer | code (`GroundingVerifier`) | a number not in the tool results sends the answer back once; still wrong → a caution is appended |
| Long text documents | code picks the sentences with amounts/dates/deadlines (`ExtractiveBrief`), one model call phrases them | map-reduce kept as an option; it was slower and lost facts |
| Questions about text documents | BM25 search with Polish/English stemming, passages fetched before the model answers | |

## What was measured (real Qwen3.5 4B, Mac; synthetic statements and documents, no real data)

- **Statement questions: 10/16 → 26/26.** Before the planner, the model often did not call the tools ("I have no access to your documents") or called only `list_documents` and invented a figure. The 26 include 10 questions written after the planner (Polish inflections: "Netflixa", "w McDonaldzie", "odłożyłem"; refunds, utilities, fuel).
- **Contract summary: 5/5 key facts in 18 s (extractive)** vs 5/5 in 31 s with weaker wording (map-reduce). Invoice: extractive 3/5 before the short-line fix (VAT line was filtered as too short), fixed with a test.
- **Document questions: 9/10 correct.** Known miss: "Czy mogę wynająć pokój komuś innemu?" - the contract says *podnajem*; keyword search cannot bridge different words for one idea, and the model answered without searching. Fix would be embeddings or query expansion.
- **Polish prose from the model is the weak spot.** Numbers were always right, but free narration had slips ("brak brakuje pieniędzy", filler closing lines). That is why the statement summary shown on upload is written by code, and the model is used for answers.
- **OCR:** a photo and a scanned PDF of a clean synthetic statement parsed 17/17 transactions and reconciled. **Real phone photos (blur, skew, glare) are untested.**

## What is NOT verified

- **Real bank files.** Parsers were written for the typical shape of mBank, PKO BP, ING, Revolut, Chase, Monzo-style exports and three PDF text layouts, tested on synthetic files rendered in those styles. Real exports differ (extra columns, odd headers, multi-line cells). The reconciliation check makes a bad parse visible (the summary says so), but to harden this we need a few **anonymised real statements** from the banks you use (CSV and PDF).
- Speed on an iPhone (Mac numbers: answers 3-30 s, summaries 10-20 s).
- Very large statements (thousands of rows), encrypted/password PDFs, multi-currency accounts beyond per-row currency.

## Privacy

Documents live in `Application Support/BolekLolek/documents.json` (iOS file protection until first unlock, needed so a payment logged while the phone is locked still works). Nothing leaves the phone. `delete_document` (asks first) removes one.
