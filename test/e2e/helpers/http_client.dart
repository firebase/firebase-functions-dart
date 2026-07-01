// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'test_client_base.dart';

/// Helper for making HTTP requests to Firebase Functions in the emulator.
final class FunctionsHttpClient extends TestClientBase {
  FunctionsHttpClient(super.baseUrl);

  /// Calls an onRequest function with GET method.
  Future<http.Response> get(
    String functionName, {
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('$baseUrl/$functionName');
    print('GET $url');
    return await client.get(
      url,
      headers: {'Accept': 'application/json', ...?headers},
    );
  }

  /// Calls an onRequest function with POST method.
  Future<http.Response> post(
    String functionName, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('$baseUrl/$functionName');
    print('POST $url');

    return await client.post(
      url,
      headers: {'Content-Type': 'application/json', ...?headers},
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// Calls a callable function (onCall).
  Future<http.Response> call(
    String functionName, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('$baseUrl/$functionName');
    print('CALL $url with data: $data');

    final body = jsonEncode({'data': data});

    return await client.post(
      url,
      headers: {'Content-Type': 'application/json', ...?headers},
      body: body,
    );
  }

  /// Parses a callable function response.
  dynamic parseCallableResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception(
        'Callable function failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // Check for error in response
    if (json.containsKey('error')) {
      final error = json['error'] as Map<String, dynamic>;
      throw Exception('Function error: ${error['message']}');
    }

    return json['result'];
  }
}
