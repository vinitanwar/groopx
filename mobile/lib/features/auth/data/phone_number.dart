String? normalizeInternationalPhone(String input) {
  var value = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
  if (value.startsWith('00')) {
    value = '+${value.substring(2)}';
  }
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
    return null;
  }
  return value;
}
