import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_model.dart';
import '../services/backend_client.dart';
import '../theme/app_theme.dart';

/// Setup screen for configuring backend URL (Step 1 of 2)
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      setState(() {
        _errorMessage = 'Backend URL is required';
      });
      return;
    }

    // Validate URL format
    try {
      final uri = Uri.parse(url);
      if (!uri.scheme.startsWith('http')) {
        setState(() {
          _errorMessage = 'URL must start with http:// or https://';
        });
        return;
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Invalid URL format';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = BackendClient(baseUrl: url);
      final success = await client.checkConnection();

      if (!success) {
        throw Exception(
          'Server responded but does not appear to be the CCC backend. '
          'Make sure the URL points to the backend API (default port 21425), '
          'not the frontend dashboard.',
        );
      }

      if (!mounted) return;

      // Save URL and navigate to login
      final settings = context.read<SettingsModel>();
      await settings.saveSettings(backendUrl: url);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Connection failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    // Hero image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 280,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Image.asset(
                          'assets/images/reimu.jpg',
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quote text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Text(
                            'Hello slacker,',
                            style: TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            'is it all right for you to slack around here?',
                            style: TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '— Reimu',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted.withOpacity(0.9),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Card with form
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Backend Setup',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _urlController,
                                decoration: const InputDecoration(
                                  labelText: 'CCC Backend URL',
                                  hintText: 'http://localhost:21425',
                                ),
                                enabled: !_isLoading,
                                keyboardType: TextInputType.url,
                                onSubmitted: (_) => _testConnection(),
                              ),
                              const SizedBox(height: 16),
                              if (_errorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: AppColors.red,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _testConnection,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Test Connection',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
