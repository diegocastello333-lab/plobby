import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plobby/core/errors/failure.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/core/widgets/state_views.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Incidencia del 16 nov 2026: en el iPhone el perfil mostraba «Parece que no hay conexión» aunque Supabase respondía
/// 200. La tarjeta de error usaba ese texto para CUALQUIER fallo. Ahora cada causa tiene su texto y solo se culpa a la
/// conexión cuando de verdad es la conexión.
void main() {
  test('cada tipo de fallo se clasifica por su causa real', () {
    expect(classifyError(TimeoutException('lento')), FailureKind.timeout);
    expect(classifyError(http.ClientException('Failed to fetch')), FailureKind.serviceUnavailable);
    expect(classifyError(const sb.PostgrestException(message: 'JWT expired', code: 'PGRST301')), FailureKind.auth);
    expect(classifyError(const sb.PostgrestException(message: 'permission denied for table profiles', code: '42501')), FailureKind.permission);
    expect(classifyError(const sb.PostgrestException(message: 'boom', code: 'P0001')), FailureKind.server);
    expect(classifyError(const sb.AuthException('Invalid Refresh Token', statusCode: '400')), FailureKind.auth);
    expect(classifyError(const MatchCreateException('network')), FailureKind.serviceUnavailable);
    expect(classifyError(const MatchCreateException('not_friend')), FailureKind.server);
  });

  test('un fallo de DATOS (respuesta 200 mal interpretada) no es un problema de conexión', () {
    Object err;
    try { final Object x = <dynamic>[]; x as Map<String, dynamic>; err = 'no'; } catch (e) { err = e; }
    final k = classifyError(err);
    expect(k, FailureKind.data);
    expect(k.isConnectivity, isFalse);
    expect(k.message.toLowerCase(), contains('no es tu conexión'));
  });

  test('los avisos de acciones solo culpan a la conexión cuando es la conexión', () {
    expect(actionErrorText(StateError('x')), isNot(contains('conexión')));
    expect(actionErrorText(const sb.PostgrestException(message: 'permission denied', code: '42501')), contains('permiso'));
    expect(actionErrorText(http.ClientException('Failed to fetch')), contains('conectar'));
  });

  testWidgets('la tarjeta de error dice la causa real y nunca «no hay conexión» si no lo es', (t) async {
    var retries = 0;
    Future<void> show(Object? e) async {
      await t.pumpWidget(MaterialApp(theme: buildPlobbyTheme(), home: Scaffold(body: ErrorStateCard(error: e, onRetry: () => retries++))));
      await t.pump(const Duration(milliseconds: 400));
    }
    await show(TypeError());
    expect(find.text('No se pudo mostrar'), findsOneWidget);
    expect(find.textContaining('conexión'), findsOneWidget);                 // «No es tu conexión: …»
    expect(find.textContaining('no hay conexión'), findsNothing);
    await show(const sb.PostgrestException(message: 'permission denied', code: '42501'));
    expect(find.text('No tienes acceso'), findsOneWidget);
    await show(null);
    expect(find.text('No se pudo cargar'), findsOneWidget);
    expect(find.textContaining('conexión'), findsNothing);
    await t.tap(find.text('Reintentar'));
    expect(retries, 1);
  });
}
