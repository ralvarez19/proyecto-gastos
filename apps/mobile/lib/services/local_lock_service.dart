import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class LocalLockService {
  LocalLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuthentication,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuthentication = localAuthentication ?? LocalAuthentication();

  static const _ownerKey = 'obraflow_lock_owner';
  static const _saltKey = 'obraflow_pin_salt';
  static const _hashKey = 'obraflow_pin_hash';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuthentication;

  Future<bool> hasPin(String uid) async {
    final values = await Future.wait([
      _storage.read(key: _ownerKey),
      _storage.read(key: _saltKey),
      _storage.read(key: _hashKey),
    ]);
    return values[0] == uid &&
        values[1]?.isNotEmpty == true &&
        values[2]?.isNotEmpty == true;
  }

  Future<void> savePin(String uid, String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const FormatException('El PIN debe tener entre 4 y 6 números.');
    }
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    final hash = _hash(uid, pin, salt);
    await _storage.write(key: _ownerKey, value: uid);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
  }

  Future<bool> verifyPin(String uid, String pin) async {
    final owner = await _storage.read(key: _ownerKey);
    final salt = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (owner != uid || salt == null || expected == null) return false;
    return _constantTimeEquals(_hash(uid, pin, salt), expected);
  }

  Future<bool> biometricsAvailable() async {
    try {
      return (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'Usa tu huella o biometría para desbloquear ObraFlow',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  String _hash(String uid, String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$uid:$pin')).toString();

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
