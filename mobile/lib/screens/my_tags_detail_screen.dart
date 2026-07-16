import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/phone_record.dart';
import '../services/api_service.dart';

class MyTagsDetailScreen extends StatefulWidget {
  final List<TagItem> allTags;
  final ApiService apiService;

  const MyTagsDetailScreen({
    super.key,
    required this.allTags,
    required this.apiService,
  });

  @override
  State<MyTagsDetailScreen> createState() => _MyTagsDetailScreenState();
}

class _MyTagsDetailScreenState extends State<MyTagsDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<TagItem> _filteredTags = [];

  @override
  void initState() {
    super.initState();
    _filteredTags = widget.allTags;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterTags(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredTags = widget.allTags;
      });
    } else {
      setState(() {
        _filteredTags = widget.allTags
            .where((tag) => tag.labelName.toLowerCase().contains(query.toLowerCase()))
            .toList();
      });
    }
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
        title: Text(
          'Detail Tag Saya',
          style: GoogleFonts.sora(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ini adalah daftar tag yang tersimpan untuk nomor Anda. Tekan tag untuk melihat profil penyimpan.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.primaryLight.withValues(alpha: 0.9),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2636),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2D3754)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterTags,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Cari tag...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _filterTags('');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _filteredTags.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.label_off_rounded, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'Belum ada tag yang disimpan.'
                              : 'Tidak menemukan tag "${_searchController.text}"',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _filteredTags.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final tag = _filteredTags[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showSaverProfile(tag),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161C2C),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF222B42)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.tag_rounded,
                                    color: AppColors.primaryLight,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    tag.labelName,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  void _showSaverProfile(TagItem tag) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // PREVIEW HARDCODE UI: 
        // 1. Jika menekan 'Ikhsan', simulasikan bahwa ini adalah Tag dari Profil Sendiri.
        if (tag.labelName.toLowerCase() == 'ikhsan') {
          return _SelfTagModal(savedTagLabel: tag.labelName);
        }
        
        // 2. Jika menekan tag lain, simulasikan sebagai tag yang di-save orang lain.
        return _SaverProfileModal(
          saverNumber: '+62 812-3456-7890',
          savedTagLabel: tag.labelName,
          apiService: widget.apiService,
        );
      },
    );
  }
}

class _SaverProfileModal extends StatefulWidget {
  final String saverNumber;
  final String savedTagLabel;
  final ApiService apiService;

  const _SaverProfileModal({
    required this.saverNumber,
    required this.savedTagLabel,
    required this.apiService,
  });

  @override
  State<_SaverProfileModal> createState() => _SaverProfileModalState();
}

class _SaverProfileModalState extends State<_SaverProfileModal> {
  bool _isLoading = true;
  PhoneRecord? _record;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    // PREVIEW HARDCODE UI: Menyimulasikan response API dan mengirim list tag dengan kemiripan
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _isLoading = false;
        _record = PhoneRecord(
          id: 'mock_id',
          phoneNumber: widget.saverNumber,
          countryCode: 'ID',
          searchCount: 1,
          trustScore: 100.0,
          carrier: 'Telkomsel',
          tags: [
            TagItem(id: '1', phoneNumberId: 'mock', labelName: 'Ikhsan Dev', upvotes: 10),
            TagItem(id: '2', phoneNumberId: 'mock', labelName: 'Ikhsan Dev BDG', upvotes: 9), // Harus terfilter oleh logika similarity
            TagItem(id: '3', phoneNumberId: 'mock', labelName: 'Rekan Kerja', upvotes: 8),
            TagItem(id: '4', phoneNumberId: 'mock', labelName: 'Teman Kampus', upvotes: 7),
            TagItem(id: '5', phoneNumberId: 'mock', labelName: 'Keluarga', upvotes: 6),
            TagItem(id: '6', phoneNumberId: 'mock', labelName: 'Tukang Servis', upvotes: 5),
          ],
        );
      });
    }
  }

  List<TagItem> _getDiverseTags(List<TagItem> tags) {
    if (tags.isEmpty) return [];
    
    final sorted = List<TagItem>.from(tags)..sort((a, b) => b.upvotes.compareTo(a.upvotes));
    final result = <TagItem>[];
    
    for (final tag in sorted) {
      if (result.length >= 5) break;
      
      final lowerName = tag.labelName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      bool isSimilar = false;
      for (final selected in result) {
        final selectedLower = selected.labelName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (lowerName.contains(selectedLower) || selectedLower.contains(lowerName)) {
           isSimilar = true;
           break;
        }
      }
      
      if (!isSimilar || result.isEmpty) {
        result.add(tag);
      }
    }
    
    if (result.length < 5) {
      for (final tag in sorted) {
        if (result.length >= 5) break;
        if (!result.any((t) => t.labelName == tag.labelName)) {
          result.add(tag);
        }
      }
    }
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF10141D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF20273C)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              ),
            )
          else if (_errorMessage.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _errorMessage,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 15),
                ),
              ),
            )
          else ...[
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
              ),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14, height: 1.4),
                  children: [
                    const TextSpan(text: 'Pengguna ini menyimpan nomor Anda dengan tag '),
                    TextSpan(
                      text: '#${widget.savedTagLabel}',
                      style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.saverNumber,
                        style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _record?.carrier ?? 'Unknown Carrier',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Tag yang melekat pada profil ini:',
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (_record!.tags.isEmpty)
              Text(
                'Belum ada tag yang tersimpan.',
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getDiverseTags(_record!.tags).map((t) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2636),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2D3754)),
                    ),
                    child: Text(
                      '# ${t.labelName}',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ]
        ],
      ),
    );
  }
}

class _AnonymousSaverModal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF10141D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF20273C)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_off_rounded, color: AppColors.textSecondary, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pengguna Anonim', style: GoogleFonts.sora(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Informasi Dilindungi', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2636),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2D3754)),
            ),
            child: Text(
              'Identitas penyimpan tag ini dilindungi oleh pengaturan privasi atau bersumber dari sinkronisasi kontak lokal. Detail profil tidak dapat ditampilkan.',
              style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, height: 1.4, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SelfTagModal extends StatelessWidget {
  final String savedTagLabel;

  const _SelfTagModal({required this.savedTagLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF10141D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF20273C)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded, color: AppColors.primaryLight, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tag Profil Anda', style: GoogleFonts.sora(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Dikelola oleh Anda', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2636),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2D3754)),
            ),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, height: 1.4, fontSize: 14),
                children: [
                  const TextSpan(text: 'Anda menyematkan tag '),
                  TextSpan(
                    text: '#$savedTagLabel',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' pada profil Anda sendiri. Tag ini membantu pengguna lain untuk mengenali Anda dengan lebih mudah.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
