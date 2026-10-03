// lib/mobil/servicios/fuentes/apis/contenido/detalle_scraper.dart
import '../../models/scraper/detalle_model.dart';
import '../detail/serieskao_detail_scraper.dart';
import '../detail/tioplus_detail_scraper.dart';
import '../detail/cuevana_detail_scraper.dart';
import '../detail/pelisplus_detail_scraper.dart';
import '../detail/cinehax_detail_scraper.dart';
class DetalleScraper {
  static Future<DetalleContenido> fetch({
    required String servicio,
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final s = servicio.toLowerCase().trim();

    print('── DetalleScraper ──────────────────────');
    print('servicio: $s');
    print('url: $url');
    print('titulo: $titulo');
    print('tipo: $tipo');

    try {
      switch (s) {
        case 'serieskao':
          return await DetalleSeriesKao.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'tioplus':
          return await DetalleTioPlus.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'cuevana':
          return await DetalleCuevana.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'pelisplus':
          return await DetallePelisPlus.fetch(url: url, titulo: titulo, tipo: tipo);
        case 'cinehax':
          return await DetalleCineHax.fetch(url: url, titulo: titulo, tipo: tipo);
        default:
          return DetalleContenido(
            ok: false,
            error: 'Servicio no soportado: "$servicio"',
            servicio: servicio,
            titulo: titulo,
            tipo: tipo,
          );
      }
    } catch (e, st) {
      print('ERROR DetalleScraper: $e');
      print(st);
      return DetalleContenido(
        ok: false,
        error: 'Excepción: $e',
        servicio: servicio,
        titulo: titulo,
        tipo: tipo,
      );
    }
  }
}