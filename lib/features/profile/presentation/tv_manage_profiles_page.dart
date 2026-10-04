import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../supabase/supabase_profiles.dart';
import '../../../supabase/supabase_config.dart';
import 'tv_edit_profile_page.dart';

/// Gestión de perfiles para TV (foco blanco + mando).
class TvManageProfilesPage extends StatefulWidget {
  const TvManageProfilesPage({super.key});

  @override
  State<TvManageProfilesPage> createState() => _TvManageProfilesPageState();
}

class _TvManageProfilesPageState extends State<TvManageProfilesPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  final List<FocusNode> _itemFocus = [];
  final FocusNode _createFocus = FocusNode(debugLabel: 'tv_create_profile');
  final FocusNode _backFocus = FocusNode(debugLabel: 'tv_manage_back');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final n in _itemFocus) {
      n.dispose();
    }
    _createFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  void _syncFocus(int count) {
    while (_itemFocus.length > count) {
      _itemFocus.removeLast().dispose();
    }
    while (_itemFocus.length < count) {
      _itemFocus.add(FocusNode(debugLabel: 'tv_manage_item_${_itemFocus.length}'));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SupabaseProfiles.list();
    if (!mounted) return;
    _syncFocus(list.length);
    setState(() {
      _profiles = list;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_itemFocus.isNotEmpty) {
        _itemFocus.first.requestFocus();
      } else {
        _createFocus.requestFocus();
      }
    });
  }

  Future<void> _createOrEdit({Map<String, dynamic>? profile}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TvEditProfilePage(profile: profile),
      ),
    );
    if (result == true && mounted) {
      await _load();
      if (profile == null) {
        final id = await SupabaseConfig.getCurrentProfileId();
        if (id != null && mounted) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cancelF = FocusNode();
        final okF = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) => cancelF.requestFocus());
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Eliminar perfil', style: TextStyle(color: Colors.white, fontSize: 20)),
          content: Text(
            '¿Seguro que quieres eliminar "${profile['name']}"?\nSe borrarán su historial, guardados y likes.',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              focusNode: cancelF,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              focusNode: okF,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    final ok = await SupabaseProfiles.delete(profile['id'].toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Perfil eliminado' : 'Error al eliminar')),
      );
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Focus(
          focusNode: _backFocus,
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent &&
                (e.logicalKey == LogicalKeyboardKey.select ||
                    e.logicalKey == LogicalKeyboardKey.enter)) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Gestionar perfiles',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              children: [
                ...List.generate(_profiles.length, (i) {
                  final p = _profiles[i];
                  return _TvManageItem(
                    focusNode: _itemFocus[i],
                    name: p['name']?.toString() ?? 'Usuario',
                    avatarUrl: p['avatar_url']?.toString(),
                    hasPin: (p['pin']?.toString() ?? '').isNotEmpty,
                    onEdit: () => _createOrEdit(profile: p),
                    onDelete: () => _delete(p),
                  );
                }),
                if (_profiles.length < 5) ...[
                  const SizedBox(height: 24),
                  Focus(
                    focusNode: _createFocus,
                    onKeyEvent: (n, e) {
                      if (e is KeyDownEvent &&
                          (e.logicalKey == LogicalKeyboardKey.select ||
                              e.logicalKey == LogicalKeyboardKey.enter)) {
                        _createOrEdit();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (ctx) {
                        final focused = Focus.of(ctx).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: focused ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => _createOrEdit(),
                            icon: const Icon(Icons.add, size: 26),
                            label: const Text('Crear nuevo perfil', style: TextStyle(fontSize: 17)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (_profiles.length >= 5)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Has alcanzado el máximo de 5 perfiles.',
                      style: TextStyle(color: Colors.white54, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TvManageItem extends StatefulWidget {
  final FocusNode focusNode;
  final String name;
  final String? avatarUrl;
  final bool hasPin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TvManageItem({
    required this.focusNode,
    required this.name,
    this.avatarUrl,
    required this.hasPin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TvManageItem> createState() => _TvManageItemState();
}

class _TvManageItemState extends State<_TvManageItem> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.select ||
              e.logicalKey == LogicalKeyboardKey.enter) {
            widget.onEdit();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _focused ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? Colors.white : Colors.white12,
            width: _focused ? 2.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white12,
              backgroundImage: (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                  ? NetworkImage(widget.avatarUrl!)
                  : null,
              child: (widget.avatarUrl == null || widget.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white70, size: 28)
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.hasPin ? 'Con PIN de seguridad' : 'Sin PIN',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white70, size: 26),
              onPressed: widget.onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 26),
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
