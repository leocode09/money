import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/dashboard_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Set system UI overlay style for immersive experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Epic Ripple-inspired color constants
  static const primaryColor = Color(0xFFE8956A);
  static const bgColor = Color(0xFF0D0A0F);
  static const cardColor = Color(0xFF1E1525);
  static const textPrimary = Color(0xFFFFF8F0);
  static const textSecondary = Color(0xFFCBB9A8);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Money Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.dark,
            ).copyWith(
              surface: bgColor,
              primary: primaryColor,
              secondary: const Color(0xFFFFCBA4),
              onSurface: textPrimary,
              onPrimary: bgColor,
            ),
        scaffoldBackgroundColor: bgColor,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: textPrimary,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textPrimary),
          bodyMedium: TextStyle(color: textPrimary),
          bodySmall: TextStyle(color: textSecondary),
          headlineLarge: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w800,
          ),
          headlineMedium: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: bgColor,
            elevation: 8,
            shadowColor: primaryColor.withOpacity(0.4),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: cardColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryColor,
        ),
      ),
      home: const MyHomePage(),
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
      address: 'M-Money', // Filter messages from M-Money
      // Remove count parameter to fetch all messages
    );
    setState(() {
      _messages = messages;
    });

    // Automatically navigate to dashboard when messages are loaded
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

    // This should not be reached as we navigate away in _getMessages
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
