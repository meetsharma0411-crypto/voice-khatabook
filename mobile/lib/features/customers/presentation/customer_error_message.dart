import 'dart:io';

import '../../../core/network/api_client.dart';

String customerErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 401) {
      return 'Authentication required. This backend uses Django session or Basic authentication; mobile sign-in is not configured yet.';
    }
    if (error.statusCode == 403) {
      return 'You do not have permission to access customer records.';
    }
    final body = error.body;
    if (body is Map && body['detail'] != null) return body['detail'].toString();
    if (body is Map && body.isNotEmpty) {
      return body.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
    return 'The server could not complete the request (HTTP ${error.statusCode}).';
  }
  if (error is SocketException || error is HttpException) {
    return 'Could not reach Django. Check that the server is running and the API URL is correct.';
  }
  if (error is FormatException) return error.message;
  return 'Something went wrong. Please try again.';
}
