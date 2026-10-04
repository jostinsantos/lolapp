import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'presentation/mobile/mobile_shell.dart' as mobile;
import 'presentation/tv/tv_shell.dart' as tv;
import 'features/downloads/presentation/notification_helper.dart';
import 'features/settings/presentation/updates/update_notification_service.dart';
import 'core/constants/versiones.dart';
import 'supabase/supabase_config.dart';
import 'supabase/supabase_client.dart';
import 'supabase/supabase_auth.dart';
import 'features/profile/presentation/profile_selection_page.dart';
import 'features/profile/presentation/tv_profile_selection_page.dart';
import 'features/foryou/presentation/taste_onboarding_page.dart';
import 'features/foryou/presentation/taste_onboarding_page_tv.dart';
import 'features/addons/presentation/screens/addons_onboarding_page.dart';
import 'data/addons/addon_manager.dart';
import 'features/player/presentation/widgets/cast_manager.dart';

const String kModeKey = 'app_mode'; // "mobile" | "tv"
const String kDisclaimerKey = 'disclaimer_accepted';
const String kTasteOnboardingKey = 'taste_onboarding_done_v1';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase central
  await AppSupabase.init();

  // Addons (fuentes + catálogos por Git)
  await AddonManager.instance.init();

  // Notificaciones (descargas + cast)
  await NotificationHelper.init();

  // Aviso de nueva versión / parche
  unawaited(UpdateNotificationService.instance.checkAndNotify());

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'downloads_channel',
      channelName: 'Descargas y Cast',
      channelDescription: 'Progreso de descargas y transmisión Cast a TV',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      showWhen: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is Map && data['cast_btn'] is String) {
      CastManager().handleNotificationButton(data['cast_btn'] as String);
    }
  });

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

  final FocusNode _mobileFocus = FocusNode(debugLabel: 'mode_mobile');
  final FocusNode _tvFocus = FocusNode(debugLabel: 'mode_tv');
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
  //  3) Auth / Perfil (login-register o invitado + elegir perfil)
  //  4) Algoritmo / Gustos (taste onboarding)
  //  5) Addons onboarding
  //  6) Home
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(kModeKey);

    if (savedMode == null) {
      if (!mounted) return;
      setState(() => _screen = 'mode');
      _focusAfterFrame(_mobileFocus);
      return;
    }

    _mode = savedMode;
    await _applyOrientation(savedMode);
    await _goDisclaimerOrNext();
  }

  Future<void> _goDisclaimerOrNext() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(kDisclaimerKey) ?? false;

    if (!accepted) {
      if (!mounted) return;
      setState(() => _screen = 'disclaimer');
      if (_isTv) _focusAfterFrame(_acceptFocus);
      return;
    }

    await _goAuthAndOnboarding();
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
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _onModeChosen(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kModeKey, mode);
    _mode = mode;
    await _applyOrientation(mode);
    await _goDisclaimerOrNext();
  }

  Future<void> _onDisclaimerAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDisclaimerKey, true);
    await _goAuthAndOnboarding();
  }

  Future<void> _onDisclaimerRejected() async {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    }
  }

  /// Flujo completo:
  /// 1) Welcome / Auth / Perfiles (ProfileSelection o TV)
  /// 2) Si 1ª vez → Taste onboarding → Addons onboarding
  /// 3) Home
  ///
  /// - Usuario registrado 1ª vez: welcome → auth → perfiles → taste → addons → home
  /// - Usuario registrado no 1ª vez: (perfiles si hace falta) → home
  /// - Invitado 1ª vez: welcome → taste → addons → home
  /// - Invitado no 1ª vez: home
  Future<void> _goAuthAndOnboarding() async {
    if (!mounted) return;

    await AppSupabase.init();

    // ¿Hay perfil seleccionado o modo invitado?
    // Si está logueado pero sin perfil elegido → mostrar selector de perfiles.
    var profileId = await SupabaseConfig.getCurrentProfileId();
    var isGuest = await SupabaseConfig.isGuest();
    final hasActiveProfile = profileId != null || isGuest;

    if (!hasActiveProfile) {
      if (!mounted) return;
      final isTv = _mode == 'tv';
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => isTv
              ? const TvProfileSelectionPage(allowDismiss: false)
              : const ProfileSelectionPage(allowDismiss: false),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );

      profileId = await SupabaseConfig.getCurrentProfileId();
      isGuest = await SupabaseConfig.isGuest();
      if (profileId == null && !isGuest) {
        // Sin elegir nada → volver a pedir
        if (mounted) await _goAuthAndOnboarding();
        return;
      }
    }

    // Onboarding de gustos + addons solo la primera vez
    await _runFirstTimeOnboardingIfNeeded();
  }

  Future<void> _runFirstTimeOnboardingIfNeeded() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final tasteDone = prefs.getBool(kTasteOnboardingKey) ?? false;
    final addonsDone = !(await AddonsOnboardingPage.shouldShow());

    final isFirstTime = !tasteDone || !addonsDone;
    if (!isFirstTime) {
      await _openHome();
      return;
    }

    final isTv = _mode == 'tv';

    // 1) Taste onboarding (contenido favorito)
    if (!tasteDone) {
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) {
            if (isTv) {
              return TasteOnboardingPageTv(
                onFinished: () {
                  Navigator.of(context).pop();
                },
              );
            }
            return TasteOnboardingPage(
              onFinished: () {
                Navigator.of(context).pop();
              },
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      await prefs.setBool(kTasteOnboardingKey, true);
    }

    // 2) Addons onboarding
    if (await AddonsOnboardingPage.shouldShow()) {
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AddonsOnboardingPage(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      // markDone se llama dentro de la página al terminar/saltar
    }

    await _openHome();
  }

  Future<void> _openHome() async {
    if (!mounted) return;
    final mode = _mode ?? 'mobile';
    final Widget home =
        mode == 'tv' ? const tv.MainHome() : const mobile.MainHome();

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (_) => false,
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
                  subtitle: 'Orientación horizontal + mando',
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.info_outline, color: Color(0xFFE50914), size: 56),
              const SizedBox(height: 20),
              const Text(
                'Aviso legal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Esta aplicación no aloja ni distribuye contenido. '
                'Solo proporciona enlaces a fuentes de terceros. '
                'El uso es responsabilidad del usuario.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _FocusButton(
                      focusNode: _rejectFocus,
                      label: 'Rechazar',
                      filled: false,
                      onTap: _onDisclaimerRejected,
                      onArrowRight: () => _acceptFocus.requestFocus(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _FocusButton(
                      focusNode: _acceptFocus,
                      label: 'Aceptar',
                      filled: true,
                      onTap: _onDisclaimerAccepted,
                      onArrowLeft: () => _rejectFocus.requestFocus(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
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
          return SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: filled
                    ? (hasFocus ? const Color(0xFFFF1A2A) : const Color(0xFFE50914))
                    : (hasFocus ? const Color(0xFF2A2A2E) : const Color(0xFF1C1C1E)),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: hasFocus
                        ? const Color(0xFFE50914)
                        : Colors.white.withOpacity(0.12),
                    width: hasFocus ? 2 : 1,
                  ),
                ),
                elevation: 0,
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
        },
      ),
    );
  }
}
