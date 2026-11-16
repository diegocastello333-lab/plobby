{{flutter_js}}
{{flutter_build_config}}

// Plobby registra su propio service worker (sw.js, desde index.html). El de Flutter 3.50 es un stub que se da de baja
// a sí mismo y, al registrarse en el mismo ámbito, sustituiría y eliminaría el nuestro: por eso no se registra.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  },
});
