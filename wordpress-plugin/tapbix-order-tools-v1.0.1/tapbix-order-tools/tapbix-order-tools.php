<?php
/**
 * Plugin Name: TapBix Order Tools
 * Plugin URI: https://tapixsolutions.com/
 * Description: TapBix order communication tools for WooCommerce: cancellation reasons in the native customer email, multilingual support details, WhatsApp contact, and order-language tracking.
 * Version: 1.0.1
 * Author: TapBix
 * Text Domain: tapbix-order-tools
 * Requires at least: 6.5
 * Requires PHP: 8.0
 * WC requires at least: 8.0
 * WC tested up to: 11.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

final class TapBix_Order_Tools {
    const VERSION      = '1.0.1';
    const OPTION_KEY   = 'tapbix_order_tools_settings';
    const META_REASON  = '_tapbix_cancellation_reason';
    const META_LANG    = '_tapbix_order_lang';
    const META_SENT    = '_tapbix_cancel_email_hash';
    const META_SENT_AT = '_tapbix_cancel_email_sent_at';

    private static $instance = null;

    public static function instance() {
        if ( null === self::$instance ) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action( 'before_woocommerce_init', array( $this, 'declare_hpos_compatibility' ) );
        add_action( 'plugins_loaded', array( $this, 'boot' ) );
    }

    public function declare_hpos_compatibility() {
        if ( class_exists( '\\Automattic\\WooCommerce\\Utilities\\FeaturesUtil' ) ) {
            \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility( 'custom_order_tables', __FILE__, true );
        }
    }

    public function boot() {
        if ( ! class_exists( 'WooCommerce' ) ) {
            add_action( 'admin_notices', array( $this, 'woocommerce_missing_notice' ) );
            return;
        }

        add_action( 'admin_menu', array( $this, 'register_settings_page' ), 99 );
        add_action( 'admin_init', array( $this, 'maybe_save_settings' ) );

        add_action( 'add_meta_boxes_shop_order', array( $this, 'add_order_meta_box_legacy' ) );
        add_action( 'add_meta_boxes_woocommerce_page_wc-orders', array( $this, 'add_order_meta_box_hpos' ) );
        add_action( 'woocommerce_process_shop_order_meta', array( $this, 'save_order_meta_box' ), 20, 1 );
        add_action( 'save_post_shop_order', array( $this, 'save_order_meta_box_legacy_fallback' ), 20, 3 );
        add_action( 'woocommerce_before_order_object_save', array( $this, 'require_reason_before_manual_cancel' ), 5, 1 );

        add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_order_script' ) );
        add_action( 'admin_notices', array( $this, 'admin_email_notice' ) );
        add_action( 'admin_post_tapbix_resend_cancel_email', array( $this, 'handle_resend_cancel_email' ) );

        add_action( 'woocommerce_checkout_create_order', array( $this, 'capture_checkout_language' ), 10, 2 );
        add_action( 'woocommerce_store_api_checkout_update_order_meta', array( $this, 'capture_store_api_language' ), 10, 1 );


        add_action( 'woocommerce_order_details_after_order_table', array( $this, 'show_reason_in_my_account' ), 20, 1 );
        add_action( 'woocommerce_email_after_order_table', array( $this, 'append_support_to_customer_emails' ), 30, 4 );
    }

    public function woocommerce_missing_notice() {
        if ( current_user_can( 'activate_plugins' ) ) {
            echo '<div class="notice notice-error"><p><strong>TapBix Order Tools</strong> requires WooCommerce to be active.</p></div>';
        }
    }

    private function defaults() {
        return array(
            'support_email'          => 'support@tapixsolutions.com',
            'whatsapp'               => '201552600646',
            'require_reason'         => 'yes',
            'include_cancel_reason_email' => 'yes',
            'append_support_details' => 'yes',
        );
    }

    private function settings() {
        $saved = get_option( self::OPTION_KEY, array() );
        return wp_parse_args( is_array( $saved ) ? $saved : array(), $this->defaults() );
    }

    public function register_settings_page() {
        add_submenu_page(
            'woocommerce',
            'TapBix Order Tools',
            'TapBix Order Tools',
            'manage_woocommerce',
            'tapbix-order-tools',
            array( $this, 'render_settings_page' )
        );
    }

    public function maybe_save_settings() {
        if ( empty( $_POST['tapbix_order_tools_save'] ) ) {
            return;
        }
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            return;
        }
        check_admin_referer( 'tapbix_order_tools_save_settings' );

        $email    = isset( $_POST['support_email'] ) ? sanitize_email( wp_unslash( $_POST['support_email'] ) ) : '';
        $whatsapp = isset( $_POST['whatsapp'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['whatsapp'] ) ) : '';

        $new = array(
            'support_email'          => $email ? $email : 'support@tapixsolutions.com',
            'whatsapp'               => $whatsapp ? $whatsapp : '201552600646',
            'require_reason'         => isset( $_POST['require_reason'] ) ? 'yes' : 'no',
            'include_cancel_reason_email' => isset( $_POST['include_cancel_reason_email'] ) ? 'yes' : 'no',
            'append_support_details' => isset( $_POST['append_support_details'] ) ? 'yes' : 'no',
        );

        update_option( self::OPTION_KEY, $new, false );
        add_settings_error( 'tapbix_order_tools', 'saved', 'TapBix Order Tools settings saved.', 'updated' );
    }

    public function render_settings_page() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            return;
        }
        $s = $this->settings();
        settings_errors( 'tapbix_order_tools' );
        ?>
        <div class="wrap">
            <h1>TapBix Order Tools</h1>
            <p>Order communication settings used for customer cancellation notices and support details.</p>
            <form method="post">
                <?php wp_nonce_field( 'tapbix_order_tools_save_settings' ); ?>
                <table class="form-table" role="presentation">
                    <tr>
                        <th scope="row"><label for="tapbix-support-email">Support email</label></th>
                        <td><input id="tapbix-support-email" name="support_email" type="email" class="regular-text" value="<?php echo esc_attr( $s['support_email'] ); ?>"></td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="tapbix-whatsapp">WhatsApp</label></th>
                        <td><input id="tapbix-whatsapp" name="whatsapp" type="text" class="regular-text" value="<?php echo esc_attr( $s['whatsapp'] ); ?>"><p class="description">International digits only, e.g. 201552600646.</p></td>
                    </tr>
                    <tr>
                        <th scope="row">Cancellation workflow</th>
                        <td>
                            <label><input type="checkbox" name="require_reason" value="1" <?php checked( $s['require_reason'], 'yes' ); ?>> Require a reason when an administrator manually cancels an order</label><br>
                            <label><input type="checkbox" name="include_cancel_reason_email" value="1" <?php checked( $s['include_cancel_reason_email'], 'yes' ); ?>> Include the cancellation reason in WooCommerce's built-in Customer cancelled order email</label><p class="description">WooCommerce sends one cancellation email. TapBix Order Tools adds the reason and support details to that same email.</p>
                        </td>
                    </tr>
                    <tr>
                        <th scope="row">Customer emails</th>
                        <td><label><input type="checkbox" name="append_support_details" value="1" <?php checked( $s['append_support_details'], 'yes' ); ?>> Add TapBix support email and WhatsApp after the order table in WooCommerce customer emails</label></td>
                    </tr>
                </table>
                <p class="submit"><button type="submit" name="tapbix_order_tools_save" value="1" class="button button-primary">Save settings</button></p>
            </form>
        </div>
        <?php
    }

    public function add_order_meta_box_legacy() {
        add_meta_box(
            'tapbix-order-communication',
            'TapBix Order Communication',
            array( $this, 'render_order_meta_box' ),
            'shop_order',
            'side',
            'high'
        );
    }

    public function add_order_meta_box_hpos() {
        $screen = function_exists( 'wc_get_page_screen_id' ) ? wc_get_page_screen_id( 'shop-order' ) : 'woocommerce_page_wc-orders';
        add_meta_box(
            'tapbix-order-communication',
            'TapBix Order Communication',
            array( $this, 'render_order_meta_box' ),
            $screen,
            'side',
            'high'
        );
    }

    private function get_order_from_meta_box_context( $object ) {
        if ( $object instanceof WC_Order ) {
            return $object;
        }
        if ( is_object( $object ) && ! empty( $object->ID ) ) {
            return wc_get_order( $object->ID );
        }
        if ( isset( $_GET['id'] ) ) {
            return wc_get_order( absint( $_GET['id'] ) );
        }
        if ( isset( $_GET['post'] ) ) {
            return wc_get_order( absint( $_GET['post'] ) );
        }
        return false;
    }

    public function render_order_meta_box( $object ) {
        $order = $this->get_order_from_meta_box_context( $object );
        if ( ! $order ) {
            echo '<p>Order not found.</p>';
            return;
        }

        $reason = (string) $order->get_meta( self::META_REASON, true );
        $lang   = $this->order_language( $order );
        $sent   = (string) $order->get_meta( self::META_SENT_AT, true );
        $presets = $this->reason_presets( $lang );

        wp_nonce_field( 'tapbix_order_tools_order_meta', 'tapbix_order_tools_nonce' );
        ?>
        <p>
            <label for="tapbix-order-language"><strong>Customer language</strong></label><br>
            <select id="tapbix-order-language" name="tapbix_order_lang" style="width:100%">
                <option value="en" <?php selected( $lang, 'en' ); ?>>English</option>
                <option value="ar" <?php selected( $lang, 'ar' ); ?>>العربية</option>
                <option value="fr" <?php selected( $lang, 'fr' ); ?>>Français</option>
            </select>
        </p>
        <p>
            <label for="tapbix-reason-preset"><strong>Quick reason</strong></label><br>
            <select id="tapbix-reason-preset" style="width:100%">
                <option value="">— Select —</option>
                <?php foreach ( $presets as $key => $text ) : ?>
                    <option value="<?php echo esc_attr( $key ); ?>" data-reason="<?php echo esc_attr( $text ); ?>"><?php echo esc_html( $text ); ?></option>
                <?php endforeach; ?>
            </select>
        </p>
        <p>
            <label for="tapbix-cancellation-reason"><strong>Cancellation reason</strong></label><br>
            <textarea id="tapbix-cancellation-reason" name="tapbix_cancellation_reason" rows="5" style="width:100%" placeholder="Explain clearly why the order is being cancelled."><?php echo esc_textarea( $reason ); ?></textarea>
        </p>
        <?php if ( 'cancelled' === $order->get_status() && $order->get_billing_email() ) :
            $url = wp_nonce_url(
                admin_url( 'admin-post.php?action=tapbix_resend_cancel_email&order_id=' . $order->get_id() ),
                'tapbix_resend_cancel_email_' . $order->get_id()
            );
            ?>
            <p><a class="button" href="<?php echo esc_url( $url ); ?>">Resend WooCommerce cancellation email</a></p>
        <?php endif; ?>
        <p class="description">When you manually set the order to Cancelled, WooCommerce sends its normal customer cancellation email and TapBix adds this reason to it.</p>
        <script>
        (function(){
            var preset = document.getElementById('tapbix-reason-preset');
            var reason = document.getElementById('tapbix-cancellation-reason');
            if (preset && reason) {
                preset.addEventListener('change', function(){
                    var opt = this.options[this.selectedIndex];
                    if (opt && opt.dataset.reason) reason.value = opt.dataset.reason;
                });
            }
        })();
        </script>
        <?php
    }

    private function reason_presets( $lang ) {
        $all = array(
            'en' => array(
                'bank_transfer_missing' => 'Bank transfer was not received or could not be confirmed.',
                'duplicate_order'       => 'This appears to be a duplicate order.',
                'customer_request'      => 'The order was cancelled at the customer’s request.',
                'payment_issue'         => 'Payment could not be confirmed.',
                'other'                 => 'Other reason — please edit this text before cancelling.',
            ),
            'ar' => array(
                'bank_transfer_missing' => 'تم إلغاء الطلب لأن التحويل البنكي لم يصل أو تعذر تأكيده.',
                'duplicate_order'       => 'تم إلغاء الطلب لأنه يبدو طلبًا مكررًا.',
                'customer_request'      => 'تم إلغاء الطلب بناءً على طلب العميل.',
                'payment_issue'         => 'تم إلغاء الطلب لأن الدفع لم يتم تأكيده.',
                'other'                 => 'سبب آخر — من فضلك عدّل هذا النص قبل الإلغاء.',
            ),
            'fr' => array(
                'bank_transfer_missing' => 'La commande a été annulée car le virement bancaire n’a pas été reçu ou confirmé.',
                'duplicate_order'       => 'La commande a été annulée car elle semble être un doublon.',
                'customer_request'      => 'La commande a été annulée à la demande du client.',
                'payment_issue'         => 'La commande a été annulée car le paiement n’a pas pu être confirmé.',
                'other'                 => 'Autre raison — modifiez ce texte avant l’annulation.',
            ),
        );
        return isset( $all[ $lang ] ) ? $all[ $lang ] : $all['en'];
    }

    public function save_order_meta_box( $order_id ) {
        if ( ! $this->can_save_order_meta() ) {
            return;
        }
        $order = wc_get_order( $order_id );
        if ( ! $order ) {
            return;
        }
        $this->apply_posted_order_meta( $order );
        $order->save_meta_data();
    }

    public function save_order_meta_box_legacy_fallback( $post_id, $post, $update ) {
        if ( ! $update || ! $this->can_save_order_meta() ) {
            return;
        }
        $order = wc_get_order( $post_id );
        if ( ! $order ) {
            return;
        }
        $this->apply_posted_order_meta( $order );
        $order->save_meta_data();
    }

    private function can_save_order_meta() {
        if ( empty( $_POST['tapbix_order_tools_nonce'] ) ) {
            return false;
        }
        $nonce = sanitize_text_field( wp_unslash( $_POST['tapbix_order_tools_nonce'] ) );
        if ( ! wp_verify_nonce( $nonce, 'tapbix_order_tools_order_meta' ) ) {
            return false;
        }
        return current_user_can( 'edit_shop_orders' ) || current_user_can( 'manage_woocommerce' );
    }

    private function apply_posted_order_meta( WC_Order $order ) {
        if ( isset( $_POST['tapbix_cancellation_reason'] ) ) {
            $reason = sanitize_textarea_field( wp_unslash( $_POST['tapbix_cancellation_reason'] ) );
            $order->update_meta_data( self::META_REASON, $reason );
        }
        if ( isset( $_POST['tapbix_order_lang'] ) ) {
            $lang = sanitize_key( wp_unslash( $_POST['tapbix_order_lang'] ) );
            if ( in_array( $lang, array( 'en', 'ar', 'fr' ), true ) ) {
                $order->update_meta_data( self::META_LANG, $lang );
            }
        }
    }

    public function require_reason_before_manual_cancel( $order ) {
        if ( ! is_admin() || wp_doing_ajax() || ! $order instanceof WC_Order ) {
            return;
        }
        $s = $this->settings();
        if ( 'yes' !== $s['require_reason'] ) {
            return;
        }

        $changes = $order->get_changes();
        if ( empty( $changes['status'] ) || 'cancelled' !== $order->get_status() ) {
            return;
        }

        if ( isset( $_POST['tapbix_cancellation_reason'] ) ) {
            $posted = sanitize_textarea_field( wp_unslash( $_POST['tapbix_cancellation_reason'] ) );
            if ( $posted ) {
                $order->update_meta_data( self::META_REASON, $posted );
            }
        }

        $reason = trim( (string) $order->get_meta( self::META_REASON, true ) );
        if ( '' === $reason && ( current_user_can( 'edit_shop_orders' ) || current_user_can( 'manage_woocommerce' ) ) ) {
            throw new Exception( 'TapBix: Please enter a cancellation reason before setting this order to Cancelled.' );
        }
    }

    public function enqueue_admin_order_script( $hook ) {
        if ( ! is_admin() ) {
            return;
        }
        $screen = function_exists( 'get_current_screen' ) ? get_current_screen() : null;
        if ( ! $screen || false === strpos( (string) $screen->id, 'shop-order' ) && false === strpos( (string) $screen->id, 'wc-orders' ) ) {
            return;
        }
        $s = $this->settings();
        if ( 'yes' !== $s['require_reason'] ) {
            return;
        }
        wp_register_script( 'tapbix-order-tools-admin', '', array( 'jquery' ), self::VERSION, true );
        wp_enqueue_script( 'tapbix-order-tools-admin' );
        $js = <<<'JS'
        jQuery(function($){
            function validateTapBixCancel(e){
                var status = $('#order_status').val();
                var reason = $.trim($('#tapbix-cancellation-reason').val() || '');
                if (status === 'wc-cancelled' && !reason) {
                    e.preventDefault();
                    alert('Please enter a Cancellation reason in the TapBix Order Communication box before cancelling this order.');
                    $('#tapbix-cancellation-reason').trigger('focus');
                    return false;
                }
            }
            $('#post').on('submit', validateTapBixCancel);
            $('.woocommerce-order-data__meta').closest('form').on('submit', validateTapBixCancel);
        });
JS;
        wp_add_inline_script( 'tapbix-order-tools-admin', $js );
    }

    public function capture_checkout_language( $order, $data ) {
        if ( $order instanceof WC_Order ) {
            $order->update_meta_data( self::META_LANG, $this->detect_current_language() );
        }
    }

    public function capture_store_api_language( $order ) {
        if ( $order instanceof WC_Order ) {
            $order->update_meta_data( self::META_LANG, $this->detect_current_language() );
        }
    }

    private function detect_current_language() {
        if ( isset( $_GET['tbx_lang'] ) ) {
            $lang = sanitize_key( wp_unslash( $_GET['tbx_lang'] ) );
            if ( in_array( $lang, array( 'en', 'ar', 'fr' ), true ) ) {
                return $lang;
            }
        }
        if ( isset( $_COOKIE['tapbix_lang'] ) ) {
            $lang = sanitize_key( wp_unslash( $_COOKIE['tapbix_lang'] ) );
            if ( in_array( $lang, array( 'en', 'ar', 'fr' ), true ) ) {
                return $lang;
            }
        }
        $locale = function_exists( 'determine_locale' ) ? determine_locale() : get_locale();
        if ( 0 === strpos( $locale, 'ar' ) ) {
            return 'ar';
        }
        if ( 0 === strpos( $locale, 'fr' ) ) {
            return 'fr';
        }
        return 'en';
    }

    private function order_language( WC_Order $order ) {
        $lang = sanitize_key( (string) $order->get_meta( self::META_LANG, true ) );
        return in_array( $lang, array( 'en', 'ar', 'fr' ), true ) ? $lang : 'en';
    }

    public function send_cancelled_customer_email( $order_id, $order = false ) {
        $s = $this->settings();
        if ( 'yes' !== $s['send_cancel_email'] ) {
            return;
        }
        if ( ! $order instanceof WC_Order ) {
            $order = wc_get_order( $order_id );
        }
        if ( ! $order ) {
            return;
        }
        $this->send_cancellation_email( $order, false );
    }

    private function send_cancellation_email( WC_Order $order, $force = false ) {
        $to = sanitize_email( $order->get_billing_email() );
        if ( ! $to ) {
            return false;
        }

        $reason = trim( (string) $order->get_meta( self::META_REASON, true ) );
        if ( '' === $reason ) {
            $reason = $this->generic_reason( $this->order_language( $order ) );
        }

        $hash = hash( 'sha256', $order->get_id() . '|' . $reason . '|' . $to );
        if ( ! $force && hash_equals( (string) $order->get_meta( self::META_SENT, true ), $hash ) ) {
            return true;
        }

        $lang = $this->order_language( $order );
        $copy = $this->email_copy( $lang, $order, $reason );
        $s    = $this->settings();

        $support_email = sanitize_email( $s['support_email'] );
        $whatsapp      = preg_replace( '/\D+/', '', $s['whatsapp'] );
        $whatsapp_url  = $whatsapp ? 'https://wa.me/' . $whatsapp : '';

        $body  = '<p>' . esc_html( $copy['intro'] ) . '</p>';
        $body .= '<p><strong>' . esc_html( $copy['reason_label'] ) . '</strong><br>' . nl2br( esc_html( $reason ) ) . '</p>';
        $body .= '<p>' . esc_html( $copy['help'] ) . '</p>';
        if ( $support_email ) {
            $body .= '<p><strong>Email:</strong> <a href="mailto:' . esc_attr( $support_email ) . '">' . esc_html( $support_email ) . '</a></p>';
        }
        if ( $whatsapp_url ) {
            $body .= '<p><strong>WhatsApp:</strong> <a href="' . esc_url( $whatsapp_url ) . '">+20 155 260 0646</a></p>';
        }
        $body .= '<p>' . esc_html( $copy['closing'] ) . '</p>';

        $mailer  = WC()->mailer();
        $message = $mailer->wrap_message( $copy['heading'], $body );
        $headers = array( 'Content-Type: text/html; charset=UTF-8' );

        $sent = $mailer->send( $to, $copy['subject'], $message, $headers );
        if ( $sent ) {
            $order->update_meta_data( self::META_SENT, $hash );
            $order->update_meta_data( self::META_SENT_AT, current_time( 'mysql' ) );
            $order->save_meta_data();
            $order->add_order_note( 'TapBix cancellation email sent to customer. Reason: ' . $reason, false, true );
        }
        return (bool) $sent;
    }

    private function generic_reason( $lang ) {
        if ( 'ar' === $lang ) {
            return 'تم إلغاء الطلب. إذا كنت تعتقد أن هذا حدث بالخطأ، تواصل مع دعم TapBix لمعرفة التفاصيل.';
        }
        if ( 'fr' === $lang ) {
            return 'La commande a été annulée. Si vous pensez qu’il s’agit d’une erreur, contactez le support TapBix pour plus de détails.';
        }
        return 'The order was cancelled. If you believe this was a mistake, please contact TapBix support for details.';
    }

    private function email_copy( $lang, WC_Order $order, $reason ) {
        $number = $order->get_order_number();
        if ( 'ar' === $lang ) {
            return array(
                'subject'      => 'تم إلغاء طلب TapBix رقم ' . $number,
                'heading'      => 'تم إلغاء طلبك',
                'intro'        => 'نود إبلاغك بأنه تم إلغاء طلب TapBix رقم ' . $number . '.',
                'reason_label' => 'سبب الإلغاء:',
                'help'         => 'إذا كنت تعتقد أن الإلغاء تم بالخطأ أو تريد إنشاء طلب جديد، تواصل معنا وسنساعدك.',
                'closing'      => 'شكرًا لاهتمامك بـ TapBix.',
            );
        }
        if ( 'fr' === $lang ) {
            return array(
                'subject'      => 'Commande TapBix n° ' . $number . ' annulée',
                'heading'      => 'Votre commande a été annulée',
                'intro'        => 'Nous vous informons que votre commande TapBix n° ' . $number . ' a été annulée.',
                'reason_label' => 'Raison de l’annulation :',
                'help'         => 'Si vous pensez qu’il s’agit d’une erreur ou si vous souhaitez passer une nouvelle commande, contactez-nous.',
                'closing'      => 'Merci de votre intérêt pour TapBix.',
            );
        }
        return array(
            'subject'      => 'Your TapBix order #' . $number . ' has been cancelled',
            'heading'      => 'Your order has been cancelled',
            'intro'        => 'Your TapBix order #' . $number . ' has been cancelled.',
            'reason_label' => 'Reason:',
            'help'         => 'If you believe this was a mistake or you would like to place a new order, please contact TapBix support.',
            'closing'      => 'Thank you for your interest in TapBix.',
        );
    }

    public function handle_resend_cancel_email() {
        $order_id = isset( $_GET['order_id'] ) ? absint( $_GET['order_id'] ) : 0;
        if ( ! $order_id || ! current_user_can( 'edit_shop_orders' ) && ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( 'You are not allowed to do this.' );
        }
        check_admin_referer( 'tapbix_resend_cancel_email_' . $order_id );
        $order = wc_get_order( $order_id );
        if ( ! $order ) {
            wp_die( 'Order not found.' );
        }
        $sent = $this->trigger_native_cancelled_email( $order );
        $url  = $this->order_edit_url( $order_id );
        $url  = add_query_arg( 'tapbix_cancel_email', $sent ? 'sent' : 'failed', $url );
        wp_safe_redirect( $url );
        exit;
    }

    private function trigger_native_cancelled_email( WC_Order $order ) {
        if ( ! function_exists( 'WC' ) || ! WC()->mailer() ) {
            return false;
        }

        $emails = WC()->mailer()->get_emails();
        foreach ( $emails as $email ) {
            if ( is_object( $email ) && isset( $email->id ) && 'customer_cancelled_order' === $email->id ) {
                if ( method_exists( $email, 'is_enabled' ) && ! $email->is_enabled() ) {
                    return false;
                }
                if ( method_exists( $email, 'trigger' ) ) {
                    $email->trigger( $order->get_id(), $order );
                    return true;
                }
            }
        }

        return false;
    }

    public function admin_email_notice() {
        if ( empty( $_GET['tapbix_cancel_email'] ) ) {
            return;
        }
        $status = sanitize_key( wp_unslash( $_GET['tapbix_cancel_email'] ) );
        if ( 'sent' === $status ) {
            echo '<div class="notice notice-success is-dismissible"><p>WooCommerce cancellation email sent successfully.</p></div>';
        } elseif ( 'failed' === $status ) {
            echo '<div class="notice notice-error is-dismissible"><p>WooCommerce could not send the cancellation email. Check that the Customer cancelled order email is enabled, the customer has an email address, and your mail settings are working.</p></div>';
        }
    }

    private function order_edit_url( $order_id ) {
        if ( class_exists( '\\Automattic\\WooCommerce\\Utilities\\OrderUtil' ) && \Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled() ) {
            return admin_url( 'admin.php?page=wc-orders&action=edit&id=' . absint( $order_id ) );
        }
        return admin_url( 'post.php?post=' . absint( $order_id ) . '&action=edit' );
    }

    public function show_reason_in_my_account( $order ) {
        if ( ! $order instanceof WC_Order || 'cancelled' !== $order->get_status() ) {
            return;
        }
        $reason = trim( (string) $order->get_meta( self::META_REASON, true ) );
        if ( ! $reason ) {
            return;
        }
        $lang = $this->order_language( $order );
        $label = 'Cancellation reason';
        if ( 'ar' === $lang ) {
            $label = 'سبب إلغاء الطلب';
        } elseif ( 'fr' === $lang ) {
            $label = 'Raison de l’annulation';
        }
        echo '<section class="woocommerce-order-details" style="margin-top:20px"><h2>' . esc_html( $label ) . '</h2><p>' . nl2br( esc_html( $reason ) ) . '</p></section>';
    }

    public function append_support_to_customer_emails( $order, $sent_to_admin, $plain_text, $email ) {
        if ( $sent_to_admin ) {
            return;
        }
        $s = $this->settings();

        $email_id = ( is_object( $email ) && isset( $email->id ) ) ? (string) $email->id : '';
        if ( 'customer_cancelled_order' === $email_id && 'yes' === $s['include_cancel_reason_email'] ) {
            $reason = trim( (string) $order->get_meta( self::META_REASON, true ) );
            if ( '' !== $reason ) {
                $lang  = $this->order_language( $order );
                $label = 'Cancellation reason';
                if ( 'ar' === $lang ) {
                    $label = 'سبب إلغاء الطلب';
                } elseif ( 'fr' === $lang ) {
                    $label = 'Raison de l’annulation';
                }

                if ( $plain_text ) {
                    echo "\n" . $label . ":\n" . $reason . "\n";
                } else {
                    echo '<div style="margin-top:20px;padding:16px;border:1px solid #e5e7eb;border-radius:8px">';
                    echo '<strong>' . esc_html( $label ) . '</strong><br>';
                    echo nl2br( esc_html( $reason ) );
                    echo '</div>';
                }
            }
        }

        if ( 'yes' !== $s['append_support_details'] ) {
            return;
        }
        $support_email = sanitize_email( $s['support_email'] );
        $whatsapp      = preg_replace( '/\D+/', '', $s['whatsapp'] );
        if ( ! $support_email && ! $whatsapp ) {
            return;
        }

        if ( $plain_text ) {
            echo "\nTapBix Support\n";
            if ( $support_email ) {
                echo 'Email: ' . $support_email . "\n";
            }
            if ( $whatsapp ) {
                echo 'WhatsApp: +' . $whatsapp . "\n";
            }
            return;
        }

        echo '<div style="margin-top:24px;padding:16px;border:1px solid #e5e7eb;border-radius:8px">';
        echo '<strong>TapBix Support</strong><br>';
        if ( $support_email ) {
            echo 'Email: <a href="mailto:' . esc_attr( $support_email ) . '">' . esc_html( $support_email ) . '</a><br>';
        }
        if ( $whatsapp ) {
            echo 'WhatsApp: <a href="' . esc_url( 'https://wa.me/' . $whatsapp ) . '">+20 155 260 0646</a>';
        }
        echo '</div>';
    }
}

TapBix_Order_Tools::instance();
