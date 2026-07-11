import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/phone_record.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class PoolingScreen extends StatefulWidget {
  final ApiService apiService;

  const PoolingScreen({super.key, required this.apiService});

  @override
  State<PoolingScreen> createState() => _PoolingScreenState();
}

class _PoolingScreenState extends State<PoolingScreen> {
  bool _isLoading = false;
  bool _hasPermission = false;
  List<Contact> _contacts = [];
  SyncContactResult? _lastSyncResult;
  String? _errorMessage;

  // Toggle states struktur perisai
  bool _isDefaultPhoneApp = true;
  bool _isOverlayAllowed = true;

  @override
  void initState() {
    super.initState();
    widget.apiService.addListener(_onApiServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkPermission();
      }
    });
  }

  void _onApiServiceChanged() {
    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  @override
  void dispose() {
    widget.apiService.removeListener(_onApiServiceChanged);
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.contacts.status;
    setState(() {
      _hasPermission = status.isGranted;
    });
    if (_hasPermission) {
      _loadContacts();
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final status = await Permission.contacts.request();
    setState(() {
      _hasPermission = status.isGranted;
      _isLoading = false;
    });

    if (_hasPermission) {
      await _loadContacts();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBgElevated,
            title: Text('Izin Kontak Dibutuhkan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text('Anda telah menolak izin kontak secara permanen. Buka Pengaturan Android untuk mengaktifkan izin kontak demi keamanan komunitas PhoneRep.', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );
        setState(() {
          _contacts = contacts.where((c) => c.phones.isNotEmpty && _getContactName(c) != 'Kontak Komunitas').toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal membaca kontak: $e';
        _isLoading = false;
      });
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

  Future<void> _performSync() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada kontak dengan nomor telepon untuk disinkronkan.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
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
          _isLoading = false;
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
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F131D),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar struktur kapsul rapi
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
                          const Icon(Icons.shield_outlined, color: AppColors.primaryLight, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Pengaturan Perlindungan & Pooling',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kartu 1: Selalu ketahui siapa yang menelepon Anda
                    _buildBlueToggleCard(
                      title: 'Selalu ketahui siapa yang menelepon Anda.',
                      subtitle: 'Atur PhoneRep sebagai aplikasi telepon default sehingga sistem dapat mengidentifikasi panggilan masuk untuk melindungi Anda dari panggilan spam.',
                      value: _isDefaultPhoneApp,
                      onChanged: (v) => setState(() => _isDefaultPhoneApp = v),
                    ),
                    const SizedBox(height: 14),

                    // Kartu 2: Izinkan untuk ditampilkan pada layar
                    _buildBlueToggleCard(
                      title: 'Izinkan untuk ditampilkan pada layar',
                      subtitle: 'Saat nomor tidak dikenal menelepon, kartu reputasi penelepon akan muncul di layar Anda secara otomatis.',
                      value: _isOverlayAllowed,
                      onChanged: (v) => setState(() => _isOverlayAllowed = v),
                    ),
                    const SizedBox(height: 28),

                    // Bagian Contact Pooling Sekali Klik (Struktur Bersih Tanpa Data Palsu)
                    Text(
                      'Sinkronisasi Buku Alamat Komunitas',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131824),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _lastSyncResult != null
                              ? AppColors.accentGreen.withValues(alpha: 0.6)
                              : const Color(0xFF2E384D),
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
                                  color: (_lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF007AFF))
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _lastSyncResult != null ? Icons.cloud_done_rounded : Icons.sync_rounded,
                                  color: _lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF2B8CFF),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Kontribusi Buku Alamat (Pooling)',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _lastSyncResult != null
                                          ? '✔ Tersinkronisasi (+${_lastSyncResult!.syncedCount} nomor)'
                                          : '${_contacts.length} Nomor terdeteksi di perangkat ini',
                                      style: GoogleFonts.outfit(
                                        color: _lastSyncResult != null ? AppColors.accentGreen : AppColors.accentCyan,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _hasPermission ? _loadContacts : _requestPermission,
                                icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Dengan menyinkronkan buku alamat secara otomatis, Anda berkontribusi memperkuat proteksi PhoneRep untuk mengenali nomor kurir, penipu, dan nomor penting tanpa membeberkan riwayat pribadi Anda.',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: GoogleFonts.outfit(color: AppColors.accentRed, fontSize: 12)),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : (_contacts.isEmpty ? _requestPermission : _performSync),
                              icon: _isLoading
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.cloud_upload_rounded, size: 20),
                              label: Text(
                                _isLoading
                                    ? 'MENGHUBUNGKAN KE SERVER...'
                                    : (_contacts.isEmpty
                                        ? 'BERI IZIN BUKU ALAMAT SEKARANG'
                                        : 'SINKRONISASI ${_contacts.length} KONTAK SEKARANG'),
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _lastSyncResult != null ? AppColors.accentGreen : const Color(0xFF007AFF),
                                foregroundColor: _lastSyncResult != null ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
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
}
