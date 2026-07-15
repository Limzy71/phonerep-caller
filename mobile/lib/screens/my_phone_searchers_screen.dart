import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/phone_record.dart';
import '../theme/app_theme.dart';

class MyPhoneSearchersScreen extends StatefulWidget {
  final int searchCount;
  final double trustScore;
  final List<TagItem> myPhoneTags;
  final String myPhoneNumber;
  final VoidCallback? onRefresh;

  const MyPhoneSearchersScreen({
    super.key,
    required this.searchCount,
    required this.trustScore,
    required this.myPhoneTags,
    required this.myPhoneNumber,
    this.onRefresh,
  });

  @override
  State<MyPhoneSearchersScreen> createState() => _MyPhoneSearchersScreenState();
}

class _MyPhoneSearchersScreenState extends State<MyPhoneSearchersScreen> {
  late int _searchCount;

  @override
  void initState() {
    super.initState();
    _searchCount = widget.searchCount;
  }

  void _handleRefresh() {
    if (widget.onRefresh != null) {
      widget.onRefresh!();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Statistik pencarian telah diperbarui.',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F141F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F141F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Siapa yang Mencari Nomor Saya',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            onPressed: _handleRefresh,
            tooltip: 'Perbarui Data',
          ),
        ],
      ),
      body: _searchCount == 0 ? _buildEmptyState() : _buildSearchersList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF161C2C),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF222B42), width: 1.5),
              ),
              child: const Icon(
                Icons.person_search_outlined,
                color: Color(0xFF007AFF),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Belum Ada Riwayat Pemeriksaan',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Belum ada orang atau nomor asing yang mencari nomor Anda.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchersList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161C2C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF222B42)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF007AFF), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ditemukan $_searchCount orang yang telah mencari atau memeriksa profil nomor Anda.',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF161C2C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF222B42)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearcherItem(
                  icon: Icons.person_search_rounded,
                  iconBg: AppColors.primaryLight.withValues(alpha: 0.15),
                  iconColor: AppColors.primaryLight,
                  phoneNumber: 'Pengguna Anonim (+62 812-****-****)',
                  timeAgo: 'Memeriksa nomor Anda • Baru-baru ini',
                  externalTag: widget.myPhoneTags.isNotEmpty
                      ? widget.myPhoneTags.first.labelName
                      : 'Penelusuran Kontak',
                ),
                if (_searchCount > 1) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  ),
                  _buildSearcherItem(
                    icon: Icons.manage_search_rounded,
                    iconBg: AppColors.accentCyan.withValues(alpha: 0.15),
                    iconColor: AppColors.accentCyan,
                    phoneNumber: 'Pengguna Anonim (+62 878-****-****)',
                    timeAgo: 'Memeriksa nomor Anda • 2 hari lalu',
                    externalTag: widget.myPhoneTags.length > 1
                        ? widget.myPhoneTags[1].labelName
                        : 'Pengecekan Rutin',
                  ),
                ],
                if (_searchCount > 2) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  ),
                  Row(
                    children: [
                      Icon(Icons.more_horiz_rounded, color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '+${_searchCount - 2} pemeriksaan oleh nomor asing lainnya',
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '* Demi menjaga privasi pengguna, digit tengah nomor pencari disembunyikan.',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSearcherItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String phoneNumber,
    required String timeAgo,
    required String externalTag,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: iconBg,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phoneNumber,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeAgo,
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Tag yang disimpan:',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2636),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2D3754)),
              ),
              child: Text(
                '# $externalTag',
                style: GoogleFonts.outfit(color: AppColors.primaryLight, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
