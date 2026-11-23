{{flutter_js}}
{{flutter_build_config}}

// Plobby registra su propio service worker (sw.js, desde index.html). El de Flutter 3.50 es un stub que se da de baja
// a sí mismo y, al registrarse en el mismo ámbito, sustituiría y eliminaría el nuestro: por eso no se registra.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    // Emojis y símbolos (🔥 ❤️ ✓…): las fuentes de respaldo se sirven desde la propia web (web/fonts/fallback), no desde
    // fonts.gstatic.com. Así la política de seguridad (CSP: font-src/connect-src 'self') no las bloquea y no hay terceros.
    const appRunner = await engineInitializer.initializeEngine({ fontFallbackBaseUrl: '/fonts/fallback/' });
    await appRunner.runApp();
  },
});
