import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv_config_shared.dart';
/// Pestaña Player — StatefulWidget independiente.
class PlayerTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const PlayerTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<PlayerTab> createState() => PlayerTabState();
}

class PlayerTabState extends State<PlayerTab>
    with AutomaticKeepAliveClientMixin {
  bool _subsAlInicio = false;
  bool _subsBold = false;
  SubSize _subSize = SubSize.mediano;
  double _playerVerticalOffset = 0;

  late final FocusNode _btnSubsInicio;
  late final FocusNode _btnSubsBold;
  late final FocusNode _btnSubSize;
  late final FocusNode _btnVerticalOffset;

  FocusNode get firstFocusNode => _btnSubsInicio;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnSubsInicio = FocusNode(debugLabel: 'cfg_subs_inicio');
    _btnSubsBold = FocusNode(debugLabel: 'cfg_subs_bold');
    _btnSubSize = FocusNode(debugLabel: 'cfg_sub_size');
    _btnVerticalOffset = FocusNode(debugLabel: 'cfg_vertical_offset');
    _loadSettings();
  }

  @override
  void dispose() {
    _btnSubsInicio.dispose();
    _btnSubsBold.dispose();
    _btnSubSize.dispose();
    _btnVerticalOffset.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _subsAlInicio = prefs.getBool('subtitulos_inicio') ?? false;
      _subsBold = prefs.getBool('subtitulos_negrita') ?? false;
      final sizeCode = prefs.getString('subtitulo_tamano') ?? 'mediano';
      _subSize = SubSize.values.firstWhere(
        (e) => e.name == sizeCode,
        orElse: () => SubSize.mediano,
      );
      _playerVerticalOffset =
          (prefs.getDouble('player_vertical_offset') ?? 0).clamp(-80.0, 80.0);
    });
  }

  Future<void> _setSubsAlInicio(bool value) async {
    await saveBool('subtitulos_inicio', value);
    if (!mounted) return;
    setState(() => _subsAlInicio = value);
  }

  Future<void> _setSubsBold(bool value) async {
    await saveBool('subtitulos_negrita', value);
    if (!mounted) return;
    setState(() => _subsBold = value);
  }

  Future<void> _setSubSize(SubSize size) async {
    await saveString('subtitulo_tamano', size.name);
    if (!mounted) return;
    setState(() => _subSize = size);
  }

  Future<void> _setPlayerVerticalOffset(double value) async {
    final v = value.clamp(-80.0, 80.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_vertical_offset', v);
    if (!mounted) return;
    setState(() => _playerVerticalOffset = v);
  }

  void requestFirstFocus() => _btnSubsInicio.requestFocus();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('SUBTÍTULOS', first: true),
        SourceToggleCard(
          title: 'Subtítulos al iniciar',
          subtitleEnabled: 'Se activan automáticamente',
          subtitleDisabled: 'Desactivados al iniciar',
          enabled: _subsAlInicio,
          loading: false,
          icon: Icons.closed_caption_rounded,
          accentColor: kConfigAccent,
          focusNode: _btnSubsInicio,
          onTap: () => _setSubsAlInicio(!_subsAlInicio),
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () => _btnSubsBold.requestFocus(),
        ),
        const SizedBox(height: 10),
        SourceToggleCard(
          title: 'Subtítulos en negrita',
          subtitleEnabled: 'Texto en negrita',
          subtitleDisabled: 'Peso normal',
          enabled: _subsBold,
          loading: false,
          icon: Icons.format_bold_rounded,
          accentColor: const Color(0xFF3B82F6),
          focusNode: _btnSubsBold,
          onTap: () => _setSubsBold(!_subsBold),
          onArrowUp: () => _btnSubsInicio.requestFocus(),
          onArrowDown: () => _btnSubSize.requestFocus(),
        ),
        const SizedBox(height: 10),
        SubSizeSelectorCard(
          focusNode: _btnSubSize,
          selected: _subSize,
          onSelect: _setSubSize,
          onArrowUp: () => _btnSubsBold.requestFocus(),
          onArrowDown: () => _btnVerticalOffset.requestFocus(),
        ),
        const SizedBox(height: 12),
        sectionTitle('IMAGEN'),
        VerticalOffsetCard(
          focusNode: _btnVerticalOffset,
          value: _playerVerticalOffset,
          onChanged: _setPlayerVerticalOffset,
          onArrowUp: () => _btnSubSize.requestFocus(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
