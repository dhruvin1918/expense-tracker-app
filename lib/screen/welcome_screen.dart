import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:practice/widgets/custom_scaffold.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() =>
      _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        const AssetImage(
            'assets/images/login_background.png'),
        context,
      );
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance
          .signInWithCredential(credential);
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (!mounted) return;

      final text = e.toString().toLowerCase();
      final message = text.contains('network')
          ? 'No internet connection. Please try again.'
          : 'Sign-in failed. Please try again.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScaffold(
      showAppBar: false,
      child: Column(
        children: [
          const Spacer(),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 80,
                  height: 80,
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Welcome!\n',
                        style: TextStyle(
                          fontSize: 45,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      TextSpan(
                        text:
                            '\nSign in to continue with your Google account',
                        style: TextStyle(
                          fontSize: 20,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(40, 0, 40, 48),
            child: ElevatedButton.icon(
              onPressed:
                  _isLoading ? null : _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                minimumSize:
                    const Size(double.infinity, 50),
              ),
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(
                          colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : const FaIcon(FontAwesomeIcons.google),
              label: Text(
                _isLoading
                    ? 'Signing in...'
                    : 'Continue with Google',
                style:
                    TextStyle(color: colorScheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
