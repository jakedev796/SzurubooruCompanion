import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_model.dart';
import '../services/backend_client.dart';
import '../models/auth.dart';

/// Login screen for JWT authentication (Step 2 of 2)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password are required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = context.read<SettingsModel>();
      final client = BackendClient(baseUrl: settings.backendUrl);

      // Login and get tokens
      final response = await client.login(username, password);
      final tokens = AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      );

      if (!mounted) return;

      // Set auth state and store tokens
      await settings.setAuthState(true, response.user['username'], tokens);

      // Set access token on client
      client.setAccessToken(tokens.accessToken);

      // Fetch and apply synced preferences
      try {
        final prefs = await client.fetchPreferences();
        await settings.applySyncedPreferences(prefs);
      } catch (e) {
        debugPrint('Failed to fetch preferences: $e');
        // Don't fail login if preference sync fails
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Login failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 2 of 2: Login',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              autofocus: true,
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              obscureText: true,
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
