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
  bool _isLoading = false;
  String? _errorMessage;
  PhoneRecord? _phoneRecord;
  String? _statusMessage;

  // Riwayat pencarian nyata selama sesi aplikasi
  final List<String> _searchHistory = [];

  // State untuk pengaturan perlindungan
  bool _isDefaultPhoneApp = true;
  bool _isOverlayAllowed = true;

  // State untuk sinkronisasi buku alamat (Contact Pooling)
  bool _isSyncLoading = false;
  bool _hasContactPermission = false;
  List<Contact> _contacts = [];
  SyncContactResult? _lastSyncResult;

  @override
  void initState() {
    super.initState();
    _checkContactPermission();
  }

  Future<void> _checkContactPermission() async {
    final status = await Permission.contacts.status;
    if (mounted) {
      setState(() {
        _hasContactPermission = status.isGranted;
      });
    }
    if (_hasContactPermission) {
      _loadContacts();
    }
  }

  Future<void> _requestContactPermission() async {
    setState(() {
      _isSyncLoading = true;
      _errorMessage = null;
    });

    final status = await Permission.contacts.request();
    if (mounted) {
      setState(() {
        _hasContactPermission = status.isGranted;
        _isSyncLoading = false;
      });
    }

    if (_hasContactPermission) {
      await _loadContacts();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C2234),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Izin Kontak Dibutuhkan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text('Anda telah menolak izin kontak secara permanen. Buka Pengaturan Android untuk mengaktifkan izin kontak demi keamanan dan proteksi bersama.', style: GoogleFonts.outfit(color: AppColors.textSecondary, height: 1.4)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Batal', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Buka Pengaturan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isSyncLoading = true;
      _errorMessage = null;
    });

    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );
        if (mounted) {
          setState(() {
            _contacts = contacts.where((c) => c.phones.isNotEmpty && _getContactName(c) != 'Kontak Komunitas').toList();
            _isSyncLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasContactPermission = false;
            _isSyncLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal membaca kontak: $e';
          _isSyncLoading = false;
        });
      }
    }
  }

  String _getContactName(Contact c) {
    if (c.displayName.trim().isNotEmpty) {
      return c.displayName.trim();
    }
    final fullName = '${c.name.first} ${c.name.middle} ${c.name.last}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return 'Kontak Komunitas';
  }

  Future<void> _performContactSync() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada kontak dengan nomor telepon untuk disinkronkan.')),
      );
      return;
    }

    setState(() {
      _isSyncLoading = true;
      _errorMessage = null;
      _lastSyncResult = null;
    });

    final payload = <Map<String, String>>[];
    for (final c in _contacts) {
      final rawNum = c.phones.first.number;
      payload.add({
        'name': _getContactName(c),
        'phoneNumber': rawNum,
      });
    }

    try {
      final res = await widget.apiService.syncContacts(
        payload,
        userId: 'android_user_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        setState(() {
          _lastSyncResult = res;
          _isSyncLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: AppColors.accentGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isSyncLoading = false;
        });
      }
    }
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
    });

    try {
      final res = await widget.apiService.lookupPhoneNumber(cleanQuery);
      if (mounted) {
        setState(() {
          _phoneRecord = res.data;
          _statusMessage = res.message;
          _isLoading = false;
          if (!_searchHistory.contains(cleanQuery)) {
            _searchHistory.insert(0, cleanQuery);
            if (_searchHistory.length > 10) _searchHistory.removeLast();
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
      backgroundColor: const Color(0xFF1A1F30),
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
                'Bantu komunitas PhoneRep mengenali nomor ini dengan memberikan label profesi, nama, atau peringatan spam.',
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: tagController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Contoh: Kurir Paket / Telemarketing / Penipu APK',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  prefixIcon: const Icon(Icons.label_outline_rounded, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFF232A40),
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
                    'SIMPAN TAG KOMUNITAS',
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
      backgroundColor: const Color(0xFF0B0F19), // Latar belakang gelap premium menyatu
      body: SafeArea(
        child: Column(
          children: [
            // TOP HEADER & SEARCH BAR ELEGAN (Menyatu dengan latar belakang, tidak ada kotak strip aneh atau kotak double)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              color: Colors.transparent, // Menyatu total dengan warna halaman
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'PhoneRep Komunitas',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Proteksi Aktif', style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Kapsul Pencarian Tunggal Super Rapih (Tanpa double border & tanpa double latar)
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171D2D), // Warna permukaan gelap mewah
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xFF262F48), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: AppColors.primaryLight, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: 'Cari nomor telepon (+62 / 08xxx)...',
                              hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
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
                            onTap: () {
                              _searchController.clear();
                              setState(() => _phoneRecord = null);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Color(0xFF262F48), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                            ),
                          )
                        else
                          InkWell(
                            onTap: () {
                              if (_searchController.text.isNotEmpty) {
                                _performSearch(_searchController.text);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_forward_rounded, color: AppColors.primaryLight, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
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
                margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusMessage!, style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 13))),
                  ],
                ),
              ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                  : _phoneRecord == null
                      ? _buildProfessionalOnePageDashboard()
                      : _buildRealSearchResultStructure(),
            ),
          ],
        ),
      ),
    );
  }

  // HALAMAN BERANDA TERPADU DENGAN DESAIN EKSEKUTIF & PROFESIONAL
  Widget _buildProfessionalOnePageDashboard() {
    return RefreshIndicator(
      color: AppColors.primaryLight,
      backgroundColor: const Color(0xFF171D2D),
      onRefresh: () async {
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------------------------------------------------------------
            // SECTION 1: KARTU DASHBOARD KEAMANAN & STATUS PROTEKSI
            // -------------------------------------------------------------
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF181F33), Color(0xFF131826)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF262F48)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Proteksi Spam Komunitas Aktif',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sistem mendeteksi panggilan spam & mencocokkan operator berstandar internasional E.164.',
                              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2338),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2A3452)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBadgeStat('Cari & Tag', 'Siap Digunakan'),
                        Container(width: 1, height: 26, color: const Color(0xFF2A3452)),
                        _buildBadgeStat('Kkoneksi Server', 'Online'),
                        Container(width: 1, height: 26, color: const Color(0xFF2A3452)),
                        _buildBadgeStat('Standar Nomor', 'E.164 Valid'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // -------------------------------------------------------------
            // SECTION 2: RIWAYAT PENCARIAN PENGGUNA
            // -------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Riwayat Pencarian Anda',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                if (_searchHistory.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _searchHistory.clear()),
                    child: Text(
                      'Hapus Semua',
                      style: GoogleFonts.outfit(color: AppColors.accentRed, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_searchHistory.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF141926),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF20273C)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.history_rounded, color: Colors.white.withValues(alpha: 0.4), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Belum Ada Riwayat Pencarian',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ketik nomor telepon di kolom atas untuk melihat reputasi & tag komunitas.',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141926),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF20273C)),
                ),
                child: Column(
                  children: _searchHistory.asMap().entries.map((entry) {
                    final index = entry.key;
                    final numStr = entry.value;
                    final isLast = index == _searchHistory.length - 1;
                    return InkWell(
                      onTap: () {
                        _searchController.text = numStr;
                        _performSearch(numStr);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          border: !isLast ? const Border(bottom: BorderSide(color: Color(0xFF20273C), width: 1)) : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.phone_outlined, color: AppColors.primaryLight, size: 18),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      numStr,
                                      style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                    Text(
                                      'Pencarian Nomor Telepon',
                                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 26),

            // -------------------------------------------------------------
            // SECTION 3: PENGATURAN PERISAI (PREMIUM DARK GLASS STYLE)
            // -------------------------------------------------------------
            Text(
              'Pengaturan Perisai Panggilan',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            _buildProfessionalToggleCard(
              icon: Icons.phone_callback_rounded,
              title: 'Atur Sebagai Aplikasi Telepon Default',
              subtitle: 'Mengidentifikasi setiap nomor telepon masuk dan memblokir panggilan spam secara real-time.',
              value: _isDefaultPhoneApp,
              onChanged: (v) => setState(() => _isDefaultPhoneApp = v),
            ),
            const SizedBox(height: 12),
            _buildProfessionalToggleCard(
              icon: Icons.layers_rounded,
              title: 'Munculkan ID Penelepon Otomatis',
              subtitle: 'Kartu ringkasan reputasi nomor akan melayang secara otomatis saat panggilan berlangsung.',
              value: _isOverlayAllowed,
              onChanged: (v) => setState(() => _isOverlayAllowed = v),
            ),
            const SizedBox(height: 26),

            // -------------------------------------------------------------
            // SECTION 4: KONTRIBUSI BUKU ALAMAT (CONTACT POOLING)
            // -------------------------------------------------------------
            Text(
              'Sinkronisasi Buku Alamat (Pooling)',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF141926),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _lastSyncResult != null ? const Color(0xFF10B981).withValues(alpha: 0.6) : const Color(0xFF20273C),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_lastSyncResult != null ? const Color(0xFF10B981) : AppColors.primary).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _lastSyncResult != null ? Icons.cloud_done_rounded : Icons.sync_rounded,
                          color: _lastSyncResult != null ? const Color(0xFF10B981) : AppColors.primaryLight,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kontribusi Buku Alamat',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _lastSyncResult != null
                                  ? '✔ Tersinkronisasi (+${_lastSyncResult!.syncedCount} kontak)'
                                  : '${_contacts.length} Nomor terdeteksi di perangkat ini',
                              style: GoogleFonts.outfit(
                                color: _lastSyncResult != null ? const Color(0xFF10B981) : AppColors.accentCyan,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _hasContactPermission ? _loadContacts : _requestContactPermission,
                        icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Sinkronisasi buku alamat membantu seluruh pengguna mengenali nomor kurir, penipu, atau kerabat tanpa membagikan riwayat pribadi Anda ke publik.',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSyncLoading ? null : (_contacts.isEmpty ? _requestContactPermission : _performContactSync),
                      icon: _isSyncLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_rounded, size: 20),
                      label: Text(
                        _isSyncLoading
                            ? 'MENGHUBUNGKAN KE SERVER...'
                            : (_contacts.isEmpty ? 'BERI IZIN BUKU ALAMAT' : 'SINKRONISASI KONTAK SEKARANG'),
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _lastSyncResult != null ? const Color(0xFF10B981) : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // -------------------------------------------------------------
            // SECTION 5: REFERENSI TAG & TIPS KOMUNITAS
            // -------------------------------------------------------------
            Text(
              'Referensi Tag & Reputasi',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
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
                    'Contoh label tag komunitas yang dapat membantu identifikasi nomor telepon:',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildProfessionalTagChip('Nomor Terverifikasi', false),
                      _buildProfessionalTagChip('Kurir Paket', false),
                      _buildProfessionalTagChip('Layanan Pelanggan', false),
                      _buildProfessionalTagChip('Spam / Penipuan', true),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2338),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.accentCyan, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Saat menerima panggilan tidak dikenal, periksa skor reputasi dan ulasan tag di PhoneRep sebelum Anda menelepon kembali.',
                            style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.outfit(color: AppColors.accentCyan, fontSize: 13.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildProfessionalToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141926),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF20273C)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF2E3450),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalTagChip(String text, bool isAlert) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isAlert ? const Color(0xFFEF4444).withValues(alpha: 0.18) : const Color(0xFF1E263D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isAlert ? const Color(0xFFEF4444).withValues(alpha: 0.5) : const Color(0xFF2C3756)),
      ),
      child: Text(
        '# $text',
        style: GoogleFonts.outfit(
          color: isAlert ? const Color(0xFFEF4444) : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Tampilan Hasil Pencarian Nyata
  Widget _buildRealSearchResultStructure() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF181F33), Color(0xFF141926)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF262F48)),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.cell_tower_rounded, color: AppColors.accentCyan, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Operator: ${_phoneRecord!.carrier}',
                        style: GoogleFonts.outfit(color: AppColors.accentCyan, fontSize: 13.5, fontWeight: FontWeight.w600),
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
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              InkWell(
                onTap: _showAddTagDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
