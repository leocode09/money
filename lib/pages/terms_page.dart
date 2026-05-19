import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../services/auth_service.dart';

class TermsPage extends StatefulWidget {
  const TermsPage({super.key, this.requireAcceptance = false, this.onAccepted});

  final bool requireAcceptance;
  final VoidCallback? onAccepted;

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  final AuthService _authService = AuthService();
  bool _isAccepting = false;

  Future<void> _acceptTerms() async {
    setState(() {
      _isAccepting = true;
    });
    await _authService.acceptTerms();
    if (!mounted) return;
    widget.onAccepted?.call();
    if (widget.onAccepted == null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Terms and Conditions'),
        automaticallyImplyLeading: !widget.requireAcceptance,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _TermsText(colors: c),
              ),
            ),
            if (widget.requireAcceptance)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border(top: BorderSide(color: c.cardBorder)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAccepting ? null : _acceptTerms,
                    child: _isAccepting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('I Accept and Continue'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (
        'Use at your own risk',
        'M-Money Dashboard is provided as-is for personal finance tracking. We do not guarantee accuracy, availability, completeness, or fitness for any purpose.',
      ),
      (
        'No financial advice',
        'The app does not provide financial, legal, tax, accounting, or investment advice. You are responsible for verifying all information before making decisions.',
      ),
      (
        'Your responsibility',
        'You are fully responsible for how you use the app, the data you enter or sync, and any actions you take based on information shown in the app.',
      ),
      (
        'SMS and data access',
        'On Android, the app may request SMS access to read M-Money messages you permit it to read. You are responsible for granting, denying, or revoking permissions.',
      ),
      (
        'Cloud sync',
        'If you sign in, some account information and monthly dashboard summaries may be stored in Firebase/Firestore to support web access and app features.',
      ),
      (
        'Privacy and sharing',
        'Public compare features are opt-in. If enabled, only monthly aggregate summaries are shared for comparison, not raw SMS bodies or transaction IDs.',
      ),
      (
        'No liability',
        'To the maximum extent allowed by law, the developers, contributors, and owners of this app are not liable for losses, damages, claims, disputes, penalties, data loss, or consequences arising from your use or misuse of the app.',
      ),
      (
        'No misuse',
        'You agree not to use the app for unlawful, harmful, fraudulent, abusive, or unauthorized activity, and you remain solely responsible for such activity.',
      ),
      (
        'Changes',
        'We may update these terms at any time. Continued use of the app after changes means you accept the updated terms.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'M-Money Dashboard Terms',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Effective version: ${AuthService.termsVersion}',
          style: TextStyle(color: colors.textSecondary),
        ),
        const SizedBox(height: 20),
        Text(
          'By using this app, you agree to these terms. If you do not agree, do not use the app.',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        for (final item in items) ...[
          Text(
            item.$1,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.$2,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
