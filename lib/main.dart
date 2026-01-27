import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/dashboard_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Money Dashboard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC77B58), // Ripple coral/orange
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF1A1018),
          primary: const Color(0xFFC77B58),
          secondary: const Color(0xFFD4956A),
          onSurface: const Color(0xFFF5EBE0),
          onPrimary: const Color(0xFF1A1018),
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1018),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFF1A1018),
          foregroundColor: Color(0xFFF5EBE0),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF5EBE0)),
          bodyMedium: TextStyle(color: Color(0xFFF5EBE0)),
          bodySmall: TextStyle(color: Color(0xFFB8A99A)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC77B58),
            foregroundColor: const Color(0xFF1A1018),
          ),
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
      address: 'M-Money',  // Filter messages from M-Money
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
      body: _hasPermission ? _buildLoadingOrDashboard() : _buildPermissionRequest(),
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
