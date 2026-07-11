import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/setup_profile_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhoneRepApp());
}

class PhoneRepApp extends StatefulWidget {
  const PhoneRepApp({super.key});

  @override
  State<PhoneRepApp> createState() => _PhoneRepAppState();
}

class _PhoneRepAppState extends State<PhoneRepApp> {
  final ApiService _apiService = ApiService();
  bool? _isProfileRegistered;

  @override
  void initState() {
    super.initState();
    _checkInitialProfile();
  }

  Future<void> _checkInitialProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_my_phone') ?? '';
    if (mounted) {
      setState(() {
        _isProfileRegistered = phone.trim().isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _apiService,
      builder: (context, child) {
        return MaterialApp(
          title: 'PhoneRep',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: _isProfileRegistered == null
              ? const Scaffold(
                  backgroundColor: AppColors.background,
                  body: Center(
                    child: CircularProgressIndicator(color: AppColors.primaryLight),
                  ),
                )
              : (_isProfileRegistered!
                  ? HomeScreen(apiService: _apiService)
                  : SetupProfileScreen(apiService: _apiService)),
        );
      },
    );
  }
}
