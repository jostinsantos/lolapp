import 'package:flutter/material.dart';

// Constantes compartidas (AHORA SON PÚBLICAS)
const kAccentColor = Color(0xFFE50914);
const kCardColor = Color(0xFF1C1C1E);

// Enum para idioma predeterminado
enum IdiomaPred {
  latino('es_MX', 'Español Latino'),
  castellano('es_ES', 'Español Castellano'),
  subtitulado('sub', 'Subtitulado en español');

  final String code;
  final String label;
  const IdiomaPred(this.code, this.label);
}

// Enum para tamaño de subtítulos
enum SubSize {
  pequeno(16.0, 'Pequeño'),
  mediano(22.0, 'Mediano'),
  grande(28.0, 'Grande');

  final double size;
  final String label;
  const SubSize(this.size, this.label);
}

// Enum para altura de subtítulos
enum SubHeight {
  baja(32.0, 'Baja'),
  media(56.0, 'Media'),
  alta(90.0, 'Alta');

  final double bottomPadding;
  final String label;
  const SubHeight(this.bottomPadding, this.label);
}

// Enum para selección de fuente
enum FuenteSeleccion {
  manual('Manual', 'Elegir servidor al reproducir'),
  autoPrimera('Auto - Primera', 'Reproducir la primera fuente disponible'),
  autoIdioma('Auto - Idioma favorito', 'Reproducir según idioma preferido');

  final String label;
  final String description;
  const FuenteSeleccion(this.label, this.description);
}