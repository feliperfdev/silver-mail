import 'dart:async';
import 'dart:math';

import 'package:googleapis/gmail/v1.dart';

/// Executa [task] para cada item com no máximo [concurrency] chamadas
/// simultâneas, respeitando um intervalo mínimo entre inícios.
///
/// A cota da Gmail API é de 250 "unidades" por segundo por usuário e um
/// `messages.get` custa 5, então ~40 requisições/s é um teto seguro.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  Future<void> Function(T item) task, {
  int concurrency = 8,
  Duration minInterval = const Duration(milliseconds: 25),
}) async {
  final iterator = items.iterator;
  var nextStart = DateTime.now();

  Future<void> worker() async {
    while (true) {
      if (!iterator.moveNext()) return;
      final item = iterator.current;
      final now = DateTime.now();
      if (nextStart.isAfter(now)) {
        final wait = nextStart.difference(now);
        nextStart = nextStart.add(minInterval);
        await Future<void>.delayed(wait);
      } else {
        nextStart = now.add(minInterval);
      }
      await task(item);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}

/// Repete a chamada com backoff exponencial quando a API sinaliza limite
/// de taxa (429) ou erro temporário (5xx).
Future<T> withRetry<T>(Future<T> Function() call, {int maxAttempts = 6}) async {
  final random = Random();
  for (var attempt = 1; ; attempt++) {
    try {
      return await call();
    } on DetailedApiRequestError catch (e) {
      final status = e.status ?? 0;
      final rateLimited =
          status == 429 ||
          (status == 403 &&
              e.errors.any(
                (err) =>
                    err.reason == 'rateLimitExceeded' ||
                    err.reason == 'userRateLimitExceeded',
              ));
      final retriable = rateLimited || status >= 500;
      if (!retriable || attempt >= maxAttempts) rethrow;
      final delayMs = (pow(2, attempt) * 500).toInt() + random.nextInt(500);
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}
