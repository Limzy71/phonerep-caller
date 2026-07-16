import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/phone_record.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class MyPhoneSearchersScreen extends StatefulWidget {
  final int searchCount;
  final double trustScore;
  final List<TagItem> myPhoneTags;
  final String myPhoneNumber;
  final List<SearcherItemData>? searcherItems;
  final VoidCallback? onRefresh;

  const MyPhoneSearchersScreen({
    super.key,
    required this.searchCount,
    required this.trustScore,
    required this.myPhoneTags,
    required this.myPhoneNumber,
    this.searcherItems,
    this.onRefresh,
  });

  @override
  State<MyPhoneSearchersScreen> createState() => _MyPhoneSearchersScreenState();
}

class _MyPhoneSearchersScreenState extends State<MyPhoneSearchersScreen> {
  late int _searchCount;
  List<SearcherItemData>? _dynamicItems;
  bool _isManualRefreshing = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _searchCount = widget.searchCount;
    // Jika null (belum pernah di-fetch), anggap kosong terlebih dahulu agar langsung tampil tanpa shimmer
    _dynamicItems = widget.searcherItems ?? [];
    
    // Refresh diam-diam di background saat pertama kali dibuka
    _backgroundRefresh();
  }

  // Refresh di background tanpa menampilkan shimmer (data lama tetap tampil)
  Future<void> _backgroundRefresh() async {
    try {
      final data = await _apiService.getPhoneSearchers(widget.myPhoneNumber);
      if (mounted) {
        setState(() {
          _dynamicItems = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    setState(() => _isManualRefreshing = true);

    // Matikan shimmer secara instan tepat setelah 500ms (tidak menunggu respon jaringan)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isManualRefreshing = false);
      }
    });

    try {
      final data = await _apiService.getPhoneSearchers(widget.myPhoneNumber);
      if (mounted) {
        setState(() {
          _dynamicItems = data;
        });
        if (widget.onRefresh != null) {
          widget.onRefresh!();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Statistik pencarian telah diperbarui.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
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
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          if (_isManualRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
              onPressed: _handleRefresh,
              tooltip: 'Perbarui Data',
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: const Color(0xFF1E2636),
        onRefresh: _handleRefresh,
        child: _buildSearchersList(),
      ),
    );
  }

  Widget _buildSearchersList() {
    if (_isManualRefreshing) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFF1E2636),
        highlightColor: const Color(0xFF2D3754),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: 5,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(width: 48, height: 48, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(width: 80, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                ),
                Container(width: 30, height: 30, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ],
            ),
          ),
        ),
      );
    }

    final items = _dynamicItems ?? [];
    final int displayCount = items.isNotEmpty ? items.length : _searchCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty) ...[
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
                      style: GoogleFonts.plusJakartaSans(
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
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saat ini belum ada pengguna atau nomor asing yang mencari profil nomor Anda.\n\nJika nanti ada nomor yang memeriksa atau menyimpan tag untuk Anda, aktivitasnya akan langsung muncul di sini.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
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
                      style: GoogleFonts.plusJakartaSans(
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
            ...items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSearcherItem(
                  initials: item.initials,
                  avatarColor: AppColors.primaryLight,
                  profileName: item.profileName,
                  phoneNumber: item.phoneNumber,
                  timeAgo: item.timeAgo,
                  checkCount: item.checkCount,
                  avatarUrl: item.avatarUrl,
                  communityTags: item.communityTags,
                ),
              );
            }),
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
    int? checkCount,
    String? avatarUrl,
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
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          avatarUrl,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Text(
                            initials,
                            style: GoogleFonts.plusJakartaSans(
                              color: avatarColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        initials,
                        style: GoogleFonts.plusJakartaSans(
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
                            style: GoogleFonts.plusJakartaSans(
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
                            style: GoogleFonts.sora(
                              color: avatarColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.phone_android_rounded, size: 14, color: avatarColor),
                        const SizedBox(width: 6),
                        Text(
                          phoneNumber,
                          style: GoogleFonts.sora(
                            color: avatarColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (checkCount != null && checkCount > 1) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF43F5E).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_fire_department_rounded, size: 11, color: Color(0xFFF43F5E)),
                                const SizedBox(width: 3),
                                Text(
                                  '${checkCount}x Dicek',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFF43F5E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      timeAgo,
                      style: GoogleFonts.plusJakartaSans(
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
            style: GoogleFonts.sora(
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
                    style: GoogleFonts.sora(
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
                          style: GoogleFonts.sora(
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
    if (allTags.length <= 15) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF161C2C),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: _AllTagsBottomSheetContent(
              profileName: profileName,
              phoneNumber: phoneNumber,
              allTags: allTags,
              scrollController: null,
            ),
          );
        },
      );
    } else {
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
}

class _AllTagsBottomSheetContent extends StatefulWidget {
  final String profileName;
  final String phoneNumber;
  final List<String> allTags;
  final ScrollController? scrollController;

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

  Widget _buildTagsContent(List<String> displayedTags, int totalCount, int currentLimit, bool hasMore) {
    if (displayedTags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'Tag "${_searchController.text}" tidak ditemukan.',
            style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
                style: GoogleFonts.sora(
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
                style: GoogleFonts.sora(
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
    );
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
        mainAxisSize: MainAxisSize.min,
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
            style: GoogleFonts.sora(
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
                style: GoogleFonts.sora(
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
                  style: GoogleFonts.sora(
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
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Cari dari ${widget.allTags.length} tag komunitas...',
                hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13.5),
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
          widget.scrollController == null
              ? Flexible(
                  child: SingleChildScrollView(
                    child: _buildTagsContent(displayedTags, totalCount, currentLimit, hasMore),
                  ),
                )
              : Expanded(
                  child: ListView(
                    controller: widget.scrollController,
                    children: [
                      _buildTagsContent(displayedTags, totalCount, currentLimit, hasMore),
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
                style: GoogleFonts.sora(
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
