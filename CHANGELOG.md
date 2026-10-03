# CNKH POS Mobile change log

## 1.10.9+37 — unreleased (build and publish blocked)

- **B001 (Both)** Read the installed Version and Build Number in About instead of maintaining duplicate Dart constants.
- **B002 (Mobile)** Await product image writes so filesystem failures remain inside the existing sync recovery path.
- **B003 (Both CI)** Update paired repository refs to the current companion main commits.

Source candidate only; no APK or Windows package was produced or published. Current downloads remain Mobile 1.10.7+35 and Desktop 1.10.8+36.

## 1.10.8+36 — unreleased (APK pending matching signing key)

- **B01** Clear a previous customer-directory phone on customer change/cancel while preserving a manually entered temporary number for the saved sale and eReceipt recipient.
- **B02** Reuse compatible supplier OCR unit conversion memory and keep base-unit stock/cost values in the purchase sync payload; require review for unit conflicts and honor manual edits.
- **B04** Merge only unmapped matching customers/suppliers; keep immutable remote identity mappings and historical references when Desktop deletes and recreates an entity.
- **B05** Block transaction cleanup while purchase, OCR attachment, or purchase-reversal outbox requests remain unresolved, including an ACK-lost request; keep unrelated catalog operations.
- **B06** Persist a click-time held-cart snapshot, guard duplicate submits, and clear only an unchanged cart after success.
- **B07** Apply exact barcode precedence and deterministic ID ordering in SQL before product pagination.
- **B08** Persist Desktop tax-state sale-void rejections as `needs_review`, allow safe independent operations to proceed, and retain the original operation ID for an explicitly reviewed retry.
- **B09** Refresh catalog/category/image settings in the retained cart screen without repricing cart snapshots or replacing manual discounts.
- **B10 / R03** Use bundled Noto Sans SC and multi-page 80 mm receipt layout for Chinese content and long receipts.

MyInvois signing changes are not included. Latest official requirements and an independent verifier remain necessary to resolve R02. No production submission or cancellation was performed.

## Ongoing maintenance

For each future build, update `version` in `pubspec.yaml` and add the real changes to this file. About reads Version + Build Number from installed package metadata; do not add a second version constant. Keep prior release entries. `test/app_version_test.dart` checks the runtime label and changelog version.
