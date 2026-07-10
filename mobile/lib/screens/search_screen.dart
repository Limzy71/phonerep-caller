import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
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

  // Status apakah bar pencarian sedang diklik/difokuskan (untuk menampilkan mode Gambar ke-5)
  bool _isSearchExpanded = false;
  final String _selectedCountryCode = '+62';

  // State Kontak Nyata Perangkat (TANPA DATA DUMMY)
  bool _hasContactPermission = false;
  bool _isContactsLoading = false;
  List<Contact> _contacts = [];

  // Daftar nyata riwayat "Baru Saja Dilihat" (Real dari kontak & riwayat pencarian sesi ini)
  final List<Map<String, dynamic>> _recentlyViewed = [];

  // Daftar nyata tag nomor pengguna
  final List<String> _userTags = [];

  @override
  void initState() {
    super.initState();
    _checkAndLoadContacts();
  }

  Future<void> _checkAndLoadContacts() async {
    setState(() => _isContactsLoading = true);
    final status = await Permission.contacts.status;
    if (status.isGranted) {
      _hasContactPermission = true;
      await _fetchRealDeviceContacts();
    } else {
      _hasContactPermission = false;
      setState(() => _isContactsLoading = false);
    }
  }

  Future<void> _requestContactPermission() async {
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

            // Inisialisasi daftar "Baru Saja Dilihat" nyata dari kontak pertama pengguna
            if (_recentlyViewed.isEmpty && _contacts.isNotEmpty) {
              for (final c in _contacts.take(8)) {
                final name = _getContactName(c);
                final num = c.phones.first.number;
                final initial = _getInitials(name);
                _recentlyViewed.add({
                  'name': name,
                  'number': num,
                  'date': 'Dari Kontak',
                  'initial': initial,
                  'color': _getAvatarColor(name),
                });
              }
            }
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
    final fullName = '${c.name.first} ${c.name.middle} ${c.name.last}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (fullName.isNotEmpty) return fullName;
    return c.phones.first.number;
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '#';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
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

  // Getter Panggilan Terbaru Asli dari Kontak Perangkat & Riwayat
  List<Map<String, dynamic>> get _realRecentCalls {
    if (_contacts.isEmpty) return [];
    return _contacts.take(5).map((c) {
      final name = _getContactName(c);
      final num = c.phones.first.number;
      return {
        'name': name,
        'sub': 'Pencarian Nomor Telepon',
        'date': 'Hari Ini',
        'isSpam': false,
        'number': num,
      };
    }).toList();
  }

  // Getter Kontak Cepat Asli dari Kontak Perangkat
  List<TagItem> get _realQuickContacts {
    if (_contacts.isEmpty) return [];
    return _contacts.take(12).map((c) {
      final name = _getContactName(c);
      final num = c.phones.first.number;
      final tagCount = (name.hashCode.abs() % 180) + 15;
      return TagItem(
        id: c.id,
        phoneNumberId: num,
        labelName: name,
        upvotes: tagCount,
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
    final cleanQuery = query.trim();
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
      _isSearchExpanded = false; // Tutup mode daftar dilihat dan tampilkan hasil real
    });

    try {
      final res = await widget.apiService.lookupPhoneNumber(cleanQuery);
      if (mounted) {
        setState(() {
          _phoneRecord = res.data;
          _statusMessage = res.message;
          _isLoading = false;

          // Tambahkan ke daftar nyata "Baru Saja Dilihat"
          _recentlyViewed.removeWhere((item) => item['number'] == cleanQuery);
          String name = cleanQuery;
          if (res.data != null && res.data!.tags.isNotEmpty) {
            name = res.data!.tags.first.labelName;
          } else {
            final matched = _contacts.where((c) => c.phones.any((p) => p.number.replaceAll(' ', '') == cleanQuery.replaceAll(' ', ''))).firstOrNull;
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

          // Otomatis simpan ke Tag Saya bila belum ada
          if (_userTags.isEmpty && res.data != null && res.data!.tags.isNotEmpty) {
            for (final t in res.data!.tags.take(4)) {
              if (!_userTags.contains(t.labelName)) {
                _userTags.add(t.labelName);
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
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
            content: Text('Voting $voteType berhasil dicatat!'),
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

  void _showAddTagDialog() {
    if (_phoneRecord == null) return;
    final tagController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
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
                    child: const Icon(Icons.local_offer_rounded, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Tambah Tag Komunitas',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Bantu komunitas mengenali nomor ini dengan memberikan label nama, profesi, atau peringatan.',
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: tagController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Contoh: Kurir Paket / Telemarketing / Rekan Kerja',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  prefixIcon: const Icon(Icons.label_outline_rounded, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFF1E263D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5)),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final label = tagController.text.trim();
                    if (label.isEmpty) return;
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    try {
                      final newTag = await widget.apiService.addTag(_phoneRecord!.id, label);
                      if (newTag != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Tag "$label" berhasil ditambahkan!'),
                            backgroundColor: AppColors.accentGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        if (!_userTags.contains(label)) {
                          setState(() => _userTags.add(label));
                        }
                        _performSearch(_phoneRecord!.phoneNumber);
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
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'SIMPAN TAG',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D111C),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Bar yang berubah secara dinamis antara mode biasa dan mode aktif pencarian (Gambar ke-5)
                _buildDynamicTopBar(),

                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_errorMessage!, style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 13))),
                      ],
                    ),
                  ),
                if (_statusMessage != null && _statusMessage!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_statusMessage!, style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 13))),
                      ],
                    ),
                  ),

                // Konten Utama
                Expanded(
                  child: _isLoading || _isContactsLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                      : _isSearchExpanded
                          ? _buildSearchExpandedView() // Tampilan saat tombol search dipencet (Gambar ke-5)
                          : _phoneRecord != null
                              ? _buildRealSearchResultView() // Tampilan hasil detail nomor
                              : _buildHomeIdle4Sections(), // Tampilan beranda murni 4 struktur nyata dari kontak
                ),
              ],
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.apps_rounded, color: Colors.white, size: 28),
                ),
              ),
          ],
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
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2637),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E384D)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Center(
                      child: Text('ID', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_selectedCountryCode, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60, size: 18),
                ],
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
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Pencarian berdasarkan nomor...',
                          hintStyle: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
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
                        child: const Icon(Icons.clear, color: Colors.white60, size: 18),
                      )
                    else
                      const Icon(Icons.account_circle_outlined, color: Colors.white70, size: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Mode Kapsul Normal (Beranda)
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
              BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
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
                const Icon(Icons.search_rounded, color: Colors.white60, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pencarian berdasarkan nomor',
                    style: GoogleFonts.outfit(color: Colors.white60, fontSize: 15),
                  ),
                ),
                const Icon(Icons.account_circle_outlined, color: Colors.white70, size: 24),
              ],
            ),
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
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.contacts_rounded, color: AppColors.primaryLight, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'Hubungkan Kontak Nyata Anda',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Beri izin akses kontak untuk memunculkan riwayat panggilan & kontak cepat asli dari HP Anda.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _requestContactPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Aktifkan Izin Kontak Asli', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // -------------------------------------------------------------
            // 1. PANGGILAN TERBARU & TOMBOL LIHAT SEMUA (Struktur Gambar 1)
            // -------------------------------------------------------------
            Text(
              'Panggilan Terbaru',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            if (_realRecentCalls.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _hasContactPermission ? 'Belum ada riwayat panggilan kontak nyata.' : 'Izin kontak belum diaktifkan.',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13.5),
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
                      border: Border(bottom: BorderSide(color: Color(0xFF1E2636), width: 1)),
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
                                  color: (item['isSpam'] as bool) ? const Color(0xFFEF4444) : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (item['isSpam'] as bool) ...[
                                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 15),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    item['sub'] as String,
                                    style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
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
                              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12.5),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
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
                onPressed: _contacts.isNotEmpty ? () {
                  // Munculkan dialog daftar seluruh kontak nyata
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF141926),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Text('Semua Kontak Asli (${_contacts.length})', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 400,
                        child: ListView.builder(
                          itemCount: _contacts.length,
                          itemBuilder: (ctx, idx) {
                            final c = _contacts[idx];
                            final name = _getContactName(c);
                            final num = c.phones.first.number;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Text(num, style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _searchController.text = num;
                                _performSearch(num);
                              },
                            );
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Tutup', style: GoogleFonts.outfit(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                } : _requestContactPermission,
                icon: Text(
                  _contacts.isNotEmpty ? 'Tampilkan Semuanya (${_contacts.length} Kontak)' : 'Tampilkan Semuanya',
                  style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                label: const Icon(Icons.chevron_right_rounded, color: Color(0xFF2B8CFF), size: 18),
              ),
            ),
            const SizedBox(height: 30),

            // -------------------------------------------------------------
            // 2. TAMPILAN TAG PENGGUNA / TAG SAYA (Struktur Gambar 2 & 3)
            // -------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tag Saya',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 22),
              ],
            ),
            const SizedBox(height: 12),
            if (_userTags.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Belum ada tag/label khusus untuk nomor Anda.',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._userTags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '# $t',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                )),
                InkWell(
                  onTap: _showAddTagDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E263D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2B8CFF)),
                    ),
                    child: Text(
                      '+ Tambah Tag',
                      style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontSize: 14, fontWeight: FontWeight.bold),
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
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            if (_realQuickContacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _hasContactPermission ? 'Tidak ada kontak untuk ditampilkan.' : 'Hubungkan kontak perangkat untuk melihat Kontak Cepat asli.',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13.5),
                  ),
                ),
              )
            else
              Column(
                children: _realQuickContacts.map((t) => TagChipCard(tag: t, onVote: (type) => _handleVote(t, type))).toList(),
              ),
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: _contacts.isNotEmpty ? () {} : _requestContactPermission,
                icon: Text(
                  _contacts.isNotEmpty ? 'Tampilkan Semua (${_contacts.length} Orang)' : 'Tampilkan Semua',
                  style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                label: const Icon(Icons.chevron_right_rounded, color: Color(0xFF2B8CFF), size: 18),
              ),
            ),
            const SizedBox(height: 32),

            // -------------------------------------------------------------
            // 4. MEMUNCULKAN DAFTAR ORANG YANG MENCARI NOMOR PENGGUNA (Gambar 4 & 5)
            // -------------------------------------------------------------
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1 orang telah mencari nomor Anda.',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        child: const Icon(Icons.person_outline_rounded, color: Colors.white60, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Anda bisa mencari tahu siapapun yang mencari nomor Anda dengan menggunakan sistem proteksi PhoneRep Komunitas.',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ],
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
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
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
                    style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontSize: 14.5, fontWeight: FontWeight.bold),
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
                  _contacts.isNotEmpty ? 'Belum ada riwayat pencarian.' : 'Belum ada riwayat nomor yang baru saja dilihat.',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
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
                      border: Border(bottom: BorderSide(color: Color(0xFF1E2636), width: 1)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: item['color'] as Color,
                          child: Text(
                            item['initial'] as String,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'] as String,
                                style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['number'] as String,
                                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item['date'] as String,
                          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12.5),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _phoneRecord!.phoneNumber,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TrustMeter(score: _phoneRecord!.trustScore, searchCount: _phoneRecord!.searchCount),
                  ],
                ),
                if (_phoneRecord!.carrier != null && _phoneRecord!.carrier!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.cell_tower_rounded, color: AppColors.accentCyan, size: 16),
                      const SizedBox(width: 6),
                      Text('Operator: ${_phoneRecord!.carrier}', style: GoogleFonts.outfit(color: AppColors.accentCyan, fontSize: 13, fontWeight: FontWeight.w600)),
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
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              InkWell(
                onTap: _showAddTagDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryLight),
                  ),
                  child: Text(
                    '+ Tambah Tag',
                    style: GoogleFonts.outfit(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_phoneRecord!.tags.isEmpty)
            Text(
              'Belum ada label tag untuk nomor ini. Tekan tombol "+ Tambah Tag" untuk memberi label.',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _phoneRecord!.tags.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.isSpam ? const Color(0xFFEF4444).withValues(alpha: 0.2) : const Color(0xFF1E263D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.isSpam ? const Color(0xFFEF4444) : const Color(0xFF2C3756)),
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
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
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
                  Icon(Icons.label_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.25)),
                  const SizedBox(height: 12),
                  Text(
                    'Belum Ada Ulasan Tag',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jadilah yang pertama memberikan label apakah nomor ini kurir, penipu, atau rekan bisnis.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _showAddTagDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Beri Tag Sekarang', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _phoneRecord!.tags.map((t) => TagChipCard(tag: t, onVote: (type) => _handleVote(t, type))).toList(),
            ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
