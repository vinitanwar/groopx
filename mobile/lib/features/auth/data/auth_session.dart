import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession extends ChangeNotifier {
  AuthSession._();
  static final instance = AuthSession._();

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _profileCompleteKey = 'auth_profile_complete';
  static const _fullNameKey = 'profile_full_name';
  static const _usernameKey = 'profile_username';
  static const _dateOfBirthKey = 'profile_date_of_birth';
  static const _genderKey = 'profile_gender';
  static const _bioKey = 'profile_bio';
  static const _avatarUrlKey = 'profile_avatar_url';

  String? _accessToken;
  String? _refreshToken;
  bool _profileComplete = false;
  String _fullName = '';
  String _username = '';
  String _dateOfBirth = '';
  String _gender = '';
  String _bio = '';
  String _avatarUrl = '';

  bool get isAuthenticated => _accessToken?.isNotEmpty == true;
  bool get profileComplete => _profileComplete;
  String? get accessToken => _accessToken;
  String get fullName => _fullName;
  String get username => _username;
  String get dateOfBirth => _dateOfBirth;
  String get gender => _gender;
  String get bio => _bio;
  String get avatarUrl => _avatarUrl;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _accessToken = preferences.getString(_accessTokenKey);
    _refreshToken = preferences.getString(_refreshTokenKey);
    _profileComplete = preferences.getBool(_profileCompleteKey) ?? false;
    _fullName = preferences.getString(_fullNameKey) ?? '';
    _username = preferences.getString(_usernameKey) ?? '';
    _dateOfBirth = preferences.getString(_dateOfBirthKey) ?? '';
    _gender = preferences.getString(_genderKey) ?? '';
    _bio = preferences.getString(_bioKey) ?? '';
    _avatarUrl = preferences.getString(_avatarUrlKey) ?? '';
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

  Future<void> saveProfile({required String fullName, required String username,
      required String dateOfBirth, required String gender, String bio = '',
      String avatarUrl = ''}) async {
    _fullName = fullName;
    _username = username;
    _dateOfBirth = dateOfBirth;
    _gender = gender;
    _bio = bio;
    _avatarUrl = avatarUrl;
    _profileComplete = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_fullNameKey, fullName);
    await preferences.setString(_usernameKey, username);
    await preferences.setString(_dateOfBirthKey, dateOfBirth);
    await preferences.setString(_genderKey, gender);
    await preferences.setString(_bioKey, bio);
    await preferences.setString(_avatarUrlKey, avatarUrl);
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
    await preferences.remove(_fullNameKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_dateOfBirthKey);
    await preferences.remove(_genderKey);
    await preferences.remove(_bioKey);
    await preferences.remove(_avatarUrlKey);
    notifyListeners();
  }
}
