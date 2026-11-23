/// Perfiles verificados. De momento solo la cuenta del fundador de Plobby; se identifica por su id de usuario (UUID de
/// Supabase), nunca por el email, que no viaja a la app. Si en el futuro hay más, pasará a una columna del servidor.
const verifiedUserIds = <String>{
  '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0',
};

/// Si el perfil con este id lleva el sello de verificado.
bool isVerifiedUser(String? userId) => userId != null && verifiedUserIds.contains(userId);
