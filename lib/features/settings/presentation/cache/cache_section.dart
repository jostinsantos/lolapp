import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config_shared.dart';
class CacheSection {
  final VoidCallback onClearHistorial;
  final VoidCallback onClearGuardados;
  final VoidCallback onClearCacheServidores;
  final VoidCallback onClearTodo;

  CacheSection({
    required this.onClearHistorial,
    required this.onClearGuardados,
    required this.onClearCacheServidores,
    required this.onClearTodo,
  });

  List<Widget> build() {
    return [
      _buildActionCard(
        title: 'Borrar historial',
        subtitle: 'Historial de reproducción',
        icon: Icons.history_rounded,
        onTap: onClearHistorial,
      ),
      _buildActionCard(
        title: 'Borrar guardados',
        subtitle: 'Lista de títulos guardados',
        icon: Icons.bookmark_outline_rounded,
        onTap: onClearGuardados,
      ),
      _buildActionCard(
        title: 'Borrar caché de servidores',
        subtitle: 'Comprobaciones guardadas',
        icon: Icons.dns_rounded,
        onTap: onClearCacheServidores,
      ),
      _buildActionCard(
        title: 'Borrar todo',
        subtitle: 'Historial + guardados + servidores',
        icon: Icons.delete_forever_rounded,
        iconColor: Colors.redAccent,
        onTap: onClearTodo,
      ),
    ];
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (iconColor ?? Colors.white).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor ?? Colors.white70, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}