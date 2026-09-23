import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'presentation/mobile/mobile_shell.dart' as mobile;
import 'presentation/tv/tv_shell.dart' as tv;
import 'features/downloads/presentation/notification_helper.dart';
import 'core/constants/versiones.dart'; // ← versiones centralizadas
import 'supabase/supabase_config.dart';
import 'supabase/supabase_client.dart';
import 'features/profile/presentation/profile_selection_page.dart';


const String kModeKey = 'app_mode'; // "mobile" | "tv"
const String kDisclaimerKey = 'disclaimer_accepted';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationHelper.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lolplustv',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// loading | mode | disclaimer
  String _screen = 'loading';

  String? _mode; // mobile | tv

  // Foco modo
  final FocusNode _mobileFocus = FocusNode(debugLabel: 'mode_mobile');
  final FocusNode _tvFocus = FocusNode(debugLabel: 'mode_tv');

  // Foco disclaimer
  final FocusNode _acceptFocus = FocusNode(debugLabel: 'disclaimer_accept');
  final FocusNode _rejectFocus = FocusNode(debugLabel: 'disclaimer_reject');

  bool get _isTv => _mode == 'tv';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _mobileFocus.dispose();
    _tvFocus.dispose();
    _acceptFocus.dispose();
    _rejectFocus.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLUJO:
  //  1) Modo (solo 1ª vez)
  //  2) Disclaimer (solo 1ª vez)
  //  3) Home  (la actualización ahora se maneja dentro de MainHome)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrap() async {
    // Mostrar el GIF de carga durante 3 segundos
    await Future.delayed(const Duration(seconds: 3));

    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(kModeKey);

    if (savedMode == null) {
      // 1) Primera vez → elegir orientación
      if (!mounted) return;
      setState(() => _screen = 'mode');
      _focusAfterFrame(_mobileFocus);
      return;
    }

    _mode = savedMode;
    await _applyOrientation(savedMode);
    await _goDisclaimerOrHome();
  }

  Future<void> _goDisclaimerOrHome() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(kDisclaimerKey) ?? false;

    if (!accepted) {
      if (!mounted) return;
      setState(() => _screen = 'disclaimer');
      if (_isTv) _focusAfterFrame(_acceptFocus);
      return;
    }

    await _goToHome();
  }

  void _focusAfterFrame(FocusNode node) {

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  Future<void> _applyOrientation(String mode) async {
    if (mode == 'tv') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _onModeChosen(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kModeKey, mode);
    _mode = mode;
    await _applyOrientation(mode);

    if (!mounted) return;
    setState(() => _screen = 'loading');
    await _goDisclaimerOrHome();
  }

  Future<void> _acceptDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDisclaimerKey, true);
    await _goToHome();
  }


  void _rejectDisclaimer() {
    SystemNavigator.pop();
  }

  Future<void> _goToHome() async {
    if (!mounted) return;

    // Solo si Supabase está configurado (URL+KEY guardados) y aún no hay perfil:
    // mostrar selección de perfiles. Si está desactivado → main normal (cache).
    final hasCreds = await SupabaseConfig.hasCredentials();
    final loggedIn = await SupabaseConfig.isLoggedIn();
    final askEvery = await SupabaseConfig.getAskProfileEveryLaunch();

    // Pedir perfil si: (hay creds y no hay sesión) O (activo y "pedir cada vez")
    final needProfile = hasCreds && (!loggedIn || askEvery);

    if (needProfile) {
      final ok = await AppSupabase.init();
      if (!mounted) return;
      // Si no se pudo inicializar, no bloquear: ir al home normal
      if (ok) {
        // ProfileSelectionPage navega sola al home (pushAndRemoveUntil)
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ProfileSelectionPage(),
            transitionDuration: const Duration(milliseconds: 350),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
        return;
      }
    }

    final mode = _mode ?? 'mobile';
    final Widget home =
        mode == 'tv' ? const tv.MainHome() : const mobile.MainHome();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }


  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case 'mode':
        return _buildModeSelector();
      case 'disclaimer':
        return _buildDisclaimer();
      default:
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Image(
              image: AssetImage('assets/spiner.gif'),
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        );
    }
  }

  // ── 1) Selector Móvil / TV ─────────────────────────────────────────────

  Widget _buildModeSelector() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '¿Cómo quieres usar la app?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Puedes cambiarlo más adelante desde ajustes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 48),
                _ModeButton(
                  focusNode: _mobileFocus,
                  icon: Icons.phone_android_rounded,
                  title: 'Móvil',
                  subtitle: 'Orientación vertical',
                  onTap: () => _onModeChosen('mobile'),
                  onArrowDown: () => _tvFocus.requestFocus(),
                ),
                const SizedBox(height: 18),
                _ModeButton(
                  focusNode: _tvFocus,
                  icon: Icons.tv_rounded,
                  title: 'TV / Android TV',
                  subtitle: 'Orientación horizontal',
                  onTap: () => _onModeChosen('tv'),
                  onArrowUp: () => _mobileFocus.requestFocus(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 2) Disclaimer ──────────────────────────────────────────────────────

  Widget _buildDisclaimer() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'lolplustv conecta con servicios de terceros para poder '
                  'funcionar; no aloja contenido propio. Es un servicio que '
                  'dispone fuentes de servidores online gratuitos en internet '
                  'para facilitar el acceso a los usuarios. No apoyamos la '
                  'piratería: te invitamos siempre a ver películas y series '
                  'por canales legales. La app no contiene anuncios por estos '
                  'motivos. Al activar, entiendes que decides usar estos '
                  'servicios bajo tu propia responsabilidad, y que la app '
                  'no responde por su uso.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: _isTv ? 18 : 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FocusButton(
                      focusNode: _acceptFocus,
                      label: 'Activar',
                      filled: true,
                      onTap: _acceptDisclaimer,
                      onArrowRight: () => _rejectFocus.requestFocus(),
                      onArrowLeft: () => _rejectFocus.requestFocus(),
                    ),
                    const SizedBox(width: 14),
                    _FocusButton(
                      focusNode: _rejectFocus,
                      label: 'Cerrar',
                      filled: false,
                      onTap: _rejectDisclaimer,
                      onArrowLeft: () => _acceptFocus.requestFocus(),
                      onArrowRight: () => _acceptFocus.requestFocus(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mode button ────────────────────────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  const _ModeButton({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onArrowUp,
    this.onArrowDown,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            onArrowUp != null) {
          onArrowUp!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            onArrowDown != null) {
          onArrowDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return SizedBox(
            width: double.infinity,
            height: 78,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    hasFocus ? const Color(0xFF2A2A2E) : const Color(0xFF1C1C1E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: hasFocus
                        ? const Color(0xFFE50914)
                        : Colors.white.withOpacity(0.12),
                    width: hasFocus ? 2 : 1,
                  ),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: const Color(0xFFE50914), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Focus buttons disclaimer ───────────────────────────────────────────────

class _FocusButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  const _FocusButton({
    required this.focusNode,
    required this.label,
    required this.filled,
    required this.onTap,
    this.onArrowLeft,
    this.onArrowRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            onArrowLeft != null) {
          onArrowLeft!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            onArrowRight != null) {
          onArrowRight!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final borderColor = hasFocus
              ? Colors.white
              : (filled ? Colors.transparent : const Color(0xFFE50914));

          if (filled) {
            return SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(color: borderColor, width: 2),
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          return SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE50914),
                side: BorderSide(
                  color: borderColor,
                  width: hasFocus ? 2.5 : 1.2,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}