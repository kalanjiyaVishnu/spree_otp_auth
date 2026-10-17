# spree_otp_auth

Passwordless One-Time Password (OTP) authentication engine for Spree Commerce and headless storefronts (Next.js / Store API v3).

Customers sign in with their mobile number and receive the code on WhatsApp (via Gupshup). Email is the backup channel. News-and-offers consent is captured during login, not at checkout.

---

## Features

- **Mobile-first, passwordless login**: the customer enters a mobile number; the code arrives on WhatsApp using the approved `verify_otp` template.
- **Email collected once**: new numbers, or accounts without a real email (synthetic `…@guest.ontodi.local` addresses count as none), are asked for an email inline before the code is sent.
- **Safe account linking**: a new number plus the email of an existing email-only account needs both the WhatsApp code and a second code sent to that email. An email already linked to a different mobile is rejected (409).
- **Email backup** (on by default, admin can turn it off):
  - automatic when Gupshup rejects the send, or later reports the message `failed` through the delivery callback (for example, number not on WhatsApp);
  - on demand via "Send code by email instead" after the resend wait.
  - Not used when linking a number to an email-only account (the WhatsApp code is the proof of the phone).
- **Only the newest code works**: resends, email-instead and automatic fallback expire the previous code.
- **News-and-offers consent at login**: ticked by default beside the email field for new customers; shown on the code screen for returning customers who aren't subscribed (unticked if they opted out before); hidden for subscribers.
- **Store-scoped configuration** in Spree Admin with a test-send button.
- **Rate limiting**: resend cooldown and 5 codes per number per hour, applied to every channel.
- **No secrets in the database, admin UI or logs**: the Gupshup key lives only in the environment; codes are stored as salted SHA-256 digests.

---

## Architecture Overview

```
Storefront (Next.js)                       spree_otp_auth engine
--------------------                       -------------------------------------------
UnifiedAuthForm  ── POST /otp/request ───▶ Spree::Otp::Generate
OtpVerificationInput                          ├─ Delivery.provider_for(channel)
  ├─ POST /otp/verify ───────────────────▶   │    ├─ Provider::GupshupWhatsapp ──▶ Gupshup API
  ├─ POST /otp/resend                        │    ├─ Provider::Email (Spree::OtpMailer)
  ├─ POST /otp/fallback ─────────────────▶   │    └─ Provider::Msg91Sms (legacy SMS)
  └─ POST /otp/status (polls ≤60s)           └─ Spree::Otp::Fallback (email backup)
                                           Spree::Otp::Verify ─▶ Spree::Otp::MarketingConsent
Gupshup ── POST /webhooks/gupshup?secret= ▶ Spree::Webhooks::GupshupController ─▶ Fallback
Admin ──── /admin/otp_configuration ─────▶ Spree::Admin::OtpConfigurationsController
```

---

## Installation

```ruby
gem 'spree_otp_auth', path: 'engines/spree_otp_auth'
```

```bash
bundle install
bin/rails g spree_otp_auth:install
bin/rails db:migrate
```

Migrations add `spree_otp_configurations` (channels, timings, Gupshup settings), `spree_otp_attempts` (code digests, staged mobile/email, purpose, delivery status, Gupshup message id), and `mobile_number`, `mobile_confirmed_at` and `email_marketing_decided_at` on `spree_users`. The consent migration back-fills customers with a verified newsletter subscription as subscribed.

---

## Gupshup setup

### Environment variables

| Variable | Purpose |
|---|---|
| `GUPSHUP_API_KEY` | Gupshup account API key. Read only from the environment; never stored, shown or logged. Without it, non-production environments simulate delivery and production refuses to send. |
| `GUPSHUP_WEBHOOK_SECRET` | Random string (`openssl rand -hex 24`) that authenticates Gupshup's delivery callbacks. |

### Steps

1. Approve a WhatsApp **authentication** template named `verify_otp` in Gupshup whose only variable is the code.
2. Spree Admin → **OTP Authentication**: fill in the business WhatsApp number, Gupshup app name and app ID (template name defaults to `verify_otp`; a template ID can override the lookup). Save with the channel still on **Email**.
3. Use **Send test WhatsApp**. A success flash shows Gupshup's message ID. If it reports a template or parameter error, the approved template needs more than one variable or a button parameter; fix the template before going live.
4. Switch the channel to **WhatsApp** and keep **Email backup** on. The switch is refused until every requirement (key, number, app name, app ID or template ID) is present.
5. In the Gupshup app's callback settings, set:

   ```
   https://<api-host>/webhooks/gupshup?secret=<GUPSHUP_WEBHOOK_SECRET>
   ```

   The secret is a query parameter so Rails' `filter_parameters` masks it in logs. Without the callback, only immediate send errors trigger the automatic email backup; customers can still choose "Send code by email instead".

Rollback: set the channel back to **Email**. Codes go to the account's email from the next request, with no deploy.

### How sending works

- `POST https://api.gupshup.io/wa/api/v1/template/msg` (form-encoded, `apikey` header) with `channel=whatsapp`, `source`, `destination`, `src.name` and `template={"id":"<uuid>","params":["<code>"]}`.
- The template UUID is looked up by name via `GET /wa/app/{app_id}/template` and cached for 12 hours per store; saving the admin form clears the cache.
- Timeouts are 5 seconds. A `2xx` with `status: "submitted"` means Gupshup accepted the message, not that it was delivered.

---

## Store Configuration (Spree Admin → OTP Authentication)

| Setting | Notes |
|---|---|
| Primary channel | WhatsApp (Gupshup) or Email. Legacy Mobile SMS stays listed only if already selected. |
| Email backup | `fallback_channel` `email` (default) or `none`. |
| Gupshup number / app name / app ID / template name / template ID | See setup above. |
| API key status | Configured / Missing, from `GUPSHUP_API_KEY`. |
| Delivery callback URL | Shown with the secret masked except its last 4 characters. |
| Email template | Store email template with `{{otp_code}}`, `{{store_name}}`, `{{expiry_minutes}}`, used for email codes; defaults to the built-in mailer. |
| Timings | Code length (4/6), expiry (≥60s), resend cooldown (≥10s; also when "email instead" unlocks). |
| MSG91 (SMS only) | Auth key (encrypted), sender ID, SMS template ID. |

---

## REST API Reference

All customer endpoints are under `/api/v3/store/otp` and need the publishable key header. Full contract: `specs/017-whatsapp-otp-marketing-consent/contracts/otp-api-v3.yaml`.

### Request a code — `POST /request`

```json
{ "identifier": "9876543210" }
```

New number or no real email on the account:

```json
{ "data": { "requires_email": true, "show_marketing_consent": true, "marketing_consent_default": true } }
```

Send again with `"email": "new@example.com"`. Code sent:

```json
{
  "data": {
    "requires_email": false,
    "requires_email_code": false,
    "channel": "whatsapp",
    "masked_target": "+91 98*** **210",
    "masked_email": null,
    "auto_fallback": false,
    "otp_length": 6,
    "cooldown_seconds": 30,
    "email_fallback_available": true,
    "show_marketing_consent": false,
    "marketing_consent_default": true
  }
}
```

Errors: `409 email_linked_to_other_mobile` / `phone_already_registered`, `422 invalid_phone` / `invalid_email` / `delivery_failed`, `429 cooldown_active` / `hourly_limit_exceeded` (with `retry_after_seconds`).

Identifiers containing `@` keep the older email-first flow (`requires_mobile`).

### Verify — `POST /verify`

```json
{ "identifier": "9876543210", "code": "491823", "email_code": "120934", "accept_marketing": true }
```

`email_code` only when `requires_email_code` was true. `accept_marketing` only when the consent box was shown; omit it to leave consent unchanged. Returns `token`, `refresh_token` and `user` (including `accepts_email_marketing`). Errors: `401 invalid_otp` / `invalid_email_code`, `429 max_attempts_exceeded`.

### Resend — `POST /resend`

`{ "identifier": "9876543210" }`. Resends on the latest attempt's channel.

### Email instead — `POST /fallback`

`{ "identifier": "9876543210" }`. Errors: `404 email_fallback_disabled`, `422 no_email_on_account`, `429 cooldown_active`.

### Where did the code go — `POST /status`

`{ "identifier": "9876543210" }` → `{ "data": { "channel": "email", "masked_target": "a***a@example.com", "delivery_status": "fallback_sent" } }`. POST keeps the phone number out of URLs and access logs.

### Link / update mobile — `PATCH /customer/mobile`

Authenticated; unchanged.

### Gupshup callback — `POST /webhooks/gupshup?secret=…`

Handles `message-event` payloads of type `failed` for message IDs the store issued; everything else gets `200` and is ignored. A wrong or missing secret gets `404`.

---

## Running the tests

```bash
# Engine specs (inside the web container)
docker exec -e RAILS_ENV=test ecom-web-1 bash -lc 'cd /rails && bundle exec rspec engines/spree_otp_auth/spec'

# Storefront
cd apps/storefront && npm test
```

Engine specs blank `GUPSHUP_API_KEY` by default and stub Gupshup HTTP (`spec/support/gupshup_helpers.rb`), so they never send real messages even when the container has a real key.

---

## License

Released under the [MIT License](LICENSE).
