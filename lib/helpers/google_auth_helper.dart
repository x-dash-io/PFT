import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthHelper {
  GoogleAuthHelper._();

  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  static Future<UserCredential?> signInWithGoogle({
    bool forceAccountSelection = true,
  }) async {
    if (forceAccountSelection) {
      // Clear previous Google session so the account chooser is shown.
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      return null;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  static String mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'invalid-credential':
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Google sign-in failed due to invalid credentials. Please try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project yet.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'network-request-failed':
      case 'network-error':
        return 'Network error. Check your internet connection and try again.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Google sign-in was cancelled.';
      default:
        return e.message ?? 'Unable to continue with Google right now.';
    }
  }
}
