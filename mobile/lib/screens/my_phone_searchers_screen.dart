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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Orang yang Melihat Nomor Anda',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
            ),
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
      body: _buildSearchersList(),
    );
  }

  // ignore: unused_element
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
    // TODO(USER-REVIEW): Flag sementara (hardcode preview) agar USER bisa me-review desain card daftar pencari nomor.
    // Jika sudah pas & disetujui, ubah isPreviewingHardcode menjadi false untuk menggunakan data dinamis database.
    const bool isPreviewingHardcode = true;
    // ignore: dead_code
    final int displayCount = isPreviewingHardcode ? 3 : _searchCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ignore: dead_code
          if (displayCount == 0 && !isPreviewingHardcode) ...[
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
                      'Belum ada orang yang mencari atau memeriksa profil nomor Anda.',
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
              decoration: BoxDecoration(
                color: const Color(0xFF161C2C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF222B42)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_search_outlined,
                      size: 44,
                      color: AppColors.primaryLight.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Belum Ada Aktivitas Pencarian',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saat ini belum ada pengguna atau nomor asing yang mencari profil nomor Anda.\n\nJika nanti ada nomor yang memeriksa atau menyimpan tag untuk Anda, aktivitasnya akan langsung muncul di sini.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
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
                      'Ditemukan $displayCount orang yang telah mencari atau memeriksa profil nomor Anda.',
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
            _buildSearcherItem(
              initials: 'SM',
              avatarColor: AppColors.primaryLight,
              profileName: 'Siska Marketing',
              phoneNumber: '+62 812-3456-7890',
              timeAgo: 'Memeriksa nomor Anda | 2 jam yang lalu',
              communityTags: const [
                '#Rekan Kerja',
                '#Sales Corporate',
                '#Marketing Office',
                '#Klien Cabang',
                '#Mitra Proyek',
                '#Divisi Promosi',
                '#Staf Gudang',
                '#PIC Vendor'
              ],
            ),
            const SizedBox(height: 14),
            _buildSearcherItem(
              initials: 'BS',
              avatarColor: AppColors.accentCyan,
              profileName: 'Budi Santoso (Kurir JNE)',
              phoneNumber: '+62 878-8921-3312',
              timeAgo: 'Memeriksa nomor Anda | Kemarin, 14:20 WIB',
              communityTags: const ['#Kurir Paket', '#JNE Express', '#Antar Barang', '#E-Commerce', '#Logistik'],
            ),
            const SizedBox(height: 14),
            _buildSearcherItem(
              initials: 'AP',
              avatarColor: const Color(0xFF34D399),
              profileName: 'Aditya Pratama',
              phoneNumber: '+62 856-4321-9011',
              timeAgo: 'Memeriksa nomor Anda | 3 hari yang lalu',
              communityTags: const ['#Mitra Bisnis', '#Klien Surabaya'],
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSearcherItem({
    required String initials,
    required Color avatarColor,
    required String profileName,
    required String phoneNumber,
    required String timeAgo,
    required List<String> communityTags,
  }) {
    // Jika tag lebih dari 4, tampilkan 4 teratas + tombol Lihat Semua / +X Tag Lainnya
    const int maxVisibleTags = 4;
    final bool hasExtraTags = communityTags.length > maxVisibleTags;
    final List<String> visibleTags = hasExtraTags
        ? communityTags.sublist(0, maxVisibleTags)
        : communityTags;
    final int extraCount = communityTags.length - maxVisibleTags;

    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatarColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: avatarColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(
                    color: avatarColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            profileName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: avatarColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Pencari',
                            style: GoogleFonts.outfit(
                              color: avatarColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone_android_rounded, size: 14, color: avatarColor),
                        const SizedBox(width: 6),
                        Text(
                          phoneNumber,
                          style: GoogleFonts.outfit(
                            color: avatarColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 12),
          Text(
            'Tag yang disimpan oleh orang lain:',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...visibleTags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2636),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2D3754)),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.outfit(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
              if (hasExtraTags)
                GestureDetector(
                  onTap: () => _showAllTagsBottomSheet(
                    profileName: profileName,
                    phoneNumber: phoneNumber,
                    allTags: communityTags,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: avatarColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: avatarColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+$extraCount Tag Lainnya',
                          style: GoogleFonts.outfit(
                            color: avatarColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 12, color: avatarColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAllTagsBottomSheet({
    required String profileName,
    required String phoneNumber,
    required List<String> allTags,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161C2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _AllTagsBottomSheetContent(
              profileName: profileName,
              phoneNumber: phoneNumber,
              allTags: allTags,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _AllTagsBottomSheetContent extends StatefulWidget {
  final String profileName;
  final String phoneNumber;
  final List<String> allTags;
  final ScrollController scrollController;

  const _AllTagsBottomSheetContent({
    required this.profileName,
    required this.phoneNumber,
    required this.allTags,
    required this.scrollController,
  });

  @override
  State<_AllTagsBottomSheetContent> createState() => _AllTagsBottomSheetContentState();
}

class _AllTagsBottomSheetContentState extends State<_AllTagsBottomSheetContent> {
  late TextEditingController _searchController;
  late List<String> _filteredTags;
  int _displayLimit = 50;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredTags = widget.allTags;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterTags(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredTags = widget.allTags;
      } else {
        _filteredTags = widget.allTags
            .where((tag) => tag.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
      _displayLimit = 50;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int totalCount = _filteredTags.length;
    final int currentLimit = _displayLimit > totalCount ? totalCount : _displayLimit;
    final List<String> displayedTags = _filteredTags.sublist(0, currentLimit);
    final bool hasMore = totalCount > currentLimit;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Semua Tag untuk ${widget.profileName}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.phoneNumber,
                style: GoogleFonts.outfit(
                  color: AppColors.primaryLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total ${widget.allTags.length} Tag',
                  style: GoogleFonts.outfit(
                    color: AppColors.accentCyan,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.allTags.length > 8) ...[
            TextField(
              controller: _searchController,
              onChanged: _filterTags,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Cari dari ${widget.allTags.length} tag komunitas...',
                hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13.5),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _filterTags('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E2636),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 14),
          Expanded(
            child: displayedTags.isEmpty
                ? Center(
                    child: Text(
                      'Tag "$_searchController" tidak ditemukan.',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  )
                : ListView(
                    controller: widget.scrollController,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: displayedTags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2636),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2D3754)),
                            ),
                            child: Text(
                              tag,
                              style: GoogleFonts.outfit(
                                color: AppColors.primaryLight,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (hasMore) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _displayLimit += 50;
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryLight, size: 18),
                            label: Text(
                              'Muat Lebih Banyak (${totalCount - currentLimit} tag tersisa)',
                              style: GoogleFonts.outfit(
                                color: AppColors.primaryLight,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Tutup',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
