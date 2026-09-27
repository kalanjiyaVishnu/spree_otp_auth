# spree_otp_auth

Enterprise-grade, passwordless One-Time Password (OTP) authentication engine for Spree Commerce and headless storefronts (Next.js / Store API v3).

Designed for modern e-commerce architectures where checkout friction must be minimized while capturing mandatory customer phone numbers for fulfillment, complying with local telecom regulations, and eliminating password reuse vulnerabilities.

---

## Features

- **Passwordless Customer Auth**: Pure Email OTP flow via single-field input with adaptive progressive disclosure for mandatory phone capture. No passwords to remember or reset.
- **Adaptive Progressive Mobile Capture**:
  - Existing users with verified mobile numbers proceed directly to Email OTP.
  - New users or accounts missing a phone number are prompted inline for their mobile number before the OTP is dispatched.
  - Mobile numbers are staged on the OTP attempt and confirmed atomically upon successful 6-digit OTP verification.
- **Mandatory Login & Phone Gate at Checkout**:
  - Guest shoppers attempting to check out are redirected to authentication; carts and promotional discounts are merged seamlessly upon login.
  - Checkout cannot advance to the payment step without a validated, confirmed mobile phone number.
- **Transactional Email Templates**:
  - Store-scoped integration with `/admin/email_templates` (`Spree::EmailTemplate`).
  - Supports dynamic variable interpolation: `{{otp_code}}`, `{{store_name}}`, `{{expiry_minutes}}`.
  - Automatic fallback to built-in responsive HTML mailer if unassigned or rendering fails.
- **Store-Scoped Multi-Tenant Configuration**: Every store can independently choose its primary channel (`email`, `mobile`, `whatsapp`), fallback channel policy (`none`, `whatsapp`, `sms`, `email`), email template, code length (4 or 6 digits), expiry windows, and credentials.
- **Encrypted Credentials at Rest**: MSG91 authentication keys are encrypted using Rails `ActiveRecord::Encryption` and masked (`••••••••`) in the Spree Admin UI.
- **Strict Cross-Account Mobile Uniqueness**: Prevents two accounts from claiming the same phone number (returns HTTP 409 Conflict).
- **Production-Ready Rate Limiting**: Built-in sliding-window limiter on request, resend, and verification attempts to eliminate brute-force and spam attacks.

---

## Architecture Overview

```
                      +-----------------------------------+
                      |      Headless Storefront          |
                      |  (Next.js / React Design Tokens)  |
                      +-----------------+-----------------+
                                        |
                            Store API v3 REST JSON
                                        |
                                        v
                 +---------------------------------------------+
                 |            spree_otp_auth Engine            |
                 |                                             |
                 |  Controllers:                               |
                 |   - Spree::Api::V3::Store::OtpController    |
                 |   - Spree::Admin::OtpConfigurationsController|
                 |                                             |
                 |  Services:                                  |
                 |   - Spree::Otp::Generate                    |
                 |   - Spree::Otp::Verify                      |
                 |   - Spree::Otp::Resend                      |
                 |   - Spree::Otp::RateLimiter                 |
                 |                                             |
                 |  Providers:                                 |
                 |   - Base < Email (Spree::OtpMailer)         |
                 |   - Base < Msg91Sms                         |
                 |   - Base < Msg91Whatsapp                    |
                 +---------------------------------------------+
```

---

## Installation

Add this engine to your Spree application's `Gemfile`:

```ruby
gem 'spree_otp_auth', path: 'engines/spree_otp_auth'
```

Install and run the migrations:

```bash
bundle install
bin/rails g spree_otp_auth:install
bin/rails db:migrate
```

The installer:
1. Copies database migrations for `spree_otp_configurations` and `spree_otp_attempts`.
2. Adds `fallback_channel` and `email_template_id` to `spree_otp_configurations`.
3. Adds `staged_mobile_number` to `spree_otp_attempts`.
4. Adds `mobile_number` and `mobile_confirmed_at` to `spree_users`.

---

## Store Configuration & Admin UI

Navigate to **Spree Admin → Settings → OTP Authentication**:

1. **Primary Verification Channel**:
   - `email`: Sends OTP via email templates (default for current phase).
   - `mobile`: Sends OTP via SMS using MSG91 DLT templates.
   - `whatsapp`: Directly sends OTP via WhatsApp.
2. **Fallback Verification Channel**:
   - `none`: No fallback.
   - `whatsapp`: WhatsApp fallback button becomes available after delay.
   - `sms`: SMS fallback.
   - `email`: Email fallback.
3. **Transactional Email Template**:
   - Select an existing template configured under `/admin/email_templates` (`Spree::EmailTemplate`).
   - Supports `{{otp_code}}`, `{{store_name}}`, `{{expiry_minutes}}` interpolation.
   - Default option: built-in responsive OTP mailer.
4. **Timing Configurations**:
   - `otp_length`: 6 digits (recommended) or 4 digits.
   - `otp_expiry_seconds`: Token validity lifetime (minimum 60s, default 600s).
   - `resend_cooldown_seconds`: Cooldown before resend button activates (default 30s).
   - `fallback_delay_seconds`: Delay before secondary fallback option displays (default 20s).
5. **Provider Credentials (MSG91)**:
   - `MSG91 Auth Key`: Encrypted in database, masked in UI.
   - `Sender ID`: 6-character registered DLT header (e.g. `ONTODI`).
   - `SMS OTP Template ID`: DLT approved transactional flow ID.
   - `WhatsApp OTP Template ID`: Meta/MSG91 integrated template ID.

---

## REST API Reference

All customer endpoints reside under `/api/v3/store/otp`:

### 1. Request OTP (Adaptive Progressive Disclosure)
- **URL**: `POST /api/v3/store/otp/request`
- **Headers**: `X-Spree-Publishable-Key: <key>`, `Content-Type: application/json`
- **Step 1 (Email submitted without mobile for new/unlinked user)**:
  ```json
  { "identifier": "new.user@example.com" }
  ```
  **Response (200 OK)**:
  ```json
  {
    "data": {
      "requires_mobile": true,
      "message": "Mobile number is required to continue."
    }
  }
  ```
- **Step 2 (Email submitted with mobile)**:
  ```json
  {
    "identifier": "new.user@example.com",
    "mobile_number": "+919876543210"
  }
  ```
  **Response (200 OK)**:
  ```json
  {
    "data": {
      "requires_mobile": false,
      "channel": "email",
      "masked_target": "n***r@example.com",
      "otp_length": 6,
      "cooldown_seconds": 30,
      "fallback_available_after_seconds": 20
    }
  }
  ```
- **Duplicate Phone Collision (409 Conflict)**:
  ```json
  {
    "error": {
      "code": "phone_already_registered",
      "message": "This mobile number is already linked to another account."
    }
  }
  ```

### 2. Verify OTP
- **URL**: `POST /api/v3/store/otp/verify`
- **Body**:
  ```json
  {
    "identifier": "new.user@example.com",
    "code": "491823"
  }
  ```
- **Response (200 OK)**:
  ```json
  {
    "token": "eyJhbGciOi...",
    "refresh_token": "rf_...",
    "user": {
      "id": "usr_...",
      "email": "new.user@example.com",
      "mobile_number": "+919876543210",
      "mobile_confirmed_at": "2026-09-27T12:00:00Z"
    }
  }
  ```

### 3. Resend OTP
- **URL**: `POST /api/v3/store/otp/resend`
- **Body**:
  ```json
  { "identifier": "shopper@example.com" }
  ```
- **Rate Limit Response (429 Too Many Requests)**:
  ```json
  {
    "error": {
      "code": "cooldown_active",
      "message": "Please wait 24 seconds before requesting another code.",
      "retry_after_seconds": 24
    }
  }
  ```

### 4. Trigger WhatsApp Fallback
- **URL**: `POST /api/v3/store/otp/whatsapp`
- **Body**:
  ```json
  { "identifier": "shopper@example.com" }
  ```

### 5. Link / Update Mobile Number
- **URL**: `PATCH /api/v3/store/otp/customer/mobile`
- **Headers**: `Authorization: Bearer <customer_jwt>`
- **Body**:
  ```json
  { "mobile_number": "9876543210" }
  ```
- **Conflict Response (409 Conflict)**:
  ```json
  {
    "error": {
      "code": "mobile_already_registered",
      "message": "This mobile number is already linked to another account. Please sign in with that account."
    }
  }
  ```

---

## Running Test Suite

```bash
# Run engine RSpec specs (in Docker)
docker compose exec -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres@postgres:5432/spree_test web bundle exec rspec engines/spree_otp_auth/spec

# Run storefront Vitest specs
cd apps/storefront
npm test
```

---

## License

Released under the [MIT License](LICENSE).
