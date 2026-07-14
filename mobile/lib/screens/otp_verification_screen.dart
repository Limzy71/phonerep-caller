import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'home_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final ApiService apiService;
  final String name;
  final String phone;
  final String? photoPath;

  const OtpVerificationScreen({
    super.key,
    required this.apiService,
    required this.name,
    required this.phone,
    this.photoPath,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _secondsRemaining = 60;
  Timer? _timer;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _otpController.addListener(_onOtpChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      widget.apiService.sendOtp(widget.phone);
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _onOtpChanged() {
    if (mounted) {
      if (_errorMessage != null && _otpController.text.isNotEmpty) {
        setState(() {
          _errorMessage = null;
        });
      }
      if (_otpController.text.length == 6 && !_isLoading) {
        _verifyAndProceed();
      }
    }
  }

  void _resendCode() {
    if (_secondsRemaining == 0) {
      _startTimer();
      widget.apiService.sendOtp(widget.phone);
      AppToast.show(
        context,
        message: 'Kode OTP baru berhasil dikirim ulang.',
        type: ToastType.success,
      );
    }
  }

  Future<void> _verifyAndProceed() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() {
        _errorMessage = 'Silakan masukkan 6 digit kode OTP.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final verifyRes = await widget.apiService.verifyOtp(widget.phone, code);
    if (verifyRes['success'] != true) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = verifyRes['message']?.toString() ?? 'Kode OTP salah. Silakan periksa kembali pesan WhatsApp Anda.';
          _otpController.value = const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          );
        });
        _focusNode.unfocus();
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) _focusNode.requestFocus();
        });
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_my_name', widget.name);
      await prefs.setString('user_my_phone', widget.phone);
      if (widget.photoPath != null && widget.photoPath!.isNotEmpty) {
        await prefs.setString('user_my_photo', widget.photoPath!);
      }

      final List<String> currentTags = prefs.getStringList('user_my_tags') ?? [];
      if (!currentTags.contains(widget.name)) {
        currentTags.add(widget.name);
        await prefs.setStringList('user_my_tags', currentTags);
      }

      try {
        final lookupRes = await widget.apiService.lookupPhoneNumber(widget.phone, skipIncrement: true);
        String phoneId = '';
        if (lookupRes.found && lookupRes.data != null) {
          phoneId = lookupRes.data!.id;
        } else {
          await widget.apiService.syncContacts([
            {'name': widget.name, 'phoneNumber': widget.phone}
          ]);
          final lookupAfter = await widget.apiService.lookupPhoneNumber(widget.phone, skipIncrement: true);
          if (lookupAfter.found && lookupAfter.data != null) {
            phoneId = lookupAfter.data!.id;
          }
        }
        if (phoneId.isNotEmpty) {
          await widget.apiService.addTag(phoneId, widget.name);
        }
      } catch (e) {
        debugPrint('Backend sync info: $e');
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              apiService: widget.apiService,
              showSuccessBanner: true,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Terjadi kesalahan saat menyimpan profil: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.removeListener(_onOtpChanged);
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildDigitBox(int index) {
    final text = _otpController.text;
    final bool hasChar = index < text.length;
    final bool isActive = index == text.length || (index == 5 && text.length == 6);

    return GestureDetector(
      onTap: () {
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) _focusNode.requestFocus();
          });
        } else {
          _focusNode.requestFocus();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasChar
              ? const Color(0xFF131C32)
              : (isActive ? const Color(0xFF0F172A) : const Color(0xFF0B111F)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _errorMessage != null
                ? Colors.redAccent
                : (isActive
                    ? AppColors.primaryLight
                    : (hasChar ? AppColors.primary.withValues(alpha: 0.6) : const Color(0xFF1E293B))),
            width: isActive || hasChar ? 2.0 : 1.2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primaryLight.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          hasChar ? text[index] : '',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon Security Badge
                Container(
                  width: 90,
                  height: 90,
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
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 26,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2.5),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF101624),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mark_email_read_rounded,
                        size: 44,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Verifikasi Keamanan OTP',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Kami telah mengirimkan 6 digit kode keamanan via ',
                      ),
                      TextSpan(
                        text: 'WhatsApp',
                        style: GoogleFonts.outfit(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' ke nomor telepon Anda:\n\n'),
                      TextSpan(
                        text: widget.phone,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit_rounded, size: 14, color: AppColors.primaryLight),
                  label: Text(
                    'Ganti Nomor Telepon',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Invisible TextField handling real keyboard input (placed off-screen and disabled selection to prevent OS cursor handles)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _otpController,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          showCursor: false,
                          enableInteractiveSelection: false, // 💡 Matikan selection handle / titik kursor OS
                          style: const TextStyle(color: Colors.transparent),
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    // Visual 6 digit boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) => _buildDigitBox(index)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Security Trust Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_rounded, color: AppColors.accentGreen, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Keamanan Terjamin: Kode OTP dikirim melalui WhatsApp resmi. Jangan bagikan kode kepada siapa pun demi keamanan akun.',
                          style: GoogleFonts.outfit(
                            color: AppColors.accentGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyAndProceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.primary.withValues(alpha: 0.5),
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
                            'Verifikasi Sekarang',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Countdown / Resend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _secondsRemaining > 0
                          ? 'Belum menerima kode OTP? Kirim ulang dalam '
                          : 'Belum menerima kode OTP? ',
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (_secondsRemaining > 0)
                      Text(
                        '0:${_secondsRemaining.toString().padLeft(2, '0')}',
                        style: GoogleFonts.outfit(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      )
                    else
                      TextButton(
                        onPressed: _resendCode,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Kirim Ulang Kode OTP',
                          style: GoogleFonts.outfit(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
    );
  }
}
