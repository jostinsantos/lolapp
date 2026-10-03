import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv_config_shared.dart';
/// Pestaña Apariencia — StatefulWidget independiente.
class AparienciaTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;
  final ValueChanged<String>? onMenuPositionChanged;

  const AparienciaTab({
    super.key,
    required this.onRequestTabFocus,
    this.onMenuPositionChanged,
  });

  @override
  State<AparienciaTab> createState() => AparienciaTabState();
}

class AparienciaTabState extends State<AparienciaTab>
    with AutomaticKeepAliveClientMixin {
  String _menuPosition = 'top';

  late final FocusNode _btnMenuPosition;
  late final FocusNode _btnApariencia;

  FocusNode get firstFocusNode => _btnMenuPosition;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnMenuPosition = FocusNode(debugLabel: 'cfg_menu_position');
    _btnApariencia = FocusNode(debugLabel: 'cfg_apariencia');
    _loadSettings();
  }

  @override
  void dispose() {
    _btnMenuPosition.dispose();
    _btnApariencia.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final pos = await MenuPositionPref.get();
    if (!mounted) return;
    setState(() => _menuPosition = pos);
  }

  Future<void> _setMenuPosition(String value) async {
    await MenuPositionPref.set(value);
    if (!mounted) return;
    setState(() => _menuPosition = value);
    widget.onMenuPositionChanged?.call(value);
  }

  Future<void> _switchToMobile() async {
    final ok = await confirmDialog(
      context: context,
      title: 'Cambiar a vista Móvil',
      body:
          'La aplicación se reiniciará para aplicar la interfaz optimizada para móvil (orientación vertical).\n\n¿Deseas continuar?',
      accent: kConfigAccent,
      confirmLabel: 'Reiniciar ahora',
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'mobile');
    if (!mounted) return;
    SystemNavigator.pop();
  }

  void requestFirstFocus() => _btnMenuPosition.requestFocus();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('MENÚ DE NAVEGACIÓN', first: true),
        MenuPositionCard(
          focusNode: _btnMenuPosition,
          selected: _menuPosition,
          onSelect: _setMenuPosition,
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () => _btnApariencia.requestFocus(),
        ),
        const SizedBox(height: 12),
        sectionTitle('MODO'),
        FocusActionCard(
          focusNode: _btnApariencia,
          icon: Icons.phone_android_rounded,
          label: 'Cambiar a vista Móvil',
          subtitle: 'Interfaz vertical optimizada para teléfono',
          onTap: _switchToMobile,
          onArrowUp: () => _btnMenuPosition.requestFocus(),
          onArrowDown: () {},
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
