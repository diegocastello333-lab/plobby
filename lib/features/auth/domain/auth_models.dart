/// Acceso y onboarding. La lógica de validación es PURA (testeable sin Flutter ni Supabase).

class AuthUser {
  const AuthUser({required this.id, required this.email, this.displayName});
  final String id, email;
  final String? displayName;
}

enum SelfLevel { beginner, intermediate, upperIntermediate, advanced }
enum CourtSide { right, left }          // derecha / revés
enum Hand { right, left }

extension SelfLevelX on SelfLevel {
  String get label => const ['Iniciación', 'Intermedio', 'Intermedio alto', 'Avanzado'][index];
  String get db => const ['beginner', 'intermediate', 'upper_intermediate', 'advanced'][index];
}

/// Datos del onboarding. `selfLevel` es el nivel DECLARADO: no se mezcla con el ELO (que solo calcula el servidor).
class OnboardingData {
  const OnboardingData({this.firstName = '', this.lastName = '', this.username = '', this.city = '', this.birthDate,
      this.selfLevel, this.side, this.hand, this.habitualClub, this.habitualPartnerId, this.avatarId, this.avatarUrl, this.completed = false});
  final String firstName, lastName, username, city;
  final DateTime? birthDate;
  final SelfLevel? selfLevel;
  final CourtSide? side;
  final Hand? hand;
  final String? habitualClub, habitualPartnerId, avatarId, avatarUrl;
  final bool completed;

  OnboardingData copyWith({String? firstName, String? lastName, String? username, String? city, DateTime? birthDate, SelfLevel? selfLevel,
          CourtSide? side, Hand? hand, String? habitualClub, String? habitualPartnerId, String? avatarId, String? avatarUrl, bool clearAvatarId = false, bool clearAvatarUrl = false, bool? completed}) =>
      OnboardingData(
          firstName: firstName ?? this.firstName, lastName: lastName ?? this.lastName, username: username ?? this.username, city: city ?? this.city,
          birthDate: birthDate ?? this.birthDate, selfLevel: selfLevel ?? this.selfLevel, side: side ?? this.side, hand: hand ?? this.hand,
          habitualClub: habitualClub ?? this.habitualClub, habitualPartnerId: habitualPartnerId ?? this.habitualPartnerId,
          avatarId: clearAvatarId ? null : (avatarId ?? this.avatarId), avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl), completed: completed ?? this.completed);
}

final _usernameRe = RegExp(r'^[a-z0-9._]{3,24}$');
bool isValidUsername(String u) => _usernameRe.hasMatch(u);

/// Mayor de [minAge] años a fecha [now].
bool isBirthDateValid(DateTime? b, {DateTime? now, int minAge = 14}) {
  if (b == null) return false;
  final n = now ?? DateTime.now();
  if (b.isAfter(n)) return false;
  final limit = DateTime(n.year - minAge, n.month, n.day);
  return !b.isAfter(limit);
}

bool step1Complete(OnboardingData d) =>
    d.firstName.trim().length >= 2 && d.lastName.trim().length >= 2 && isValidUsername(d.username) && d.city.trim().length >= 2 && isBirthDateValid(d.birthDate);
bool step2Complete(OnboardingData d) => d.selfLevel != null && d.side != null && d.hand != null;
bool step3Complete(OnboardingData d) => d.avatarId != null || (d.avatarUrl != null && d.avatarUrl!.isNotEmpty);

/// Pasos PENDIENTES (1 datos, 2 juego, 3 foto/avatar, 4 bienvenida). Un usuario existente solo ve lo que le falta.
/// En producción el servidor responde lo mismo (`onboarding_pending_steps()`); esto se usa para la UI y los tests.
List<int> pendingSteps(OnboardingData d) => [
      if (!step1Complete(d)) 1,
      if (!step2Complete(d)) 2,
      if (!step3Complete(d)) 3,
      if (!d.completed) 4,
    ];

/// Errores del paso 1 (clave → mensaje). Vacío = válido. [usernameAvailable]: null = aún sin comprobar.
Map<String, String> validateStep1(OnboardingData d, {bool? usernameAvailable, DateTime? now}) => {
      if (d.firstName.trim().length < 2) 'firstName': 'Escribe tu nombre.',
      if (d.lastName.trim().length < 2) 'lastName': 'Escribe tus apellidos.',
      if (!isValidUsername(d.username)) 'username': 'Usa 3–24 letras minúsculas, números, punto o guion bajo.'
      else if (usernameAvailable == false) 'username': 'Ese usuario ya está en uso.'
      else if (usernameAvailable == null) 'username': 'Espera a que comprobemos la disponibilidad.',
      if (d.city.trim().length < 2) 'city': 'Indica tu ciudad.',
      if (!isBirthDateValid(d.birthDate, now: now)) 'birthDate': 'Indica una fecha válida (mínimo 14 años).',
    };

/// Avatares deportivos predefinidos (ids a1..a12; el dibujo está en `presentation/avatar_catalog.dart`).
const avatarIds = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a10', 'a11', 'a12'];
bool isValidAvatarId(String? id) => id != null && avatarIds.contains(id);
