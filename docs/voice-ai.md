# Phase 6: Gemini Voice Khata

## Current model selection

The backend uses Google's dedicated `gemini-3.5-transcribe` model for audio-to-text, then `gemini-3.5-flash-lite` with JSON-schema constrained output for transaction extraction. The transcription model documents automatic detection for 85+ languages and code-switching; the extraction step is configured for Gujarati, Hindi, English, Hinglish, and mixed speech. Model names are environment-configurable so they can be changed without editing application code.

Current official standard-tier estimates (USD): transcription is approximately $0.005 per recorded minute; Flash-Lite extraction is $0.30 per million input tokens and $2.50 per million output tokens. Check Google's pricing before production because rates and model availability can change. Google's pricing page currently distinguishes data use by tier: free-tier submissions may be used to improve products, while paid-tier submissions are not. Business audio can contain customer information, so choose the API tier and terms accordingly.

Official references:

- [Audio transcription](https://ai.google.dev/gemini-api/docs/transcribe)
- [Gemini 3.5 Transcribe model](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe)
- [Gemini 3.5 Flash-Lite model](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite)
- [Structured output](https://ai.google.dev/gemini-api/docs/structured-output)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)

## Configuration

Add these values to the local, ignored root `.env` file. Keep the key on the Django server; never add it to Flutter or commit it.

```dotenv
GEMINI_API_KEY=your-google-ai-studio-api-key
GEMINI_TRANSCRIBE_MODEL=gemini-3.5-transcribe
GEMINI_EXTRACTION_MODEL=gemini-3.5-flash-lite
```

The Android application records AAC/M4A locally, then sends the file to Django using the shared JWT `ApiClient`. The backend uploads it to Gemini, transcribes and extracts a proposal, then attempts to delete the temporary Gemini file. Django's temporary audio file is removed when the request ends. Only the transcript, parsed proposal, idempotency hash, and draft relationship are kept in the application's database; the audio bytes are not stored there.

## Voice request flow

1. The authenticated client posts multipart audio to `POST /api/voice/proposals/` with `Idempotency-Key`; `customer_id` is optional.
2. Gemini returns a transcript and schema-constrained extraction. Django validates every field and converts numeric values to `Decimal`.
3. Django exactly matches a spoken customer name against active customers. Unknown or conflicting names require the user to choose a customer through `POST /api/voice/proposals/{id}/customer/`.
4. Product names resolve through `Product` and `ProductAlias`. Applicable `ProductPrice` is selected by transaction date. Python calculates quantity × price; the model is never given responsibility for prices or balances.
5. Django calls the existing simple-entry service to create a `source=voice` **draft**, then calls the existing draft preview service. Ambiguous transaction types, unmatched products, missing rates, and missing amounts create no ledger entry.
6. Flutter displays the transcript and Django preview. The user must explicitly confirm through the existing `POST /api/transactions/{id}/confirm/` action. Until confirmation, this voice flow never posts a ledger entry.

The proposal endpoint is throttled to 20 requests per authenticated user per hour. A repeated idempotency key with the same audio returns the existing proposal; a different audio payload conflicts. Proposal records are scoped to the user who created them.

### Voice endpoints

- `POST /api/voice/proposals/` — upload audio and receive a draft preview or a clarification result.
- `POST /api/voice/proposals/{id}/customer/` — attach a user-selected active customer to an unresolved proposal.
- `GET /api/voice/knowledge/?search=...` — search active business rules and product guidance.
- Existing `GET /api/transactions/{id}/preview/`, `POST /api/transactions/{id}/confirm/`, and `POST /api/transactions/{id}/cancel/` remain the draft workflow.

## Product and business knowledge

The existing `Product`, `ProductPrice`, and `Product.default_unit` tables remain the source of product rates and units. Add speech spellings/translations through the Product Alias inline in Django admin. Add small business rules in the new Business Knowledge admin screen. The initial retrieval is deterministic exact alias lookup plus lexical rule matching; it does not add vector infrastructure or a product catalog UI.

## Database changes awaiting review

No production database migration has been applied. Two new migration files were generated and exercised only by the isolated SQLite test database:

- `catalog.0002_productalias` — creates `catalog_productalias` with alias, language, product foreign key, and a unique alias constraint.
- `voice.0001_initial` — creates `voice_businessknowledge` and `voice_voiceproposal`, with foreign keys to the existing user, customer, and simple Khata draft tables.

These migrations create new tables only. They do not alter, copy, or delete existing Customer, Ledger, product, or price rows. Review them with `python manage.py migrate --plan`; apply to MariaDB only after separately approving the plan.
