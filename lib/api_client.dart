import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: 'accessToken');

  Future<void> logout() => _storage.delete(key: 'accessToken');

  Future<Map<String, dynamic>> register({
    required String email,
    required String displayName,
    required String password,
    required String accountType,
  }) {
    return _jsonRequest(
      'POST',
      '/auth/register',
      body: {
        'email': email,
        'displayName': displayName,
        'password': password,
        'accountType': accountType,
      },
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _jsonRequest(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    final token = response['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('Le serveur n’a pas fourni de session valide.');
    }
    await _storage.write(key: 'accessToken', value: token);
    return response;
  }

  Future<Map<String, dynamic>> currentUser() {
    return _jsonRequest('GET', '/auth/me', authenticated: true);
  }

  Future<List<Map<String, dynamic>>> books({String search = ''}) async {
    final result = await _jsonRequest(
      'GET',
      '/books?search=${Uri.encodeQueryComponent(search)}',
    );
    return _mapList(result['books']);
  }

  Future<List<Map<String, dynamic>>> authorBooks() async {
    final result = await _jsonRequest(
      'GET',
      '/author/books',
      authenticated: true,
    );
    return _mapList(result['books']);
  }

  Future<Map<String, dynamic>> uploadBook({
    required String title,
    required String description,
    required String price,
    required String currency,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/author/books');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = await _authorizationHeader()
      ..fields.addAll({
        'title': title,
        'description': description,
        'price': price,
        'currency': currency,
      });

    if (file.path case final path?) {
      request.files.add(
        await http.MultipartFile.fromPath('file', path, filename: file.name),
      );
    } else {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    }

    final streamedResponse = await _send(request.send);
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<List<Map<String, dynamic>>> adminBooks({
    String status = 'pending',
  }) async {
    final result = await _jsonRequest(
      'GET',
      '/admin/books?status=${Uri.encodeQueryComponent(status)}',
      authenticated: true,
    );
    return _mapList(result['books']);
  }

  Future<List<Map<String, dynamic>>> adminUsers({
    String? status,
    String? role,
  }) async {
    final query = <String, String>{};
    if (status != null) query['status'] = status;
    if (role != null) query['role'] = role;
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final result = await _jsonRequest(
      'GET',
      '/admin/users$suffix',
      authenticated: true,
    );
    return _mapList(result['users']);
  }

  Future<http.Response> downloadAdminFile(int bookId) async {
    final uri = Uri.parse('$apiBaseUrl/admin/books/$bookId/file');
    final headers = {
      'Authorization': await _authorizationHeader(),
      'Accept': 'application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    final response = await _send(() => _client.get(uri, headers: headers));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decodeResponse(response);
      throw ApiException(
        decoded['message'] as String? ?? 'Téléchargement impossible.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> createPaymentCheckout(int bookId) {
    return _jsonRequest(
      'POST',
      '/payments/checkout',
      authenticated: true,
      body: {'bookId': bookId},
    );
  }

  Future<Map<String, dynamic>> verifyPayment(int orderId) {
    return _jsonRequest(
      'GET',
      '/payments/orders/$orderId',
      authenticated: true,
    );
  }

  Future<http.Response> downloadPurchasedFile(int bookId) async {
    final uri = Uri.parse('$apiBaseUrl/purchases/$bookId/file');
    final headers = {
      'Authorization': await _authorizationHeader(),
      'Accept': 'application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    final response = await _send(() => _client.get(uri, headers: headers));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decodeResponse(response);
      throw ApiException(
        decoded['message'] as String? ?? 'Téléchargement impossible.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> reviewBook({
    required int bookId,
    required String status,
    String reviewNote = '',
  }) {
    return _jsonRequest(
      'PATCH',
      '/admin/books/$bookId/review',
      authenticated: true,
      body: {'status': status, 'reviewNote': reviewNote},
    );
  }

  Future<Map<String, dynamic>> setUserStatus({
    required int userId,
    required String status,
  }) {
    return _jsonRequest(
      'PATCH',
      '/admin/users/$userId/status',
      authenticated: true,
      body: {'status': status},
    );
  }

  Future<Map<String, dynamic>> commission() {
    return _jsonRequest(
      'GET',
      '/admin/settings/commission',
      authenticated: true,
    );
  }

  Future<Map<String, dynamic>> setCommission(double percent) {
    return _jsonRequest(
      'PUT',
      '/admin/settings/commission',
      authenticated: true,
      body: {'percent': percent},
    );
  }

  Future<Map<String, dynamic>> paymentProvider() {
    return _jsonRequest(
      'GET',
      '/admin/settings/payment-provider',
      authenticated: true,
    );
  }

  Future<Map<String, dynamic>> dashboard() {
    return _jsonRequest('GET', '/admin/dashboard', authenticated: true);
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated) headers['Authorization'] = await _authorizationHeader();

    final response = await _send(() {
      switch (method) {
        case 'GET':
          return _client.get(uri, headers: headers);
        case 'POST':
          return _client.post(uri, headers: headers, body: jsonEncode(body));
        case 'PATCH':
          return _client.patch(uri, headers: headers, body: jsonEncode(body));
        case 'PUT':
          return _client.put(uri, headers: headers, body: jsonEncode(body));
        default:
          throw ArgumentError.value(method, 'method', 'Méthode HTTP inconnue.');
      }
    });
    return _decodeResponse(response);
  }

  Future<String> _authorizationHeader() async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        'Connectez-vous pour continuer.',
        statusCode: 401,
      );
    }
    return 'Bearer $token';
  }

  Future<T> _send<T>(Future<T> Function() send) async {
    try {
      return await send().timeout(const Duration(seconds: 20));
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('Connexion au serveur impossible : $error');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'Le serveur a renvoyé une réponse illisible.',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'Le serveur a renvoyé un format de réponse invalide.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'];
      throw ApiException(
        message is String ? message : 'La requête a échoué.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) {
      throw const ApiException('Le serveur a renvoyé une liste invalide.');
    }
    return value.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  void close() => _client.close();
}
