import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'otp_verification_screen.dart';

class SetupProfileScreen extends StatefulWidget {
  final ApiService apiService;

  const SetupProfileScreen({super.key, required this.apiService});

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _profilePhotoPath;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final text = _nameController.text;
      if (text.isNotEmpty && RegExp(r"^[^a-zA-Z]").hasMatch(text)) {
        _nameController.value = TextEditingValue(
          text: text.replaceFirst(RegExp(r"^[^a-zA-Z]+"), ""),
          selection: const TextSelection.collapsed(offset: 0),
        );
        AppToast.show(context, message: 'Nama harus diawali dengan huruf.', type: ToastType.info);
      }
      if (mounted) setState(() {});
    });

    _phoneController.addListener(() {
      final text = _phoneController.text;
      if (text.isNotEmpty && RegExp(r"^[1-9]").hasMatch(text)) {
        final newText = "0$text";
        _phoneController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    final cleanName = name.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').trim();
    if (cleanName.isEmpty) return '?';
    final parts = cleanName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _profilePhotoPath = pickedFile.path;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _showPhotoOptionsModal() {
    final hasPhoto = _profilePhotoPath != null && File(_profilePhotoPath!).existsSync();
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
                style: GoogleFonts.sora(
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
                title: Text('Pilih dari Galeri', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto();
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
                  title: Text('Hapus Foto Profil', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      setState(() {
                        _profilePhotoPath = null;
                      });
                      AppToast.show(
                        context,
                        message: 'Foto profil dihapus. Avatar kembali ke default huruf awal.',
                        type: ToastType.success,
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

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    String phone = _phoneController.text.trim();
    
    // Sanitasi input nomor telepon untuk menghilangkan spasi dan strip (-)
    phone = phone.replaceAll(RegExp(r'[\s\-]+'), '');

    if (name.isEmpty) {
      AppToast.show(context, message: 'Mohon isi nama lengkap Anda.', type: ToastType.error);
      return;
    }

    // Validasi Nama (Allow-list + Anti-Smash + Anti-Repeat): Harus diawali huruf, 3-30 karakter, maks 4 konsonan berurutan, maks 3 huruf identik berurutan
    final nameRegex = RegExp(
      r"^(?!.*(.)\1{3,})(?!.*[bcdfghjklmnpqrstvwxyz]{5,})(?!.*[\.\']{2,})[a-z][a-z\s\.\']{2,29}$",
      caseSensitive: false,
    );
    if (!nameRegex.hasMatch(name)) {
      AppToast.show(
        context,
        message: 'Format nama tidak sesuai standar. Gunakan nama asli tanpa angka, simbol, atau ketikan acak.',
        type: ToastType.error,
      );
      return;
    }

    if (phone.isEmpty) {
      AppToast.show(context, message: 'Mohon isi nomor telepon aktif Anda.', type: ToastType.error);
      return;
    }

    // Validasi Nomor (Allow-list): Diawali 0 atau +, 8-15 karakter
    final phoneRegex = RegExp(r"^(\+|0)[0-9]{7,14}$");
    if (!phoneRegex.hasMatch(phone)) {
      AppToast.show(
        context,
        message: 'Format nomor telepon tidak sesuai standar. Pastikan diawali 0 atau + dengan panjang 8-15 digit.',
        type: ToastType.error,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    // Simulasi pengiriman kode OTP via WhatsApp/SMS
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            apiService: widget.apiService,
            name: name,
            phone: phone,
            photoPath: _profilePhotoPath,
          ),
        ),
      );

      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scrollController.hasClients &&
        MediaQuery.of(context).viewInsets.bottom == 0 &&
        _scrollController.offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.offset > 0) {
          _scrollController.jumpTo(0);
        }
      });
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B3E), // Deep neon royal blue glow at top
              Color(0xFF0A0D14), // Blends smoothly into App background
              Color(0xFF0A0D14),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  GestureDetector(
                    onTap: _showPhotoOptionsModal,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primaryLight,
                                AppColors.primary,
                                Color(0xFF0D1B3E),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.45),
                                blurRadius: 28,
                                spreadRadius: 0,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF101624),
                            ),
                            child: ClipOval(
                              child: _profilePhotoPath != null &&
                                      File(_profilePhotoPath!).existsSync()
                                  ? Image.file(
                                      File(_profilePhotoPath!),
                                      fit: BoxFit.cover,
                                      width: 104,
                                      height: 104,
                                    )
                                  : Container(
                                      width: 104,
                                      height: 104,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Color(0xFF6C63FF), Color(0xFF2B8CFF)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                        child: Center(
                                          child: Text(
                                            _getInitials(_nameController.text),
                                            style: GoogleFonts.sora(
                                              fontSize: 38,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ),
                            ),
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF0D1B3E),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ketuk untuk memilih foto profil Anda',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.primaryLight.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
                Text(
                  'Profil & Identitas Saya',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Daftarkan identitas resmi dan nomor telepon aktif Anda untuk mengakses sistem perlindungan PhoneRep.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nama Lengkap Anda',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\.\']")),
                          LengthLimitingTextInputFormatter(30),
                        ],
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Contoh: Budi Santoso',
                          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF131824),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Nomor Telepon Aktif',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d\+]')),
                          LengthLimitingTextInputFormatter(15),
                        ],
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Contoh: 081234567890',
                          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.phone_android_rounded,
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF131824),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'SIMPAN & LANJUTKAN',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Data identitas Anda disimpan secara aman di perangkat dan dienkripsi untuk keperluan verifikasi keamanan nomor.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
        ),
      ),
    );
  }
}
