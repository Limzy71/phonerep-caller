import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Tipe notifikasi untuk menentukan gaya visual banner.
enum ToastType { success, error, info }

/// Layanan toast global berbasis [Overlay] yang menampilkan banner melayang
/// di bagian atas layar. Menerapkan logika anti-spam:
/// - Pesan yang sama akan memperpanjang durasi tampil, bukan muncul ulang.
/// - Pesan berbeda akan menggantikan yang sedang aktif secara instan.
class AppToast {
  static OverlayEntry? _activeEntry;
  static _AppToastWidgetState? _activeState;
  static String? _activeMessage;
  static Timer? _cleanupTimer;

  /// Tampilkan sebuah toast. Panggil ini dari mana saja yang memiliki [BuildContext].
  ///
  /// - [message]: Teks yang akan ditampilkan.
  /// - [type]: Gaya visual ([ToastType.success], [ToastType.error], atau [ToastType.info]).
  /// - [duration]: Durasi tampil sebelum otomatis menghilang (default 4 detik).
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.success,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;

    // ─── Anti-Spam: Pesan sama → perpanjang durasi, jangan muncul ulang ───
    if (_activeMessage == message && _activeState != null && _activeEntry != null) {
      _activeState!.extendDuration(duration);
      return;
    }

    // ─── Tutup toast aktif sebelumnya jika pesannya berbeda ───
    _forceRemove();

    if (!context.mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => _AppToastWidget(
        message: message,
        type: type,
        duration: duration,
        onStateReady: (state) {
          _activeState = state;
        },
        onDismiss: () {
          _cleanupTimer?.cancel();
          if (_activeEntry == entry) {
            _activeEntry?.remove();
            _activeEntry = null;
            _activeState = null;
            _activeMessage = null;
          }
        },
      ),
    );

    _activeEntry = entry;
    _activeMessage = message;
    overlay.insert(entry);

    // Backup cleanup timer jika widget tidak ter-dispose dengan benar
    _cleanupTimer = Timer(duration + const Duration(seconds: 2), () {
      if (_activeEntry == entry) {
        _forceRemove();
      }
    });
  }

  static void _forceRemove() {
    _cleanupTimer?.cancel();
    _activeState?.dismiss();
    _activeEntry?.remove();
    _activeEntry = null;
    _activeState = null;
    _activeMessage = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget Internal (tidak diekspos ke luar file)
// ─────────────────────────────────────────────────────────────────────────────

class _AppToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final void Function(_AppToastWidgetState state) onStateReady;
  final VoidCallback onDismiss;

  const _AppToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onStateReady,
    required this.onDismiss,
  });

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
    _scheduleDismiss(widget.duration);

    // Daftarkan state ini ke controller eksternal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onStateReady(this);
    });
  }

  void _scheduleDismiss(Duration after) {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(after, () {
      if (mounted && !_isDismissing) dismiss();
    });
  }

  /// Perpanjang durasi tampil (dipanggil saat pesan yang sama dikirim lagi).
  void extendDuration(Duration extra) {
    if (_isDismissing) return;
    _scheduleDismiss(extra);
  }

  /// Animasikan penutupan lalu panggil [onDismiss].
  void dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
    if (!_controller.isDismissed) {
      _controller.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    } else {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    final (Color accent, IconData icon) = switch (widget.type) {
      ToastType.success => (AppColors.accentGreen, Icons.check_circle_rounded),
      ToastType.error   => (const Color(0xFFEF4444), Icons.error_outline_rounded),
      ToastType.info    => (AppColors.primaryLight, Icons.info_outline_rounded),
    };

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Dismissible(
              key: ValueKey(widget.message),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: _buildCard(accent, icon),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Color accent, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.75), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ─── Ikon Status ───
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),

          // ─── Pesan ───
          Expanded(
            child: Text(
              widget.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
