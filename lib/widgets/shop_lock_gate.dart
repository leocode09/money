import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../services/auth_service.dart';

/// Locks the dashboard behind the shop password when enabled. Re-locks when
/// the app goes to the background.
class ShopLockGate extends StatefulWidget {
  final Widget child;

  const ShopLockGate({super.key, required this.child});

  @override
  State<ShopLockGate> createState() => _ShopLockGateState();
}

class _ShopLockGateState extends State<ShopLockGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final _passwordController = TextEditingController();

  bool _enabled = false;
  bool _unlocked = false;
  bool _obscure = true;
  bool _checking = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _enabled) {
      setState(() {
        _unlocked = false;
        _passwordController.clear();
        _errorMessage = null;
      });
    }
  }

  Future<void> _loadLockState() async {
    final enabled = await _authService.isShopPasswordEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _unlocked = !enabled;
      _checking = false;
    });
  }

  /// Call after the shop password is set, changed, or removed in settings.
  Future<void> refreshLockState() async {
    await _loadLockState();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter your shop password.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final ok = await _authService.verifyShopPassword(password);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _unlocked = true;
        _submitting = false;
        _passwordController.clear();
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _submitting = false;
      _errorMessage = 'Incorrect shop password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_enabled && !_unlocked) _buildLockOverlay(context),
      ],
    );
  }

  Widget _buildLockOverlay(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront_rounded, size: 72, color: c.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Shop locked',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your shop password to view the dashboard.',
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: c.cardBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _unlock(),
                          decoration: InputDecoration(
                            labelText: 'Shop password',
                            prefixIcon: Icon(Icons.lock, color: c.primary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: c.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: TextStyle(color: c.danger, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _unlock,
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Unlock'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
