import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/club_models.dart';
import 'club_repository.dart';

class SupabaseClubRepository implements ClubRepository {
  SupabaseClubRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      final code = RegExp(r'(rate_limited|invalid_club|club_not_available|forbidden|invalid_target|not_found|invalid_action)')
              .firstMatch('${e.message} ${e.code}')?.group(1) ?? (e.code == '42501' ? 'forbidden' : 'server');
      throw ClubException(code);
    } on SocketException {
      throw ClubException('network');
    } on http.ClientException {
      throw ClubException('network');
    } on TimeoutException {
      throw ClubException('network');
    }
  }

  List<ClubHit> _hits(dynamic rows) => [for (final r in (rows as List? ?? const [])) ClubHit.fromJson((r as Map).cast<String, dynamic>())];

  @override
  Future<List<ClubHit>> search(String query, {double? lat, double? lng, List<ClubType>? types, int limit = 8}) => _guard(() async =>
      _hits(await _db.rpc('search_clubs', params: {'q': query, 'lat': lat, 'lng': lng, 'types': types?.map((t) => t.db).toList(), 'limit': limit})));

  @override
  Future<List<ClubHit>> nearby(double lat, double lng, {int limit = 8}) =>
      _guard(() async => _hits(await _db.rpc('nearby_clubs', params: {'lat': lat, 'lng': lng, 'limit': limit})));

  @override
  Future<ProposeOutcome> propose({required String name, required String municipality, ClubType type = ClubType.privateClub,
          String? address, bool force = false}) =>
      _guard(() async {
        final j = ((await _db.rpc('propose_club', params: {'p_name': name.trim(), 'p_municipality': municipality.trim(), 'p_type': type.db,
            'p_address': (address ?? '').trim().isEmpty ? null : address!.trim(), 'p_force': force})) as Map).cast<String, dynamic>();
        if (j['status'] == 'created') return ProposeCreated(j['id'] as String);
        return ProposeDuplicates(_hits(j['candidates']));
      });

  @override
  Future<ClubPage?> page(String clubId) => _guard(() async {
        final j = await _db.rpc('club_page', params: {'p_club': clubId});
        return j == null ? null : ClubPage.fromJson((j as Map).cast<String, dynamic>());
      });

  @override
  Future<void> setMyClub(String? clubId) => _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw ClubException('not_authenticated');
        await _db.from('profiles').update({
          'habitual_club_id': clubId,
          if (clubId == null) 'habitual_club': null,   // quitar el club también borra el texto antiguo
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', uid);
      });

  @override
  bool get isAdmin => _db.auth.currentUser?.appMetadata['plobby_admin'] == true;

  @override
  Future<List<PendingClub>> pending() => _guard(() async =>
      [for (final r in (await _db.rpc('admin_pending_clubs') as List? ?? const [])) PendingClub.fromJson((r as Map).cast<String, dynamic>())]);

  @override
  Future<void> review(String clubId, String action, {String? targetId, String? note}) => _guard(() async =>
      _db.rpc('admin_review_club', params: {'p_club': clubId, 'p_action': action, 'p_target': targetId, 'p_note': note}));

  @override
  Future<void> addAlias(String clubId, String alias) =>
      _guard(() async => _db.rpc('admin_add_club_alias', params: {'p_club': clubId, 'p_alias': alias}));
}
