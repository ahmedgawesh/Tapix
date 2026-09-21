=== TapBix Order Tools ===
Contributors: TapBix
Tags: woocommerce, orders, cancellation, email, whatsapp
Requires at least: 6.5
Requires PHP: 8.0
Stable tag: 1.0.1

TapBix-specific WooCommerce order communication tools.

== Features ==

* Cancellation reason field inside the WooCommerce order screen.
* Quick cancellation reason presets in English, Arabic and French.
* Optional mandatory reason for manual admin cancellations.
* Automatic customer cancellation email with the actual reason.
* English / Arabic / French cancellation email copy based on stored order language.
* Captures TapBix site language at checkout when available.
* Support email and WhatsApp included in cancellation messages.
* Optional support block in standard WooCommerce customer emails.
* Displays cancellation reason in My Account order details.
* Manual "Resend cancellation email" button for cancelled orders.
* Duplicate-email protection.
* Settings page under WooCommerce > TapBix Order Tools.
* HPOS compatibility declaration.
* Does not modify TapBix license keys, SKUs, downloads, or license-server logic.

== Installation ==

1. WordPress > Plugins > Add New Plugin > Upload Plugin.
2. Upload tapbix-order-tools.zip.
3. Install and Activate.
4. Open WooCommerce > TapBix Order Tools and verify support details.
5. Test with a non-production order before relying on the workflow.

== Recommended test ==

1. Create a test order using your own email address.
2. Open the order in wp-admin.
3. In TapBix Order Communication choose or enter a cancellation reason.
4. Change status to Cancelled and save/update the order.
5. Confirm the email includes the order number, cancellation reason, support email and WhatsApp.
6. Check My Account > Orders > View to confirm the cancellation reason is visible.

== Changelog ==

= 1.0.1 =
* Initial release.


= 1.0.1 =
* Fixed duplicate cancellation emails by using WooCommerce's built-in Customer cancelled order email instead of sending a second custom email.
* Cancellation reason is injected into the native WooCommerce email.
* Resend action now triggers the native WooCommerce cancellation email.
