import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device identity stays in the OS credential store, outside database backups.
class LanTlsIdentity {
  LanTlsIdentity(this.certificatePem, this.privateKeyPem);

  final String certificatePem;
  final String privateKeyPem;

  String get fingerprint => sha256
      .convert(
        base64Decode(
          certificatePem
              .split('\n')
              .where((line) => !line.startsWith('---'))
              .map((line) => line.trim())
              .join(),
        ),
      )
      .toString();

  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  static Future<LanTlsIdentity> loadOrCreate(String deviceId) async {
    const storage = FlutterSecureStorage();
    final key = 'lan.tls.identity.v2.$deviceId';
    final stored = await storage.read(key: key);
    final Map<String, dynamic> data;
    if (stored == null) {
      data = await Isolate.run(_generate);
      // A single write prevents storing mismatched certificate/key halves.
      await storage.write(key: key, value: jsonEncode(data));
    } else {
      data = jsonDecode(stored) as Map<String, dynamic>;
    }
    return LanTlsIdentity(
      data['certificate'] as String,
      data['privateKey'] as String,
    );
  }

  static Map<String, String> _generate() {
    final pair = CryptoUtils.generateEcKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'Tapix LAN'},
      privateKey,
      publicKey,
      signingAlgorithm: 'SHA-256',
    );
    return {
      'certificate': X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        3650,
        notBefore: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
      'privateKey': CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
    };
  }
}
