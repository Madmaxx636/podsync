import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// An error as a short sentence for the user: no class names, no stack, no uri= suffix.
String cleanError(Object e) {
  if (e is TimeoutException) return 'Timed out';
  if (e is http.ClientException) return e.message;
  if (e is SocketException) {
    return e.message.isEmpty ? 'Network error' : 'Network error: ${e.message}';
  }
  // Only the leading "SomethingException: " goes. (Removing it anywhere turned
  // "ClientException: Redirect limit exceeded" into "ClientRedirect limit exceeded".)
  return e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception: '), '');
}
