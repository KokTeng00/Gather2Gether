class Validators {
  const Validators._();

  static String? requiredText(
    String? value, {
    int minLength = 1,
    int maxLength = 120,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'This field is required.';
    if (text.length < minLength) {
      return 'Use at least $minLength characters.';
    }
    if (text.length > maxLength) return 'Use $maxLength characters or fewer.';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text);
    return valid ? null : 'Enter a valid email address.';
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.length < 10) return 'Use at least 10 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(text) ||
        !RegExp(r'[0-9]').hasMatch(text)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static String? participantLimit(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 2 || parsed > 500) {
      return 'Choose a limit from 2 to 500.';
    }
    return null;
  }
}
