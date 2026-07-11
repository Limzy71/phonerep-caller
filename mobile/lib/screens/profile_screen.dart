import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService apiService;

  const ProfileScreen({super.key, required this.apiService});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = 'Pengguna PhoneRep';
  String _userPhone = '+62...';
  List<String> _userTags = [];
  String? _userPhotoPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_my_name') ?? 'Pengguna PhoneRep';
        _userPhone = prefs.getString('user_my_phone') ?? 'Belum Diatur';
        _userTags = prefs.getStringList('user_my_tags') ?? [];
        _userPhotoPath = prefs.getString('user_my_photo');
        _isLoading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_my_photo', pickedFile.path);
        if (mounted) {
          setState(() {
            _userPhotoPath = pickedFile.path;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
    }
  }

  void _showPhotoOptionsModal() {
    final hasPhoto = _userPhotoPath != null && File(_userPhotoPath!).existsSync();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kelola Foto Profil',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primaryLight),
                ),
                title: Text('Pilih dari Galeri', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto();
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444)),
                  ),
                  title: Text('Hapus Foto Profil', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_my_photo');
                    if (mounted) {
                      setState(() {
                        _userPhotoPath = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Foto profil dihapus. Avatar kembali ke default huruf awal.'),
                          backgroundColor: AppColors.accentGreen,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _userName);
    final phoneCtrl = TextEditingController(text: _userPhone);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Edit Profil Saya',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nama Lengkap Anda', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Contoh: Budi Santoso',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF131824),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Nomor Telepon Aktif', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Contoh: 081234567890',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF131824),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                final newPhone = phoneCtrl.text.trim();
                if (newName.isNotEmpty && newPhone.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_my_name', newName);
                  await prefs.setString('user_my_phone', newPhone);

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);

                  if (mounted) {
                    setState(() {
                      _userName = newName;
                      _userPhone = newPhone;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Profil Anda berhasil diperbarui.'),
                        backgroundColor: AppColors.accentGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Simpan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profil Saya',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(Icons.edit_rounded, color: AppColors.primaryLight),
                    tooltip: 'Edit Profil',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Profile Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E273A), Color(0xFF131824)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showPhotoOptionsModal,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF2B8CFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _userPhotoPath != null &&
                                      File(_userPhotoPath!).existsSync()
                                  ? Image.file(
                                      File(_userPhotoPath!),
                                      fit: BoxFit.cover,
                                      width: 72,
                                      height: 72,
                                    )
                                  : Center(
                                      child: Text(
                                        _getInitials(_userName),
                                        style: GoogleFonts.outfit(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF1E273A), width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _userName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, color: AppColors.primaryLight, size: 20),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userPhone,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accentGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.shield_rounded, color: AppColors.accentGreen, size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Akun Terverifikasi',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.accentGreen,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Statistik Komunitas
              Text(
                'Statistik Keamanan Nomor',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Reputasi Nomor',
                      'Terverifikasi',
                      Icons.task_alt_rounded,
                      AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildStatCard(
                      'Perlindungan',
                      '24 Jam Aktif',
                      Icons.security_rounded,
                      AppColors.accentGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Daftar Tag Saya di Profil
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daftar Tag Saya',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${_userTags.length} Label',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_userTags.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Belum ada tag khusus untuk nomor Anda. Anda dapat menambahkannya melalui Beranda di bagian Tag Saya.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _userTags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E263D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tag_rounded, color: AppColors.primaryLight, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          tag,
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              const SizedBox(height: 28),

              // Menu Pengaturan Server & Statistik
              Text(
                'Pengaturan & Sistem',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnalyticsScreen(apiService: widget.apiService),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: AppColors.trustWarningGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.dns_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statistik & Koneksi Server',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Kelola IP Backend (${widget.apiService.baseUrl}) & data sistem',
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
