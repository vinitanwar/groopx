import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DeviceContactFailure implements Exception {
  const DeviceContactFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceContactCard {
  const DeviceContactCard({required this.name, required this.phone});

  factory DeviceContactCard.fromMap(Map<dynamic, dynamic> value) => DeviceContactCard(
        name: value['name']?.toString().trim() ?? '',
        phone: value['phone']?.toString().trim() ?? '',
      );

  final String name;
  final String phone;
}

class DeviceContacts {
  DeviceContacts._();
  static final instance = DeviceContacts._();
  static const _channel = MethodChannel('com.futureittouch.groopx/contacts');

  Future<void> _requirePermission() async {
    var permission = await Permission.contacts.status;
    if (!permission.isGranted) permission = await Permission.contacts.request();
    if (permission.isPermanentlyDenied) {
      throw const DeviceContactFailure('Contacts permission phone Settings se allow karein.');
    }
    if (!permission.isGranted) {
      throw const DeviceContactFailure('GroopX contacts dhoondhne ke liye Contacts permission allow karein.');
    }
  }

  Future<List<String>> phoneNumbers() async {
    await _requirePermission();
    try {
      final values = await _channel.invokeListMethod<String>('getPhoneNumbers');
      return (values ?? const <String>[]).where((value) => value.trim().isNotEmpty).take(500).toList();
    } on PlatformException catch (failure) {
      throw DeviceContactFailure(failure.message ?? 'Phone contacts read nahi ho sake.');
    } on MissingPluginException {
      throw const DeviceContactFailure('Phone contact sync is device par available nahi hai.');
    }
  }

  Future<List<DeviceContactCard>> contacts() async {
    await _requirePermission();
    try {
      final values = await _channel.invokeListMethod<dynamic>('getContacts');
      return (values ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(DeviceContactCard.fromMap)
          .where((contact) => contact.name.isNotEmpty && contact.phone.isNotEmpty)
          .take(500)
          .toList(growable: false);
    } on PlatformException catch (failure) {
      throw DeviceContactFailure(failure.message ?? 'Phone contacts read nahi ho sake.');
    } on MissingPluginException {
      throw const DeviceContactFailure('Contact sharing is device par available nahi hai.');
    }
  }

  Future<bool> openContactEditor(DeviceContactCard contact) async {
    try {
      return await _channel.invokeMethod<bool>('openContactEditor', <String, String>{
            'name': contact.name,
            'phone': contact.phone,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
