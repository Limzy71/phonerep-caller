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

  // Riwayat pencarian nyata selama sesi
  final List<String> _searchHistory = [];

  // State untuk pengaturan perlindungan di halaman Beranda
  bool _isDefaultPhoneApp = true;
  bool _isOverlayAllowed = true;

  // State untuk sinkronisasi buku alamat (Contact Pooling) di halaman Beranda
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
            backgroundColor: const Color(0xFF1F2637),
            title: Text('Izin Kontak Dibutuhkan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text('Anda telah menolak izin kontak secara permanen. Buka Pengaturan Android untuk mengaktifkan izin kontak demi memperkuat proteksi bersama.', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
                child: Text('Buka Pengaturan', style: GoogleFonts.outfit(color: Colors.white)),
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
      backgroundColor: const Color(0xFF131824),
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
              const SizedBox(height: 16),
              Text(
                'Bantu komunitas PhoneRep mengenali nomor ini dengan memberikan label nama, penipu, atau profesi asli.',
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Contoh: Kurir Paket / Telemarketing / Penipu APK',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  prefixIcon: const Icon(Icons.label, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFF1F2637),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
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
                          ),
                        );
                      }
                      setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      backgroundColor: const Color(0xFF0F131D),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar Pencarian berstruktur kapsul
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: const Color(0xFF131824),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2637),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF2E384D), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: Colors.white60, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Pencarian berdasarkan nomor (+62 / 08xxx)...',
                                hintStyle: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
                                border: InputBorder.none,
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
                              child: const Icon(Icons.clear, color: Colors.white60, size: 20),
                            )
                          else
                            InkWell(
                              onTap: () {
                                if (_searchController.text.isNotEmpty) {
                                  _performSearch(_searchController.text);
                                }
                              },
                              child: const Icon(Icons.arrow_forward_rounded, color: AppColors.primaryLight, size: 22),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
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
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
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
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)))
                  : _phoneRecord == null
                      ? _buildUnifiedOnePageDashboard()
                      : _buildRealSearchResultStructure(),
            ),
          ],
        ),
      ),
    );
  }

  // SATU HALAMAN TERPADU YANG MEMUAT KE-5 STRUKTUR (Gambar 1 sampai Gambar 5) DALAM 1 ALUR SCROLL
  Widget _buildUnifiedOnePageDashboard() {
    return RefreshIndicator(
      color: const Color(0xFF007AFF),
      backgroundColor: const Color(0xFF1F2637),
      onRefresh: () async {
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------------------------------------------------------------
            // STRUKTUR 1: Panggil / Pencarian Terbaru (Gambar 1)
            // -------------------------------------------------------------
            Text(
              'Riwayat Pencarian Terbaru',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            if (_searchHistory.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF131824),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF1E2636)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.history_rounded, size: 36, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 8),
                    Text(
                      'Belum Ada Riwayat Pencarian',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Coba ketik nomor di atas untuk melihat operator, reputasi spam, dan tag komunitas.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _searchHistory.map((numStr) {
                  return InkWell(
                    onTap: () {
                      _searchController.text = numStr;
                      _performSearch(numStr);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFF1E2636), width: 1)),
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
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                  Text(
                                    'Pencarian Nomor Telepon',
                                    style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 28),

            // -------------------------------------------------------------
            // STRUKTUR 2: Perlindungan dan Keamanan (Gambar 1 & Gambar 2)
            // -------------------------------------------------------------
            Text(
              'Perlindungan dan Keamanan',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 14),
            
            // Gauge Meter Perlindungan (Dari struktur Gambar 1)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF1E2636)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 110,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 90,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFF10B981), width: 14),
                              left: BorderSide(color: Color(0xFF10B981), width: 14),
                              right: BorderSide(color: Color(0xFF334155), width: 14),
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(90),
                              topRight: Radius.circular(90),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              'STATUS PROTEKSI',
                              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            Text(
                              'Aktif & Aman',
                              style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sistem identifikasi dan proteksi dari panggilan spam atau nomor berbahaya aktif bekerja di perangkat Anda.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Toggle Pengaturan Perisai (Dari struktur Gambar 2)
            _buildBlueToggleCard(
              title: 'Selalu ketahui siapa yang menelepon Anda.',
              subtitle: 'Atur PhoneRep sebagai aplikasi telepon default sehingga sistem dapat mengidentifikasi panggilan masuk untuk melindungi Anda dari panggilan spam.',
              value: _isDefaultPhoneApp,
              onChanged: (v) => setState(() => _isDefaultPhoneApp = v),
            ),
            const SizedBox(height: 14),
            _buildBlueToggleCard(
              title: 'Izinkan untuk ditampilkan pada layar',
              subtitle: 'Saat nomor tidak dikenal menelepon, kartu reputasi penelepon akan muncul di layar Anda secara otomatis.',
              value: _isOverlayAllowed,
              onChanged: (v) => setState(() => _isOverlayAllowed = v),
            ),
            const SizedBox(height: 14),

            // Kartu Sinkronisasi Buku Alamat (Pooling) nyata
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _lastSyncResult != null ? AppColors.accentGreen.withValues(alpha: 0.6) : const Color(0xFF2E384D),
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
                          color: (_lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF007AFF)).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _lastSyncResult != null ? Icons.cloud_done_rounded : Icons.sync_rounded,
                          color: _lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF2B8CFF),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sinkronisasi Buku Alamat (Pooling)',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _lastSyncResult != null
                                  ? '✔ Tersinkronisasi (+${_lastSyncResult!.syncedCount} nomor)'
                                  : '${_contacts.length} Nomor terdeteksi di perangkat ini',
                              style: GoogleFonts.outfit(
                                color: _lastSyncResult != null ? AppColors.accentGreen : AppColors.accentCyan,
                                fontSize: 13,
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
                    'Dengan menyinkronkan buku alamat, Anda membantu seluruh pengguna mengenali nomor kurir, penipu, dan nomor penting tanpa membeberkan riwayat pribadi Anda.',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSyncLoading ? null : (_contacts.isEmpty ? _requestContactPermission : _performContactSync),
                      icon: _isSyncLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_rounded, size: 20),
                      label: Text(
                        _isSyncLoading
                            ? 'MENGHUBUNGKAN...'
                            : (_contacts.isEmpty ? 'BERI IZIN BUKU ALAMAT' : 'SINKRONISASI SEKARANG'),
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF007AFF),
                        foregroundColor: _lastSyncResult != null ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // -------------------------------------------------------------
            // STRUKTUR 3: Tag Saya & Rekomendasi (Gambar 3)
            // -------------------------------------------------------------
            Text(
              'Tag & Label Komunitas',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1E2636)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tag yang Anda kontribusikan atau cari akan muncul sebagai label referensi:',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTagPill('Nomor Terverifikasi'),
                      _buildTagPill('Kurir Resmi'),
                      _buildTagPill('Layanan Pelanggan'),
                      _buildTagPill('Rekan Komunitas'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Rekomendasi Perlindungan (Dari struktur Gambar 3)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF004085),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D253F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                        const SizedBox(width: 6),
                        Text('Direkomendasikan', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Perlindungan Identitas Panggilan',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saat menelepon kembali nomor yang tidak dikenal, selalu periksa reputasi skor dan ulasan tag di aplikasi terlebih dahulu.',
                    style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // -------------------------------------------------------------
            // STRUKTUR 4: Kontak Cepat / Daftar Ulasan (Gambar 4)
            // -------------------------------------------------------------
            Text(
              'Kontak & Tag Terpopuler Komunitas',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1E2636)),
              ),
              child: Column(
                children: [
                  Icon(Icons.groups_rounded, size: 42, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 10),
                  Text(
                    'Cari Nomor Untuk Melihat Daftar Ulasan',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Setiap nomor yang dicari akan menampilkan struktur avatar lingkaran, label nama, dan badge jumlah reputasi (# upvote) secara lengkap.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // -------------------------------------------------------------
            // STRUKTUR 5: Info Pencarian / Status Panggilan (Gambar 5)
            // -------------------------------------------------------------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E2636)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: const Icon(Icons.security_rounded, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sistem Proteksi Komunitas Aktif',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Identitas dan buku alamat Anda dilindungi dengan normalisasi E.164 berstandar tinggi.',
                          style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildTagPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '# $text',
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBlueToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2B8CFF),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B8CFF).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF0F172A),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF1E293B),
          ),
        ],
      ),
    );
  }

  // Tampilan Hasil Pencarian Nyata
  Widget _buildRealSearchResultStructure() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF131824),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E2636)),
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
                    color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF007AFF)),
                  ),
                  child: Text(
                    '+ Tambah Tag',
                    style: GoogleFonts.outfit(color: const Color(0xFF2B8CFF), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                    color: t.isSpam ? const Color(0xFFEF4444).withValues(alpha: 0.2) : const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(10),
                    border: t.isSpam ? Border.all(color: const Color(0xFFEF4444)) : null,
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
          const SizedBox(height: 12),
          if (_phoneRecord!.tags.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF131824),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1E2636)),
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
                    'Jadilah yang pertama memberikan label apakah nomor ini penipu, kurir, atau rekan bisnis.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _showAddTagDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Beri Tag Sekarang', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
