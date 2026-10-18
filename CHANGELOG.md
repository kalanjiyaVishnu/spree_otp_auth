# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the gem uses
[Semantic Versioning](https://semver.org/). While the version is 0.x, a minor
bump may change the public API; such changes are listed under **Breaking**.

## 0.2.0 — Unreleased

### Breaking

- Codes are delivered through `spree_notification_providers` (`~> 0.1`, new
  dependency). Configure providers, credentials and the **Login code**
  template in Admin → Settings → Notification providers.
- Removed `Spree::Otp::Provider::*` (Email, Msg91Sms, Msg91Whatsapp,
  GupshupWhatsapp), `Spree::Otp::WhatsappSettings` and
  `Spree::Otp::Delivery.provider_for`; use `Spree::Otp::Delivery.deliver`.
- Removed the MSG91 fields from the OTP admin page and the `effective_msg91_*`
  readers on `Spree::OtpConfiguration`.
- The Gupshup webhook (`POST /webhooks/gupshup`) moved to
  `spree_notification_providers` and checks each store's own webhook secret;
  `GUPSHUP_API_KEY` and `GUPSHUP_WEBHOOK_SECRET` are no longer read.
- The synthetic email domain is configurable
  (`SpreeOtpAuth.synthetic_email_domain`, default `@guest.example.invalid`).

### Added

- SMS as a primary login channel (any SMS provider).
- `Spree::Otp::DeliveryFailedSubscriber`: a provider's later failure report
  sends the email backup.
- `spree_otp_attempts.delivery_message_ref` links an attempt to its Delivery
  log rows.

### Changed

- A send whose outcome is unknown (for example a timeout after the request
  went out) is not resent or switched to email.

## 0.1.0

- Initial in-repo version: mobile-first OTP login over WhatsApp (Gupshup) with
  email backup, marketing consent at login, store-scoped admin settings.
