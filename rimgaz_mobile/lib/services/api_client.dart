import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient._internal();
  static final ApiClient instance = ApiClient._internal();

  // Android emulator  host machine. For iOS simulator, use 127.0.0.1.
  //static const String baseUrl = 'http://10.0.2.2:8000';
  // Ios simulator localhost
  static const String baseUrl = 'http://127.0.0.1:8000';

  final http.Client _client = http.Client();
  String? _accessToken;
  String? _refreshToken;
  String? _role;

  String? get role => _role;

  Map<String, String> _authHeaders() {
    final headers = <String, String>{};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Map<String, String> _headers({bool withAuth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (withAuth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<bool> _refreshTokensIfNeeded() async {
    if (_refreshToken == null) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/token/refresh/');
      final res = await _client.post(
        uri,
        headers: _headers(withAuth: false),
        body: jsonEncode({'refresh': _refreshToken}),
      );
      if (res.statusCode != 200) {
        // Refresh failed, clear tokens for safety
        print('TOKEN REFRESH ERROR ${res.statusCode}: ${res.body}');
        logout();
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newAccess = data['access'] as String?;
      if (newAccess == null) {
        print('TOKEN REFRESH ERROR: missing access in response: ${res.body}');
        logout();
        return false;
      }
      _accessToken = newAccess;
      return true;
    } catch (e) {
      print('TOKEN REFRESH EXCEPTION: $e');
      logout();
      return false;
    }
  }

  Future<http.Response> _sendWithAutoRefresh(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    // First attempt with current access token
    var res = await send(_headers());
    if (res.statusCode != 401) return res;

    // Try to refresh the token once if we can
    final refreshed = await _refreshTokensIfNeeded();
    if (!refreshed) {
      return res;
    }

    // Retry once with new access token
    res = await send(_headers());
    return res;
  }

  Future<void> login(
      {required String username, required String password}) async {
    final uri = Uri.parse('$baseUrl/api/token/');
    final res = await _client.post(
      uri,
      headers: _headers(withAuth: false),
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      // Log technical details to debug console
      print('LOGIN ERROR ${res.statusCode}: ${res.body}');
      // Throw a generic error for the UI
      throw Exception('Identifiants invalides');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = data['access'] as String?;
    _refreshToken = data['refresh'] as String?;
    _role = data['role'] as String?;
    if (_accessToken == null || _refreshToken == null) {
      print('LOGIN ERROR: missing tokens in response: ${res.body}');
      throw Exception('Réponse token invalide');
    }
  }

  void logout() {
    _accessToken = null;
    _refreshToken = null;
    _role = null;
  }

  Future<void> sendBusPosition({
    required int busId,
    required double latitude,
    required double longitude,
    double? speedKmh,
    String status = 'on_tour',
  }) async {
    final uri = Uri.parse('$baseUrl/api/bus-positions/');
    final body = <String, dynamic>{
      'bus': busId,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
    };
    if (speedKmh != null) {
      body['speed_kmh'] = speedKmh;
    }

    final res = await _sendWithAutoRefresh(
      (headers) => _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ),
    );
    if (res.statusCode != 201) {
      // Ne pas remonter d'erreur bloquante pour le tracking
      print('BUS POSITION ERROR ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<dynamic>> fetchBusPositions() async {
    final uri = Uri.parse('$baseUrl/api/bus-positions/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement bus-positions');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchBusAlerts() async {
    final uri = Uri.parse('$baseUrl/api/bus-alerts/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement bus-alerts');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchClients() async {
    final uri = Uri.parse('$baseUrl/api/clients/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement clients');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchBuses() async {
    final uri = Uri.parse('$baseUrl/api/buses/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement bus');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> createClientPayment(
      {required double amountMru, String? method}) async {
    final uri = Uri.parse('$baseUrl/api/client-payments/');
    final body = <String, dynamic>{
      'amount_mru': amountMru,
    };
    if (method != null && method.isNotEmpty) {
      body['method'] = method;
    }

    final res = await _sendWithAutoRefresh(
      (headers) => _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ),
    );
    if (res.statusCode != 201) {
      throw Exception(
          'Erreur ${res.statusCode} lors de la création de la demande');
    }
  }

  Future<List<dynamic>> fetchBottleTypes() async {
    final uri = Uri.parse('$baseUrl/api/bottle-types/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    print('BOTTLE TYPES ${res.statusCode}: ${res.body}');
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement bouteilles');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    print('BOTTLE TYPES COUNT: ${list.length}');
    return list;
  }

  Future<List<dynamic>> fetchClientOrders() async {
    final uri = Uri.parse('$baseUrl/api/client-orders/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement commandes');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchDriverOrders() async {
    final uri = Uri.parse('$baseUrl/api/driver-orders/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Erreur ${res.statusCode} chargement commandes chauffeur');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchClientPayments() async {
    final uri = Uri.parse('$baseUrl/api/client-payments/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.get(uri, headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur ${res.statusCode} chargement paiements');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> createClientOrder({
    required int bottleTypeId,
    required int quantity,
  }) async {
    final uri = Uri.parse('$baseUrl/api/client-orders/');
    final body = {
      'bottle_type_id': bottleTypeId,
      'quantity': quantity,
    };
    final res = await _sendWithAutoRefresh(
      (headers) => _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ),
    );
    if (res.statusCode != 201) {
      throw Exception(
          'Erreur ${res.statusCode} lors de la création de la commande');
    }
  }

  Future<Map<String, dynamic>> markOrderDelivered({
    required int orderId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/driver-orders/$orderId/');
    final res = await _sendWithAutoRefresh(
      (headers) => _client.patch(
        uri,
        headers: headers,
        body: jsonEncode(<String, dynamic>{}),
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Erreur ${res.statusCode} lors de la mise à jour de la livraison');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> uploadClientPaymentReceipt({
    required int paymentId,
    required String filePath,
    String? method,
  }) async {
    final uri = Uri.parse('$baseUrl/api/client-payments/$paymentId/');
    final request = http.MultipartRequest('PATCH', uri);
    request.headers.addAll(_authHeaders());
    request.files
        .add(await http.MultipartFile.fromPath('receipt_image', filePath));

    if (method != null && method.isNotEmpty) {
      request.fields['method'] = method;
    }

    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Erreur ${response.statusCode} lors de l\'envoi du reçu');
    }
  }
}
