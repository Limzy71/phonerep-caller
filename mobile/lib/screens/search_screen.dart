import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/phone_record.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tag_chip_card.dart';
import '../widgets/trust_meter.dart';

class SearchScreen extends StatefulWidget {
  final ApiService apiService;

  const SearchScreen({super.key, required this.apiService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
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
      setState(() {
        _myPhoneNumber = phone.trim();
        _isMyStatsLoading = true;
      });
    }

    try {
      final res = await widget.apiService.lookupPhoneNumber(_myPhoneNumber, skipIncrement: true);
      if (mounted && res.data != null) {
        setState(() {
          _myPhoneSearchCount = res.data!.searchCount;
          _myPhoneTrustScore = res.data!.trustScore;
          _myPhoneTags = res.data!.tags;
          _isMyStatsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isMyStatsLoading = false;
        });
      }
    }
  }

  void _showMyPhoneProtectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: const Color(0xFF10141D),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: const Color(0xFF20273C)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.shield_rounded, color: AppColors.primaryLight, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Laporan Reputasi & Proteksi',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _myPhoneNumber.isNotEmpty ? _myPhoneNumber : 'Nomor Belum Terdaftar',
                          style: GoogleFonts.outfit(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161C2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF222B42)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Diperiksa / Dicari',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_myPhoneSearchCount Kali',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white12),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skor Reputasi',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${_myPhoneTrustScore.toStringAsFixed(0)}%',
                                style: GoogleFonts.outfit(color: AppColors.accentGreen, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),
                              Text('Aman', style: GoogleFonts.outfit(color: AppColors.accentGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_myPhoneTags.isNotEmpty) ...[
                Text(
                  'Label Komunitas Terdeteksi (${_myPhoneTags.length})',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _myPhoneTags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: t.isSpam ? AppColors.accentRed.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.isSpam ? AppColors.accentRed.withValues(alpha: 0.4) : AppColors.primaryLight.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      t.labelName,
                      style: GoogleFonts.outfit(
                        color: t.isSpam ? AppColors.accentRed : AppColors.primaryLight,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                'Mengapa identitas pencari tidak ditampilkan?',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Sesuai regulasi privasi & keamanan siber Undang-Undang Perlindungan Data Pribadi (UU PDP No. 27/2022), identitas spesifik pencari dienkripsi dan tidak dipublikasikan untuk mencegah risiko stalking atau pelanggaran privasi.\n\nNamun, Sistem Proteksi PhoneRep secara aktif memantau pola pencarian. Jika terdeteksi aktivitas pemindaian massal (crawling) atau pelabelan spam terhadap nomor Anda, sistem proteksi AI otomatis memblokir dan mengirimkan notifikasi peringatan.',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _fetchMyPhoneSearchStats();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('Perbarui Statistik', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF2D3754)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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

  void _showContactAccessConsentModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
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
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Untuk mendeteksi panggilan spam/penipuan secara real-time, mengidentifikasi nomor asing, dan melindungi kontak Anda dalam komunitas, aplikasi membutuhkan izin akses untuk membaca Kontak & Log Telepon Anda.',
                style: GoogleFonts.outfit(
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
                        style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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

  Future<void> _requestCallLogPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasAgreed = prefs.getBool('has_agreed_contact_access') ?? false;
    if (!hasAgreed) {
      _showContactAccessConsentModal();
      return;
    }
    setState(() => _isContactsLoading = true);
    final status = await Permission.phone.request();
    if (status.isGranted) {
      _hasCallLogPermission = true;
      await _fetchRealCallLogs();
    } else {
      _hasCallLogPermission = false;
      if (mounted && status.isPermanentlyDenied) {
        openAppSettings();
      }
    }
    if (mounted) {
      setState(() => _isContactsLoading = false);
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
      }
    } catch (e) {
      // Abaikan jika gagal mengakses log
    }
  }

  Future<void> _requestContactPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasAgreed = prefs.getBool('has_agreed_contact_access') ?? false;
    if (!hasAgreed) {
      _showContactAccessConsentModal();
      return;
    }
    setState(() => _isContactsLoading = true);
    final status = await Permission.contacts.request();
    if (status.isGranted) {
      _hasContactPermission = true;
      await _fetchRealDeviceContacts();
    } else {
      _hasContactPermission = false;
      setState(() => _isContactsLoading = false);
      if (mounted && status.isPermanentlyDenied) {
        openAppSettings();
      }
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
          setState(() {
            _contacts = contacts.where((c) => c.phones.isNotEmpty).toList();
            _isContactsLoading = false;
          });
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

  // Getter Panggilan Terbaru Asli dari Kontak Perangkat & Riwayat Nyata
  List<Map<String, dynamic>> get _realRecentCalls {
    final List<Map<String, dynamic>> combined = [];
    // Prioritaskan riwayat pencarian nyata pengguna jika ada
    for (final item in _recentlyViewed) {
      if (item['date'] != 'Dari Kontak') {
        combined.add({
          'name': item['name'],
          'sub': item['number'],
          'date': item['date'],
          'isSpam': false,
          'number': item['number'],
        });
      }
    }
    // Tambahkan dari riwayat panggilan nyata HP (CallLog) jika ada
    if (_callLogs.isNotEmpty) {
      for (final log in _callLogs) {
        if (combined.length >= 8) break;
        final num = (log.number ?? '').trim();
        if (num.isNotEmpty && !combined.any((x) => x['number'] == num)) {
          final name = (log.name != null && log.name!.trim().isNotEmpty) ? log.name!.trim() : num;
          final typeStr = log.callType == CallType.incoming
              ? 'Panggilan Masuk'
              : log.callType == CallType.outgoing
                  ? 'Panggilan Keluar'
                  : 'Tak Terjawab';
          combined.add({
            'name': name,
            'sub': '$num ($typeStr)',
            'date': 'Log Telepon',
            'isSpam': false,
            'number': num,
          });
        }
      }
    }
    // Lengkapi dengan kontak asli HP pengguna tanpa hardcode string/tanggal palsu
    if (_contacts.isNotEmpty) {
      for (final c in _contacts) {
        if (combined.length >= 5) break;
        final num = c.phones.first.number;
        if (!combined.any((x) => x['number'] == num)) {
          final labelStr =
              (c.phones.first.label == PhoneLabel.custom
                      ? c.phones.first.customLabel
                      : c.phones.first.label.name)
                  .trim();
          final cleanLabel = labelStr.isNotEmpty && labelStr != 'custom'
              ? labelStr
              : 'Ponsel';
          combined.add({
            'name': _getContactName(c),
            'sub': '$num ($cleanLabel)',
            'date': 'Kontak HP',
            'isSpam': false,
            'number': num,
          });
        }
      }
    }
    return combined.take(5).toList();
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
      final realCount = c.phones.isNotEmpty ? c.phones.length : 1;
      return TagItem(
        id: c.id,
        phoneNumberId: num,
        labelName: name,
        upvotes: realCount,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nomor telepon yang valid.')),
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
      final res = await widget.apiService.lookupPhoneNumber(cleanQuery);
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

          // Tambahkan ke daftar nyata "Baru Saja Dilihat"
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
        });
      }
    } catch (e) {
      if (mounted) {
        _showAutoDismissStatus(null, error: e.toString().replaceAll('Exception: ', ''));
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleVote(TagItem tag, String voteType) async {
    try {
      final success = await widget.apiService.voteTag(tag.id, voteType);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Penilaian reputasi ($voteType) berhasil dicatat.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (_phoneRecord != null) {
          _performSearch(_phoneRecord!.phoneNumber);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
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
                    style: GoogleFonts.outfit(
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
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: Text(
                          item['code']!,
                          style: GoogleFonts.outfit(
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
                    _phoneRecord == null ? 'Tambah Tag Saya' : 'Tambah Tag Komunitas',
                    style: GoogleFonts.outfit(
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
                    : 'Bantu komunitas mengenali nomor ini dengan memberikan label nama, profesi, atau peringatan.',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: tagController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _phoneRecord == null
                      ? 'Nama Tag Saya (misal: My Im3 / Bisnis Saya / Pribadi)'
                      : 'Contoh: Kurir Paket / Toko Online / Rekan Kerja',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
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
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nomor Telepon Anda (Opsional, untuk sinkronisasi server)',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38),
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
                        final lookupRes = await widget.apiService.lookupPhoneNumber(numTarget);
                        if (lookupRes.found && lookupRes.data != null) {
                          phoneId = lookupRes.data!.id;
                        }
                      }

                      if (phoneId.isNotEmpty) {
                        await widget.apiService.addTag(phoneId, label);
                      }

                      if (mounted) {
                        if (!_userTags.contains(label)) {
                          setState(() => _userTags.add(label));
                          _saveUserTagsToPrefs();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Label "#$label" berhasil ditambahkan.'),
                            backgroundColor: AppColors.accentGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Label "#$label" ditambahkan ke daftar Anda. (${e.toString().replaceAll('Exception: ', '')})'),
                            backgroundColor: AppColors.accentGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('SIMPAN TAG', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
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
              height: MediaQuery.of(ctx).size.height * 0.8,
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Riwayat Panggilan (${filteredLogs.length})',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                    child: Row(
                      children: ['Hari Ini', 'Minggu Ini', 'Bulan Ini', 'Semua'].map((filterStr) {
                        final isSel = currentFilter == filterStr;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filterStr, style: GoogleFonts.outfit(color: isSel ? Colors.white : AppColors.textSecondary, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
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
                            child: Text('Tidak ada riwayat panggilan untuk filter "$currentFilter".', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                          )
                        : ListView.builder(
                            itemCount: filteredLogs.length,
                            itemBuilder: (ctx, idx) {
                              final log = filteredLogs[idx];
                              final numStr = (log['number'] as String? ?? '').trim();
                              final nameStr = (log['name'] as String? ?? '').trim();
                              final ts = log['timestamp'] as int?;
                              final logDate = ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
                              final dateStr = logDate != null
                                  ? (logDate.day == now.day && logDate.month == now.month && logDate.year == now.year
                                      ? 'Hari ini ${logDate.hour.toString().padLeft(2, '0')}:${logDate.minute.toString().padLeft(2, '0')}'
                                      : '${logDate.day}/${logDate.month}/${logDate.year}')
                                  : 'Baru saja';
                              final callType = log['callType'] as CallType?;
                              final typeStr = callType == CallType.incoming ? 'Masuk' : callType == CallType.outgoing ? 'Keluar' : 'Tak Terjawab';
                              final typeColor = callType == CallType.missed ? AppColors.accentRed : AppColors.accentCyan;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: typeColor.withValues(alpha: 0.2),
                                  child: Icon(
                                    callType == CallType.incoming ? Icons.call_received_rounded : callType == CallType.outgoing ? Icons.call_made_rounded : Icons.call_missed_rounded,
                                    color: typeColor,
                                    size: 20,
                                  ),
                                ),
                                title: Text(nameStr.isNotEmpty ? nameStr : numStr, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                subtitle: Text('$numStr • $typeStr ($dateStr)', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5)),
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
            );
          },
        );
      },
    );
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

            return Container(
              width: double.infinity,
              height: MediaQuery.of(ctx).size.height * 0.85,
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Semua Kontak (${_contacts.length} Orang)',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Cari nama atau nomor telepon...',
                      hintStyle: GoogleFonts.outfit(color: Colors.white38),
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
                        ? Center(child: Text('Kontak tidak ditemukan.', style: GoogleFonts.outfit(color: AppColors.textSecondary)))
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
                                    style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(nameStr, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                subtitle: Text(numStr, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
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
                            style: GoogleFonts.outfit(
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
                            style: GoogleFonts.outfit(
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
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryLight,
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
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2637),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E384D)),
                ),
                child: Row(
                  children: [
                    Text(
                      _getFlagForCountryCode(_selectedCountryCode),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedCountryCode,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white60,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
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
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: _getDynamicSearchHint(),
                          hintStyle: GoogleFonts.outfit(
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
                      const Icon(
                        Icons.account_circle_outlined,
                        color: Colors.white70,
                        size: 22,
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
                          style: GoogleFonts.outfit(
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28324A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_getFlagForCountryCode(_selectedCountryCode), style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCountryCode,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                          style: GoogleFonts.outfit(
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
              const SizedBox(width: 8),
              const Icon(
                Icons.account_circle_outlined,
                color: Colors.white70,
                size: 24,
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
            // Promt Izin Kontak Nyata bila belum diberi izin
            if (!_hasContactPermission)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2637),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.contacts_rounded,
                      color: AppColors.primaryLight,
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hubungkan Kontak Nyata Anda',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Beri izin akses kontak untuk memunculkan riwayat panggilan & kontak cepat asli dari HP Anda.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _requestContactPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Aktifkan Izin Kontak Asli',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ---------------------------------------------
            // 1. PANGGILAN TERBARU & TOMBOL LIHAT SEMUA
            // ---------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Panggilan Terbaru',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                InkWell(
                  onTap: () {
                    if (!_hasCallLogPermission) {
                      _requestCallLogPermission();
                    } else if (!_hasContactPermission) {
                      _requestContactPermission();
                    } else {
                      _fetchRealCallLogs();
                      _fetchRealDeviceContacts();
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 16, color: AppColors.primaryLight),
                        const SizedBox(width: 4),
                        Text(
                          _hasCallLogPermission && _hasContactPermission ? 'Perbarui' : 'Izin Log Telepon',
                          style: GoogleFonts.outfit(
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
            if (_realRecentCalls.isEmpty || !_hasCallLogPermission || !_hasContactPermission)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasContactPermission && _hasCallLogPermission ? Icons.phone_disabled_rounded : Icons.lock_outline_rounded,
                        size: 38,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasContactPermission && _hasCallLogPermission
                            ? 'Belum ada riwayat panggilan kontak nyata.'
                            : 'Izin Akses Kontak & Log Telepon Diperlukan\nKami menghormati privasi Anda dan tidak membaca kontak sampai Anda mengaktifkannya.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                      if (!_hasContactPermission || !_hasCallLogPermission) ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _showContactAccessConsentModal,
                          icon: const Icon(Icons.shield_rounded, size: 16, color: AppColors.primaryLight),
                          label: Text(
                            'Aktifkan Izin Akses',
                            style: GoogleFonts.outfit(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              ..._realRecentCalls.map((item) {
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
                                style: GoogleFonts.outfit(
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
                                    style: GoogleFonts.outfit(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            Text(
                              item['date'] as String,
                              style: GoogleFonts.outfit(
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
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _showAllCallLogsModal,
                icon: Text(
                  'Tampilkan Semuanya ($_callLogFilterTime)',
                  style: GoogleFonts.outfit(
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
            const SizedBox(height: 30),

            // -------------------------------------------------------------
            // 2. TAMPILAN TAG PENGGUNA / TAG SAYA (Struktur Gambar 2 & 3)
            Text(
              'Tag Saya',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            if (_userTags.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Belum ada tag/label khusus untuk nomor Anda.',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._userTags.map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '# $t',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _showAddTagDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E263D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2B8CFF)),
                    ),
                    child: Text(
                      '+ Tambah Tag',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF2B8CFF),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // -------------------------------------------------------------
            // 3. KONTAK CEPAT & DAFTAR ULASAN (REAL DARI KONTAK PERANGKAT)
            // -------------------------------------------------------------
            Text(
              'Kontak Cepat',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            if (_realQuickContacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _hasContactPermission
                        ? 'Tidak ada kontak untuk ditampilkan.'
                        : 'Hubungkan kontak perangkat untuk melihat Kontak Cepat asli.',
                    style: GoogleFonts.outfit(
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
                      (t) => TagChipCard(
                        tag: t,
                        onVote: (type) => _handleVote(t, type),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: _contacts.isNotEmpty
                    ? _showAllContactsModal
                    : _requestContactPermission,
                icon: Text(
                  _contacts.isNotEmpty
                      ? 'Tampilkan Semua (${_contacts.length} Orang)'
                      : 'Tampilkan Semua',
                  style: GoogleFonts.outfit(
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
            const SizedBox(height: 32),

            // -------------------------------------------------------------
            // 4. MEMUNCULKAN DAFTAR ORANG YANG MENCARI NOMOR PENGGUNA (Gambar 4 & 5)
            // -------------------------------------------------------------
            Material(
              color: const Color(0xFF141926),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: _showMyPhoneProtectionModal,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF20273C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _isMyStatsLoading
                                  ? 'Memeriksa status proteksi nomor Anda...'
                                  : (_myPhoneSearchCount > 0
                                      ? '$_myPhoneSearchCount aktivitas pencarian terhadap nomor Anda.'
                                      : 'Nomor Anda dalam pemantauan proteksi aktif.'),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primaryLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
                            child: const Icon(
                              Icons.shield_outlined,
                              color: AppColors.primaryLight,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _myPhoneSearchCount > 0
                                  ? 'Reputasi saat ini: ${_myPhoneTrustScore.toStringAsFixed(0)}% Aman. Tekan di sini untuk melihat analisis detail aktivitas pencarian dan perlindungan privasi PhoneRep Komunitas.'
                                  : 'Belum ada aktivitas pencarian mencurigakan terhadap nomor Anda. Tekan di sini untuk memeriksa status perlindungan & jejak digital Anda.',
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
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

  // =========================================================================
  // TAMPILAN SAAT TOMBOL SEARCH DIPENCET (Persis Gambar ke-5: "Baru Saja Dilihat")
  // =========================================================================
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
                style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  _contacts.isNotEmpty
                      ? 'Belum ada riwayat pencarian.'
                      : 'Belum ada riwayat nomor yang baru saja dilihat.',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
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
                            style: GoogleFonts.outfit(
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
                                style: GoogleFonts.outfit(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['number'] as String,
                                style: GoogleFonts.outfit(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item['date'] as String,
                          style: GoogleFonts.outfit(
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
                  style: GoogleFonts.outfit(
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
                      const Icon(
                        Icons.cell_tower_rounded,
                        color: AppColors.accentCyan,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Operator: ${_phoneRecord!.carrier}',
                        style: GoogleFonts.outfit(
                          color: AppColors.accentCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
                style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
              style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
            'Daftar Ulasan & Reputasi Komunitas',
            style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jadilah yang pertama memberikan label apakah nomor ini kurir, penipu, atau rekan bisnis.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
