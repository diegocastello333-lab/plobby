# Icono de la app Plobby

Originales tal y como se entregaron (no se usan directamente en la compilación).

- **iOS** (`ios/Runner/Assets.xcassets/AppIcon.appiconset`): `plobby-icon-1024-ios.png` reescalado a cada tamaño, sin transparencia (la App Store la rechaza).
- **Android 8+** (`mipmap-anydpi-v26/ic_launcher.xml`): icono adaptativo con fondo `#D2F548` (`values/ic_launcher_background.xml`),
  primer plano `ic_launcher_foreground.png` y `ic_launcher_monochrome.png` (iconos temáticos de Android 13+).
  Las dos capas se reducen al 85,2 % respecto al original para que la «p.» quede dentro de la zona segura de 66 dp
  (antes rozaba el borde en lanzadores circulares) y tenga la misma proporción que en iOS.
- **Android < 8**: `ic_launcher.png` (de `plobby-icon-1024-rounded.png`) e `ic_launcher_round.png` (cuadrado recortado en círculo).
- **Play Store**: `plobby-icon-512-playstore.png` se sube a mano en Google Play Console.
