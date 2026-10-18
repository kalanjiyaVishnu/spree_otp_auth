# spree_otp_auth

Passwordless One-Time Password (OTP) authentication engine for Spree Commerce and headless storefronts (Next.js / Store API v3).

Customers sign in with their mobile number and receive the code on WhatsApp or SMS; email is the backup channel. Codes are delivered through [spree_notification_providers](../spree_notification_providers/README.md), so the store chooses the providers (Gupshup, MSG91, or its own) and their priority there. News-and-offers consent is captured during login, not at checkout.

---

## Features

- **Mobile-first, passwordless login**: the customer enters a mobile number; the code arrives on the store's chosen channel (WhatsApp, SMS or email).
- **Any provider, in priority order**: delivery goes through spree_notification_providers. A provider that definitely fails moves the code to the next one; a send that may have gone out is never repeated.
- **Email collected once**: new numbers, or accounts without a real email (synthetic `…<SpreeOtpAuth.synthetic_email_domain>` addresses count as none), are asked for an email inline before the code is sent.
- **Safe account linking**: a new number plus the email of an existing email-only account needs both the phone code and a second code sent to that email. An email already linked to a different mobile is rejected (409).
- **Email backup** (on by default, admin can turn it off):
  - automatic when no provider can send the code, or when a provider later reports it `failed` (for example, number not on WhatsApp);
  - on demand via "Send code by email instead" after the resend wait.
  - Not used when linking a number to an email-only account (the phone code is the proof of the phone).
- **Only the newest code works**: resends, email-instead and automatic fallback expire the previous code.
- **News-and-offers consent at login**: ticked by default beside the email field for new customers; shown on the code screen for returning customers who aren't subscribed (unticked if they opted out before); hidden for subscribers.
- **Store-scoped configuration** in Spree Admin.
- **Rate limiting**: resend cooldown and 5 codes per number per hour, applied to every channel.
- **No codes in the database or logs**: codes are stored as salted SHA-256 digests; provider secrets are stored encrypted by spree_notification_providers.

---

## Architecture Overview

```
Storefront (Next.js)                       spree_otp_auth                       spree_notification_providers
--------------------                       --------------------------------     ----------------------------
UnifiedAuthForm  ── POST /otp/request ───▶ Spree::Otp::Generate
OtpVerificationInput                          └─ Spree::Otp::Delivery ─────────▶ deliver(type: :otp_code)
  ├─ POST /otp/verify ───────────────────▶ Spree::Otp::Verify                     ├─ Gupshup / MSG91 / …
  ├─ POST /otp/resend                                                             └─ Delivery log
  ├─ POST /otp/fallback ─────────────────▶ Spree::Otp::Fallback ─▶ Spree::OtpMailer (deliver_later)
  └─ POST /otp/status (polls ≤60s)
Provider callback ─────────────────────────────────────────────────────────────▶ notification.delivery_failed
                                           Spree::Otp::DeliveryFailedSubscriber ◀┘ (email backup)
Admin ──── /admin/otp_configuration ─────▶ Spree::Admin::OtpConfigurationsController
```

---

## Installation

Install spree_notification_providers first (this gem depends on it), then:

```ruby
gem 'spree_notification_providers', '~> 0.1'
gem 'spree_otp_auth', '~> 0.2'
```

```bash
bundle install
bin/rails g spree_notification_providers:install
bin/rails g spree_otp_auth:install
bin/rails db:migrate
```

Migrations add `spree_otp_configurations` (channels and timings), `spree_otp_attempts` (code digests, staged mobile/email, purpose, delivery status, provider message id and delivery reference), and `mobile_number`, `mobile_confirmed_at` and `email_marketing_decided_at` on `spree_users`. The consent migration back-fills customers with a verified newsletter subscription as subscribed.

Set the placeholder email domain for accounts created from a mobile number alone (default `@guest.example.invalid`):

```ruby
# config/initializers/spree_otp_auth.rb
SpreeOtpAuth.synthetic_email_domain = '@guest.example.local'
```

---

## Delivery providers

This gem registers the `otp_code` message type ("Login code"). Configure the providers in **Spree Admin → Settings → Notification providers**:

1. **WhatsApp** tab: add Gupshup (or MSG91), fill in its inputs and, under *Templates*, the **Login code** template (for Gupshup, an approved authentication template whose only variable is the code, by name or UUID). Use **Send test**, then enable it.
2. **SMS** tab (optional): add MSG91 with the DLT-approved OTP template as **Login code**.
3. Order providers per channel; the next one is tried only when a provider definitely did not take the code.
4. For Gupshup delivery callbacks, set the provider's **Webhook secret** and point the Gupshup app at `https://<api-host>/webhooks/gupshup?secret=<webhook secret>`. Without callbacks, only immediate send failures trigger the automatic email backup.

Then **Spree Admin → OTP Authentication**: each channel shows **Ready** or what is missing, with a link to its providers. Switching the primary channel to WhatsApp or SMS is refused until a provider can send login codes.

Rollback: set the channel back to **Email**. Codes go to the account's email from the next request, with no deploy.

---

## Store Configuration

**Spree Admin → OTP Authentication** (per store):

| Setting | Notes |
|---|---|
| Primary channel | WhatsApp, SMS or Email. |
| Email backup | `fallback_channel` `email` (default) or `none`. |
| Channel status | Ready, or Not set up with what's missing; links to Notification providers. |
| Email template | Store email template with `{{otp_code}}`, `{{store_name}}`, `{{expiry_minutes}}`, used for email codes; defaults to the built-in mailer. |
| Timings | Code length (4/6), expiry (≥60s), resend cooldown (≥10s; also when "email instead" unlocks), fallback option delay. |

Provider credentials and templates are not stored here. The old `msg91_*` / `gupshup_*` columns are read only by the 0.2 upgrade import and are dropped in a later version.

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

### Delivery failure reports

Provider callbacks (for example Gupshup's `POST /webhooks/gupshup?secret=…`) are handled by spree_notification_providers, which publishes `notification.delivery_failed`. This gem subscribes to it and sends the email backup.

---

## Running the tests

```bash
# Inside the host app's web container
docker exec -e RAILS_ENV=test ecom-web-1 bash -lc 'cd /rails && bundle exec rspec engines/spree_otp_auth/spec'

# Standalone (generates spec/dummy with spree_dev_tools)
bundle exec rake test_app
bundle exec rspec
```

Specs stub provider HTTP through `SpreeNotificationProviders::Http` (`spec/support/gupshup_helpers.rb`), so they never send real messages.

---

## License

Released under the [BSD 3-Clause License](LICENSE).
