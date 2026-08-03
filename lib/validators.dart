/// Reusable input validators for forms across the app.
class Validators {
  // Standard email format: something@something.something
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  /// Returns null if valid, or an error message if invalid.
  static String? email(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return "Email is required";
    }
    if (!_emailRegex.hasMatch(trimmed)) {
      return "Enter a valid email address";
    }
    return null;
  }

  // Password rules:
  // - at least 8 characters
  // - at least 1 uppercase letter
  // - at least 1 lowercase letter
  // - at least 1 number
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');

  /// Returns null if valid, or an error message describing what's missing.
  static String? password(String value) {
    if (value.isEmpty) {
      return "Password is required";
    }
    if (value.length < 8) {
      return "Password must be at least 8 characters";
    }
    if (!_hasUppercase.hasMatch(value)) {
      return "Password must include an uppercase letter";
    }
    if (!_hasLowercase.hasMatch(value)) {
      return "Password must include a lowercase letter";
    }
    if (!_hasDigit.hasMatch(value)) {
      return "Password must include a number";
    }
    return null;
  }
}