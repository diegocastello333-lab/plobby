import 'dart:ui';

/// Llama de Plobby en una caja de 100 × 130. Compartida por la UI y por la imagen exportada.
Path flameOuter() => Path()
  ..moveTo(50, 0)
  ..cubicTo(58, 25, 85, 40, 85, 75)
  ..cubicTo(85, 105, 68, 128, 50, 128)
  ..cubicTo(32, 128, 15, 105, 15, 75)
  ..cubicTo(15, 58, 25, 48, 33, 38)
  ..cubicTo(35, 50, 40, 55, 45, 55)
  ..cubicTo(42, 35, 44, 15, 50, 0)
  ..close();

Path flameInner() => Path()
  ..moveTo(50, 62)
  ..cubicTo(56, 78, 68, 84, 68, 100)
  ..cubicTo(68, 114, 60, 124, 50, 124)
  ..cubicTo(40, 124, 32, 114, 32, 100)
  ..cubicTo(32, 90, 40, 84, 44, 76)
  ..cubicTo(46, 82, 48, 84, 50, 84)
  ..cubicTo(48, 76, 48, 70, 50, 62)
  ..close();
