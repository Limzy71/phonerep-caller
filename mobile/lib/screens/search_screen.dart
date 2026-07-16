import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/phone_record.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tag_chip_card.dart';
import '../widgets/app_toast.dart';
import '../widgets/trust_meter.dart';
import 'my_phone_searchers_screen.dart';
import 'my_tags_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final ApiService apiService;

  const SearchScreen({super.key, required this.apiService});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  PhoneRecord? _phoneRecord;
  String? _statusMessage;

  void _showAutoDismissStatus(String? status, {String? error}) {
    setState(() {
      _statusMessage = status;
      _errorMessage = error;
    });
    if (status != null || error != null) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && (_statusMessage == status || _errorMessage == error)) {
          setState(() {
            if (_statusMessage == status) _statusMessage = null;
            if (_errorMessage == error) _errorMessage = null;
          });
        }
      });
    }
  }

  // Status apakah bar pencarian sedang diklik/difokuskan (untuk menampilkan mode Gambar ke-5)
  bool _isSearchExpanded = false;
  String _selectedCountryCode = '+62';
  String _callLogFilterTime = 'Semua';

  String _getDynamicSearchHint() {
    switch (_selectedCountryCode.trim()) {
      case '+62':
        return 'Contoh: 0812... / 62812...';
      case '+60':
        return 'Contoh: 012... / 6012...';
      case '+65':
        return 'Contoh: 812... / 65812...';
      case '+1':
        return 'Contoh: 202... / 1202...';
      case '+44':
        return 'Contoh: 0712... / 44712...';
      case '+61':
        return 'Contoh: 0412... / 61412...';
      case '+81':
        return 'Contoh: 090... / 8190...';
      case '+82':
        return 'Contoh: 010... / 8210...';
      default:
        return 'Contoh awalan nomor ($_selectedCountryCode)...';
    }
  }

  String _formatQueryWithCountryCode(String raw) {
    String clean = raw.trim().replaceAll(' ', '').replaceAll('-', '');
    if (clean.isEmpty) return clean;
    if (clean.startsWith('+')) return clean;
    if (_selectedCountryCode == '+62') {
      if (clean.startsWith('08')) {
        return '+62${clean.substring(1)}';
      } else if (clean.startsWith('628')) {
        return '+$clean';
      } else if (clean.startsWith('8')) {
        return '+62$clean';
      }
    } else {
      if (clean.startsWith('0')) {
        return '$_selectedCountryCode${clean.substring(1)}';
      } else if (!clean.startsWith(_selectedCountryCode.replaceAll('+', ''))) {
        return '$_selectedCountryCode$clean';
      } else {
        return '+$clean';
      }
    }
    return clean;
  }

  // State Kontak & Riwayat Telepon Nyata Perangkat (TANPA DATA DUMMY / ALFABETIS)
  bool _hasContactPermission = false;
  bool _hasCallLogPermission = false;
  bool _isContactsLoading = false;
  bool _isRefreshingCallLog = false;
  List<Contact> _contacts = [];
  List<CallLogEntry> _callLogs = [];

  // Daftar nyata riwayat "Baru Saja Dilihat" (Real dari kontak & riwayat pencarian sesi ini)
  final List<Map<String, dynamic>> _recentlyViewed = [];

  // Daftar nyata tag nomor pengguna
  final List<String> _userTags = [];

  // Statistik Real-Time Proteksi & Pencarian Nomor Pengguna Sendiri
  int _myPhoneSearchCount = 0;
  double _myPhoneTrustScore = 100.0;
  List<TagItem> _myPhoneTags = [];
  String _myPhoneNumber = '';
  bool _isMyStatsLoading = true;
  final Map<String, int> _quickContactTagCounts = {};
  // Cache data pencari nomor agar layar buka instan. Null berarti belum pernah di-fetch.
  List<SearcherItemData>? _cachedSearcherItems;
  final Map<String, String> _recentCallTags = {};

  void refreshHomeData() {
    if (!mounted) return;
    _loadUserTagsFromPrefs();
    _fetchMyPhoneSearchStats();
    _checkAndLoadContacts();
  }

  @override
  void initState() {
    super.initState();
    _loadUserTagsFromPrefs();
    _fetchMyPhoneSearchStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Berikan delay singkat agar Android merender frame pertama dan menutup splash screen terlebih dahulu
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            _checkAndLoadContacts();
          }
        });
      }
    });
  }

  Future<void> _fetchMyPhoneSearchStats() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_my_phone') ?? '';
    if (phone.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isMyStatsLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      if (_myPhoneTags.isEmpty && _userTags.isEmpty && _myPhoneSearchCount == 0) {
        setState(() {
          _myPhoneNumber = phone.trim();
          _isMyStatsLoading = true;
        });
      } else {
        _myPhoneNumber = phone.trim();
      }
    }

    try {
      final res = await widget.apiService.lookupPhoneNumber(_myPhoneNumber, skipIncrement: true, hasContactAccess: _hasContactPermission);
      if (mounted && res.data != null) {
        setState(() {
          _myPhoneSearchCount = res.data!.searchCount;
          _myPhoneTrustScore = res.data!.trustScore;
          _myPhoneTags = res.data!.tags;
          for (final t in res.data!.tags) {
            if (!_userTags.contains(t.labelName)) {
              _userTags.add(t.labelName);
            }
          }
          _isMyStatsLoading = false;
        });
        _saveUserTagsToPrefs();
        // Pre-fetch data pencari di background setelah stats berhasil
        _prefetchSearchers(_myPhoneNumber);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isMyStatsLoading = false;
        });
      }
    }
  }

  Future<void> _prefetchSearchers(String phoneNumber) async {
    if (phoneNumber.trim().isEmpty) return;
    try {
      final apiService = ApiService();
      final data = await apiService.getPhoneSearchers(phoneNumber);
      if (mounted) {
        setState(() {
          _cachedSearcherItems = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchQuickContactsTagCounts() async {
    final list = _realQuickContacts;
    if (list.isEmpty) return;

    // Parallel: semua request jalan bersamaan, bukan satu per satu
    await Future.wait(
      list.where((t) => t.phoneNumberId.isNotEmpty).map((t) async {
        try {
          final res = await widget.apiService.lookupPhoneNumber(
            t.phoneNumberId,
            skipIncrement: true,
            hasContactAccess: _hasContactPermission,
          ).timeout(const Duration(seconds: 4));
          if (mounted && res.data != null) {
            setState(() {
              _quickContactTagCounts[t.phoneNumberId] = res.data!.tags.length;
            });
          }
        } catch (_) {}
      }),
    );
  }





  Future<void> _loadUserTagsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTags = prefs.getStringList('user_my_tags') ?? [];
    if (mounted && savedTags.isNotEmpty) {
      setState(() {
        for (final t in savedTags) {
          if (!_userTags.contains(t)) {
            _userTags.add(t);
          }
        }
      });
    }
  }

  Future<void> _saveUserTagsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_my_tags', _userTags);
  }

  List<TagItem> get _allMyTagsCombined {
    final list = <TagItem>[];
    final seen = <String>{};
    
    // Prioritas: _myPhoneTags dari backend (pastikan tag profil pengguna ditandai sebagai self-tag)
    for (final t in _myPhoneTags) {
      final cleanLabel = t.labelName.trim();
      if (cleanLabel.isNotEmpty && !seen.contains(cleanLabel)) {
        seen.add(cleanLabel);
        final isSelfTag = _userTags.any((ut) => ut.trim().toLowerCase() == cleanLabel.toLowerCase()) ||
            (t.userId != null && _myPhoneNumber.isNotEmpty && t.userId == _myPhoneNumber);
        list.add(TagItem(
          id: t.id,
          phoneNumberId: t.phoneNumberId,
          labelName: cleanLabel,
          userId: isSelfTag ? (_myPhoneNumber.isNotEmpty ? _myPhoneNumber : 'me') : t.userId,
          upvotes: t.upvotes,
          downvotes: t.downvotes,
          createdAt: t.createdAt,
        ));
      }
    }
    
    // Fallback: Untuk _userTags (lokal/tanpa userId)
    for (final t in _userTags) {
      final cleanLabel = t.trim();
      if (cleanLabel.isNotEmpty && !seen.contains(cleanLabel)) {
        seen.add(cleanLabel);
        list.add(TagItem(
          id: '',
          phoneNumberId: '',
          labelName: cleanLabel,
          userId: _myPhoneNumber.isNotEmpty ? _myPhoneNumber : 'me',
        ));
      }
    }
    return list;
  }

  void _showContactAccessConsentModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF131A29),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.primaryLight, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Izin Akses & Keamanan Kontak',
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Untuk mendeteksi panggilan spam/penipuan secara real-time, mengidentifikasi nomor asing, dan memproteksi daftar kontak Anda, aplikasi membutuhkan izin akses untuk membaca Kontak & Log Telepon Anda.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2636),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: AppColors.accentGreen, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Privasi Anda adalah prioritas utama. Data kontak Anda dienkripsi dan tidak akan pernah disebarkan tanpa izin.',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_agreed_contact_access', true);
                    setState(() => _isContactsLoading = true);
                    final contactStatus = await Permission.contacts.request();
                    final callStatus = await Permission.phone.request();
                    if (mounted) {
                      setState(() {
                        _hasContactPermission = contactStatus.isGranted;
                        _hasCallLogPermission = callStatus.isGranted;
                      });
                      if (_hasContactPermission) {
                        await _fetchRealDeviceContacts();
                      }
                      if (_hasCallLogPermission) {
                        await _fetchRealCallLogs();
                      }
                      setState(() => _isContactsLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 6,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Aktifkan Izin & Proteksi',
                      maxLines: 1,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_agreed_contact_access', false);
                    if (mounted) {
                      setState(() {
                        _hasContactPermission = false;
                        _hasCallLogPermission = false;
                        _contacts = [];
                        _callLogs = [];
                        _isContactsLoading = false;
                      });
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Lanjutkan Tanpa Izin',
                    style: GoogleFonts.sora(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuotaExceededModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF131A29),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.lock_clock_rounded, color: Color(0xFFFBBF24), size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Batas Gratis 1x Habis',
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Anda telah menggunakan 1x kesempatan pencarian gratis hari ini untuk perangkat ini.\n\nAktifkan izin akses kontak untuk mendapatkan pencarian nomor tanpa batas & mengaktifkan proteksi dari nomor penipuan/spam secara penuh!',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_agreed_contact_access', true);
                    setState(() => _isContactsLoading = true);
                    final contactStatus = await Permission.contacts.request();
                    final callStatus = await Permission.phone.request();
                    if (mounted) {
                      setState(() {
                        _hasContactPermission = contactStatus.isGranted;
                        _hasCallLogPermission = callStatus.isGranted;
                      });
                      if (_hasContactPermission) {
                        await _fetchRealDeviceContacts();
                        if (!context.mounted) return;
                        AppToast.show(
                          context,
                          message: 'Pencarian tanpa batas telah aktif!',
                          type: ToastType.success,
                        );
                        if (_searchController.text.isNotEmpty) {
                          _performSearch(_searchController.text);
                        }
                      } else {
                        if (!context.mounted) return;
                        AppToast.show(
                          context,
                          message: 'Izin kontak belum diberikan. Batas 1x tetap berlaku.',
                          type: ToastType.info,
                        );
                      }
                      if (_hasCallLogPermission) {
                        await _fetchRealCallLogs();
                        if (!context.mounted) return;
                      }
                      if (mounted) {
                        setState(() => _isContactsLoading = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    foregroundColor: const Color(0xFF131A29),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 6,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Aktifkan Izin & Buka Batas (Gratis)',
                      maxLines: 1,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Tutup',
                    style: GoogleFonts.sora(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkAndLoadContacts() async {
    if (mounted) {
      setState(() => _isRefreshingCallLog = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _isRefreshingCallLog = false);
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool hasAgreedContactAccess = prefs.getBool('has_agreed_contact_access') ?? false;

      if (!hasAgreedContactAccess) {
        if (mounted) {
          setState(() {
            _hasContactPermission = false;
            _hasCallLogPermission = false;
            _contacts = [];
            _callLogs = [];
            _isContactsLoading = false;
          });
          _showContactAccessConsentModal();
        }
        return;
      }

      final contactStatus = await Permission.contacts.status;
      final callStatus = await Permission.phone.status;

      if (mounted) {
        setState(() {
          _hasContactPermission = contactStatus.isGranted;
          _hasCallLogPermission = callStatus.isGranted;
        });
      }

      if (_hasContactPermission) {
        await _fetchRealDeviceContacts();
        _fetchQuickContactsTagCounts();
      }
      if (_hasCallLogPermission) {
        await _fetchRealCallLogs();
      }
    } catch (e) {
      debugPrint('Error loading initial contacts/call logs: $e');
    } finally {
      if (mounted) {
        setState(() => _isContactsLoading = false);
      }
    }
  }

  Future<void> _fetchRealCallLogs() async {
    try {
      final Iterable<CallLogEntry> entries = await CallLog.get();
      if (mounted) {
        setState(() {
          _callLogs = entries
              .where((e) => (e.number ?? '').trim().isNotEmpty)
              .take(60)
              .toList();
        });
        _fetchRecentCallTags();
      }
    } catch (e) {
      // Abaikan jika gagal mengakses log
    }
  }

  Future<void> _fetchRealDeviceContacts() async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );
        if (mounted) {
          final validContacts = contacts.where((c) => c.phones.isNotEmpty).toList();
          setState(() {
            _contacts = validContacts;
            _isContactsLoading = false;
          });

          // Sinkronisasikan kontak ke database PostgreSQL backend (Contact Pooling & Community Tags)
          if (validContacts.isNotEmpty) {
            final payload = <Map<String, String>>[];
            final seenKeys = <String>{};
            for (final c in validContacts) {
              if (c.phones.isNotEmpty) {
                final rawNum = c.phones.first.number.trim();
                final name = _getContactName(c).trim();
                if (rawNum.isNotEmpty && name.isNotEmpty) {
                  // Normalisasi nomor secara lokal untuk deteksi duplikat
                  String norm = rawNum.replaceAll(RegExp(r'[\s\-\(\)\.]+'), '');
                  if (norm.startsWith('08')) {
                    norm = '+62${norm.substring(1)}';
                  } else if (norm.startsWith('628')) {
                    norm = '+$norm';
                  }
                  
                  // Filter: Abaikan kontak jika nomornya adalah nomor pengguna sendiri
                  String myNorm = _myPhoneNumber.replaceAll(RegExp(r'[\s\-\(\)\.]+'), '');
                  if (myNorm.startsWith('08')) {
                    myNorm = '+62${myNorm.substring(1)}';
                  } else if (myNorm.startsWith('628')) {
                    myNorm = '+$myNorm';
                  }
                  
                  if (_myPhoneNumber.isNotEmpty && norm == myNorm) {
                    continue;
                  }

                  final key = '${norm}_${name.toLowerCase()}';
                  if (!seenKeys.contains(key)) {
                    seenKeys.add(key);
                    payload.add({
                      'name': name,
                      'phoneNumber': rawNum,
                    });
                  }
                }
              }
            }

            if (payload.isNotEmpty) {
              final prefs = await SharedPreferences.getInstance();
              final myPhone = prefs.getString('user_my_phone') ?? 'android_user_${DateTime.now().millisecondsSinceEpoch}';
              widget.apiService.syncContacts(
                payload.take(500).toList(),
                userId: myPhone,
              ).then((res) {
                debugPrint('✅ Kontak berhasil disinkronkan ke database PostgreSQL: ${res.message}');
                _fetchQuickContactsTagCounts();
              }).catchError((err) {
                debugPrint('⚠️ Gagal sinkronisasi kontak: $err');
                _fetchQuickContactsTagCounts();
              });
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _hasContactPermission = false;
            _isContactsLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isContactsLoading = false;
        });
      }
    }
  }

  String _getContactName(Contact c) {
    if (c.displayName.trim().isNotEmpty) return c.displayName.trim();
    final fullName = '${c.name.first} ${c.name.middle} ${c.name.last}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (fullName.isNotEmpty) return fullName;
    return c.phones.first.number;
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '#';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Color _getAvatarColor(String seed) {
    final colors = [
      const Color(0xFF3B4358),
      const Color(0xFF6C63FF),
      const Color(0xFF10B981),
      const Color(0xFFEF4444),
      const Color(0xFF2B8CFF),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
    ];
    return colors[seed.hashCode.abs() % colors.length];
  }

  String _formatCallTime(int? timestamp) {
    if (timestamp == null || timestamp == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDate = DateTime(dt.year, dt.month, dt.day);

    if (callDate == today) {
      final hourStr = dt.hour.toString().padLeft(2, '0');
      final minStr = dt.minute.toString().padLeft(2, '0');
      return '$hourStr.$minStr';
    } else if (callDate == yesterday) {
      return 'Kemarin';
    } else {
      final diffDays = today.difference(callDate).inDays;
      if (diffDays >= 2 && diffDays <= 6) {
        return '$diffDays hari lalu';
      } else {
        return '${dt.day}/${dt.month}';
      }
    }
  }

  Future<void> _fetchRecentCallTags() async {
    final calls = _realRecentCalls;
    if (calls.isEmpty) return;

    await Future.wait(
      calls.map((c) async {
        final num = c['number'] as String?;
        if (num == null || num.isEmpty) return;
        try {
          final res = await widget.apiService.lookupPhoneNumber(
            num,
            skipIncrement: true,
            hasContactAccess: _hasContactPermission,
          ).timeout(const Duration(seconds: 4));
          if (mounted && res.data != null && res.data!.tags.isNotEmpty) {
            final sortedTags = List.of(res.data!.tags)
              ..sort((a, b) => (b.upvotes - b.downvotes).compareTo(a.upvotes - a.downvotes));
            final topTag = sortedTags.first.labelName;
            final formatted = topTag.startsWith('#') ? topTag : '#$topTag';
            setState(() {
              _recentCallTags[num] = formatted;
            });
          }
        } catch (_) {}
      }),
    );
  }

  // Getter Panggilan Terbaru Asli dari Riwayat Telepon Nyata HP (Call Log)
  List<Map<String, dynamic>> get _realRecentCalls {
    final List<Map<String, dynamic>> combined = [];
    // Prioritaskan murni dari riwayat panggilan nyata HP (CallLog)
    if (_callLogs.isNotEmpty) {
      for (final log in _callLogs) {
        if (combined.length >= 5) break;
        final num = (log.number ?? '').trim();
        if (num.isNotEmpty && !combined.any((x) => x['number'] == num)) {
          final hasContactName = log.name != null && log.name!.trim().isNotEmpty;
          final name = hasContactName ? log.name!.trim() : num;
          final typeStr = log.callType == CallType.incoming
              ? 'Panggilan Masuk'
              : log.callType == CallType.outgoing
                  ? 'Panggilan Keluar'
                  : 'Tak Terjawab';
          
          final timeStr = _formatCallTime(log.timestamp);
          final timeAndType = timeStr.isNotEmpty ? '$timeStr | $typeStr' : typeStr;
          
          // Jika nomor belum tersimpan sebagai nama kontak, jangan ulang nomor di subtitle!
          final sub = hasContactName ? '$num | $timeAndType' : timeAndType;

          combined.add({
            'name': name,
            'sub': sub,
            'date': 'Log Telepon',
            'isSpam': false,
            'number': num,
          });
        }
      }
    } else if (_contacts.isNotEmpty && !_hasCallLogPermission) {
      // Hanya tampil sebagai cadangan sementara jika izin Log Telepon belum diberikan
      for (final c in _contacts) {
        if (combined.length >= 5) break;
        final num = c.phones.first.number;
        if (!combined.any((x) => x['number'] == num)) {
          final contactName = _getContactName(c).trim();
          final hasContactName = contactName.isNotEmpty && contactName != num;
          final name = hasContactName ? contactName : num;
          final labelStr = (c.phones.first.label == PhoneLabel.custom
                      ? c.phones.first.customLabel
                      : c.phones.first.label.name)
                  .trim();
          final cleanLabel = labelStr.isNotEmpty && labelStr != 'custom'
              ? labelStr
              : 'Ponsel';
          
          final sub = hasContactName ? '$num | $cleanLabel' : cleanLabel;

          combined.add({
            'name': name,
            'sub': sub,
            'date': 'Log Telepon',
            'isSpam': false,
            'number': num,
          });
        }
      }
    }
    return combined;
  }

  // Getter Kontak Cepat Asli dari Kontak Perangkat (Maksimal 5, 1 alfabet 1 kontak loncat berurutan A, B, dst)
  List<TagItem> get _realQuickContacts {
    if (_contacts.isEmpty) return [];

    final sorted = List.of(_contacts)
      ..sort((a, b) => _getContactName(a).toLowerCase().compareTo(_getContactName(b).toLowerCase()));

    final Set<String> usedLetters = {};
    final List<Contact> selectedContacts = [];

    for (final c in sorted) {
      if (selectedContacts.length >= 5) break;
      final name = _getContactName(c).trim();
      if (name.isEmpty) continue;
      final firstLetter = name[0].toUpperCase();
      if (firstLetter.contains(RegExp(r'[A-Z]')) && !usedLetters.contains(firstLetter)) {
        usedLetters.add(firstLetter);
        selectedContacts.add(c);
      }
    }

    if (selectedContacts.length < 5) {
      for (final c in sorted) {
        if (selectedContacts.length >= 5) break;
        if (!selectedContacts.contains(c)) {
          selectedContacts.add(c);
        }
      }
    }

    return selectedContacts.map((c) {
      final name = _getContactName(c);
      final num = c.phones.isNotEmpty ? c.phones.first.number : '';
      return TagItem(
        id: c.id,
        phoneNumberId: num,
        labelName: name,
        upvotes: 1, // Penanda awal 1 label kontak dari buku telepon Anda
        isSpam: false,
      );
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = _formatQueryWithCountryCode(query);
    if (cleanQuery.isEmpty) {
      AppToast.show(
        context,
        message: 'Masukkan nomor telepon yang valid.',
        type: ToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
      _isSearchExpanded =
          false; // Tutup mode daftar dilihat dan tampilkan hasil real
    });

    try {
      final res = await widget.apiService.lookupPhoneNumber(
        cleanQuery,
        skipIncrement: cleanQuery == _myPhoneNumber,
        hasContactAccess: _hasContactPermission,
      );
      if (mounted) {
        setState(() {
          _phoneRecord = res.data;
          // Jangan tampilkan banner status bila data detail nomor berhasil dimuat ke layar
          if (res.data == null) {
            _showAutoDismissStatus(res.message);
          } else {
            _statusMessage = null;
            _errorMessage = null;
          }
          _isLoading = false;

          // Tambahkan ke daftar nyata "Baru Saja Dilihat" (Kecuali nomor milik pengguna sendiri)
          if (cleanQuery != _myPhoneNumber) {
            _recentlyViewed.removeWhere((item) => item['number'] == cleanQuery);
            String name = cleanQuery;
            if (res.data != null && res.data!.tags.isNotEmpty) {
              name = res.data!.tags.first.labelName;
            } else {
              final matched = _contacts
                  .where(
                    (c) => c.phones.any(
                      (p) =>
                          p.number.replaceAll(' ', '') ==
                          cleanQuery.replaceAll(' ', ''),
                    ),
                  )
                  .firstOrNull;
              if (matched != null) {
                name = _getContactName(matched);
              }
            }
            _recentlyViewed.insert(0, {
              'name': name,
              'number': cleanQuery,
              'date': 'Baru Saja',
              'initial': _getInitials(name),
              'color': _getAvatarColor(name),
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        if (e is QuotaExceededException || e.toString().contains('Limit pencarian gratis')) {
          AppToast.show(
            context,
            message: 'Limit gratis harian (1x) telah habis.',
            type: ToastType.info,
          );
          _showQuotaExceededModal();
        } else {
          String rawErr = e.toString().replaceAll('Exception: ', '');
          if (rawErr.contains('TimeoutException') || rawErr.contains('Future not completed')) {
            rawErr = 'Koneksi ke server lambat atau terputus. Silakan periksa jaringan internet Anda.';
          }
          _showAutoDismissStatus(null, error: rawErr);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleVote(TagItem tag, String voteType) async {
    try {
      final success = await widget.apiService.voteTag(tag.id, voteType, userId: _myPhoneNumber.isNotEmpty ? _myPhoneNumber : null);
      if (success && mounted) {
        AppToast.show(
          context,
          message: 'Penilaian reputasi ($voteType) berhasil dicatat.',
          type: ToastType.success,
        );
        if (_phoneRecord != null) {
          _performSearch(_phoneRecord!.phoneNumber);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
          type: ToastType.error,
        );
      }
    }
  }

  String _getFlagForCountryCode(String code) {
    switch (code.trim()) {
      case '+62': return '🇮🇩';
      case '+60': return '🇲🇾';
      case '+65': return '🇸🇬';
      case '+1': return '🇺🇸';
      case '+44': return '🇬🇧';
      case '+61': return '🇦🇺';
      case '+81': return '🇯🇵';
      case '+82': return '🇰🇷';
      case '+86': return '🇨🇳';
      case '+91': return '🇮🇳';
      default: return '🌐';
    }
  }

  void _showCountryCodeModal() {
    final countries = [
      {'name': 'Indonesia', 'code': '+62', 'flag': '🇮🇩'},
      {'name': 'Malaysia', 'code': '+60', 'flag': '🇲🇾'},
      {'name': 'Singapura', 'code': '+65', 'flag': '🇸🇬'},
      {'name': 'Amerika Serikat', 'code': '+1', 'flag': '🇺🇸'},
      {'name': 'Inggris', 'code': '+44', 'flag': '🇬🇧'},
      {'name': 'Australia', 'code': '+61', 'flag': '🇦🇺'},
      {'name': 'Jepang', 'code': '+81', 'flag': '🇯🇵'},
      {'name': 'Korea Selatan', 'code': '+82', 'flag': '🇰🇷'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text(
                    'Pilih Kode Negara',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: countries.map((item) {
                      final isSel = _selectedCountryCode == item['code'];
                      return ListTile(
                        leading: Text(item['flag']!, style: const TextStyle(fontSize: 24)),
                        title: Text(
                          item['name']!,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: Text(
                          item['code']!,
                          style: GoogleFonts.plusJakartaSans(
                            color: isSel ? const Color(0xFF007AFF) : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _selectedCountryCode = item['code']!);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddTagDialog() {
    final tagController = TextEditingController();
    final phoneController = TextEditingController(text: _phoneRecord?.phoneNumber ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _phoneRecord == null ? 'Tambah Tag Saya' : 'Tambah Label Baru',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _phoneRecord == null
                    ? 'Buat label identitas atau catatan khusus untuk nomor Anda sendiri yang tersimpan di Tag Saya.'
                    : 'Bantu pengguna lain mengenali nomor ini dengan memberikan label nama, profesi, atau kategori.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: tagController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _phoneRecord == null
                      ? 'Nama Tag Saya (misal: My Im3 / Bisnis Saya / Pribadi)'
                      : 'Contoh: Kurir Paket / Toko Online / Rekan Kerja',
                  hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38),
                  prefixIcon: const Icon(
                    Icons.label_outline_rounded,
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E263D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                autofocus: true,
              ),
              if (_phoneRecord == null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nomor Telepon Anda (Opsional, untuk sinkronisasi server)',
                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38),
                    prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: const Color(0xFF1E263D),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final label = tagController.text.trim();
                    if (label.isEmpty) return;
                    final numTarget = phoneController.text.trim();
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);

                    try {
                      String phoneId = _phoneRecord?.id ?? '';
                      // Jika menambah dari Beranda/Tag Saya dan ada nomor telepon yang dimasukkan
                      if (phoneId.isEmpty && numTarget.isNotEmpty) {
                        final lookupRes = await widget.apiService.lookupPhoneNumber(numTarget, hasContactAccess: _hasContactPermission);
                        if (lookupRes.found && lookupRes.data != null) {
                          phoneId = lookupRes.data!.id;
                        }
                      }

                      if (phoneId.isNotEmpty) {
                        await widget.apiService.addTag(phoneId, label, userId: _myPhoneNumber);
                      }

                      if (mounted) {
                        if (!_userTags.contains(label)) {
                          setState(() => _userTags.add(label));
                          _saveUserTagsToPrefs();
                        }
                        AppToast.show(
                          context,
                          message: 'Label "#$label" berhasil ditambahkan.',
                          type: ToastType.success,
                        );
                        if (_phoneRecord != null) {
                          _performSearch(_phoneRecord!.phoneNumber);
                        } else if (numTarget.isNotEmpty) {
                          _searchController.text = numTarget;
                          _performSearch(numTarget);
                        } else {
                          setState(() => _isLoading = false);
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        if (!_userTags.contains(label)) {
                          setState(() => _userTags.add(label));
                          _saveUserTagsToPrefs();
                        }
                        AppToast.show(
                          context,
                          message: 'Label "#$label" ditambahkan ke daftar Anda. (${e.toString().replaceAll('Exception: ', '')})',
                          type: ToastType.success,
                        );
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('SIMPAN TAG', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAllCallLogsModal() {
    String currentFilter = _callLogFilterTime;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final now = DateTime.now();
            final List<Map<String, dynamic>> logsList = _callLogs.isNotEmpty
                ? _callLogs.map((log) {
                    return {
                      'number': (log.number ?? '').trim(),
                      'name': (log.name != null && log.name!.trim().isNotEmpty) ? log.name!.trim() : (log.number ?? '').trim(),
                      'timestamp': log.timestamp,
                      'callType': log.callType,
                    };
                  }).toList()
                : _realRecentCalls.map((item) {
                    return {
                      'number': item['number'] ?? item['sub'] ?? '',
                      'name': item['name'] ?? item['number'] ?? '',
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                      'callType': CallType.incoming,
                    };
                  }).toList();

            final filteredLogs = logsList.where((log) {
              final ts = log['timestamp'] as int?;
              if (ts == null) return true;
              final logDate = DateTime.fromMillisecondsSinceEpoch(ts);
              if (currentFilter == 'Hari Ini') {
                return logDate.year == now.year && logDate.month == now.month && logDate.day == now.day;
              } else if (currentFilter == 'Minggu Ini') {
                return now.difference(logDate).inDays <= 7;
              } else if (currentFilter == 'Bulan Ini') {
                return logDate.year == now.year && logDate.month == now.month;
              }
              return true;
            }).toList();

            return Container(
              width: double.infinity,
              height: MediaQuery.of(ctx).size.height * 0.52,
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Riwayat Panggilan (${filteredLogs.length})',
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: ['Hari Ini', 'Minggu Ini', 'Bulan Ini', 'Semua'].map((filterStr) {
                        final isSel = currentFilter == filterStr;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                            label: Text(
                              filterStr,
                              style: GoogleFonts.sora(
                                color: isSel ? Colors.white : AppColors.textSecondary,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFF007AFF),
                            backgroundColor: const Color(0xFF1E263D),
                            onSelected: (sel) {
                              if (sel) {
                                setModalState(() => currentFilter = filterStr);
                                setState(() => _callLogFilterTime = filterStr);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: filteredLogs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1E263D),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.phone_disabled_rounded,
                                      size: 32,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Belum Ada Panggilan $currentFilter',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.sora(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Riwayat panggilan untuk filter ini belum tersedia atau kosong.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredLogs.length,
                            itemBuilder: (ctx, idx) {
                              final log = filteredLogs[idx];
                              final numStr = (log['number'] as String? ?? '').trim();
                              final rawName = (log['name'] as String? ?? '').trim();
                              final hasContactName = rawName.isNotEmpty && rawName != numStr;
                              final titleName = hasContactName ? rawName : numStr;

                              final ts = log['timestamp'] as int?;
                              final timeFormatted = _formatCallTime(ts);
                              final callType = log['callType'] as CallType?;
                              final typeStr = callType == CallType.incoming
                                  ? 'Panggilan Masuk'
                                  : callType == CallType.outgoing
                                      ? 'Panggilan Keluar'
                                      : 'Tak Terjawab';
                              final typeColor = callType == CallType.missed
                                  ? AppColors.accentRed
                                  : AppColors.accentCyan;

                              final timeAndType = timeFormatted.isNotEmpty
                                  ? '$timeFormatted | $typeStr'
                                  : typeStr;
                              final subStr = hasContactName
                                  ? '$numStr | $timeAndType'
                                  : timeAndType;

                              String? tag = _recentCallTags[numStr];

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: typeColor.withValues(alpha: 0.2),
                                  child: Icon(
                                    callType == CallType.incoming
                                        ? Icons.call_received_rounded
                                        : callType == CallType.outgoing
                                            ? Icons.call_made_rounded
                                            : Icons.call_missed_rounded,
                                    color: typeColor,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  titleName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.sora(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 3),
                                    Text(
                                      subStr,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppColors.textSecondary,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    if (tag != null && tag.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: AppColors.primaryLight.withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          tag,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppColors.primaryLight,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF007AFF),
                                  size: 20,
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _searchController.text = numStr;
                                  _performSearch(numStr);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _onSearchContactIconTapped() async {
    if (!_hasContactPermission) {
      AppToast.show(
        context,
        message: 'Izin akses kontak diperlukan untuk memilih nomor dari kontak.',
        type: ToastType.info,
      );
      _showContactAccessConsentModal();
      return;
    }

    if (_contacts.isEmpty) {
      AppToast.show(
        context,
        message: 'Memuat daftar kontak Anda...',
        type: ToastType.info,
      );
      await _fetchRealDeviceContacts();
      if (!mounted) return;
    }

    if (_contacts.isEmpty) {
      AppToast.show(
        context,
        message: 'Daftar buku telepon Anda masih kosong.',
        type: ToastType.info,
      );
      return;
    }

    _showAllContactsModal();
  }

  void _showAllContactsModal() {
    String searchContactQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredContacts = _contacts.where((c) {
              final name = _getContactName(c).toLowerCase();
              final num = (c.phones.isNotEmpty ? c.phones.first.number : '').toLowerCase();
              final q = searchContactQuery.toLowerCase();
              return name.contains(q) || num.contains(q);
            }).toList();
            final isKeyboardOpen = MediaQuery.of(ctx).viewInsets.bottom > 0;
            final targetHeight = isKeyboardOpen
                ? MediaQuery.of(ctx).size.height * 0.85
                : MediaQuery.of(ctx).size.height * 0.52;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuad,
              width: double.infinity,
              height: targetHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 20,
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Semua Kontak (${_contacts.length} Orang)',
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    style: GoogleFonts.plusJakartaSans(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Cari nama atau nomor telepon...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: const Color(0xFF1E263D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchContactQuery = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? Center(child: Text('Kontak tidak ditemukan.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (ctx, idx) {
                              final c = filteredContacts[idx];
                              final nameStr = _getContactName(c);
                              final numStr = c.phones.isNotEmpty ? c.phones.first.number : '-';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.2),
                                  child: Text(
                                    nameStr.isNotEmpty ? nameStr.substring(0, 1).toUpperCase() : '#',
                                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF2B8CFF), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(nameStr, style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                subtitle: Text(numStr, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13)),
                                trailing: const Icon(Icons.search_rounded, color: Color(0xFF007AFF), size: 20),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _searchController.text = numStr;
                                  _performSearch(numStr);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSearchExpanded && _phoneRecord == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Jika sedang di mode pencarian aktif → kembali ke idle
        if (_isSearchExpanded) {
          setState(() {
            _isSearchExpanded = false;
            _searchController.clear();
            _searchFocusNode.unfocus();
          });
          return;
        }
        // Jika sedang menampilkan hasil pencarian → bersihkan hasil
        if (_phoneRecord != null) {
          setState(() {
            _phoneRecord = null;
            _errorMessage = null;
            _statusMessage = null;
            _searchController.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D111C),
        body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                // Top Bar yang berubah secara dinamis antara mode biasa dan mode aktif pencarian (Gambar ke-5)
                _buildDynamicTopBar(),

                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFFEF4444),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _errorMessage = null),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFFEF4444),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_statusMessage != null && _statusMessage!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF10B981),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _statusMessage = null),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFF10B981),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Konten Utama
                Expanded(
                  child: _isLoading || _isContactsLoading
                      ? Shimmer.fromColors(
                          baseColor: const Color(0xFF1E2636),
                          highlightColor: const Color(0xFF2D3754),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Skeleton header card
                                Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Skeleton tag chips row
                                Row(
                                  children: [
                                    Container(width: 80, height: 34, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                                    const SizedBox(width: 8),
                                    Container(width: 110, height: 34, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                                    const SizedBox(width: 8),
                                    Container(width: 70, height: 34, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Skeleton section title
                                Container(width: 180, height: 18, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                                const SizedBox(height: 14),
                                // Skeleton list items
                                ...List.generate(3, (i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Container(
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                )),
                              ],
                            ),
                          ),
                        )
                      : _isSearchExpanded
                      ? _buildSearchExpandedView() // Tampilan saat tombol search dipencet (Gambar ke-5)
                      : _phoneRecord != null
                      ? _buildRealSearchResultView() // Tampilan hasil detail nomor
                      : _buildHomeIdle4Sections(), // Tampilan beranda murni 4 struktur nyata dari kontak
                ),
              ],
            ),
          ),

            // Floating Dialpad Button ala aplikasi referensi (muncul di Beranda saat idle)
            if (!_isSearchExpanded && _phoneRecord == null)
              Positioned(
                right: 20,
                bottom: 24,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _isSearchExpanded = true;
                    });
                    _searchFocusNode.requestFocus();
                  },
                  backgroundColor: const Color(0xFF004085),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.apps_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }

  // Bar Atas Dinamis
  Widget _buildDynamicTopBar() {
    if (_isSearchExpanded) {
      // Mode Gambar ke-5: Tombol Kembali + Kapsul Kode Negara + Input
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        color: const Color(0xFF131824),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _isSearchExpanded = false;
                  _searchFocusNode.unfocus();
                });
              },
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _showCountryCodeModal,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2637),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E384D), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getFlagForCountryCode(_selectedCountryCode),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _selectedCountryCode,
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 1),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white60,
                      size: 13,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2637),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF2E384D)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: _getDynamicSearchHint(),
                          hintStyle: GoogleFonts.plusJakartaSans(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        keyboardType: TextInputType.phone,
                        onSubmitted: _performSearch,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => _searchController.clear(),
                        child: const Icon(
                          Icons.clear,
                          color: Colors.white60,
                          size: 18,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _onSearchContactIconTapped,
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.account_circle_outlined,
                            color: AppColors.primaryLight,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else if (_phoneRecord != null) {
      // Mode Hasil Pencarian Detail: Tombol Kembali + Kapsul Info Nomor/Tutup
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        color: const Color(0xFF131824),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _phoneRecord = null;
                  _statusMessage = null;
                  _errorMessage = null;
                  _searchController.clear();
                });
              },
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isSearchExpanded = true;
                  });
                  _searchFocusNode.requestFocus();
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2133),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF2A3450), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white60,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _phoneRecord!.phoneNumber,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _phoneRecord = null;
                            _statusMessage = null;
                            _errorMessage = null;
                            _searchController.clear();
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white60,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Mode Kapsul Normal (Beranda) dengan Contoh Negara Dinamis
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: Colors.transparent, // Menyatu dengan warna background utama
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2133),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF2A3450), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _showCountryCodeModal,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28324A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_getFlagForCountryCode(_selectedCountryCode), style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 3),
                      Text(
                        _selectedCountryCode,
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 1),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white60,
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isSearchExpanded = true;
                    });
                    _searchFocusNode.requestFocus();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white60,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getDynamicSearchHint(),
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _onSearchContactIconTapped,
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.account_circle_outlined,
                    color: AppColors.primaryLight,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // =========================================================================
  // 4 STRUKTUR MURNI BERANDA (100% REAL DATA DARI KONTAK PERANGKAT)
  // =========================================================================
  Widget _buildHomeIdle4Sections() {
    return RefreshIndicator(
      color: AppColors.primaryLight,
      backgroundColor: const Color(0xFF1F2637),
      onRefresh: _checkAndLoadContacts,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Panggilan Terbaru',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (_hasCallLogPermission && _hasContactPermission)
                  InkWell(
                    onTap: _isRefreshingCallLog
                        ? null
                        : () async {
                            setState(() => _isRefreshingCallLog = true);
                            Future.delayed(const Duration(milliseconds: 500), () {
                              if (mounted) setState(() => _isRefreshingCallLog = false);
                            });
                            _fetchRealCallLogs();
                            _fetchRealDeviceContacts();
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          _isRefreshingCallLog
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryLight,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16, color: AppColors.primaryLight),
                          const SizedBox(width: 4),
                          Text(
                            _isRefreshingCallLog ? 'Memperbarui...' : 'Perbarui',
                            style: GoogleFonts.sora(
                              color: AppColors.primaryLight,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isRefreshingCallLog)
              Shimmer.fromColors(
                baseColor: const Color(0xFF1E2636),
                highlightColor: const Color(0xFF2D3754),
                child: Column(
                  children: List.generate(
                    3,
                    (index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 140,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 180,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 60,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (_realRecentCalls.isEmpty || !_hasCallLogPermission || !_hasContactPermission)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: (!_hasContactPermission || !_hasCallLogPermission)
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2035),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.contacts_rounded,
                                  color: AppColors.primaryLight,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Izin Kontak Diperlukan',
                                style: GoogleFonts.sora(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Izinkan akses kontak & log panggilan untuk melihat riwayat panggilan asli dari HP Anda.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _showContactAccessConsentModal,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Izinkan Akses Kontak',
                                    style: GoogleFonts.sora(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_disabled_rounded,
                              size: 38,
                              color: AppColors.textSecondary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada riwayat panggilan kontak nyata.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else
              ..._realRecentCalls.map((item) {
                final num = item['number'] as String;
                String? topTag = _recentCallTags[num];
                return InkWell(
                  onTap: () {
                    _searchController.text = num;
                    _performSearch(num);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1E2636), width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.sora(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: (item['isSpam'] as bool)
                                      ? const Color(0xFFEF4444)
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (item['isSpam'] as bool) ...[
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 15,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    item['sub'] as String,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              if (topTag != null && topTag.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.primaryLight.withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    topTag,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.primaryLight,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            Text(
                              item['date'] as String,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white54,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (_hasCallLogPermission && _hasContactPermission && _realRecentCalls.isNotEmpty) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _showAllCallLogsModal,
                  icon: Text(
                    'Tampilkan Semuanya ($_callLogFilterTime)',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF2B8CFF),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  label: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF2B8CFF),
                    size: 18,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 30),

            // -------------------------------------------------------------
            // 2. TAMPILAN TAG PENGGUNA / TAG SAYA (Struktur Gambar 2 & 3)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tag Saya',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (_allMyTagsCombined.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyTagsDetailScreen(
                              allTags: _allMyTagsCombined,
                              apiService: widget.apiService,
                              myPhoneNumber: _myPhoneNumber,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2636),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2D3754)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Detail',
                              style: GoogleFonts.sora(
                                color: AppColors.primaryLight,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, color: AppColors.primaryLight, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_allMyTagsCombined.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Belum ada tag/label khusus untuk nomor Anda.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._allMyTagsCombined.take(5).map(
                  (t) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyTagsDetailScreen(
                              allTags: _allMyTagsCombined,
                              apiService: widget.apiService,
                              myPhoneNumber: _myPhoneNumber,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '# ${t.labelName}',
                              style: GoogleFonts.sora(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_hasContactPermission) ...[
              const SizedBox(height: 28),
              Text(
                'Kontak Cepat',
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              if (_realQuickContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Tidak ada kontak untuk ditampilkan.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: _realQuickContacts
                      .map(
                        (t) {
                          final dbCount = _quickContactTagCounts[t.phoneNumberId];
                          final displayTag = TagItem(
                            id: t.id,
                            phoneNumberId: t.phoneNumberId,
                            labelName: t.labelName,
                            upvotes: dbCount ?? t.upvotes,
                            isSpam: t.isSpam,
                          );
                          return TagChipCard(
                            tag: displayTag,
                            onVote: (type) => _handleVote(t, type),
                            onTap: () {
                              if (t.phoneNumberId.isNotEmpty) {
                                _searchController.text = t.phoneNumberId;
                                _performSearch(t.phoneNumberId);
                              }
                            },
                          );
                        },
                      )
                      .toList(),
                ),
              if (_contacts.isNotEmpty) ...[
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _showAllContactsModal,
                      icon: Text(
                        'Tampilkan Semua (${_contacts.length} Orang)',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF2B8CFF),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      label: const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF2B8CFF),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 28),

            // -------------------------------------------------------------
            // 4. MEMUNCULKAN DAFTAR ORANG YANG MENCARI NOMOR PENGGUNA (Gambar 4 & 5)
            // -------------------------------------------------------------
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyPhoneSearchersScreen(
                        searchCount: _myPhoneSearchCount,
                        trustScore: _myPhoneTrustScore,
                        myPhoneTags: _myPhoneTags,
                        myPhoneNumber: _myPhoneNumber,
                        searcherItems: _cachedSearcherItems,
                        onRefresh: _fetchMyPhoneSearchStats,
                        onSearchNumber: (String number) {
                          Navigator.pop(context); // Tutup halaman MyPhoneSearchersScreen
                          _searchController.text = number;
                          _performSearch(number); // Lakukan pencarian
                        },
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141926),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF20273C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(
                                    Icons.person_search_rounded,
                                    color: AppColors.primaryLight,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Aktivitas Pencarian Nomor Anda',
                                    style: GoogleFonts.sora(
                                      color: AppColors.primaryLight,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2636),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF2D3754)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Detail',
                                  style: GoogleFonts.sora(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_isMyStatsLoading)
                        Text(
                          'Memeriksa aktivitas pencarian...',
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_myPhoneSearchCount > 0)
                        Text(
                          '${_myPhoneSearchCount}x Diperiksa Orang Lain',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else
                        Text(
                          'Belum tercatat aktivitas pemeriksaan atau penelusuran pada profil nomor Anda.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),

                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // =======================================
  // TAMPILAN SAAT TOMBOL SEARCH DIPENCET
  // =======================================
  Widget _buildSearchExpandedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Baru Saja Dilihat',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (_recentlyViewed.isNotEmpty)
                InkWell(
                  onTap: () {
                    setState(() {
                      _recentlyViewed.clear();
                    });
                  },
                  child: Text(
                    'Hapus',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF2B8CFF),
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentlyViewed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _contacts.isNotEmpty
                          ? 'Belum Ada Riwayat Pencarian'
                          : 'Belum Ada Nomor Dilihat',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _contacts.isNotEmpty
                          ? 'Nomor yang Anda cari akan otomatis tercatat di sini.'
                          : 'Riwayat nomor telepon yang baru saja Anda periksa akan muncul di sini.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _recentlyViewed.map((item) {
                return InkWell(
                  onTap: () {
                    _searchController.text = item['number'] as String;
                    _performSearch(item['number'] as String);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1E2636), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: item['color'] as Color,
                          child: Text(
                            item['initial'] as String,
                            style: GoogleFonts.sora(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'] as String,
                                style: GoogleFonts.sora(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['number'] as String,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item['date'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // Tampilan Hasil Pencarian Detail Nomor Asli
  Widget _buildRealSearchResultView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF141926),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF20273C)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phoneRecord!.phoneNumber,
                  style: GoogleFonts.sora(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                TrustMeter(
                  score: _phoneRecord!.trustScore,
                  searchCount: _phoneRecord!.searchCount,
                ),
                if (_phoneRecord!.carrier != null &&
                    _phoneRecord!.carrier!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        (_phoneRecord!.carrier!.contains('PSTN') ||
                                _phoneRecord!.carrier!.contains('Fixed Line') ||
                                _phoneRecord!.carrier!.contains('Telkom Indonesia'))
                            ? Icons.phone_rounded
                            : Icons.cell_tower_rounded,
                        color: AppColors.accentCyan,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Operator: ${_phoneRecord!.carrier}',
                          style: GoogleFonts.sora(
                            color: AppColors.accentCyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tag & Label (${_phoneRecord!.tags.length})',
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              InkWell(
                onTap: _showAddTagDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryLight),
                  ),
                  child: Text(
                    '+ Tambah Tag',
                    style: GoogleFonts.sora(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_phoneRecord!.tags.isEmpty)
            Text(
              'Belum ada label tag untuk nomor ini. Tekan tombol "+ Tambah Tag" untuk memberi label.',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _phoneRecord!.tags.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.isSpam
                        ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                        : const Color(0xFF1E263D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: t.isSpam
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF2C3756),
                    ),
                  ),
                  child: Text(
                    '# ${t.labelName}',
                    style: GoogleFonts.plusJakartaSans(
                      color: t.isSpam ? const Color(0xFFEF4444) : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 28),

          Text(
            'Daftar Ulasan & Reputasi',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          if (_phoneRecord!.tags.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF141926),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF20273C)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.label_off_rounded,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Belum Ada Ulasan Tag',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jadilah yang pertama memberikan label apakah nomor ini kurir, penipu, atau rekan bisnis.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _showAddTagDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      'Beri Tag Sekarang',
                      style: GoogleFonts.sora(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _phoneRecord!.tags
                  .map(
                    (t) => TagChipCard(
                      tag: t,
                      onVote: (type) => _handleVote(t, type),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
