<?php
/**
 * Plugin Name: TapBix License Server
 * Description: Offline-first license issuing and device activation server for TapBix Windows and Linux, integrated with WooCommerce.
 * Version: 0.5.1
 * Author: Tapix Solutions
 * Requires at least: 6.4
 * Requires PHP: 8.1
 * Text Domain: tapbix-license-server
 */
if (!defined('ABSPATH')) exit;

final class TapBix_License_Server {
    const VERSION='0.5.1';
    const PRODUCT_CODE='tapbix-desktop';
    const ADD_DEVICE_SKU='TAPBIX-DESKTOP-ADD-DEVICE';
    const APP_ID='com.tapix.pos';
    const OFFLINE_LEASE_SECONDS=604800;
    const REVALIDATE_AFTER_SECONDS=86400;
    const PRIV_OPT='tapbix_license_private_key';
    const PUB_OPT='tapbix_license_public_key';
    const ENDPOINT='tapbix-licenses';
    const DB_VERSION_OPT='tapbix_license_server_version';
    private static $instance=null;

    public static function instance(){ if(self::$instance===null) self::$instance=new self(); return self::$instance; }
    private function __construct(){
        register_activation_hook(__FILE__,[$this,'activate']);
        add_action('init',[$this,'register_account_endpoint']);
        add_filter('query_vars',[$this,'account_query_vars']);
        add_filter('woocommerce_account_menu_items',[$this,'account_menu_item']);
        add_action('woocommerce_account_'.self::ENDPOINT.'_endpoint',[$this,'render_account_licenses']);
        add_action('template_redirect',[$this,'handle_customer_deactivate']);
        add_action('woocommerce_payment_complete',[$this,'issue_for_order']);
        add_action('woocommerce_order_status_completed',[$this,'issue_for_order']);
        add_action('woocommerce_order_refunded',[$this,'handle_order_refunded'],10,2);
        add_action('woocommerce_order_status_cancelled',[$this,'handle_order_cancelled'],10,2);
        add_filter('woocommerce_add_to_cart_validation',[$this,'validate_add_device_cart_request'],10,6);
        add_action('woocommerce_check_cart_items',[$this,'validate_add_device_cart']);
        add_filter('woocommerce_get_item_data',[$this,'display_add_device_cart_data'],10,2);
        add_action('woocommerce_checkout_create_order_line_item',[$this,'store_add_device_order_item_meta'],10,4);
        add_action('woocommerce_email_after_order_table',[$this,'email_license_details'],20,4);
        add_action('rest_api_init',[$this,'register_rest_routes']);
        add_action('admin_menu',[$this,'admin_menu']);
        add_action('admin_notices',[$this,'admin_notices']);
        add_action('admin_post_tapbix_license_action',[$this,'handle_admin_action']);
        add_action('admin_post_tapbix_create_test_license',[$this,'handle_create_test_license']);
        add_action('admin_post_tapbix_test_activation',[$this,'handle_test_activation']);
        add_action('admin_post_tapbix_adjust_max_devices',[$this,'handle_adjust_max_devices']);
        add_action('admin_init',[$this,'maybe_upgrade']);
    }
    private function table($n){ global $wpdb; return $wpdb->prefix.'tapbix_'.$n; }
    private function now(){ return current_time('mysql',true); }

    private static function sku_configs(){
        return [
            'TAPBIX-DESKTOP-MONTHLY-1D'=>['plan'=>'monthly','max_devices'=>1],
            'TAPBIX-DESKTOP-ANNUAL-1D'=>['plan'=>'annual','max_devices'=>1],
            'TAPBIX-DESKTOP-LIFETIME-1D'=>['plan'=>'lifetime','max_devices'=>1],
            'TAPBIX-WIN-LIFE-1D'=>['plan'=>'lifetime','max_devices'=>1],
        ];
    }
    private function config_for_sku($sku){
        $sku=strtoupper(trim((string)$sku));
        $configs=self::sku_configs();
        return $configs[$sku]??null;
    }
    private function expiry_for_plan($plan,$base_timestamp=null){
        if($plan==='lifetime') return null;
        if(!in_array($plan,['monthly','annual'],true)) return null;

        $base=(new DateTimeImmutable('@'.($base_timestamp?:time())))->setTimezone(new DateTimeZone('UTC'));
        $year=(int)$base->format('Y')+($plan==='annual'?1:0);
        $month=(int)$base->format('n')+($plan==='monthly'?1:0);
        if($month>12){$month-=12;$year++;}
        $day=(int)$base->format('j');
        $target=$base->setDate($year,$month,1);
        $target=$target->setDate($year,$month,min($day,(int)$target->format('t')));
        return $target->format('Y-m-d H:i:s');
    }
    private function is_add_device_product($product){
        return $product&&strtoupper(trim((string)$product->get_sku()))===self::ADD_DEVICE_SKU;
    }
    private function add_device_product(){
        if(!function_exists('wc_get_product_id_by_sku')||!function_exists('wc_get_product')) return null;
        $product_id=absint(wc_get_product_id_by_sku(self::ADD_DEVICE_SKU));
        if(!$product_id) return null;
        $product=wc_get_product($product_id);
        return $this->is_add_device_product($product)?$product:null;
    }
    private function normalize_device_quantity($value){
        $value=trim((string)$value);
        if(!preg_match('/^[1-9][0-9]*$/',$value)) return 0;
        $quantity=absint($value);
        return $quantity>=1?$quantity:0;
    }
    private function license_belongs_to_user($license,$user){
        if(!$license||!$user||!$user->exists()) return false;
        if((int)$license->customer_id>0) return (int)$license->customer_id===(int)$user->ID;
        return !empty($license->customer_email)&&strtolower((string)$license->customer_email)===strtolower((string)$user->user_email);
    }
    private function license_belongs_to_order_customer($license,$order){
        if(!$license||!$order) return false;
        $customer_id=(int)$order->get_customer_id();
        if((int)$license->customer_id>0) return $customer_id>0&&(int)$license->customer_id===$customer_id;
        $email=sanitize_email($order->get_billing_email());
        return !empty($license->customer_email)&&$email&&strtolower((string)$license->customer_email)===strtolower($email);
    }
    private function is_add_device_eligible_license($license){
        return $license&&$license->status==='active'&&$license->product_code===self::PRODUCT_CODE&&$license->plan==='lifetime'&&empty($license->expires_at);
    }
    private function masked_license_key($key){
        $key=(string)$key;
        if(strlen($key)<12) return '••••';
        return substr($key,0,8).'-••••-••••-'.substr($key,-4);
    }
    private function add_device_failure($license_id,$reason,$details=[]){
        $details=array_merge(['reason'=>sanitize_key($reason)],$details);
        $this->log(absint($license_id)?:null,'add_device_validation_failed',$details);
    }

    private function handle_add_device_request(){
        if(($_SERVER['REQUEST_METHOD']??'')!=='POST'||empty($_POST['tapbix_add_device'])) return;
        if(!function_exists('WC')||!function_exists('wc_add_notice')||!function_exists('wc_get_account_endpoint_url')) wp_die('WooCommerce is required for this request.');
        $license_id=isset($_POST['license_id'])?absint(wp_unslash($_POST['license_id'])):0;
        $nonce=isset($_POST['tapbix_add_device_nonce'])?sanitize_text_field(wp_unslash($_POST['tapbix_add_device_nonce'])):'';
        if(!$license_id||!wp_verify_nonce($nonce,'tapbix_add_device_'.$license_id)){
            $this->add_device_failure($license_id,'invalid_nonce');
            wp_die('Invalid or expired request.');
        }
        if(!is_user_logged_in()){
            $this->add_device_failure($license_id,'authentication_required');
            wp_die('Please log in to purchase additional device capacity.');
        }

        $license=$this->get_license_by_id($license_id);
        $user=wp_get_current_user();
        if(!$this->license_belongs_to_user($license,$user)||!$this->is_add_device_eligible_license($license)){
            $this->add_device_failure($license_id,'ineligible_or_not_owned',['user_id'=>(int)$user->ID]);
            wc_add_notice('This license is not eligible for additional devices.','error');
            wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT));
            exit;
        }

        $quantity=$this->normalize_device_quantity(wp_unslash($_POST['quantity']??'1'));
        $product=$this->add_device_product();
        if(!$quantity||!$product||!$product->is_purchasable()||!$product->is_in_stock()){
            $this->add_device_failure($license_id,'product_or_quantity_invalid');
            wc_add_notice('The additional-device product is unavailable or the quantity is invalid.','error');
            wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT));
            exit;
        }
        $max_quantity=(int)$product->get_max_purchase_quantity();
        if($max_quantity>0&&$quantity>$max_quantity){
            wc_add_notice('The requested quantity exceeds the product purchase limit.','error');
            wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT));
            exit;
        }
        if(!WC()->cart&&function_exists('wc_load_cart')) wc_load_cart();
        $added=WC()->cart?WC()->cart->add_to_cart($product->get_id(),$quantity,0,[],['tapbix_target_license_id'=>$license_id]):false;
        if(!$added){
            wc_add_notice('The additional device could not be added to your cart.','error');
            wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT));
            exit;
        }
        wp_safe_redirect(wc_get_cart_url());
        exit;
    }

    public function validate_add_device_cart_request($passed,$product_id,$quantity,$variation_id=0,$variations=[],$cart_item_data=[]){
        $product=function_exists('wc_get_product')?wc_get_product($variation_id?:$product_id):null;
        if(!$this->is_add_device_product($product)||!$passed) return $passed;
        $license_id=absint($cart_item_data['tapbix_target_license_id']??0);
        $license=$license_id?$this->get_license_by_id($license_id):null;
        $user=wp_get_current_user();
        $valid_quantity=(float)$quantity>=1&&floor((float)$quantity)===(float)$quantity;
        if(!$valid_quantity||!$this->license_belongs_to_user($license,$user)||!$this->is_add_device_eligible_license($license)){
            $this->add_device_failure($license_id,'cart_validation_failed',['user_id'=>(int)$user->ID]);
            wc_add_notice('Additional devices can only be purchased for your own active lifetime TapBix license.','error');
            return false;
        }
        return true;
    }
    public function validate_add_device_cart(){
        if(!function_exists('WC')||!WC()->cart) return;
        $user=wp_get_current_user();
        foreach(WC()->cart->get_cart() as $cart_item){
            if(!$this->is_add_device_product($cart_item['data']??null)) continue;
            $license_id=absint($cart_item['tapbix_target_license_id']??0);
            $license=$license_id?$this->get_license_by_id($license_id):null;
            if(!$this->license_belongs_to_user($license,$user)||!$this->is_add_device_eligible_license($license)){
                $this->add_device_failure($license_id,'checkout_cart_validation_failed',['user_id'=>(int)$user->ID]);
                wc_add_notice('An additional-device cart item no longer has a valid eligible license.','error');
            }
        }
    }
    public function display_add_device_cart_data($item_data,$cart_item){
        if(!$this->is_add_device_product($cart_item['data']??null)) return $item_data;
        $license=$this->get_license_by_id(absint($cart_item['tapbix_target_license_id']??0));
        if($license) $item_data[]=['key'=>'TapBix license','value'=>$this->masked_license_key($license->license_key)];
        return $item_data;
    }
    public function store_add_device_order_item_meta($item,$cart_item_key,$values,$order){
        if(!$this->is_add_device_product($values['data']??null)) return;
        $license_id=absint($values['tapbix_target_license_id']??0);
        $license=$license_id?$this->get_license_by_id($license_id):null;
        if(!$this->license_belongs_to_order_customer($license,$order)||!$this->is_add_device_eligible_license($license)){
            $this->add_device_failure($license_id,'order_item_validation_failed',['order_id'=>$order->get_id()]);
            throw new Exception('The additional-device item is not linked to an eligible customer license.');
        }
        $item->add_meta_data('_tapbix_target_license_id',$license_id,true);
        $item->add_meta_data('TapBix license',$this->masked_license_key($license->license_key),true);
    }

    public function activate(){
        $this->create_tables();
        $this->ensure_keys();
        update_option(self::DB_VERSION_OPT,self::VERSION,false);
        $this->register_account_endpoint();
        flush_rewrite_rules();
    }
    public function maybe_upgrade(){
        if(get_option(self::DB_VERSION_OPT)!==self::VERSION){
            $this->create_tables();
            $this->ensure_keys();
            update_option(self::DB_VERSION_OPT,self::VERSION,false);
        }
    }
    private function create_tables(){
        global $wpdb; require_once ABSPATH.'wp-admin/includes/upgrade.php'; $c=$wpdb->get_charset_collate();
        dbDelta("CREATE TABLE {$this->table('licenses')} (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license_key VARCHAR(64) NOT NULL,
            product_code VARCHAR(64) NOT NULL DEFAULT 'tapbix-desktop',
            plan VARCHAR(32) NOT NULL DEFAULT 'lifetime',
            max_devices INT UNSIGNED NOT NULL DEFAULT 1,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            customer_id BIGINT UNSIGNED NULL,
            customer_email VARCHAR(190) NULL,
            order_id BIGINT UNSIGNED NULL,
            order_item_id BIGINT UNSIGNED NULL,
            created_at DATETIME NOT NULL,
            expires_at DATETIME NULL,
            notes TEXT NULL,
            PRIMARY KEY (id), UNIQUE KEY license_key (license_key), UNIQUE KEY order_item_unique (order_id,order_item_id),
            KEY customer_id (customer_id), KEY customer_email (customer_email), KEY status (status)
        ) $c;");
        dbDelta("CREATE TABLE {$this->table('activations')} (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license_id BIGINT UNSIGNED NOT NULL,
            device_id VARCHAR(190) NOT NULL,
            platform VARCHAR(20) NOT NULL DEFAULT 'windows',
            activation_token_hash CHAR(64) NULL,
            device_name VARCHAR(190) NULL,
            app_version VARCHAR(50) NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            activated_at DATETIME NOT NULL,
            last_seen_at DATETIME NOT NULL,
            deactivated_at DATETIME NULL,
            PRIMARY KEY (id), UNIQUE KEY license_device_unique (license_id,device_id), KEY license_id (license_id), KEY status (status)
        ) $c;");
        dbDelta("CREATE TABLE {$this->table('license_logs')} (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license_id BIGINT UNSIGNED NULL,
            event_type VARCHAR(60) NOT NULL,
            ip_hash VARCHAR(64) NULL,
            details LONGTEXT NULL,
            created_at DATETIME NOT NULL,
            PRIMARY KEY (id), KEY license_id (license_id), KEY event_type (event_type), KEY created_at (created_at)
        ) $c;");
        dbDelta("CREATE TABLE {$this->table('capacity_transactions')} (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license_id BIGINT UNSIGNED NOT NULL,
            order_id BIGINT UNSIGNED NOT NULL,
            order_item_id BIGINT UNSIGNED NOT NULL,
            purchased_qty INT UNSIGNED NOT NULL,
            reversed_qty INT UNSIGNED NOT NULL DEFAULT 0,
            status VARCHAR(20) NOT NULL DEFAULT 'applied',
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            PRIMARY KEY (id), UNIQUE KEY order_item_unique (order_id,order_item_id),
            KEY license_id (license_id), KEY status (status)
        ) ENGINE=InnoDB $c;");
    }
    private function ensure_keys(){
        $private_key=get_option(self::PRIV_OPT);
        $public_key=get_option(self::PUB_OPT);
        if($private_key&&$public_key) return true;
        // Never replace half of an existing production key pair automatically.
        if($private_key||$public_key) return false;
        if(!function_exists('openssl_pkey_new')) return false;
        $r=openssl_pkey_new(['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA]); if(!$r) return false;
        $priv=''; if(!openssl_pkey_export($r,$priv)) return false; $d=openssl_pkey_get_details($r); if(empty($d['key'])) return false;
        update_option(self::PRIV_OPT,$priv,false); update_option(self::PUB_OPT,$d['key'],false); return true;
    }
    private function gen_key(){ $a='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; $g=[]; for($x=0;$x<5;$x++){ $p=''; for($i=0;$i<4;$i++) $p.=$a[random_int(0,strlen($a)-1)]; $g[]=$p; } return 'TBX-'.implode('-',$g); }
    private function log($lid,$type,$details=[]){
        global $wpdb; $ip=isset($_SERVER['REMOTE_ADDR'])?sanitize_text_field(wp_unslash($_SERVER['REMOTE_ADDR'])):''; $h=$ip?hash('sha256',wp_salt('auth').'|'.$ip):null;
        $wpdb->insert($this->table('license_logs'),['license_id'=>$lid?:null,'event_type'=>sanitize_key($type),'ip_hash'=>$h,'details'=>wp_json_encode($details,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),'created_at'=>$this->now()],['%d','%s','%s','%s','%s']);
    }
    public function issue_for_order($order_id){
        if(!function_exists('wc_get_order')) return;
        $o=is_a($order_id,'WC_Order')?$order_id:wc_get_order($order_id);
        if(!$o) return;

        foreach($o->get_items('line_item') as $item_id=>$item){
            if($this->is_add_device_product($item->get_product())) $this->apply_add_device_purchase($o,$item_id,$item);
        }

        $renewal=$this->renewal_source_order_ids($o);
        if($renewal!==null){
            $this->renew_licenses_for_order($o,$renewal);
            return;
        }

        foreach($o->get_items('line_item') as $item_id=>$item){
            $p=$item->get_product();
            if($this->is_add_device_product($p)) continue;
            $config=$p?$this->config_for_sku($p->get_sku()):null;
            if(!$config) continue;
            $this->issue_license($o,$item_id,$config);
        }
    }
    private function issue_license($o,$item_id,$config){
        global $wpdb; $t=$this->table('licenses'); $oid=$o->get_id();
        $exists=$wpdb->get_var($wpdb->prepare("SELECT id FROM $t WHERE order_id=%d AND order_item_id=%d LIMIT 1",$oid,$item_id)); if($exists) return (int)$exists;
        do{ $key=$this->gen_key(); $dup=$wpdb->get_var($wpdb->prepare("SELECT id FROM $t WHERE license_key=%s LIMIT 1",$key)); }while($dup);
        $expires_at=$this->expiry_for_plan($config['plan']);
        $ok=$wpdb->insert($t,['license_key'=>$key,'product_code'=>self::PRODUCT_CODE,'plan'=>$config['plan'],'max_devices'=>$config['max_devices'],'status'=>'active','customer_id'=>$o->get_customer_id()?:null,'customer_email'=>sanitize_email($o->get_billing_email()),'order_id'=>$oid,'order_item_id'=>$item_id,'created_at'=>$this->now(),'expires_at'=>$expires_at],['%s','%s','%s','%d','%s','%d','%s','%d','%d','%s','%s']);
        if(!$ok) return null;
        $license_id=(int)$wpdb->insert_id;
        $this->log($license_id,'license_issued',['order_id'=>$oid,'order_item_id'=>$item_id,'plan'=>$config['plan'],'expires_at'=>$expires_at]);
        return $license_id;
    }
    private function capacity_transaction($order_id,$order_item_id){
        global $wpdb;
        return $wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('capacity_transactions')} WHERE order_id=%d AND order_item_id=%d LIMIT 1",$order_id,$order_item_id));
    }
    private function capacity_transactions_for_order($order_id){
        global $wpdb;
        return $wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('capacity_transactions')} WHERE order_id=%d ORDER BY id",$order_id));
    }
    private function apply_add_device_purchase($order,$item_id,$item){
        $order_id=(int)$order->get_id();
        $item_id=(int)$item_id;
        $existing=$this->capacity_transaction($order_id,$item_id);
        if($existing){
            $this->log((int)$existing->license_id,'capacity_purchase_duplicate_ignored',['order_id'=>$order_id,'order_item_id'=>$item_id,'quantity'=>(int)$existing->purchased_qty]);
            return;
        }

        $license_id=absint($item->get_meta('_tapbix_target_license_id',true));
        $quantity=$this->normalize_device_quantity($item->get_quantity());
        $license=$license_id?$this->get_license_by_id($license_id):null;
        if(!$quantity||!$this->license_belongs_to_order_customer($license,$order)||!$this->is_add_device_eligible_license($license)){
            $this->add_device_failure($license_id,'paid_order_validation_failed',['order_id'=>$order_id,'order_item_id'=>$item_id,'quantity'=>$quantity]);
            $order->add_order_note('TapBix additional-device capacity was not applied because the target license was missing, ineligible, or did not belong to this customer.');
            return;
        }

        global $wpdb;
        if($wpdb->query('START TRANSACTION')===false){
            $this->add_device_failure($license_id,'transaction_start_failed',['order_id'=>$order_id,'order_item_id'=>$item_id]);
            return;
        }
        $previous_suppression=$wpdb->suppress_errors(true);
        $inserted=$wpdb->insert($this->table('capacity_transactions'),['license_id'=>$license_id,'order_id'=>$order_id,'order_item_id'=>$item_id,'purchased_qty'=>$quantity,'reversed_qty'=>0,'status'=>'applied','created_at'=>$this->now(),'updated_at'=>$this->now()],['%d','%d','%d','%d','%d','%s','%s','%s']);
        $wpdb->suppress_errors($previous_suppression);
        if(!$inserted){
            $wpdb->query('ROLLBACK');
            $duplicate=$this->capacity_transaction($order_id,$item_id);
            if($duplicate){
                $this->log((int)$duplicate->license_id,'capacity_purchase_duplicate_ignored',['order_id'=>$order_id,'order_item_id'=>$item_id,'quantity'=>(int)$duplicate->purchased_qty]);
            }else{
                $this->add_device_failure($license_id,'capacity_transaction_insert_failed',['order_id'=>$order_id,'order_item_id'=>$item_id]);
            }
            return;
        }
        $updated=$wpdb->query($wpdb->prepare("UPDATE {$this->table('licenses')} SET max_devices=max_devices+%d WHERE id=%d AND status='active' AND product_code=%s AND plan='lifetime' AND (expires_at IS NULL OR expires_at='')",$quantity,$license_id,self::PRODUCT_CODE));
        if($updated!==1){
            $wpdb->query('ROLLBACK');
            $this->add_device_failure($license_id,'capacity_license_update_failed',['order_id'=>$order_id,'order_item_id'=>$item_id]);
            return;
        }
        if($wpdb->query('COMMIT')===false){
            $wpdb->query('ROLLBACK');
            $this->add_device_failure($license_id,'capacity_transaction_commit_failed',['order_id'=>$order_id,'order_item_id'=>$item_id]);
            return;
        }

        $license=$this->get_license_by_id($license_id);
        $item->update_meta_data('_tapbix_capacity_applied','yes');
        $item->update_meta_data('_tapbix_capacity_quantity',$quantity);
        $item->save_meta_data();
        $this->log($license_id,'device_capacity_purchased',['order_id'=>$order_id,'order_item_id'=>$item_id,'quantity'=>$quantity,'max_devices'=>(int)$license->max_devices]);
        $order->add_order_note(sprintf('TapBix license #%d device allowance increased by %d to %d.',$license_id,$quantity,(int)$license->max_devices));
    }
    private function renewal_source_order_ids($order){
        if(function_exists('wcs_order_contains_renewal')&&function_exists('wcs_get_subscriptions_for_renewal_order')&&wcs_order_contains_renewal($order)){
            $source_ids=[];
            foreach((array)wcs_get_subscriptions_for_renewal_order($order) as $subscription){
                if(is_object($subscription)&&method_exists($subscription,'get_parent_id')){
                    $parent_id=absint($subscription->get_parent_id());
                    if($parent_id) $source_ids[]=$parent_id;
                }
            }
            return array_values(array_unique($source_ids));
        }

        // Other recurring-payment plugins may return source order IDs here.
        $source_ids=apply_filters('tapbix_license_renewal_source_order_ids',null,$order);
        if($source_ids===null) return null;
        return array_values(array_unique(array_filter(array_map('absint',(array)$source_ids))));
    }
    private function order_reference_timestamp($order){
        foreach(['get_date_paid','get_date_completed','get_date_created'] as $method){
            if(!method_exists($order,$method)) continue;
            $date=$order->$method();
            if(is_object($date)&&method_exists($date,'getTimestamp')) return (int)$date->getTimestamp();
        }
        return time();
    }
    private function renew_licenses_for_order($order,$source_order_ids){
        if($order->get_meta('_tapbix_license_renewal_processed',true)==='yes') return;

        $renewal_items=[];
        foreach($order->get_items('line_item') as $item_id=>$item){
            $product=$item->get_product();
            $sku=$product?strtoupper(trim((string)$product->get_sku())):'';
            $config=$this->config_for_sku($sku);
            if($config) $renewal_items[(int)$item_id]=['sku'=>$sku,'config'=>$config];
        }
        if(!$renewal_items) return;
        if(!$source_order_ids){
            $this->log(null,'renewal_source_missing',['renewal_order_id'=>$order->get_id()]);
            return;
        }

        global $wpdb;
        $renewed=[];
        $renewal_map=[];
        $renewal_time=$this->order_reference_timestamp($order);
        foreach($source_order_ids as $source_order_id){
            $source_order=wc_get_order($source_order_id);
            if(!$source_order) continue;
            $licenses=$wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE order_id=%d ORDER BY id",$source_order_id));
            foreach($licenses as $license){
                if($license->status!=='active'||!in_array($license->plan,['monthly','annual'],true)) continue;
                $source_item=$source_order->get_item((int)$license->order_item_id);
                $source_product=$source_item?$source_item->get_product():null;
                $source_sku=$source_product?strtoupper(trim((string)$source_product->get_sku())):'';
                $matches=[];
                foreach($renewal_items as $renewal_item_id=>$renewal_item){
                    if($renewal_item['sku']===$source_sku) $matches[]=$renewal_item_id;
                }
                if(!$matches){
                    foreach($renewal_items as $renewal_item_id=>$renewal_item){
                        if($renewal_item['config']['plan']===$license->plan) $matches[]=$renewal_item_id;
                    }
                }
                if(count($matches)!==1){
                    $this->log((int)$license->id,'renewal_mapping_ambiguous',['renewal_order_id'=>$order->get_id(),'source_order_id'=>$source_order_id]);
                    continue;
                }

                $current_expiry=$license->expires_at?strtotime($license->expires_at.' UTC'):0;
                $base=max($renewal_time,$current_expiry?:0);
                $new_expiry=$this->expiry_for_plan($license->plan,$base);
                if(!$new_expiry) continue;
                $updated=$wpdb->update($this->table('licenses'),['expires_at'=>$new_expiry],['id'=>$license->id],['%s'],['%d']);
                if($updated===false) continue;

                $license_id=(int)$license->id;
                $renewal_item_id=(int)$matches[0];
                $renewed[]=$license_id;
                $renewal_map[$renewal_item_id][]=$license_id;
                $this->log($license_id,'license_renewed',['renewal_order_id'=>$order->get_id(),'source_order_id'=>$source_order_id,'previous_expires_at'=>$license->expires_at,'expires_at'=>$new_expiry]);
            }
        }

        $renewed=array_values(array_unique($renewed));
        if(!$renewed){
            $this->log(null,'renewal_license_missing',['renewal_order_id'=>$order->get_id(),'source_order_ids'=>$source_order_ids]);
            return;
        }
        foreach($renewal_map as $item_id=>$ids) $renewal_map[$item_id]=array_values(array_unique($ids));
        $order->update_meta_data('_tapbix_license_renewal_map',$renewal_map);
        $order->update_meta_data('_tapbix_license_renewed_ids',$renewed);
        $order->update_meta_data('_tapbix_license_renewal_processed','yes');
        $order->save_meta_data();
    }
    private function license_ids_for_order_item($order,$item_id){
        global $wpdb;
        $ids=$wpdb->get_col($wpdb->prepare("SELECT id FROM {$this->table('licenses')} WHERE order_id=%d AND order_item_id=%d",$order->get_id(),$item_id));
        $map=$order->get_meta('_tapbix_license_renewal_map',true);
        if(is_array($map)&&isset($map[$item_id])) $ids=array_merge($ids,(array)$map[$item_id]);
        return array_values(array_unique(array_filter(array_map('absint',$ids))));
    }
    private function license_ids_for_order($order){
        global $wpdb;
        $ids=$wpdb->get_col($wpdb->prepare("SELECT id FROM {$this->table('licenses')} WHERE order_id=%d",$order->get_id()));
        $renewed=$order->get_meta('_tapbix_license_renewed_ids',true);
        if(is_array($renewed)) $ids=array_merge($ids,$renewed);
        return array_values(array_unique(array_filter(array_map('absint',$ids))));
    }
    private function licenses_for_order($order){
        $licenses=[];
        foreach($this->license_ids_for_order($order) as $license_id){
            $license=$this->get_license_by_id($license_id);
            if($license) $licenses[]=$license;
        }
        return $licenses;
    }
    private function suspend_license_ids($license_ids,$event,$details){
        global $wpdb;
        foreach(array_unique(array_map('absint',(array)$license_ids)) as $license_id){
            if(!$license_id) continue;
            $updated=$wpdb->update($this->table('licenses'),['status'=>'suspended'],['id'=>$license_id,'status'=>'active'],['%s'],['%d','%s']);
            if($updated) $this->log($license_id,$event,$details);
        }
    }
    private function order_is_fully_refunded($order){
        $total=(float)$order->get_total();
        return $order->has_status('refunded')||($total>0&&(float)$order->get_total_refunded()+0.000001>=$total);
    }
    private function reverse_capacity_for_order($order,$reason,$refund_id=0){
        $fully_refunded=$reason==='cancelled'||$this->order_is_fully_refunded($order);
        foreach($this->capacity_transactions_for_order($order->get_id()) as $transaction){
            $desired=0;
            if($fully_refunded){
                $desired=(int)$transaction->purchased_qty;
            }else{
                $item=$order->get_item((int)$transaction->order_item_id);
                if(!$item) continue;
                $refunded_qty=abs((int)$order->get_qty_refunded_for_item($transaction->order_item_id));
                $line_total=abs((float)$item->get_total());
                $refunded_total=abs((float)$order->get_total_refunded_for_item($transaction->order_item_id));
                if($line_total>0&&$refunded_total+0.000001>=$line_total){
                    $desired=(int)$transaction->purchased_qty;
                }elseif($refunded_qty>0){
                    $desired=min((int)$transaction->purchased_qty,$refunded_qty);
                }
            }
            if($desired>0) $this->reverse_capacity_transaction($order,(int)$transaction->id,$desired,$reason,absint($refund_id));
        }
    }
    private function reverse_capacity_transaction($order,$transaction_id,$desired_reversed,$reason,$refund_id){
        global $wpdb;
        if($wpdb->query('START TRANSACTION')===false) return;
        $transaction=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('capacity_transactions')} WHERE id=%d FOR UPDATE",$transaction_id));
        if(!$transaction){$wpdb->query('ROLLBACK');return;}
        $desired_reversed=min((int)$transaction->purchased_qty,max(0,(int)$desired_reversed));
        $delta=$desired_reversed-(int)$transaction->reversed_qty;
        if($delta<=0){
            $wpdb->query('ROLLBACK');
            return;
        }
        $license=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE id=%d FOR UPDATE",$transaction->license_id));
        if(!$license){
            $wpdb->query('ROLLBACK');
            $this->add_device_failure($transaction->license_id,'capacity_reversal_license_missing',['order_id'=>$order->get_id(),'order_item_id'=>(int)$transaction->order_item_id]);
            return;
        }

        $old_max=max(1,(int)$license->max_devices);
        $new_max=max(1,$old_max-$delta);
        $actual_change=$old_max-$new_max;
        if($actual_change>0){
            $updated=$wpdb->update($this->table('licenses'),['max_devices'=>$new_max],['id'=>$license->id],['%d'],['%d']);
            if($updated===false){$wpdb->query('ROLLBACK');return;}
        }
        $status=$desired_reversed>=(int)$transaction->purchased_qty?($reason==='cancelled'?'cancelled':'refunded'):'partially_refunded';
        $updated_transaction=$wpdb->update($this->table('capacity_transactions'),['reversed_qty'=>$desired_reversed,'status'=>$status,'updated_at'=>$this->now()],['id'=>$transaction->id],['%d','%s','%s'],['%d']);
        if($updated_transaction===false){$wpdb->query('ROLLBACK');return;}
        if($wpdb->query('COMMIT')===false){$wpdb->query('ROLLBACK');return;}

        $event=$reason==='cancelled'?'device_capacity_reversed_cancel':'device_capacity_reduced_refund';
        $details=['order_id'=>$order->get_id(),'order_item_id'=>(int)$transaction->order_item_id,'refund_id'=>$refund_id,'quantity'=>$delta,'actual_change'=>$actual_change,'max_devices'=>$new_max];
        $this->log((int)$license->id,$event,$details);
        $order->add_order_note(sprintf('TapBix license #%d device allowance reduced by %d to %d after %s.',(int)$license->id,$actual_change,$new_max,$reason==='cancelled'?'order cancellation':'refund'));
        $active_devices=$this->active_count($license->id);
        if($active_devices>$new_max){
            $warning=sprintf('TapBix warning: license #%d has %d active devices but now allows %d. No activation was deleted.',(int)$license->id,$active_devices,$new_max);
            $order->add_order_note($warning);
            $this->log((int)$license->id,'device_capacity_over_limit',['order_id'=>$order->get_id(),'active_devices'=>$active_devices,'max_devices'=>$new_max]);
        }
    }
    public function handle_order_refunded($order_id,$refund_id){
        if(!function_exists('wc_get_order')) return;
        $order=wc_get_order($order_id);
        if(!$order) return;

        $this->reverse_capacity_for_order($order,'refunded',$refund_id);
        $fully_refunded=$this->order_is_fully_refunded($order);
        if($fully_refunded){
            $this->suspend_license_ids($this->license_ids_for_order($order),'license_suspended_refund',['order_id'=>$order->get_id(),'refund_id'=>absint($refund_id),'scope'=>'full_order']);
            return;
        }

        foreach($order->get_items('line_item') as $item_id=>$item){
            $license_ids=$this->license_ids_for_order_item($order,$item_id);
            if(!$license_ids) continue;
            $ordered_qty=abs((float)$item->get_quantity());
            $refunded_qty=abs((float)$order->get_qty_refunded_for_item($item_id));
            $line_total=abs((float)$item->get_total());
            $refunded_total=abs((float)$order->get_total_refunded_for_item($item_id));
            $quantity_fully_refunded=$ordered_qty>0&&$refunded_qty+0.000001>=$ordered_qty;
            $amount_fully_refunded=$line_total>0&&$refunded_total+0.000001>=$line_total;
            if(!$quantity_fully_refunded&&!$amount_fully_refunded) continue;
            $this->suspend_license_ids($license_ids,'license_suspended_refund',['order_id'=>$order->get_id(),'refund_id'=>absint($refund_id),'order_item_id'=>(int)$item_id,'scope'=>'full_line_item','matched_by'=>$quantity_fully_refunded?'quantity':'amount']);
        }
    }
    public function handle_order_cancelled($order_id,$order=null){
        if(!function_exists('wc_get_order')) return;
        $order=is_a($order,'WC_Order')?$order:wc_get_order($order_id);
        if(!$order) return;
        $this->reverse_capacity_for_order($order,'cancelled');
        $this->suspend_license_ids($this->license_ids_for_order($order),'license_suspended_cancelled',['order_id'=>$order->get_id()]);
    }
    private function expiry_label($license){
        if(empty($license->expires_at)) return 'Lifetime';
        $timestamp=strtotime($license->expires_at.' UTC');
        if(!$timestamp) return (string)$license->expires_at;
        return wp_date(get_option('date_format').' '.get_option('time_format'),$timestamp);
    }
    private function get_license($key){ global $wpdb; return $wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE license_key=%s LIMIT 1",$key)); }
    private function activation($lid,$did){ global $wpdb; return $wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('activations')} WHERE license_id=%d AND device_id=%s LIMIT 1",$lid,$did)); }
    private function active_count($lid){ global $wpdb; return (int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM {$this->table('activations')} WHERE license_id=%d AND status='active'",$lid)); }
    private function rate_ok(){ $ip=isset($_SERVER['REMOTE_ADDR'])?sanitize_text_field(wp_unslash($_SERVER['REMOTE_ADDR'])):'unknown'; $k='tapbix_rl_'.md5(wp_salt('nonce').'|'.$ip); $n=(int)get_transient($k); if($n>=20)return false; set_transient($k,$n+1,5*MINUTE_IN_SECONDS); return true; }

    public function register_rest_routes(){
        register_rest_route('tapbix/v1','/activate',['methods'=>'POST','callback'=>[$this,'rest_activate'],'permission_callback'=>'__return_true']);
        register_rest_route('tapbix/v1','/validate',['methods'=>'POST','callback'=>[$this,'rest_validate'],'permission_callback'=>'__return_true']);
    }
    private function normalize_platform($value){
        $platform=strtolower(sanitize_key((string)$value));
        return in_array($platform,['windows','linux'],true)?$platform:'';
    }
    private function allowed_platforms($license){
        $product=(string)$license->product_code;
        if($product==='tapbix-desktop') return ['windows','linux'];
        if($product==='tapbix-linux') return ['linux'];
        return ['windows'];
    }
    private function get_license_by_id($id){ global $wpdb; return $wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE id=%d LIMIT 1",$id)); }
    private function new_activation_token(){ return rtrim(strtr(base64_encode(random_bytes(32)),'+/','-_'),'='); }
    private function token_hash($token){ return hash('sha256',(string)$token); }
    private function payload($l,$did,$platform){
        $now=time();
        return [
            'schema'=>2,
            'app_id'=>self::APP_ID,
            'license_id'=>(int)$l->id,
            'product'=>(string)$l->product_code,
            'plan'=>(string)$l->plan,
            'max_devices'=>(int)$l->max_devices,
            'device_id'=>(string)$did,
            'platform'=>(string)$platform,
            'platforms'=>$this->allowed_platforms($l),
            'issued_at'=>gmdate('c',$now),
            'revalidate_after'=>gmdate('c',$now+self::REVALIDATE_AFTER_SECONDS),
            'offline_valid_until'=>gmdate('c',$now+self::OFFLINE_LEASE_SECONDS),
            'expires_at'=>$l->expires_at?gmdate('c',strtotime($l->expires_at.' UTC')):null
        ];
    }
    private function sign($payload){ $priv=get_option(self::PRIV_OPT); if(!$priv||!function_exists('openssl_sign')) return new WP_Error('signing_unavailable','License signing unavailable.',['status'=>500]); $json=wp_json_encode($payload,JSON_UNESCAPED_SLASHES); $sig=''; if(!openssl_sign($json,$sig,$priv,OPENSSL_ALGO_SHA256)) return new WP_Error('signing_failed','Could not sign license.',['status'=>500]); return ['payload'=>$payload,'payload_json'=>$json,'signature'=>base64_encode($sig),'algorithm'=>'RSA-SHA256']; }

    private function is_test_license($license){
        return $license && is_string($license->notes) && strpos($license->notes,'[TEST]')===0;
    }

    private function create_test_license(){
        global $wpdb;
        $u=wp_get_current_user();
        if(!$u||!$u->exists()) return new WP_Error('no_user','No current administrator user.');
        $config=$this->config_for_sku('TAPBIX-DESKTOP-LIFETIME-1D');

        do{
            $key=$this->gen_key();
            $dup=$wpdb->get_var($wpdb->prepare(
                "SELECT id FROM {$this->table('licenses')} WHERE license_key=%s LIMIT 1",
                $key
            ));
        }while($dup);

        $ok=$wpdb->insert(
            $this->table('licenses'),
            [
                'license_key'=>$key,
                'product_code'=>self::PRODUCT_CODE,
                'plan'=>$config['plan'],
                'max_devices'=>$config['max_devices'],
                'status'=>'active',
                'customer_id'=>$u->ID,
                'customer_email'=>$u->user_email,
                'order_id'=>null,
                'order_item_id'=>null,
                'created_at'=>$this->now(),
                'expires_at'=>null,
                'notes'=>'[TEST] Development license created from WordPress admin.'
            ],
            ['%s','%s','%s','%d','%s','%d','%s','%d','%d','%s','%s','%s']
        );

        if(!$ok) return new WP_Error('db_insert_failed','Could not create the test license.');

        $id=(int)$wpdb->insert_id;
        $this->log($id,'test_license_created',['admin_user_id'=>$u->ID]);
        return $this->get_license($key);
    }

    private function run_internal_test_activation($license){
        if(!$license) return new WP_Error('missing_license','License not found.');
        if(!$this->is_test_license($license)) return new WP_Error('not_test_license','Only TEST licenses can use the built-in activation test.');

        $device_id='tapbix-test-device-'.(int)$license->id;
        $device_name='TapBix Test Device';
        $app_version='TEST-0.5.1';
        $platform='linux';
        if(!in_array($platform,$this->allowed_platforms($license),true)){
            return new WP_Error('invalid_product','The TEST license does not allow Linux.');
        }
        $token=$this->new_activation_token();
        $token_hash=$this->token_hash($token);

        global $wpdb;
        $a=$this->activation($license->id,$device_id);
        if($a){
            $ok=$wpdb->update(
                $this->table('activations'),
                ['platform'=>$platform,'activation_token_hash'=>$token_hash,'device_name'=>$device_name,'app_version'=>$app_version,'status'=>'active','last_seen_at'=>$this->now(),'deactivated_at'=>null],
                ['id'=>$a->id],
                ['%s','%s','%s','%s','%s','%s','%s'],
                ['%d']
            );
        }else{
            if($this->active_count($license->id)>=(int)$license->max_devices){
                return new WP_Error('device_limit_reached','The test license has already reached its device limit. Use Reset devices first.');
            }
            $ok=$wpdb->insert(
                $this->table('activations'),
                ['license_id'=>$license->id,'device_id'=>$device_id,'platform'=>$platform,'activation_token_hash'=>$token_hash,'device_name'=>$device_name,'app_version'=>$app_version,'status'=>'active','activated_at'=>$this->now(),'last_seen_at'=>$this->now()],
                ['%d','%s','%s','%s','%s','%s','%s','%s','%s']
            );
        }
        if($ok===false) return new WP_Error('activation_write_failed','Could not store the test activation.');

        $signed=$this->sign($this->payload($license,$device_id,$platform));
        if(is_wp_error($signed)) return $signed;
        $public_key=get_option(self::PUB_OPT);
        if(!$public_key||!function_exists('openssl_verify')) return new WP_Error('verify_unavailable','Public-key verification is unavailable on the server.');
        $signature=base64_decode($signed['signature'],true);
        if($signature===false) return new WP_Error('signature_decode_failed','Could not decode the generated signature.');
        $verify=openssl_verify($signed['payload_json'],$signature,$public_key,OPENSSL_ALGO_SHA256);
        if($verify!==1) return new WP_Error('signature_verify_failed','The generated license signature did not verify with the public key.');

        $payload=json_decode($signed['payload_json'],true);
        if(!is_array($payload)||(int)($payload['schema']??0)!==2||($payload['app_id']??'')!==self::APP_ID||($payload['platform']??'')!==$platform||strlen($token)<32){
            return new WP_Error('protocol_test_failed','The generated activation response does not match the desktop v2 protocol.');
        }
        $this->log($license->id,'test_activation_success',['device_id'=>$device_id,'platform'=>$platform,'signature_verified'=>true,'protocol_schema'=>2]);
        return ['device_id'=>$device_id,'device_name'=>$device_name,'platform'=>$platform,'signature_verified'=>true,'protocol_schema'=>2,'algorithm'=>$signed['algorithm']];
    }

    public function rest_activate(WP_REST_Request $r){
        if(!$this->rate_ok()) return new WP_Error('rate_limited','Too many attempts.',['status'=>429]);
        $key=strtoupper(trim((string)$r->get_param('license_key')));
        $did=trim((string)$r->get_param('device_id'));
        $name=substr(sanitize_text_field((string)$r->get_param('device_name')),0,190);
        $ver=substr(sanitize_text_field((string)$r->get_param('app_version')),0,50);
        $platform=$this->normalize_platform($r->get_param('platform'));
        if(!preg_match('/^TBX(?:-[A-HJ-NP-Z2-9]{4}){5}$/',$key)||strlen($did)<8||strlen($did)>190||!$platform){
            return new WP_Error('invalid_request','Valid license_key, device_id, and platform are required.',['status'=>400]);
        }

        $l=$this->get_license($key);
        if(!$l){
            $this->log(null,'activation_invalid_key');
            return new WP_Error('invalid_license','Invalid license key.',['status'=>404]);
        }
        if($l->status!=='active') return new WP_Error('license_revoked','License is not active.',['status'=>403]);
        if($l->expires_at&&strtotime($l->expires_at.' UTC')<time()) return new WP_Error('license_expired','License expired.',['status'=>403]);
        if(!in_array($platform,$this->allowed_platforms($l),true)) return new WP_Error('invalid_product','License is not valid for this platform.',['status'=>403]);

        $token=$this->new_activation_token();
        $token_hash=$this->token_hash($token);
        global $wpdb;
        $a=$this->activation($l->id,$did);
        if($a){
            if($a->status!=='active'&&$this->active_count($l->id)>=(int)$l->max_devices){
                return new WP_Error('device_limit_reached','Device limit reached.',['status'=>409]);
            }
            $ok=$wpdb->update(
                $this->table('activations'),
                ['platform'=>$platform,'activation_token_hash'=>$token_hash,'device_name'=>$name,'app_version'=>$ver,'status'=>'active','last_seen_at'=>$this->now(),'deactivated_at'=>null],
                ['id'=>$a->id],
                ['%s','%s','%s','%s','%s','%s','%s'],
                ['%d']
            );
        }else{
            if($this->active_count($l->id)>=(int)$l->max_devices) return new WP_Error('device_limit_reached','Device limit reached.',['status'=>409]);
            $ok=$wpdb->insert(
                $this->table('activations'),
                ['license_id'=>$l->id,'device_id'=>$did,'platform'=>$platform,'activation_token_hash'=>$token_hash,'device_name'=>$name,'app_version'=>$ver,'status'=>'active','activated_at'=>$this->now(),'last_seen_at'=>$this->now()],
                ['%d','%s','%s','%s','%s','%s','%s','%s','%s']
            );
        }
        if($ok===false) return new WP_Error('activation_write_failed','Could not store device activation.',['status'=>500]);

        $s=$this->sign($this->payload($l,$did,$platform));
        if(is_wp_error($s)) return $s;
        $this->log($l->id,'activation_success',['device_id_hash'=>substr(hash('sha256',$did),0,16),'platform'=>$platform,'app_version'=>$ver]);
        return rest_ensure_response(['ok'=>true,'license_id'=>(int)$l->id,'activation_token'=>$token,'license'=>$s]);
    }

    public function rest_validate(WP_REST_Request $r){
        if(!$this->rate_ok()) return new WP_Error('rate_limited','Too many attempts.',['status'=>429]);
        $license_id=absint($r->get_param('license_id'));
        $token=trim((string)$r->get_param('activation_token'));
        $did=trim((string)$r->get_param('device_id'));
        $platform=$this->normalize_platform($r->get_param('platform'));
        $ver=substr(sanitize_text_field((string)$r->get_param('app_version')),0,50);
        if(!$license_id||strlen($token)<32||strlen($token)>200||strlen($did)<8||strlen($did)>190||!$platform){
            return new WP_Error('invalid_request','license_id, activation_token, device_id, and platform are required.',['status'=>400]);
        }

        $l=$this->get_license_by_id($license_id);
        if(!$l||$l->status!=='active') return new WP_Error('license_revoked','License is not active.',['status'=>403]);
        if($l->expires_at&&strtotime($l->expires_at.' UTC')<time()) return new WP_Error('license_expired','License expired.',['status'=>403]);
        if(!in_array($platform,$this->allowed_platforms($l),true)) return new WP_Error('invalid_product','License is not valid for this platform.',['status'=>403]);

        $a=$this->activation($l->id,$did);
        if(!$a||$a->status!=='active') return new WP_Error('device_not_active','Device not active.',['status'=>403]);
        if((string)$a->platform!==$platform) return new WP_Error('platform_mismatch','Activation belongs to another platform.',['status'=>403]);
        if(empty($a->activation_token_hash)||!hash_equals((string)$a->activation_token_hash,$this->token_hash($token))){
            return new WP_Error('activation_required','Activate this device again.',['status'=>403]);
        }

        global $wpdb;
        $wpdb->update($this->table('activations'),['app_version'=>$ver,'last_seen_at'=>$this->now()],['id'=>$a->id],['%s','%s'],['%d']);
        $s=$this->sign($this->payload($l,$did,$platform));
        if(is_wp_error($s)) return $s;
        $this->log($l->id,'validation_success',['device_id_hash'=>substr(hash('sha256',$did),0,16),'platform'=>$platform,'app_version'=>$ver]);
        return rest_ensure_response(['ok'=>true,'license'=>$s]);
    }

    public function register_account_endpoint(){ add_rewrite_endpoint(self::ENDPOINT,EP_ROOT|EP_PAGES); }
    public function account_query_vars($v){$v[]=self::ENDPOINT;return $v;}
    public function account_menu_item($items){ $logout=$items['customer-logout']??null; if($logout!==null)unset($items['customer-logout']); $items[self::ENDPOINT]='TapBix Licenses'; if($logout!==null)$items['customer-logout']=$logout; return $items; }
    private function customer_licenses(){ global $wpdb; $u=wp_get_current_user(); if(!$u||!$u->exists())return []; return $wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE customer_id=%d OR ((customer_id IS NULL OR customer_id=0) AND customer_email=%s) ORDER BY id DESC",$u->ID,$u->user_email)); }
    public function render_account_licenses(){
        if(!is_user_logged_in()){echo '<p>Please log in.</p>';return;}
        $licenses=$this->customer_licenses();
        echo '<h2>TapBix Licenses</h2>';
        if(!$licenses){echo '<p>No TapBix licenses linked to this account yet.</p>';return;}
        global $wpdb;
        $add_product=$this->add_device_product();
        $add_product_available=$add_product&&$add_product->is_purchasable()&&$add_product->is_in_stock();
        foreach($licenses as $license){
            $activations=$wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('activations')} WHERE license_id=%d AND status='active' ORDER BY id DESC",$license->id));
            $active_count=count($activations);
            echo '<div style="border:1px solid #ddd;border-radius:10px;padding:18px;margin:0 0 18px">';
            echo '<strong>TapBix Desktop</strong><br>';
            echo 'License: <code>'.esc_html($license->license_key).'</code><br>';
            echo 'Plan: '.esc_html(ucfirst($license->plan)).'<br>';
            echo 'Status: '.esc_html(ucfirst($license->status)).'<br>';
            echo 'Devices: '.(int)$active_count.' of '.(int)$license->max_devices.'<br>';
            echo 'Expires: '.esc_html($this->expiry_label($license));
            if($active_count>(int)$license->max_devices) echo '<p style="color:#b45309"><strong>Warning:</strong> Active devices exceed the current allowance. No device was removed; deactivate an unused device before adding another.</p>';
            if($activations){
                echo '<ul>';
                foreach($activations as $activation){
                    $url=wp_nonce_url(wc_get_account_endpoint_url(self::ENDPOINT).'?tapbix_deactivate='.(int)$activation->id,'tapbix_deactivate_'.(int)$activation->id);
                    echo '<li>'.esc_html($activation->device_name?:'Desktop device').' — <a href="'.esc_url($url).'">Deactivate</a></li>';
                }
                echo '</ul>';
            }
            if($add_product_available&&$this->is_add_device_eligible_license($license)){
                $max_quantity=(int)$add_product->get_max_purchase_quantity();
                echo '<form method="post" action="'.esc_url(wc_get_account_endpoint_url(self::ENDPOINT)).'" style="display:flex;gap:8px;align-items:end;flex-wrap:wrap;margin-top:14px">';
                echo '<input type="hidden" name="tapbix_add_device" value="1">';
                echo '<input type="hidden" name="license_id" value="'.(int)$license->id.'">';
                wp_nonce_field('tapbix_add_device_'.(int)$license->id,'tapbix_add_device_nonce');
                echo '<label>Additional devices<br><input type="number" name="quantity" min="1"'.($max_quantity>0?' max="'.(int)$max_quantity.'"':'').' value="1" required style="width:90px"></label>';
                echo '<button type="submit" class="button">Add another device</button>';
                echo '</form>';
            }
            echo '</div>';
        }
    }
    public function handle_customer_deactivate(){
        $this->handle_add_device_request();
        if(!is_user_logged_in()||empty($_GET['tapbix_deactivate']))return; $id=absint($_GET['tapbix_deactivate']); check_admin_referer('tapbix_deactivate_'.$id); global $wpdb; $a=$wpdb->get_row($wpdb->prepare("SELECT a.*,l.customer_id,l.customer_email FROM {$this->table('activations')} a INNER JOIN {$this->table('licenses')} l ON l.id=a.license_id WHERE a.id=%d LIMIT 1",$id)); $u=wp_get_current_user(); $owns=$a&&((int)$a->customer_id>0?(int)$a->customer_id===(int)$u->ID:!empty($a->customer_email)&&strtolower((string)$a->customer_email)===strtolower((string)$u->user_email)); if(!$owns)wp_die('Not allowed.'); $wpdb->update($this->table('activations'),['status'=>'inactive','deactivated_at'=>$this->now()],['id'=>$id],['%s','%s'],['%d']); $this->log($a->license_id,'customer_device_deactivated',['activation_id'=>$id]); wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT)); exit;
    }
    public function email_license_details($order,$sent,$plain,$email){
        if($sent||!$order||!is_a($order,'WC_Order')) return;
        $licenses=$this->licenses_for_order($order);
        $capacity_transactions=$this->capacity_transactions_for_order($order->get_id());
        if(!$licenses&&!$capacity_transactions) return;
        if($plain){
            if($licenses) echo "\nTapBix Desktop License\n";
            foreach($licenses as $license){
                echo "Activation code: {$license->license_key}\nPlan: ".ucfirst($license->plan)."\nExpires: ".$this->expiry_label($license)."\nAllowed devices: {$license->max_devices}\n";
                if($license->plan==='lifetime') echo "This is a perpetual license. The same TapBix Desktop license supports Windows and Linux where available.\n";
                echo "\n";
            }
        foreach($capacity_transactions as $transaction){
            $license=$this->get_license_by_id($transaction->license_id);
            if(!$license) continue;
                if(in_array($transaction->status,['refunded','cancelled'],true)){
                    echo "\nTapBix Desktop device allowance adjustment\nExisting activation code: {$license->license_key}\nReversed device capacity: {$transaction->reversed_qty}\nAllowed devices now: {$license->max_devices}\nNo activation or device history was deleted.\n\n";
                }elseif($transaction->status==='partially_refunded'){
                    echo "\nYour TapBix Desktop device allowance was adjusted after a partial refund.\nExisting activation code: {$license->license_key}\nPurchased device capacity: {$transaction->purchased_qty}\nReversed device capacity: {$transaction->reversed_qty}\nAllowed devices now: {$license->max_devices}\nContinue using your existing activation code.\n\n";
                }else{
                    echo "\nYour existing TapBix Desktop license was updated.\nExisting activation code: {$license->license_key}\nPurchased device capacity: {$transaction->purchased_qty}\nAllowed devices now: {$license->max_devices}\nContinue using your existing activation code.\n\n";
                }
            }
            return;
        }
        if($licenses) echo '<h2>TapBix Desktop License</h2>';
        foreach($licenses as $license){
            echo '<p><strong>Activation code:</strong> <code>'.esc_html($license->license_key).'</code><br><strong>Plan:</strong> '.esc_html(ucfirst($license->plan)).'<br><strong>Expires:</strong> '.esc_html($this->expiry_label($license)).'<br><strong>Allowed devices:</strong> '.(int)$license->max_devices;
            if($license->plan==='lifetime') echo '<br>This is a perpetual license. The same TapBix Desktop license supports Windows and Linux where available.';
            echo '</p>';
        }
        foreach($capacity_transactions as $transaction){
            $license=$this->get_license_by_id($transaction->license_id);
            if(!$license) continue;
            if(in_array($transaction->status,['refunded','cancelled'],true)){
                echo '<h2>TapBix Desktop device allowance adjustment</h2><p>The device capacity from this order was reversed. No activation or device history was deleted.<br><strong>Existing activation code:</strong> <code>'.esc_html($license->license_key).'</code><br><strong>Reversed device capacity:</strong> '.(int)$transaction->reversed_qty.'<br><strong>Allowed devices now:</strong> '.(int)$license->max_devices.'</p>';
            }elseif($transaction->status==='partially_refunded'){
                echo '<h2>TapBix Desktop device allowance adjusted</h2><p>Your device allowance was adjusted after a partial refund.<br><strong>Existing activation code:</strong> <code>'.esc_html($license->license_key).'</code><br><strong>Purchased device capacity:</strong> '.(int)$transaction->purchased_qty.'<br><strong>Reversed device capacity:</strong> '.(int)$transaction->reversed_qty.'<br><strong>Allowed devices now:</strong> '.(int)$license->max_devices.'<br>Continue using your existing activation code.</p>';
            }else{
                echo '<h2>TapBix Desktop device allowance updated</h2><p>Your existing license was updated; no new activation code was created.<br><strong>Existing activation code:</strong> <code>'.esc_html($license->license_key).'</code><br><strong>Purchased device capacity:</strong> '.(int)$transaction->purchased_qty.'<br><strong>Allowed devices now:</strong> '.(int)$license->max_devices.'<br>Continue using your existing activation code.</p>';
            }
        }
    }

    public function admin_menu(){ add_menu_page('TapBix Licenses','TapBix Licenses','manage_woocommerce','tapbix-licenses',[$this,'admin_page'],'dashicons-admin-network',56); }
    private function admin_customer_details($license){
        $email=sanitize_email($license->customer_email??'');
        $name='';
        $phone='';

        if(!empty($license->order_id)&&function_exists('wc_get_order')){
            static $order_customers=[];
            $order_id=absint($license->order_id);
            if(!array_key_exists($order_id,$order_customers)){
                $order=wc_get_order($order_id);
                $order_customers[$order_id]=$order?[
                    'name'=>trim((string)$order->get_billing_first_name().' '.(string)$order->get_billing_last_name()),
                    'phone'=>(string)$order->get_billing_phone(),
                    'email'=>(string)$order->get_billing_email(),
                ]:[];
            }
            $order_customer=$order_customers[$order_id];
            $name=(string)($order_customer['name']??'');
            $phone=(string)($order_customer['phone']??'');
            if(!$email) $email=sanitize_email($order_customer['email']??'');
        }

        if((!$name||!$phone||!$email)&&!empty($license->customer_id)){
            static $user_customers=[];
            $customer_id=absint($license->customer_id);
            if(!array_key_exists($customer_id,$user_customers)){
                $user=get_userdata($customer_id);
                if($user){
                    $first=(string)get_user_meta($customer_id,'billing_first_name',true);
                    $last=(string)get_user_meta($customer_id,'billing_last_name',true);
                    if(!$first&&!$last){
                        $first=(string)get_user_meta($customer_id,'first_name',true);
                        $last=(string)get_user_meta($customer_id,'last_name',true);
                    }
                    $user_customers[$customer_id]=[
                        'name'=>trim($first.' '.$last)?:$user->display_name,
                        'phone'=>(string)get_user_meta($customer_id,'billing_phone',true),
                        'email'=>$user->user_email,
                    ];
                }else{
                    $user_customers[$customer_id]=[];
                }
            }
            $user_customer=$user_customers[$customer_id];
            if(!$name) $name=(string)($user_customer['name']??'');
            if(!$phone) $phone=(string)($user_customer['phone']??'');
            if(!$email) $email=sanitize_email($user_customer['email']??'');
        }

        return ['name'=>sanitize_text_field($name),'phone'=>sanitize_text_field($phone),'email'=>$email];
    }
    private function admin_customer_matches($details,$search){
        $search=trim((string)$search);
        if($search==='') return true;
        $normalize=static function($value){
            $value=(string)$value;
            return function_exists('mb_strtolower')?mb_strtolower($value,'UTF-8'):strtolower($value);
        };
        $needle=$normalize($search);
        $haystack=$normalize(implode(' ',[(string)$details['name'],(string)$details['email'],(string)$details['phone']]));
        if(strpos($haystack,$needle)!==false) return true;
        $phone_needle=preg_replace('/\D+/','',$search);
        $phone_value=preg_replace('/\D+/','',(string)$details['phone']);
        return strlen($phone_needle)>=3&&strpos($phone_value,$phone_needle)!==false;
    }
    private function admin_license_rows($search){
        global $wpdb;
        $matches=[];
        $customers=[];
        $batch_size=250;
        $offset=0;
        do{
            $rows=$wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('licenses')} ORDER BY id DESC LIMIT %d OFFSET %d",$batch_size,$offset));
            foreach($rows as $license){
                $customer=$this->admin_customer_details($license);
                if(!$this->admin_customer_matches($customer,$search)) continue;
                $matches[]=$license;
                $customers[(int)$license->id]=$customer;
                if(count($matches)>=250) break 2;
            }
            $offset+=$batch_size;
        }while(count($rows)===$batch_size&&$search!=='');
        return ['licenses'=>$matches,'customers'=>$customers,'limited'=>count($matches)>=250];
    }
    public function admin_page(){
        if(!current_user_can('manage_woocommerce')) return;

        $search=isset($_GET['s'])?sanitize_text_field(wp_unslash($_GET['s'])):'';
        $admin_rows=$this->admin_license_rows($search);
        $ls=$admin_rows['licenses'];
        $customer_details=$admin_rows['customers'];
        $pub=get_option(self::PUB_OPT,'');

        echo '<div class="wrap"><h1>TapBix Licenses</h1>';
        echo '<p>Plugin version: <code>'.esc_html(self::VERSION).'</code></p>';
        echo '<p><strong>Supported SKUs:</strong></p><ul style="list-style:disc;padding-left:22px">';
        foreach(self::sku_configs() as $sku=>$config) echo '<li><code>'.esc_html($sku).'</code> — '.esc_html(ucfirst($config['plan'])).', '.(int)$config['max_devices'].' device</li>';
        echo '<li><code>'.esc_html(self::ADD_DEVICE_SKU).'</code> — additional capacity for an existing eligible lifetime license; never issues a license key</li>';
        echo '</ul>';

        if(!empty($_GET['tapbix_notice'])){
            $notice=sanitize_key(wp_unslash($_GET['tapbix_notice']));
            $message=isset($_GET['tapbix_message'])?sanitize_text_field(wp_unslash($_GET['tapbix_message'])):'';
            if($notice==='test_created'){
                echo '<div class="notice notice-success inline"><p><strong>Test license created successfully.</strong> You can now click <em>Test activation</em> on that license row.</p></div>';
            }elseif($notice==='test_activation_ok'){
                $device=isset($_GET['tapbix_device'])?sanitize_text_field(wp_unslash($_GET['tapbix_device'])):'';
                echo '<div class="notice notice-success inline"><p><strong>Activation test passed.</strong> Device was activated and the RSA-SHA256 signature and desktop schema 2 verified successfully with the public key.';
                if($device) echo ' Test device: <code>'.esc_html($device).'</code>';
                echo '</p></div>';
            }elseif(in_array($notice,['test_create_error','test_activation_error'],true)){
                echo '<div class="notice notice-error inline"><p><strong>Test failed:</strong> '.esc_html($message?:'Unknown error').'</p></div>';
            }
        }

        echo '<div style="background:#fff;border:1px solid #dcdcde;border-radius:8px;padding:18px;margin:18px 0;max-width:900px">';
        echo '<h2 style="margin-top:0">Controlled test tools</h2>';
        echo '<p>Create a development-only license without publishing the product or connecting a payment gateway. Test licenses are clearly marked and can be deleted safely.</p>';
        echo '<form method="post" action="'.esc_url(admin_url('admin-post.php')).'">';
        echo '<input type="hidden" name="action" value="tapbix_create_test_license">';
        wp_nonce_field('tapbix_create_test_license');
        submit_button('Create Test License','secondary','submit',false);
        echo '</form></div>';

        echo '<h2>Public key for TapBix Desktop</h2>';
        if($pub){
            echo '<textarea readonly style="width:100%;max-width:900px;height:180px;font-family:monospace">'.esc_textarea($pub).'</textarea>';
            echo '<p><strong>Keep the private key on this server only.</strong> The public key above must match the key embedded in the TapBix Desktop app.</p>';
        }else{
            echo '<div class="notice notice-error inline"><p>Signing key unavailable. Confirm PHP OpenSSL is enabled.</p></div>';
        }

        echo '<h2>Licenses</h2>';
        echo '<form method="get" action="'.esc_url(admin_url('admin.php')).'" style="display:flex;gap:8px;align-items:center;margin:10px 0 16px">';
        echo '<input type="hidden" name="page" value="tapbix-licenses">';
        echo '<label class="screen-reader-text" for="tapbix-license-search">Search by customer email, name, or phone</label>';
        echo '<input id="tapbix-license-search" type="search" name="s" value="'.esc_attr($search).'" placeholder="Email, customer name, or phone" style="min-width:320px">';
        echo '<button type="submit" class="button">Search</button>';
        if($search!=='') echo '<a class="button" href="'.esc_url(admin_url('admin.php?page=tapbix-licenses')).'">Clear</a>';
        echo '</form>';
        if($search!=='') echo '<p>'.($admin_rows['limited']?'Showing the first 250 matching licenses.':'Found '.count($ls).' matching license'.(count($ls)===1?'':'s').'.').'</p>';
        echo '<table class="widefat striped"><thead><tr>';
        echo '<th>ID</th><th>License</th><th>Customer</th><th>Name</th><th>Phone</th><th>Plan</th><th>Expires</th><th>Used</th><th>Max</th><th>Status</th><th>Order</th><th>Type</th><th>Created</th><th>Actions</th>';
        echo '</tr></thead><tbody>';

        if(!$ls) echo '<tr><td colspan="14">'.($search!==''?'No licenses matched this customer search.':'No licenses issued yet.').'</td></tr>';

        foreach($ls as $l){
            $c=$this->active_count($l->id);
            $is_test=$this->is_test_license($l);
            $customer=$customer_details[(int)$l->id]??$this->admin_customer_details($l);
            $customer_email=$l->customer_email?:$customer['email'];
            $phone_link=preg_replace('/[^0-9+]/','',(string)$customer['phone']);

            echo '<tr>';
            echo '<td>'.(int)$l->id.'</td>';
            echo '<td><code>'.esc_html($l->license_key).'</code></td>';
            echo '<td>'.($customer_email?'<a href="'.esc_attr('mailto:'.$customer_email).'">'.esc_html($customer_email).'</a>':'—').'</td>';
            echo '<td>'.esc_html($customer['name']?:'—').'</td>';
            echo '<td>'.($customer['phone']?($phone_link?'<a href="'.esc_attr('tel:'.$phone_link).'">'.esc_html($customer['phone']).'</a>':esc_html($customer['phone'])):'—').'</td>';
            echo '<td>'.esc_html($l->plan).'</td>';
            echo '<td>'.esc_html($this->expiry_label($l)).'</td>';
            echo '<td>'.$c.($c>(int)$l->max_devices?'<br><strong style="color:#b45309">Over capacity</strong>':'').'</td>';
            echo '<td>'.(int)$l->max_devices.'</td>';
            echo '<td>'.esc_html($l->status).'</td>';
            echo '<td>'.esc_html($l->order_id?'#'.$l->order_id:'—').'</td>';
            echo '<td>'.($is_test?'<strong style="color:#b45309">TEST</strong>':'Live').'</td>';
            echo '<td>'.esc_html($l->created_at).'</td>';
            echo '<td>';

            foreach(['active'=>'Activate','suspended'=>'Suspend','revoked'=>'Revoke','reset'=>'Reset devices'] as $act=>$lab){
                $url=wp_nonce_url(
                    admin_url('admin-post.php?action=tapbix_license_action&license_id='.(int)$l->id.'&license_action='.rawurlencode($act)),
                    'tapbix_admin_license_'.(int)$l->id
                );
                echo '<a style="margin-right:8px" href="'.esc_url($url).'">'.esc_html($lab).'</a>';
            }

            echo '<form method="post" action="'.esc_url(admin_url('admin-post.php')).'" style="margin-top:8px;display:flex;gap:5px;align-items:center">';
            echo '<input type="hidden" name="action" value="tapbix_adjust_max_devices">';
            echo '<input type="hidden" name="license_id" value="'.(int)$l->id.'">';
            wp_nonce_field('tapbix_adjust_max_devices_'.(int)$l->id,'tapbix_adjust_max_devices_nonce');
            echo '<input type="number" name="max_devices" min="1" value="'.(int)$l->max_devices.'" required style="width:70px">';
            echo '<button type="submit" class="button button-small">Set max</button></form>';

            if($is_test){
                $test_url=wp_nonce_url(
                    admin_url('admin-post.php?action=tapbix_test_activation&license_id='.(int)$l->id),
                    'tapbix_test_activation_'.(int)$l->id
                );
                $delete_url=wp_nonce_url(
                    admin_url('admin-post.php?action=tapbix_license_action&license_id='.(int)$l->id.'&license_action=delete_test'),
                    'tapbix_admin_license_'.(int)$l->id
                );
                echo '<br><a style="margin-right:8px;font-weight:600" href="'.esc_url($test_url).'">Test activation</a>';
                echo '<a style="color:#b32d2e" href="'.esc_url($delete_url).'" onclick="return confirm(\'Delete this TEST license and its test activations?\')">Delete test</a>';
            }

            echo '</td></tr>';
        }

        echo '</tbody></table></div>';
    }
    public function handle_admin_action(){
        if(!current_user_can('manage_woocommerce'))wp_die('Not allowed.'); $id=isset($_GET['license_id'])?absint($_GET['license_id']):0; $act=isset($_GET['license_action'])?sanitize_key(wp_unslash($_GET['license_action'])):''; check_admin_referer('tapbix_admin_license_'.$id); global $wpdb; if(in_array($act,['active','suspended','revoked'],true)){
            $wpdb->update($this->table('licenses'),['status'=>$act],['id'=>$id],['%s'],['%d']);
            $this->log($id,'admin_status_changed',['status'=>$act]);
            $event=['active'=>'license_activated','suspended'=>'license_suspended','revoked'=>'license_revoked'][$act];
            $this->log($id,$event,['source'=>'admin']);
        }elseif($act==='reset'){
            $wpdb->update($this->table('activations'),['status'=>'inactive','deactivated_at'=>$this->now()],['license_id'=>$id,'status'=>'active'],['%s','%s'],['%d','%s']);
            $this->log($id,'admin_devices_reset');
        }elseif($act==='delete_test'){
            $license=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE id=%d LIMIT 1",$id));
            if(!$this->is_test_license($license)) wp_die('Only TEST licenses can be deleted with this action.');
            $wpdb->delete($this->table('activations'),['license_id'=>$id],['%d']);
            $wpdb->delete($this->table('license_logs'),['license_id'=>$id],['%d']);
            $wpdb->delete($this->table('licenses'),['id'=>$id],['%d']);
        }
        wp_safe_redirect(admin_url('admin.php?page=tapbix-licenses'));exit;
    }

    public function handle_adjust_max_devices(){
        if(!current_user_can('manage_woocommerce')) wp_die('Not allowed.');
        $license_id=isset($_POST['license_id'])?absint(wp_unslash($_POST['license_id'])):0;
        $nonce=isset($_POST['tapbix_adjust_max_devices_nonce'])?sanitize_text_field(wp_unslash($_POST['tapbix_adjust_max_devices_nonce'])):'';
        if(!$license_id||!wp_verify_nonce($nonce,'tapbix_adjust_max_devices_'.$license_id)) wp_die('Invalid request.');
        $max_devices=$this->normalize_device_quantity(wp_unslash($_POST['max_devices']??''));
        if(!$max_devices) wp_die('Maximum devices must be an integer of at least 1.');
        $license=$this->get_license_by_id($license_id);
        if(!$license) wp_die('License not found.');
        global $wpdb;
        $old_max=(int)$license->max_devices;
        $updated=$wpdb->update($this->table('licenses'),['max_devices'=>$max_devices],['id'=>$license_id],['%d'],['%d']);
        if($updated===false) wp_die('Could not update maximum devices.');
        $this->log($license_id,'manual_max_devices_changed',['old_max_devices'=>$old_max,'max_devices'=>$max_devices,'admin_user_id'=>get_current_user_id()]);
        $active_devices=$this->active_count($license_id);
        if($active_devices>$max_devices) $this->log($license_id,'device_capacity_over_limit',['source'=>'manual_adjustment','active_devices'=>$active_devices,'max_devices'=>$max_devices]);
        wp_safe_redirect(admin_url('admin.php?page=tapbix-licenses'));
        exit;
    }

    public function handle_create_test_license(){
        if(!current_user_can('manage_woocommerce')) wp_die('Not allowed.');
        check_admin_referer('tapbix_create_test_license');

        $result=$this->create_test_license();
        if(is_wp_error($result)){
            $url=add_query_arg([
                'page'=>'tapbix-licenses',
                'tapbix_notice'=>'test_create_error',
                'tapbix_message'=>$result->get_error_message()
            ],admin_url('admin.php'));
        }else{
            $url=add_query_arg([
                'page'=>'tapbix-licenses',
                'tapbix_notice'=>'test_created',
                'tapbix_license_id'=>(int)$result->id
            ],admin_url('admin.php'));
        }

        wp_safe_redirect($url);
        exit;
    }

    public function handle_test_activation(){
        if(!current_user_can('manage_woocommerce')) wp_die('Not allowed.');
        $id=isset($_GET['license_id'])?absint($_GET['license_id']):0;
        check_admin_referer('tapbix_test_activation_'.$id);

        $license=null;
        if($id){
            global $wpdb;
            $license=$wpdb->get_row($wpdb->prepare(
                "SELECT * FROM {$this->table('licenses')} WHERE id=%d LIMIT 1",
                $id
            ));
        }

        $result=$this->run_internal_test_activation($license);
        if(is_wp_error($result)){
            $url=add_query_arg([
                'page'=>'tapbix-licenses',
                'tapbix_notice'=>'test_activation_error',
                'tapbix_message'=>$result->get_error_message()
            ],admin_url('admin.php'));
        }else{
            $url=add_query_arg([
                'page'=>'tapbix-licenses',
                'tapbix_notice'=>'test_activation_ok',
                'tapbix_license_id'=>$id,
                'tapbix_device'=>$result['device_id']
            ],admin_url('admin.php'));
        }

        wp_safe_redirect($url);
        exit;
    }

    public function admin_notices(){ if(!current_user_can('activate_plugins'))return; if(!class_exists('WooCommerce'))echo '<div class="notice notice-warning"><p><strong>TapBix License Server:</strong> WooCommerce must be active.</p></div>'; if(!get_option(self::PRIV_OPT)||!get_option(self::PUB_OPT))echo '<div class="notice notice-error"><p><strong>TapBix License Server:</strong> The RSA signing key pair is unavailable or incomplete. Existing key material was not replaced; restore the missing key from backup.</p></div>'; }
}
TapBix_License_Server::instance();
