import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/messaging/data/supabase_messaging_repository.dart';

/// Seguridad Fase 2: las imágenes de grupo están en un bucket privado y la app vuelve a firmar su URL al leerla.
void main() {
  test('extrae la ruta del bucket privado de una URL firmada', () {
    const url = 'https://x.supabase.co/storage/v1/object/sign/group-avatars/5f3c2a1e-0000-4000-8000-000000000000/avatar.jpg?token=abc&v=17';
    expect(SupabaseMessagingRepository.groupAvatarPath(url), '5f3c2a1e-0000-4000-8000-000000000000/avatar.jpg');
  });

  test('no toca URLs públicas, avatares predefinidos ni null', () {
    expect(SupabaseMessagingRepository.groupAvatarPath('https://x.supabase.co/storage/v1/object/public/avatars/u/a.jpg'), isNull);
    expect(SupabaseMessagingRepository.groupAvatarPath(null), isNull);
    expect(SupabaseMessagingRepository.groupAvatarPath('p3'), isNull);
  });
}
