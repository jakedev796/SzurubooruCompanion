import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_model.dart';
import '../services/backend_client.dart';

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
        throw Exception('Unable to reach backend');
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
      appBar: AppBar(
        title: const Text('Setup'),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 1 of 2: Backend Setup',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'CCC Backend URL',
                hintText: 'http://localhost:21425',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _testConnection(),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testConnection,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test Connection'),
            ),
          ],
        ),
      ),
    );
  }
}
