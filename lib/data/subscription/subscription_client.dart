import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SubscriptionException implements Exception {
  const SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SubscriptionClient {
  Future<String> fetch(Uri uri);
}

class HttpSubscriptionClient implements SubscriptionClient {
  HttpSubscriptionClient({HttpClient? httpClient, Duration? timeout})
      : _httpClient = httpClient ?? HttpClient(),
        _timeout = timeout ?? const Duration(seconds: 20) {
    _httpClient.connectionTimeout = _timeout;
  }

  final HttpClient _httpClient;
  final Duration _timeout;

  @override
  Future<String> fetch(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const SubscriptionException('订阅地址必须使用 HTTP 或 HTTPS');
    }
    try {
      final request = await _httpClient.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SubscriptionException('订阅服务器返回 HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } on TimeoutException {
      throw const SubscriptionException('下载订阅超时');
    } on SocketException {
      throw const SubscriptionException('无法连接订阅服务器');
    } on HttpException {
      throw const SubscriptionException('订阅服务器响应无效');
    }
  }
}