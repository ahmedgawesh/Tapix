# TapBix License Server v0.5.2

Production WooCommerce license issuing and offline-first device activation server for TapBix Desktop on Windows and Linux.

## Public sales model

The current public product is the perpetual TapBix Desktop license. It issues one license key with one device initially. A customer who needs more computers buys device capacity for that exact existing license and continues using the same activation code.

| SKU | Purpose | Result |
| --- | --- | --- |
| `TAPBIX-DESKTOP-LIFETIME-1D` | Public lifetime license | New lifetime `tapbix-desktop` key, 1 device |
| `TAPBIX-DESKTOP-ADD-DEVICE` | Capacity add-on | Adds the purchased quantity to one existing eligible license; never issues a key |
| `TAPBIX-WIN-LIFE-1D` | Legacy lifetime product | New lifetime `tapbix-desktop` key, 1 device |
| `TAPBIX-DESKTOP-MONTHLY-1D` | Reserved monthly plan | New monthly `tapbix-desktop` key, 1 device |
| `TAPBIX-DESKTOP-ANNUAL-1D` | Reserved annual plan | New annual `tapbix-desktop` key, 1 device |

All license-issuing SKUs retain Windows and Linux compatibility through product code `tapbix-desktop`.

## Configure WooCommerce

Create a simple virtual WooCommerce product with the exact SKU `TAPBIX-DESKTOP-ADD-DEVICE` and the required per-device price. Configure it as follows:

- Catalog visibility: **Hidden**. The intended entry point is My Account -> TapBix Licenses.
- Purchasable and in stock while add-on sales are enabled.
- Do not enable **Sold individually** if customers should be able to buy quantity 2 or more in one order.
- Do not link downloads or license-delivery automation to this product; the plugin updates an existing license.
- Use normal WooCommerce payment methods. Capacity is applied only through the existing payment-complete/completed order hooks.

Also create or retain the public lifetime product with SKU `TAPBIX-DESKTOP-LIFETIME-1D`. Keep monthly and annual products hidden unless they are intentionally offered later.

## Secure add-device flow

For every eligible active lifetime license, My Account displays a nonce-protected **Add another device** form. The plugin puts only the internal target license ID in private cart/order metadata and shows a masked key for confirmation. It rechecks logged-in ownership, active status, plan, product code, quantity, and order ownership on the server at cart, checkout, and paid-order stages.

A direct or forged purchase of the cheaper add-on SKU without an eligible owned license is rejected. It creates neither a standalone key nor unauthorized capacity.

Each applied add-on line is recorded in the additive `<wp-prefix>tapbix_capacity_transactions` table (normally `wp_tapbix_capacity_transactions`). Its unique `(order_id, order_item_id)` key and the transactional license update guarantee that repeated WooCommerce hooks cannot apply the same capacity twice.

## Refunds and cancellations

- A full or reliable quantity refund of an add-device line reverses only that line's capacity.
- A partial quantity refund reverses only the cumulative refunded quantity exposed by WooCommerce.
- A cancelled add-device order reverses capacity only if that order item was previously applied.
- Every reversal is cumulative and idempotent, and `max_devices` never falls below 1.
- Activations and device history are never automatically deleted. If used devices exceed the reduced allowance, the customer/admin views and audit/order notes surface a warning; new activations remain limited by `max_devices`.
- Refunding or cancelling an add-on does not suspend the base lifetime license.
- Existing v0.4.0 behavior remains for the original license purchase: a full order or fully refunded licensed line may suspend that issued license, and cancellation after issuance may suspend it. Historical records are retained.

## Customer and administrator views

My Account shows the license, plan, status, expiry/Lifetime, active devices, allowed devices, device deactivation controls, over-capacity warnings, and the add-device form where eligible.

Original-license emails contain the activation code, plan, expiry, allowance, and lifetime Windows/Linux wording. Add-device emails clearly state that the existing license allowance changed and that no new activation code was created. Refund/cancellation emails describe a reversal rather than a purchase.

The administrator table shows the existing customer email plus separate customer name and phone columns, with a search box that matches email, name, or phone (including normalized phone digits). It also shows used and maximum devices separately and retains Activate, Suspend, Revoke, Reset devices, and Test activation. The nonce/capability-protected **Set max** control accepts only integers of at least 1, logs old/new values, and never removes activations.

## Upgrade and data safety

1. Back up the WordPress database and the current plugin ZIP.
2. Package the reviewed `tapbix-license-server/` source as version 0.5.2, then upload it in Plugins -> Add Plugin -> Upload Plugin.
3. Choose **Replace current with uploaded**.
4. Open any WordPress page or the REST endpoint so the non-destructive version check creates the rate-limit table before serving requests.
5. Confirm the displayed public key is unchanged and matches TapBix Desktop.
6. Configure the hidden add-device product as described above, then test using a staging customer/order before accepting live payments.

Version 0.5.2 adds an independent rate-limit table and ensures transactional tables use InnoDB. It does not rename, remove, or rewrite licenses, activations, activation tokens, or RSA options. Never delete `tapbix_license_private_key` or `tapbix_license_public_key`. If only half of the key pair exists, the plugin refuses to generate a replacement and displays an administrator warning.

## Renewal integration retained from v0.4.0

When WooCommerce Subscriptions is present and safely identifies a renewal, the matching monthly/annual license expiry is extended instead of issuing an unrelated key. The renewal order stores processed metadata so duplicate hooks cannot extend it twice.

WooCommerce Subscriptions is not required. Another recurring-payment component can identify a paid renewal through:

```php
add_filter('tapbix_license_renewal_source_order_ids', function ($source_order_ids, $renewal_order) {
    // Return original paid WooCommerce order IDs only for a confirmed renewal.
    // Return null for an ordinary purchase.
    return $source_order_ids;
}, 10, 2);
```

The external subscription/payment component remains responsible for charging customers and creating paid renewal orders.

## Activation concurrency and trusted proxies

Device activation locks the license row inside an InnoDB transaction before counting or adding devices, so concurrent requests cannot exceed `max_devices`. Rate limits use atomic database counters with separate per-IP and per-license buckets.

Forwarded IP headers are ignored by default. A site behind a trusted proxy may opt in with both filters below. Never enable a forwarded header without restricting the proxy addresses or CIDR ranges.

```php
add_filter('tapbix_trusted_proxy_header', fn() => 'HTTP_CF_CONNECTING_IP');
add_filter('tapbix_trusted_proxies', fn() => ['203.0.113.0/24', '2001:db8::/32']);
```

Supported header names are `HTTP_CF_CONNECTING_IP`, `HTTP_X_REAL_IP`, and `HTTP_X_FORWARDED_FOR`. Optional filters `tapbix_license_rate_limit_per_ip` and `tapbix_license_rate_limit_per_license` can adjust the defaults of 60 and 20 requests per five minutes.

## Desktop protocol compatibility

- `POST /wp-json/tapbix/v1/activate`
- `POST /wp-json/tapbix/v1/validate`
- Signed payload schema: `2`
- App ID: `com.tapix.pos`
- Offline lease: 7 days
- Revalidation interval: 24 hours

These endpoints, inputs/outputs, activation-token behavior, signed payload, RSA keys, and Windows/Linux compatibility are unchanged from v0.4.0. The private RSA key remains only in WordPress.

## Release review checklist

Before production, verify on staging: base lifetime issuance and duplicate hooks; add-on quantities 1 and 2; targeting the correct one of two licenses; forged/direct add-on rejection; repeated payment/refund/cancel hooks; partial/full add-on refunds; base-license refund suspension; legacy SKU issuance; an existing v0.4.0 activation/validation; and activation on Windows and Linux.

## Changelog

### 0.5.2

- Made device activation capacity checks atomic with an InnoDB license-row lock.
- Added atomic per-IP and per-license request limits without trusting forwarded headers by default.
- Added explicit trusted-proxy CIDR and forwarded-header configuration.

### 0.5.1

- Added separate customer name and phone columns without removing or replacing the existing customer email column.
- Added administrator search by customer email, name, or phone without changing the database schema.

### 0.5.0

- Added secure, targeted, quantity-based lifetime license device-capacity purchases.
- Added exact-once capacity application and exact-once refund/cancellation reversal ledger.
- Added add-device My Account flow, customer email wording, admin visibility/manual allowance control, warnings, and audit events.
- Preserved all v0.4.0 license plans, renewal support, licensing data, RSA and desktop REST protocol behavior.

### 0.4.0

- Added monthly/annual/current lifetime SKU mapping, expiry display, safe base refunds/cancellations, and isolated renewal integration.
