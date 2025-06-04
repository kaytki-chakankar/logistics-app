import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'sign_in_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDBT2FQVuoCYba45hpI2Cu9yy_wrARYPc4",
      authDomain: "janksters-logistics.firebaseapp.com",
      projectId: "janksters-logistics",
      storageBucket: "janksters-logistics.firebasestorage.app",
      messagingSenderId: "235386524486",
      appId: "1:235386524486:web:09f4d0dd47a24b2fa1cb47",
      measurementId: "G-3C5NGM8HCD",
    ),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AuthenticationWrapper(),
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return const SignInPage(); // Make sure SignInPage is defined elsewhere
          } else {
            return HomePage(user: user);
          }
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  final User user;
  const HomePage({required this.user, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: Center(
        child: Text('Hello, ${user.email ?? user.displayName ?? 'User'}!'),
      ),
    );
  }
}
