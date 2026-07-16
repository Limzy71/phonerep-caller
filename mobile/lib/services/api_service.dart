import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import '../models/phone_record.dart';

class QuotaExceededException implements Exception {
  final String message;
  QuotaExceededException(this.message);
  @override
  String toString() => message;
}

class ApiService extends ChangeNotifier {
  late String _baseUrl;
  static String? _cachedDeviceId;

  ApiService() {
    if (!kIsWeb && Platform.isAndroid) {
      // IP Wi-Fi PC saat ini: http://192.168.100.220:3000 (juga mendukung ADB reverse via 127.0.0.1:3000)
      _baseUrl = 'http://192.168.100.220:3000';
    } else {
      _baseUrl = 'http://localhost:3000';
    }
  }

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedDeviceId = androidInfo.id;
        return _cachedDeviceId!;
      }
    } catch (_) {}
    _cachedDeviceId = 'unknown-device';
    return _cachedDeviceId!;
  }

  String _getAltUrl() {
    if (_baseUrl.contains('127.0.0.1') || _baseUrl.contains('localhost')) {
      return 'http://192.168.100.220:3000';
    }
    return 'http://127.0.0.1:3000';
  }

  String get baseUrl => _baseUrl;

  void setBaseUrl(String newUrl) {
    if (newUrl.trim().isNotEmpty) {
      _baseUrl = newUrl.trim();
      if (_baseUrl.endsWith('/')) {
        _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
      }
      notifyListeners();
    }
  }

  Map<String, String> get _defaultHeaders => {
    'Content-Type': 'application/json',
    'x-phonerep-client-key': 'phonerep-mobile-v1-secret-token-2026',
  };

  Future<LookupResponse> lookupPhoneNumber(
    String rawNumber, {
    bool skipIncrement = false,
    bool hasContactAccess = true,
  }) async {
    final query = skipIncrement ? '?skipIncrement=true' : '';
    final deviceId = await getDeviceId();
    final headers = {
      ..._defaultHeaders,
      'x-device-id': deviceId,
      'x-has-contact-access': hasContactAccess ? 'true' : 'false',
    };

    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/${Uri.encodeComponent(rawNumber)}$query');
      final response = await http.get(
        url,
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return LookupResponse.fromJson(decoded);
      } else if (response.statusCode == 403) {
        try {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          if (decoded['code'] == 'QUOTA_EXCEEDED') {
            throw QuotaExceededException('Limit pencarian gratis harian (1x) telah habis.');
          }
        } catch (e) {
          if (e is QuotaExceededException) rethrow;
        }
        throw QuotaExceededException('Limit pencarian gratis harian (1x) telah habis.');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (e is QuotaExceededException) rethrow;
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/${Uri.encodeComponent(rawNumber)}$query');
          final retryRes = await http.get(retryUri, headers: headers).timeout(const Duration(seconds: 10));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            final decoded = jsonDecode(retryRes.body) as Map<String, dynamic>;
            return LookupResponse.fromJson(decoded);
          } else if (retryRes.statusCode == 403) {
            try {
              final decoded = jsonDecode(retryRes.body) as Map<String, dynamic>;
              if (decoded['code'] == 'QUOTA_EXCEEDED') {
                throw QuotaExceededException('Limit pencarian gratis harian (1x) telah habis.');
              }
            } catch (err) {
              if (err is QuotaExceededException) rethrow;
            }
            throw QuotaExceededException('Limit pencarian gratis harian (1x) telah habis.');
          }
        } catch (err) {
          if (err is QuotaExceededException) rethrow;
        }
      }
      throw Exception('Gagal menghubungi server: $e');
    }
  }

  Future<SyncContactResult> syncContacts(
    List<Map<String, String>> contacts, {
    String? userId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/sync');
      final payload = {
        'userId': userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
        'contacts': contacts,
      };

      final response = await http
          .post(
            url,
            headers: _defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncContactResult.fromJson(decoded);
      } else {
        throw Exception('Server error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/sync');
          final payload = {
            'userId': userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
            'contacts': contacts,
          };
          final retryRes = await http.post(retryUri, headers: _defaultHeaders, body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            final decoded = jsonDecode(retryRes.body) as Map<String, dynamic>;
            return SyncContactResult.fromJson(decoded);
          }
        } catch (_) {}
      }
      throw Exception('Gagal menyinkronkan kontak: $e');
    }
  }

  Future<TagItem?> addTag(
    String phoneNumberId,
    String labelName, {
    String? userId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/tag');
      final payload = {
        'phoneNumberId': phoneNumberId,
        'labelName': labelName,
        'userId': userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
      };

      final response = await http
          .post(
            url,
            headers: _defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          return TagItem.fromJson(decoded['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/tag');
          final payload = {
            'phoneNumberId': phoneNumberId,
            'labelName': labelName,
            'userId': userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
          };
          final retryRes = await http.post(retryUri, headers: _defaultHeaders, body: jsonEncode(payload)).timeout(const Duration(seconds: 10));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            final decoded = jsonDecode(retryRes.body) as Map<String, dynamic>;
            if (decoded['success'] == true && decoded['data'] != null) {
              return TagItem.fromJson(decoded['data'] as Map<String, dynamic>);
            }
          }
        } catch (_) {}
      }
      throw Exception('Gagal menambah tag: $e');
    }
  }

  Future<bool> voteTag(
    String tagId,
    String voteType, {
    String? userId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/vote');
      final payload = {
        'tagId': tagId,
        'userId': userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
        'voteType': voteType, // 'UPVOTE' or 'DOWNVOTE'
      };

      final response = await http
          .post(
            url,
            headers: _defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return decoded['success'] == true;
      }
      return false;
    } catch (e) {
      throw Exception('Gagal melakukan voting: $e');
    }
  }

  Future<bool> resetUserData(String phoneNumber) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/reset/${Uri.encodeComponent(phoneNumber)}');
      final response = await http.delete(url, headers: _defaultHeaders).timeout(const Duration(seconds: 15));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/reset/${Uri.encodeComponent(phoneNumber)}');
          final retryRes = await http.delete(retryUri, headers: _defaultHeaders).timeout(const Duration(seconds: 10));
          return retryRes.statusCode == 200 || retryRes.statusCode == 201;
        } catch (_) {}
      }
      return false;
    }
  }

  Future<AnalyticsResponse> getAnalytics() async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/analytics');
      final response = await http.get(
        url,
        headers: _defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return AnalyticsResponse.fromJson(decoded);
      } else {
        throw Exception('Server error (${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Gagal memuat analitik: $e');
    }
  }

  Future<List<SearcherItemData>> getPhoneSearchers(String phoneNumber) async {
    try {
      final encodedNumber = Uri.encodeComponent(phoneNumber);
      final url = Uri.parse('$_baseUrl/phone-lookup/searchers/$encodedNumber');
      final response = await http.get(
        url,
        headers: _defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final rawList = decoded['data'] as List<dynamic>;
          return rawList.map((item) => SearcherItemData.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final encodedNumber = Uri.encodeComponent(phoneNumber);
          final retryUri = Uri.parse('$altUrl/phone-lookup/searchers/$encodedNumber');
          final retryRes = await http.get(retryUri, headers: _defaultHeaders).timeout(const Duration(seconds: 10));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            final decoded = jsonDecode(retryRes.body) as Map<String, dynamic>;
            if (decoded['success'] == true && decoded['data'] != null) {
              final rawList = decoded['data'] as List<dynamic>;
              return rawList.map((item) => SearcherItemData.fromJson(item as Map<String, dynamic>)).toList();
            }
          }
        } catch (_) {}
      }
      throw Exception('Gagal memuat daftar pencari: $e');
    }
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber, {bool isResend = false}) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/send-otp');
      final response = await http.post(
        url,
        headers: _defaultHeaders,
        body: jsonEncode({'phoneNumber': phoneNumber, 'isResend': isResend}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'Gagal mengirim OTP (${response.statusCode})'};
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/send-otp');
          final retryRes = await http.post(
            retryUri,
            headers: _defaultHeaders,
            body: jsonEncode({'phoneNumber': phoneNumber, 'isResend': isResend}),
          ).timeout(const Duration(seconds: 10));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            return jsonDecode(retryRes.body) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      return {'success': false, 'message': 'Tidak dapat terhubung ke server. Pastikan koneksi internet Anda stabil dan coba lagi.'};
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phoneNumber, String code) async {
    try {
      final url = Uri.parse('$_baseUrl/phone-lookup/verify-otp');
      final response = await http.post(
        url,
        headers: _defaultHeaders,
        body: jsonEncode({'phoneNumber': phoneNumber, 'code': code}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'Verifikasi gagal (${response.statusCode})'};
    } catch (e) {
      if (e.toString().contains('Connection refused') || e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        final altUrl = _getAltUrl();
        try {
          final retryUri = Uri.parse('$altUrl/phone-lookup/verify-otp');
          final retryRes = await http.post(
            retryUri,
            headers: _defaultHeaders,
            body: jsonEncode({'phoneNumber': phoneNumber, 'code': code}),
          ).timeout(const Duration(seconds: 10));
          if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
            _baseUrl = altUrl;
            notifyListeners();
            return jsonDecode(retryRes.body) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      return {'success': false, 'message': 'Tidak dapat terhubung ke server. Pastikan koneksi internet Anda stabil dan coba lagi.'};
    }
  }
}
