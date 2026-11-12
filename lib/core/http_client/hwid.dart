import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';

/// HWID headers (x-hwid, x-device-os, x-ver-os, x-device-model) that panels such as Remnawave
/// use for their device limit. They go only with subscription requests.
///
/// The id is a hash of the Windows MachineGuid, so it stays the same across reinstalls of the
/// app. Elsewhere, or when the registry cannot be read, it is a random id kept in preferences.
/// Remnawave v3 accepts `^[a-zA-Z0-9=-]{10,64}$`; a 32-character hex string fits.
abstract final class Hwid {
  static const _prefsKey = 'hwid_fallback_id';
  static Map<String, String>? _headers;

  static Future<Map<String, String>> headers() async {
    final cached = _headers;
    if (cached != null) return cached;
    final id = await _id();
    return _headers = {
      'x-hwid': id,
      'x-device-os': _os(),
      'x-ver-os': _osVersion(),
      'x-device-model': _model(),
    };
  }

  static Future<String> _id() async {
    String? source;
    if (Platform.isWindows) {
      try {
        final key = Registry.openPath(RegistryHive.localMachine, path: r'SOFTWARE\Microsoft\Cryptography');
        try {
          source = key.getStringValue('MachineGuid');
        } finally {
          key.close();
        }
      } catch (_) {
        source = null;
      }
    }
    if (source == null || source.trim().isEmpty) {
      source = await _fallbackSource();
    }
    return sha256.convert(utf8.encode('hiddify-hwid:${source.trim()}')).toString().substring(0, 32);
  }

  static Future<String> _fallbackSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) return saved;
      final created = _random();
      await prefs.setString(_prefsKey, created);
      return created;
    } catch (_) {
      return _random();
    }
  }

  static String _random() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _os() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  static String _osVersion() {
    // "Windows 10 Pro" 10.0 (Build 22631) -> 10.0.22631
    final v = Platform.operatingSystemVersion;
    final m = RegExp(r'(\d+\.\d+)\D*\(Build (\d+)\)').firstMatch(v);
    if (m != null) return '${m.group(1)}.${m.group(2)}';
    return _ascii(v);
  }

  static String _model() {
    final name = _ascii(Platform.localHostname);
    return name.isEmpty ? '${_os()} PC' : name;
  }

  // header values must stay printable ASCII
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}
