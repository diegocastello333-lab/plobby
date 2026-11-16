/// El navegador exige que compartir o copiar ocurra justo después de un toque (Safari en iPhone es estricto). Si se
/// tardó demasiado en generar la imagen, se lanza esto y la interfaz ofrece un botón para hacerlo con otro toque.
class ImageActionNeedsTap implements Exception {
  const ImageActionNeedsTap();
}

/// La persona cerró la hoja de compartir sin elegir nada: no es un error.
class ImageActionCancelled implements Exception {
  const ImageActionCancelled();
}

/// Resultado de «Guardar»: en el móvil va directo a la galería; en la web se abre la hoja del sistema (donde está
/// «Guardar imagen») o se descarga el archivo.
enum ImageSaveResult { savedToGallery, shareSheet, downloaded }
