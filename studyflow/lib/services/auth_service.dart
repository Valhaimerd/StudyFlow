import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'database_service.dart';

class AuthMessageException implements Exception {
  const AuthMessageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentGoogleUser;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> initialize() async {
    try {
      await _googleSignIn.initialize().timeout(const Duration(seconds: 4));
    } catch (_) {
      return;
    }

    _googleSignIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _currentGoogleUser = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _currentGoogleUser = null;
      }
    });
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final User? user = userCredential.user;

      if (user == null) {
        throw const AuthMessageException(
          'Sign-in could not be completed right now. Please try again.',
        );
      }

      _currentGoogleUser = googleUser;

      await DatabaseService.instance.createOrUpdateUserProfile(
        uid: user.uid,
        fullName: user.displayName ?? 'Student',
        email: user.email ?? '',
      );

      return userCredential;
    } on AuthMessageException {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw AuthMessageException(_googleSignInMessage(error));
    } on FirebaseAuthException catch (error) {
      throw AuthMessageException(_firebaseAuthMessage(error));
    } catch (_) {
      throw const AuthMessageException(
        'Could not sign you in right now. Please try again in a moment.',
      );
    }
  }

  Future<Map<String, String>?> authorizationHeadersForScopes(
    List<String> scopes, {
    bool promptIfNecessary = false,
  }) async {
    final account = await _getGoogleUser();
    if (account == null) {
      return null;
    }

    return account.authorizationClient.authorizationHeaders(
      scopes,
      promptIfNecessary: promptIfNecessary,
    );
  }

  bool authorizationRequiresUserInteraction() {
    return _googleSignIn.authorizationRequiresUserInteraction();
  }

  Future<GoogleSignInAccount?> _getGoogleUser() async {
    if (_currentGoogleUser != null) {
      return _currentGoogleUser;
    }

    final restoredSession = _googleSignIn.attemptLightweightAuthentication();
    if (restoredSession == null) {
      return null;
    }

    _currentGoogleUser = await restoredSession;
    return _currentGoogleUser;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    _currentGoogleUser = null;
  }

  String _googleSignInMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
        return 'Sign-in was canceled. Choose a Google account to continue.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in is not available on this device right now.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is temporarily unavailable. Please try again later.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Please finish signing in with the selected Google account and try again.';
      case GoogleSignInExceptionCode.unknownError:
        return 'Could not complete Google sign-in right now. Please try again.';
    }
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'network-request-failed':
        return 'Could not reach Google right now. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many sign-in attempts were made. Please wait a moment and try again.';
      case 'user-disabled':
        return 'This Google account cannot sign in right now. Try a different account.';
      case 'account-exists-with-different-credential':
        return 'This email is already linked to a different sign-in method.';
      case 'invalid-credential':
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Google sign-in could not be verified. Please try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not available right now. Please try again later.';
      default:
        return 'Could not sign you in right now. Please try again in a moment.';
    }
  }
}
