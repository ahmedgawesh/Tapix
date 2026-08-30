<?php
/**
 * Plugin Name: TapBix License Server
 * Description: Offline-first license issuing and device activation server for TapBix Windows and Linux, integrated with WooCommerce.
 * Version: 0.3.0
 * Author: Tapix Solutions
 * Requires at least: 6.4
 * Requires PHP: 8.1
 * Text Domain: tapbix-license-server
 */
if (!defined('ABSPATH')) exit;

final class TapBix_License_Server {
    const VERSION='0.3.0';
    const PRODUCT_SKU='TAPBIX-WIN-LIFE-1D';
    const PRODUCT_CODE='tapbix-desktop';
    const APP_ID='com.tapix.pos';
    const OFFLINE_LEASE_SECONDS=604800;
    const REVALIDATE_AFTER_SECONDS=86400;
    const PLAN='lifetime';
    const MAX_DEVICES=1;
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
        add_action('woocommerce_email_after_order_table',[$this,'email_license_details'],20,4);
        add_action('rest_api_init',[$this,'register_rest_routes']);
        add_action('admin_menu',[$this,'admin_menu']);
        add_action('admin_notices',[$this,'admin_notices']);
        add_action('admin_post_tapbix_license_action',[$this,'handle_admin_action']);
        add_action('admin_post_tapbix_create_test_license',[$this,'handle_create_test_license']);
        add_action('admin_post_tapbix_test_activation',[$this,'handle_test_activation']);
        add_action('admin_init',[$this,'maybe_upgrade']);
    }
    private function table($n){ global $wpdb; return $wpdb->prefix.'tapbix_'.$n; }
    private function now(){ return current_time('mysql',true); }

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
    }
    private function ensure_keys(){
        if(get_option(self::PRIV_OPT)&&get_option(self::PUB_OPT)) return true;
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
        if(!function_exists('wc_get_order')) return; $o=wc_get_order($order_id); if(!$o) return;
        foreach($o->get_items('line_item') as $item_id=>$item){ $p=$item->get_product(); if(!$p||$p->get_sku()!==self::PRODUCT_SKU) continue; $this->issue_license($o,$item_id); }
    }
    private function issue_license($o,$item_id){
        global $wpdb; $t=$this->table('licenses'); $oid=$o->get_id();
        $exists=$wpdb->get_var($wpdb->prepare("SELECT id FROM $t WHERE order_id=%d AND order_item_id=%d LIMIT 1",$oid,$item_id)); if($exists) return;
        do{ $key=$this->gen_key(); $dup=$wpdb->get_var($wpdb->prepare("SELECT id FROM $t WHERE license_key=%s LIMIT 1",$key)); }while($dup);
        $ok=$wpdb->insert($t,['license_key'=>$key,'product_code'=>self::PRODUCT_CODE,'plan'=>self::PLAN,'max_devices'=>self::MAX_DEVICES,'status'=>'active','customer_id'=>$o->get_customer_id()?:null,'customer_email'=>sanitize_email($o->get_billing_email()),'order_id'=>$oid,'order_item_id'=>$item_id,'created_at'=>$this->now(),'expires_at'=>null],['%s','%s','%s','%d','%s','%d','%s','%d','%d','%s','%s']);
        if($ok) $this->log((int)$wpdb->insert_id,'license_issued',['order_id'=>$oid,'order_item_id'=>$item_id]);
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
                'plan'=>self::PLAN,
                'max_devices'=>self::MAX_DEVICES,
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
        $app_version='TEST-0.3.0';
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
    private function customer_licenses(){ global $wpdb; $u=wp_get_current_user(); if(!$u||!$u->exists())return []; return $wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE customer_id=%d OR customer_email=%s ORDER BY id DESC",$u->ID,$u->user_email)); }
    public function render_account_licenses(){
        if(!is_user_logged_in()){echo '<p>Please log in.</p>';return;} $ls=$this->customer_licenses(); echo '<h2>TapBix Licenses</h2>'; if(!$ls){echo '<p>No TapBix licenses linked to this account yet.</p>';return;} global $wpdb;
        foreach($ls as $l){ $as=$wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('activations')} WHERE license_id=%d AND status='active' ORDER BY id DESC",$l->id)); echo '<div style="border:1px solid #ddd;border-radius:10px;padding:18px;margin:0 0 18px"><strong>TapBix POS &amp; ERP for Desktop</strong><br><code>'.esc_html($l->license_key).'</code><br>Plan: '.esc_html(ucfirst($l->plan)).'<br>Status: '.esc_html(ucfirst($l->status)).'<br>Devices: '.count($as).' / '.(int)$l->max_devices; if($as){echo '<ul>'; foreach($as as $a){$url=wp_nonce_url(wc_get_account_endpoint_url(self::ENDPOINT).'?tapbix_deactivate='.(int)$a->id,'tapbix_deactivate_'.(int)$a->id); echo '<li>'.esc_html($a->device_name?:'Desktop device').' — <a href="'.esc_url($url).'">Deactivate</a></li>'; } echo '</ul>'; } echo '</div>'; }
    }
    public function handle_customer_deactivate(){
        if(!is_user_logged_in()||empty($_GET['tapbix_deactivate']))return; $id=absint($_GET['tapbix_deactivate']); check_admin_referer('tapbix_deactivate_'.$id); global $wpdb; $a=$wpdb->get_row($wpdb->prepare("SELECT a.*,l.customer_id,l.customer_email FROM {$this->table('activations')} a INNER JOIN {$this->table('licenses')} l ON l.id=a.license_id WHERE a.id=%d LIMIT 1",$id)); $u=wp_get_current_user(); if(!$a||((int)$a->customer_id!==(int)$u->ID&&strtolower($a->customer_email)!==strtolower($u->user_email)))wp_die('Not allowed.'); $wpdb->update($this->table('activations'),['status'=>'inactive','deactivated_at'=>$this->now()],['id'=>$id],['%s','%s'],['%d']); $this->log($a->license_id,'customer_device_deactivated',['activation_id'=>$id]); wp_safe_redirect(wc_get_account_endpoint_url(self::ENDPOINT)); exit;
    }
    public function email_license_details($order,$sent,$plain,$email){ if($sent||!$order||!is_a($order,'WC_Order'))return; global $wpdb; $ls=$wpdb->get_results($wpdb->prepare("SELECT * FROM {$this->table('licenses')} WHERE order_id=%d ORDER BY id",$order->get_id())); if(!$ls)return; if($plain){echo "\nTapBix License\n";foreach($ls as $l)echo "License: {$l->license_key}\nPlan: ".ucfirst($l->plan)."\nDevices: {$l->max_devices}\n\n";return;} echo '<h2>TapBix License</h2>'; foreach($ls as $l)echo '<p><strong>License:</strong> <code>'.esc_html($l->license_key).'</code><br><strong>Plan:</strong> '.esc_html(ucfirst($l->plan)).'<br><strong>Devices:</strong> '.(int)$l->max_devices.'</p>'; }

    public function admin_menu(){ add_menu_page('TapBix Licenses','TapBix Licenses','manage_woocommerce','tapbix-licenses',[$this,'admin_page'],'dashicons-admin-network',56); }
    public function admin_page(){
        if(!current_user_can('manage_woocommerce')) return;

        global $wpdb;
        $ls=$wpdb->get_results("SELECT * FROM {$this->table('licenses')} ORDER BY id DESC LIMIT 250");
        $pub=get_option(self::PUB_OPT,'');

        echo '<div class="wrap"><h1>TapBix Licenses</h1>';
        echo '<p>Plugin version: <code>'.esc_html(self::VERSION).'</code> &nbsp; Watched SKU: <code>'.esc_html(self::PRODUCT_SKU).'</code></p>';

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

        echo '<h2>Licenses</h2><table class="widefat striped"><thead><tr>';
        echo '<th>ID</th><th>License</th><th>Customer</th><th>Plan</th><th>Devices</th><th>Status</th><th>Order</th><th>Type</th><th>Created</th><th>Actions</th>';
        echo '</tr></thead><tbody>';

        if(!$ls) echo '<tr><td colspan="10">No licenses issued yet.</td></tr>';

        foreach($ls as $l){
            $c=$this->active_count($l->id);
            $is_test=$this->is_test_license($l);

            echo '<tr>';
            echo '<td>'.(int)$l->id.'</td>';
            echo '<td><code>'.esc_html($l->license_key).'</code></td>';
            echo '<td>'.esc_html($l->customer_email?:'—').'</td>';
            echo '<td>'.esc_html($l->plan).'</td>';
            echo '<td>'.$c.' / '.(int)$l->max_devices.'</td>';
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

    public function admin_notices(){ if(!current_user_can('activate_plugins'))return; if(!class_exists('WooCommerce'))echo '<div class="notice notice-warning"><p><strong>TapBix License Server:</strong> WooCommerce must be active.</p></div>'; if(!get_option(self::PUB_OPT))echo '<div class="notice notice-error"><p><strong>TapBix License Server:</strong> RSA signing keys could not be created. PHP OpenSSL must be enabled.</p></div>'; }
}
TapBix_License_Server::instance();
