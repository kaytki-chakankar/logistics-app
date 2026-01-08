
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'attendance_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool isSigningIn = false;

  Future<void> signInWithGoogle() async {
    if (isSigningIn) return; 
    setState(() => isSigningIn = true);

    try {
      final googleProvider = GoogleAuthProvider();

      final userCredential =
          await FirebaseAuth.instance.signInWithPopup(googleProvider);
      final user = userCredential.user;

      if (!mounted) return;

      if (user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AttendancePage(), 
          ),
        );
      }
    } catch (e) {
      print('Google sign-in error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign-in failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Center(
        child: isSigningIn
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
                onPressed: signInWithGoogle,
              ),
      ),
    );
  }
}
