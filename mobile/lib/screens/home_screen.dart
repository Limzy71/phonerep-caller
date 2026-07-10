import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'pooling_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;

  const HomeScreen({super.key, required this.apiService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {0}; // Hanya muat tab 0 (Beranda) saat startup agar tidak stuck loading

  Widget _getScreen(int index) {
    if (!_loadedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return SearchScreen(apiService: widget.apiService);
      case 1:
        return _buildChatPlaceholder();
      case 2:
        return PoolingScreen(apiService: widget.apiService);
      case 3:
        return AnalyticsScreen(apiService: widget.apiService);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Widget _buildChatPlaceholder() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    'Obrolan Komunitas PhoneRep',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_chat_unread_rounded, size: 56, color: AppColors.primaryLight),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Pesan & Forum Anti-Spam',
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fitur obrolan antar pengguna PhoneRep untuk bertukar info penipuan dan nomor mencurigakan sedang dalam persiapan.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _getScreen(0),
          _getScreen(1),
          _getScreen(2),
          _getScreen(3),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF10141D),
          border: const Border(top: BorderSide(color: Color(0xFF1E2536), width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) {
            setState(() {
              _currentIndex = idx;
              _loadedTabs.add(idx);
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 68,
          indicatorColor: AppColors.primary.withValues(alpha: 0.25),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.phone_rounded, color: AppColors.textSecondary, size: 24),
              selectedIcon: const Icon(Icons.phone_rounded, color: AppColors.primaryLight, size: 24),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textSecondary, size: 24),
              selectedIcon: const Icon(Icons.chat_bubble_rounded, color: AppColors.primaryLight, size: 24),
              label: 'Obrolan',
            ),
            NavigationDestination(
              icon: const Icon(Icons.shield_outlined, color: AppColors.textSecondary, size: 24),
              selectedIcon: const Icon(Icons.shield_rounded, color: AppColors.accentGreen, size: 24),
              label: 'Perlindungan',
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_rounded, color: AppColors.textSecondary, size: 24),
              selectedIcon: const Icon(Icons.menu_open_rounded, color: AppColors.accentOrange, size: 24),
              label: 'Menu',
            ),
          ],
        ),
      ),
    );
  }
}
