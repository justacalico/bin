import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to a Next.js server action endpoint (the renderbux backend that
/// rbxava shells out to). Action responses are React Server Component
/// payloads: one `N:<json>` line per frame, result in the last line.
class ServerActionClient {
  ServerActionClient({
    http.Client? client,
    Uri? endpoint,
  })  : client = client ?? http.Client(),
        endpoint = endpoint ?? defaultEndpoint;

  final http.Client client;
  final Uri endpoint;

  static final defaultEndpoint = Uri.parse('https://www.renderbux.com/p/new');

  Future<String> call(String actionId, String payload) async {
    final response = await client.post(
      endpoint,
      headers: {
        'Content-Type': 'text/plain;charset=UTF-8',
        'Accept': 'text/x-component',
        'Next-Action': actionId,
      },
      body: payload,
    );
    if (response.statusCode != 200) {
      throw ServerActionException(
          'action call failed (HTTP ${response.statusCode})');
    }
    return response.body;
  }

  /// Decodes the value frame of an RSC action response. Returns null when the
  /// response carries `1:null` or has no value line.
  static dynamic extractValue(String body) {
    String? valueLine;
    for (final line in const LineSplitter().convert(body)) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('1:')) {
        valueLine = trimmed.substring(2);
      }
    }
    if (valueLine == null) {
      throw ServerActionException('no value frame in action response');
    }
    return jsonDecode(valueLine);
  }
}

class ServerActionException implements Exception {
  ServerActionException(this.message);

  final String message;

  @override
  String toString() => 'ServerActionException: $message';
}
