# TapBix License Server v0.3.0

Secure desktop activation server for TapBix Windows and Linux.

## New in v0.3.0

- Implements the Flutter desktop activation protocol (schema 2).
- Supports tapbix-desktop, tapbix-windows, and tapbix-linux products.
- Returns a per-device activation token after first activation.
- Stores only the SHA-256 digest of each activation token in WordPress.
- Validates devices with license_id, activation_token, device_id, and platform.
- Issues signed offline leases valid for 7 days and requests online refresh after 24 hours.
- Preserves the existing RSA key pair and existing licenses during upgrade.
- Existing activations must activate once again so a secure token can be issued.

## Upgrade

1. Back up the WordPress database.
2. Upload this ZIP from WordPress -> Plugins -> Add Plugin -> Upload Plugin.
3. Choose Replace current with uploaded.
4. Open WordPress Admin -> TapBix Licenses. This triggers the database migration.
5. Confirm the displayed public key is the same key embedded in the Flutter app.

Do not delete the tapbix_license_private_key or tapbix_license_public_key options. Replacing the key pair invalidates every signed offline license already issued.

## Linux end-to-end test

1. Open WordPress Admin -> TapBix Licenses.
2. Click Create Test License.
3. Copy the generated TBX key from the TEST row.
4. If you previously clicked the internal test action, click Reset devices before using the key in Flutter because test licenses allow one device by default.
5. Start the TapBix Linux application and enter the copied key.
6. Close and reopen the app: it should load from the signed offline lease without asking for the key again.
7. In WordPress, use Revoke and trigger an online validation to verify revocation handling.

The Test activation action remains available and now verifies RSA-SHA256 plus the desktop schema-2 fields. It uses a fake device and therefore consumes the single device slot until Reset devices is clicked.

## REST contract

- POST /wp-json/tapbix/v1/activate
  - Input: license_key, device_id, device_name, platform, app_version
  - Output: ok, license_id, activation_token, license
- POST /wp-json/tapbix/v1/validate
  - Input: license_id, activation_token, device_id, platform, app_version
  - Output: ok, license

The RSA private key never leaves WordPress. The Flutter application contains only the public key.
