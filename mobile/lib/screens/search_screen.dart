import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/phone_record.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
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

  @override
  void initState() {
    super.initState();
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
        // Refresh detail
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
      backgroundColor: AppColors.cardBg,
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
                    child: Icon(Icons.local_offer_rounded, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Tambah Tag Komunitas',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Bantu komunitas mengenali nomor ini dengan memberikan label nama, penipu, atau profesi.',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagController,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Contoh: Kurir Paket / Telemarketing / Penipu APK',
                  prefixIcon: const Icon(Icons.label, color: AppColors.textSecondary),
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
                    if (label.isEmpty) {
                      return;
                    }
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    try {
                      final newTag = await widget.apiService.addTag(
                        _phoneRecord!.id,
                        label,
                      );
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
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'SIMPAN TAG',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
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
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.cardBgElevated,
          onRefresh: () async {
            if (_searchController.text.isNotEmpty) {
              await _performSearch(_searchController.text);
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PhoneRep Check',
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Pelacak Reputasi & Crowdsourcing',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: AppColors.accentCyan,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Search Bar
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                hintText: 'Cari nomor (+62 / 08xxx)...',
                                prefixIcon: const Icon(Icons.search, color: AppColors.primaryLight),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 20),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                              ),
                              onSubmitted: _performSearch,
                              onChanged: (v) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _isLoading ? null : () => _performSearch(_searchController.text),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _isLoading
                                  ? const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 26),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              if (_errorMessage != null)
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: GlassCard(
                      borderColor: AppColors.accentRed.withValues(alpha: 0.5),
                      backgroundColor: AppColors.accentRed.withValues(alpha: 0.1),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.accentRed, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gagal Memperoleh Data',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.accentRed,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _errorMessage!,
                                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_phoneRecord != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_statusMessage != null && _statusMessage!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.accentCyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: AppColors.accentCyan, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: GoogleFonts.outfit(color: AppColors.accentCyan, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Number Header Card
                        GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NOMOR TELEPON TERDETEKSI',
                                      style: GoogleFonts.outfit(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _phoneRecord!.phoneNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.public, color: AppColors.primaryLight, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      _phoneRecord!.countryCode,
                                      style: GoogleFonts.outfit(
                                        color: AppColors.primaryLight,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Trust Meter Widget
                        TrustMeter(
                          score: _phoneRecord!.trustScore,
                          searchCount: _phoneRecord!.searchCount,
                        ),
                        const SizedBox(height: 24),
                        // Tags Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.groups_rounded, color: AppColors.accentCyan, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Tag & Ulasan (${_phoneRecord!.tags.length})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _showAddTagDialog,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add, color: AppColors.primaryLight, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tambah Tag',
                                      style: GoogleFonts.outfit(
                                        color: AppColors.primaryLight,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: _phoneRecord!.tags.isEmpty
                      ? SliverToBoxAdapter(
                          child: GlassCard(
                            padding: const EdgeInsets.all(30),
                            child: Column(
                              children: [
                                Icon(Icons.label_off_outlined, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Belum ada tag komunitas untuk nomor ini',
                                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _showAddTagDialog,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Jadilah yang pertama memberi tag'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, idx) {
                              final tag = _phoneRecord!.tags[idx];
                              return TagChipCard(
                                tag: tag,
                                onVote: (vType) => _handleVote(tag, vType),
                              );
                            },
                            childCount: _phoneRecord!.tags.length,
                          ),
                        ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ] else if (!_isLoading)
                SliverPadding(
                  padding: const EdgeInsets.all(40),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.manage_search_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'Cari Nomor Telepon Apa Pun',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ketik nomor untuk mendeteksi operator, reputasi spam, dan tag dari komunitas.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}
