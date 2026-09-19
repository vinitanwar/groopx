import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession extends ChangeNotifier {
  AuthSession._();
  static final instance = AuthSession._();

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _profileCompleteKey = 'auth_profile_complete';

  String? _accessToken;
  String? _refreshToken;
  bool _profileComplete = false;

  bool get isAuthenticated => _accessToken?.isNotEmpty == true;
  bool get profileComplete => _profileComplete;
  String? get accessToken => _accessToken;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _accessToken = preferences.getString(_accessTokenKey);
    _refreshToken = preferences.getString(_refreshTokenKey);
    _profileComplete = preferences.getBool(_profileCompleteKey) ?? false;
  }

  Future<void> saveAuthentication(Map<String, dynamic> response,
      {required bool profileComplete}) async {
    final accessToken = response['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException('The server did not return an access token.');
    }
    _accessToken = accessToken;
    _refreshToken = response['refresh_token']?.toString();
    _profileComplete = profileComplete;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, accessToken);
    if (_refreshToken?.isNotEmpty == true) {
      await preferences.setString(_refreshTokenKey, _refreshToken!);
    }
    await preferences.setBool(_profileCompleteKey, profileComplete);
    notifyListeners();
  }

  Future<void> markProfileComplete() async {
    _profileComplete = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_profileCompleteKey, true);
    notifyListeners();
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _profileComplete = false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
    await preferences.remove(_profileCompleteKey);
    notifyListeners();
  }
}
