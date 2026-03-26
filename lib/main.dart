import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_colors.dart';
import 'pages/dashboard_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        final isDark = themeMode == ThemeMode.dark;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor:
              isDark ? AppColors.dark.bg : AppColors.light.bg,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp(
          title: 'M-Money Dashboard',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _buildTheme(AppColors.light, Brightness.light),
          darkTheme: _buildTheme(AppColors.dark, Brightness.dark),
          home: const MyHomePage(),
        );
      },
    );
  }

  static ThemeData _buildTheme(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      extensions: [c],
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.primary,
        brightness: brightness,
      ).copyWith(
        surface: c.bg,
        primary: c.primary,
        secondary: c.accent,
        onSurface: c.textPrimary,
        onPrimary: isDark ? c.bg : Colors.white,
      ),
      scaffoldBackgroundColor: c.bg,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.textPrimary),
        bodyMedium: TextStyle(color: c.textPrimary),
        bodySmall: TextStyle(color: c.textSecondary),
        headlineLarge: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: isDark ? c.bg : Colors.white,
          elevation: isDark ? 8 : 4,
          shadowColor: c.primary.withValues(alpha: isDark ? 0.4 : 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SmsQuery _query = SmsQuery();
  List<SmsMessage> _messages = [];
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final permission = await Permission.sms.status;
    setState(() {
      _hasPermission = permission.isGranted;
    });
    if (_hasPermission) {
      _getMessages();
    }
  }

  Future<void> _requestPermission() async {
    final permission = await Permission.sms.request();
    setState(() {
      _hasPermission = permission.isGranted;
    });
    if (_hasPermission) {
      _getMessages();
    }
  }

  Future<void> _getMessages() async {
    final messages = await _query.querySms(
      kinds: [SmsQueryKind.inbox],
      address: 'M-Money',
    );
    setState(() {
      _messages = messages;
    });

    if (mounted && _messages.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardPage(messages: _messages),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _hasPermission
          ? _buildLoadingOrDashboard()
          : _buildPermissionRequest(),
    );
  }

  Widget _buildLoadingOrDashboard() {
    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading M-Money messages...'),
          ],
        ),
      );
    }

    return DashboardPage(messages: _messages);
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'This app needs permission to read SMS messages from M-Money.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _requestPermission,
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }
}
