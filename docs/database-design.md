# Database design

## Design goals

- Keep a durable, customer-wise ledger of all debits, credits, and adjustments.
- Support an opening balance when an existing customer is first registered.
- Preserve the historical price and quantity used by each posted sale.
- Keep financial history auditable; posted entries are reversed or adjusted, never silently deleted.
- Keep voice interpretation separate from posting. AI-created transactions remain drafts until a user explicitly confirms them.

MariaDB is the target database. Django models define the schema. Phase 1 migrations have been applied; Phase 2 model changes still need a migration file and database migration.

## Tables and relationships

| Table / Django model | Purpose and important fields |
|---|---|
| `customers.Customer` (`customers_customer`) | Customer identity: name, mobile number, address, notes, active flag, timestamps. |
| `catalog.Product` (`catalog_product`) | Product identity and default unit, such as litre, kg, or piece. |
| `catalog.ProductPrice` (`catalog_productprice`) | Effective-dated product price history. A transaction item also snapshots its applied unit price. |
| `khata.LedgerEntry` (`khata_ledgerentry`) | Customer ledger row with type/status/date, debit and credit amounts, notes, and optional creator. Types include opening balance, sale, Udhaar, Jama, payment, adjustment, and reversal. Draft entries are not included in the posted balance. |
| `khata.KhataTransaction` (`khata_khatatransaction`) | Customer sale, initially draft, with date, source, total, notes, and linked ledger entry after confirmation. |
| `khata.KhataTransactionItem` (`khata_khatatransactionitem`) | Product ID/name snapshot, quantity, unit, unit price snapshot, and calculated line total for a sale. |
| `khata.SimpleKhataEntry` (`khata_simplekhataentry`) | Product-free Udhaar/Jama draft with positive Decimal amount, description, customer, date, source, unique idempotency key, and a link to its posted ledger entry. |
| `payments.Payment` (`payments`) | Receipt from a customer: amount, date, method, reference, and status. |
| `payments.PaymentAllocation` (`payment_allocations`) | Amount of a payment applied to a ledger transaction. Supports partial payments and one receipt covering multiple entries. |
| `voice.VoiceRequest` (`voice_requests`) | Optional transcription/interpretation record: language, transcript, parsed proposal, review status, and linked transaction after confirmation. Avoid storing raw audio unless a separate retention policy is approved. |

Relationships:

- One customer has many khata transactions and payments.
- One khata transaction has one or more item rows; each item refers to one product and snapshots its name, unit, and applied price.
- A confirmed sale has a linked posted debit entry in the customer's ledger. Its total is the sum of rounded line totals.
- A confirmed simple Udhaar creates a debit ledger row; a confirmed Jama creates a credit ledger row. Draft entries have no ledger row and do not affect balances.
- `LedgerEntry.reversal_of` links an opposite posted reversal to its original ledger row. It is unique, so one original can be reversed at most once; the original stays unchanged.
- A payment can be allocated to multiple transactions, and a transaction can have multiple payment allocations.
- A voice request may produce a draft transaction; it is linked to a posted transaction only after explicit user confirmation.

## Opening balance and customer ledger

An opening balance is represented as a dated ledger entry, not as a mutable number on the customer row. During customer setup, the operator can enter an opening amount and whether the customer owes the business (debit) or the business owes the customer (credit). The system records it as a posted `OPENING_BALANCE` entry with its effective date and notes. A zero opening balance requires no ledger row.

The customer ledger is the ordered view of posted transactions and payment credits. Its running balance is calculated from ledger entries, with each row carrying a debit or credit amount. The balance is therefore explainable from the history. Draft transactions do not affect it. Opening balances, sales, payments, adjustments, and reversals remain individually visible.

Recommended integrity rules:

- Use fixed-precision decimal columns for quantities, prices, and money; never binary floating point.
- Validate positive quantities and amounts where appropriate, and store a currency convention consistently (initially INR).
- Calculate line totals and transaction totals on the server using decimal arithmetic.
- Round each line total to two decimal places using decimal half-up rounding, then sum the rounded lines.
- Snapshot unit prices on transaction items so later price changes cannot rewrite history.
- Use database transactions when posting a sale or allocating a payment so partial writes cannot leave inconsistent ledger state.
- Add indexes for customer/date ledger queries and a uniqueness rule for normalized mobile numbers if the business confirms numbers are unique per customer.

## Posting, reversal, and deletion policy

Posted ledger rows are immutable in normal application workflows. Do not expose a delete operation for posted transactions, payment receipts, or allocations. The current ledger model blocks instance and queryset deletion of posted entries and rejects edits after posting. To correct a posted event, create a linked reversal or adjustment entry with a reason and actor, then post the corrected entry if needed. Drafts may be discarded before posting. Database retention and administrative correction procedures should be documented before production use.

## Voice confirmation workflow

1. Record the selected language and transcription/LLM proposal as a reviewable draft.
2. Resolve the intended customer and products, and calculate a preview on the backend.
3. Show customer, items, quantities, prices, and total to the user.
4. Require an explicit confirmation action before creating/posting the financial ledger entry.
5. Store the confirmed result and link it to the voice request for traceability.

Gujarati, Hindi, English, and Hinglish recognition are input concerns. They must not change the canonical customer, product, amount, or ledger rules.

## Phase boundary

Phase 1 customer records, opening-balance capture, and read-only ledger viewing are implemented and migrated. Phase 2 product pricing, draft sales, server-side calculations, confirmation, ledger posting, and simple Udhaar/Jama APIs are implemented in backend code. Phase 2 migration files have been generated for review but have not been applied. Payments, voice processing, and the Flutter client remain for later phases.

Simple Udhaar/Jama API drafts, explicit posting, idempotency, linked reversals, customer history/balance, and dashboard/report views are being added in Phase 2. These model changes require a new migration. Do not apply it until the migration plan has been reviewed and approved. Dashboard Udhaar/Jama totals represent posted sale/Udhaar and payment/Jama activity net of linked reversals; outstanding balance is calculated from every posted debit minus every posted credit, including opening balances and corrections.
