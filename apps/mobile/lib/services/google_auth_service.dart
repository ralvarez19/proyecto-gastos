import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  Future<void>? _initialization;

  Future<UserCredential> signIn() async {
    _initialization ??= GoogleSignIn.instance.initialize();
    await _initialization;
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google no devolvió un token de identidad.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    try {
      _initialization ??= GoogleSignIn.instance.initialize();
      await _initialization;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Firebase is already signed out; Google cleanup is best effort.
    }
  }
}
