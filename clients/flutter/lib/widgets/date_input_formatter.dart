import 'package:flutter/services.dart';

/// Types the slashes of dd/mm/aaaa for the user: after the second digit of the day and of the month a "/" follows by itself.
/// Slashes typed by hand are kept (so 5/3/26 still works), a second slash in a row is dropped, deleting is never touched, and
/// text with anything other than digits and slashes (an ISO date, a paste) is left exactly as typed.
class DateSlashFormatter extends TextInputFormatter {
  const DateSlashFormatter();

  static final _plain = RegExp(r'^[0-9/]*$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.length <= oldValue.text.length || !_plain.hasMatch(text)) return newValue;
    // Only a character added at the end is shaped; an edit in the middle stays as typed.
    if (!text.startsWith(oldValue.text) || text.length != oldValue.text.length + 1) return newValue;
    final typed = text[text.length - 1];
    final parts = oldValue.text.split('/');
    var result = text;
    if (typed == '/') {
      // Nothing to separate yet, a slash already there, or the year is being typed.
      if (oldValue.text.isEmpty || oldValue.text.endsWith('/') || parts.length >= 3) result = oldValue.text;
    } else {
      final last = parts.last;
      final index = parts.length - 1;
      if (index < 2 && last.length == 1) result = '$text/';
      if (index >= 2 && last.length >= 4) result = oldValue.text;
    }
    if (result == text) return newValue;
    return TextEditingValue(text: result, selection: TextSelection.collapsed(offset: result.length));
  }
}
