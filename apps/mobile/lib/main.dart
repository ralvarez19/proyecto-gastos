import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/expenses_controller.dart';
import 'data/local_category.dart';
import 'data/local_expense.dart';
import 'data/local_provider.dart';
import 'data/local_project.dart';
import 'data/local_labor.dart';
import 'firebase_options.dart';
import 'services/export_service.dart';
import 'services/firebase_sync_service.dart';
import 'services/google_auth_service.dart';
import 'services/local_lock_service.dart';

final expensesController = ExpensesController();
FirebaseSyncService? firebaseSyncService;
final localLockService = LocalLockService();
final googleAuthService = GoogleAuthService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  firebaseSyncService = FirebaseSyncService();
  await expensesController.initialize();
  runApp(const ObraFlowApp());
}

class ObraFlowApp extends StatefulWidget {
  const ObraFlowApp({super.key});
  @override
  State<ObraFlowApp> createState() => _ObraFlowAppState();
}

class _ObraFlowAppState extends State<ObraFlowApp> {
  ThemeMode mode = ThemeMode.light;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ObraFlow',
      themeMode: mode,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: AuthGate(
        onTheme: () => setState(
          () =>
              mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.onTheme});
  final VoidCallback onTheme;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    initialData: FirebaseAuth.instance.currentUser,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      return user == null
          ? const LoginPage()
          : AuthenticatedHome(user: user, onTheme: onTheme);
    },
  );
}

class AuthenticatedHome extends StatefulWidget {
  const AuthenticatedHome({
    super.key,
    required this.user,
    required this.onTheme,
  });
  final User user;
  final VoidCallback onTheme;

  @override
  State<AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<AuthenticatedHome>
    with WidgetsBindingObserver {
  bool? pinConfigured;
  bool unlocked = false;
  DateTime? backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    expensesController.onLocalChange = sync;
    checkLocalLock();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      unlocked = false;
      pinConfigured = null;
      checkLocalLock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    expensesController.onLocalChange = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed &&
        unlocked &&
        backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt!) >
            const Duration(seconds: 30)) {
      setState(() => unlocked = false);
    }
  }

  Future<void> checkLocalLock() async {
    final configured = await localLockService.hasPin(widget.user.uid);
    if (!mounted) return;
    setState(() => pinConfigured = configured);
  }

  void completeUnlock() {
    if (!mounted) return;
    setState(() {
      pinConfigured = true;
      unlocked = true;
      backgroundedAt = null;
    });
    sync();
  }

  Future<void> sync() async {
    await firebaseSyncService?.sync(widget.user.uid);
    await expensesController.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (pinConfigured == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (pinConfigured == false) {
      return PinSetupPage(
        uid: widget.user.uid,
        email: widget.user.email ?? '',
        onComplete: completeUnlock,
        onSignOut: googleAuthService.signOut,
      );
    }
    if (!unlocked) {
      return UnlockPage(
        uid: widget.user.uid,
        email: widget.user.email ?? '',
        onUnlocked: completeUnlock,
        onSignOut: googleAuthService.signOut,
      );
    }
    return AppShell(
      onTheme: widget.onTheme,
      onSync: sync,
      onSignOut: googleAuthService.signOut,
    );
  }
}

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({
    super.key,
    required this.uid,
    required this.email,
    required this.onComplete,
    required this.onSignOut,
  });
  final String uid;
  final String email;
  final VoidCallback onComplete;
  final Future<void> Function() onSignOut;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final pin = TextEditingController();
  final confirmation = TextEditingController();
  bool saving = false;
  String error = '';

  @override
  void dispose() {
    pin.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: Brand()),
                    const SizedBox(height: 18),
                    Text(
                      'Protege ObraFlow',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea un PIN local. Después podrás entrar con huella o con este PIN sin escribir nuevamente tu contraseña de Firebase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    _pinField(pin, 'PIN de 4 a 6 números'),
                    const SizedBox(height: 14),
                    _pinField(confirmation, 'Confirma el PIN'),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shield_outlined),
                      label: const Text('Guardar y continuar'),
                    ),
                    TextButton(
                      onPressed: saving ? null : widget.onSignOut,
                      child: const Text('Usar otra cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 6,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.pin_outlined),
      counterText: '',
    ),
  );

  Future<void> save() async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin.text)) {
      setState(() => error = 'El PIN debe tener entre 4 y 6 números.');
      return;
    }
    if (pin.text != confirmation.text) {
      setState(() => error = 'Los PIN no coinciden.');
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await localLockService.savePin(widget.uid, pin.text);
      widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo guardar el PIN de forma segura.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class UnlockPage extends StatefulWidget {
  const UnlockPage({
    super.key,
    required this.uid,
    required this.email,
    required this.onUnlocked,
    required this.onSignOut,
  });
  final String uid;
  final String email;
  final VoidCallback onUnlocked;
  final Future<void> Function() onSignOut;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final pin = TextEditingController();
  bool checkingBiometric = false;
  bool biometricAvailable = false;
  bool checkingPin = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => prepareBiometric());
  }

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  Future<void> prepareBiometric() async {
    final available = await localLockService.biometricsAvailable();
    if (!mounted) return;
    setState(() => biometricAvailable = available);
    if (available) await unlockWithBiometric();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: Brand()),
                    const SizedBox(height: 18),
                    Text(
                      'Desbloquea ObraFlow',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.email, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (biometricAvailable) ...[
                      IconButton.filledTonal(
                        onPressed: checkingBiometric
                            ? null
                            : unlockWithBiometric,
                        iconSize: 42,
                        tooltip: 'Desbloquear con huella',
                        icon: checkingBiometric
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.fingerprint),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Usa tu huella o ingresa el PIN',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextField(
                      controller: pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onSubmitted: (_) => unlockWithPin(),
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: Icon(Icons.pin_outlined),
                        counterText: '',
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: checkingPin ? null : unlockWithPin,
                      child: Text(
                        checkingPin ? 'Verificando…' : 'Desbloquear con PIN',
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onSignOut,
                      child: const Text('Volver a iniciar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> unlockWithBiometric() async {
    setState(() {
      checkingBiometric = true;
      error = '';
    });
    final success = await localLockService.authenticateBiometric();
    if (!mounted) return;
    setState(() => checkingBiometric = false);
    if (success) widget.onUnlocked();
  }

  Future<void> unlockWithPin() async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin.text)) {
      setState(() => error = 'Ingresa tu PIN de 4 a 6 números.');
      return;
    }
    setState(() {
      checkingPin = true;
      error = '';
    });
    final success = await localLockService.verifyPin(widget.uid, pin.text);
    if (!mounted) return;
    setState(() {
      checkingPin = false;
      error = success ? '' : 'PIN incorrecto.';
    });
    if (success) widget.onUnlocked();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool obscure = true;
  String error = '';

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: Brand()),
                    const SizedBox(height: 16),
                    Text(
                      'Ingresa a ObraFlow',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tus datos se guardan en el celular y se sincronizan con tu cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: obscure,
                      onSubmitted: (_) => authenticate(register: false),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: loading
                          ? null
                          : () => authenticate(register: false),
                      icon: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Ingresar'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: loading ? null : signInWithGoogle,
                      icon: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDADCE0)),
                        ),
                        child: const Text(
                          'G',
                          style: TextStyle(
                            color: Color(0xFF4285F4),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      label: const Text('Continuar con Google'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: loading
                          ? null
                          : () => authenticate(register: true),
                      child: const Text('Crear mi cuenta personal'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> authenticate({required bool register}) async {
    final cleanEmail = email.text.trim();
    if (!cleanEmail.contains('@') || password.text.length < 6) {
      setState(
        () => error =
            'Ingresa un correo válido y una contraseña de al menos 6 caracteres.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = '';
    });
    try {
      if (register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: cleanEmail,
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (exception) {
      if (!mounted) return;
      setState(() => error = _authMessage(exception.code));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      await googleAuthService.signIn();
    } on FirebaseAuthException catch (exception) {
      if (!mounted) return;
      setState(() => error = _authMessage(exception.code));
    } catch (exception) {
      if (!mounted) return;
      final message = exception.toString().toLowerCase();
      setState(
        () => error = message.contains('cancel')
            ? 'Se canceló el acceso con Google.'
            : 'No se pudo ingresar con Google. Verifica que el proveedor esté activo en Firebase.',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _authMessage(String code) => switch (code) {
    'email-already-in-use' => 'Ese correo ya tiene una cuenta. Pulsa Ingresar.',
    'invalid-credential' ||
    'wrong-password' => 'Correo o contraseña incorrectos.',
    'operation-not-allowed' =>
      'Este método de acceso todavía no está activo en Firebase Authentication.',
    'network-request-failed' => 'No hay conexión con Firebase.',
    _ => 'No se pudo completar el acceso. Inténtalo nuevamente.',
  };
}

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF176B56),
    brightness: brightness,
    surface: dark ? const Color(0xFF101412) : const Color(0xFFF5F7F5),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF19201D) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF242B28) : const Color(0xFFF0F3F1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}

const navItems = [
  (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Inicio'),
  (Icons.apartment_outlined, Icons.apartment, 'Proyectos'),
  (Icons.receipt_long_outlined, Icons.receipt_long, 'Gastos'),
  (Icons.groups_outlined, Icons.groups, 'Personal'),
  (Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
  (Icons.grid_view_outlined, Icons.grid_view, 'Más'),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onTheme,
    required this.onSync,
    required this.onSignOut,
  });
  final VoidCallback onTheme;
  final Future<void> Function() onSync;
  final Future<void> Function() onSignOut;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      Dashboard(onExpense: () => openExpense(context)),
      const ProjectsPage(),
      const ExpensesPage(),
      const PersonnelPage(),
      const ReportsPage(),
      MorePage(
        onTheme: widget.onTheme,
        onSync: widget.onSync,
        onSignOut: widget.onSignOut,
      ),
    ];
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            SideNav(index: index, onSelect: (v) => setState(() => index = v)),
          Expanded(
            child: SafeArea(
              child: IndexedStack(index: index, children: pages),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (v) => setState(() => index = v),
              destinations: [
                for (final n in navItems)
                  NavigationDestination(
                    icon: Icon(n.$1),
                    selectedIcon: Icon(n.$2),
                    label: n.$3,
                  ),
              ],
            ),
      floatingActionButton: index == 0 || index == 2
          ? FloatingActionButton.extended(
              onPressed: () => openExpense(context),
              icon: const Icon(Icons.add),
              label: const Text('Registrar gasto'),
            )
          : null,
    );
  }
}

Future<void> openExpense(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const ExpenseForm(),
);

class SideNav extends StatelessWidget {
  const SideNav({super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final syncService = firebaseSyncService;
    final animation = syncService == null
        ? expensesController
        : Listenable.merge([expensesController, syncService]);
    return Container(
      width: 248,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Brand(),
                SizedBox(width: 12),
                Text(
                  'ObraFlow',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          for (var i = 0; i < navItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: ListTile(
                selected: i == index,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(i == index ? navItems[i].$2 : navItems[i].$1),
                title: Text(navItems[i].$3),
                onTap: () => onSelect(i),
              ),
            ),
          const Spacer(),
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_android_outlined, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      (syncService?.syncing ?? false)
                          ? syncService!.label
                          : expensesController.pendingSyncCount == 0
                          ? syncService?.label ?? 'Guardado en el celular'
                          : '${expensesController.pendingSyncCount} pendiente(s) de sincronizar',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 6),
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(
              FirebaseAuth.instance.currentUser?.email?.split('@').first ??
                  'Usuario',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Cuenta personal'),
          ),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.onExpense});
  final VoidCallback onExpense;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
    children: [
      Header(onExpense: onExpense),
      const SizedBox(height: 28),
      Text(
        'Vista general',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      const ProjectStatusFilter(),
      const SizedBox(height: 14),
      const MetricGrid(),
      const SizedBox(height: 20),
      const BudgetPulse(),
      const SizedBox(height: 20),
      const DashboardContent(),
    ],
  );
}

class ProjectStatusFilter extends StatelessWidget {
  const ProjectStatusFilter({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: expensesController,
    builder: (context, _) => SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'ACTIVE',
          label: Text('Activos'),
          icon: Icon(Icons.play_circle_outline),
        ),
        ButtonSegment(
          value: 'PAUSED',
          label: Text('Pausados'),
          icon: Icon(Icons.pause_circle_outline),
        ),
        ButtonSegment(
          value: 'ALL',
          label: Text('Todos'),
          icon: Icon(Icons.layers_outlined),
        ),
      ],
      selected: {expensesController.projectFilter},
      onSelectionChanged: (value) =>
          expensesController.setProjectFilter(value.first),
      showSelectedIcon: false,
    ),
  );
}

class Header extends StatelessWidget {
  const Header({super.key, required this.onExpense});
  final VoidCallback onExpense;
  @override
  Widget build(BuildContext context) {
    final roomy = MediaQuery.sizeOf(context).width >= 650;
    return Row(
      children: [
        if (!roomy) ...[const Brand(), const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Sábado, 15 de agosto',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9D5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'DEMO',
                      style: TextStyle(
                        color: Color(0xFF8A4316),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Buenos días, Marcelo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Buscar',
          onPressed: () =>
              showSearch(context: context, delegate: ExpenseSearch()),
          icon: const Icon(Icons.search),
        ),
        const SizedBox(width: 8),
        Badge(
          label: const Text('2'),
          child: IconButton.filledTonal(
            tooltip: 'Alertas',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ),
        if (roomy) ...[
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onExpense,
            icon: const Icon(Icons.add),
            label: const Text('Registrar gasto'),
          ),
        ],
      ],
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final count = w >= 1150
        ? 4
        : w >= 620
        ? 2
        : 1;
    return AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) {
        final projects = expensesController.filteredProjects;
        final budget = projects.fold<int>(
          0,
          (sum, project) => sum + project.budgetCents,
        );
        final spent = projects.fold<int>(
          0,
          (sum, project) =>
              sum + expensesController.projectExecutedCents(project),
        );
        final average = projects.isEmpty
            ? 0.0
            : projects.fold<double>(
                    0,
                    (sum, project) => sum + project.progress,
                  ) /
                  projects.length;
        final data = [
          (
            'Presupuesto total',
            formatMoney(budget),
            '${projects.length} proyectos activos',
            Icons.account_balance_wallet_outlined,
            const Color(0xFF176B56),
          ),
          (
            'Gasto acumulado',
            formatMoney(spent),
            '${expensesController.filteredExpenses.length} movimientos',
            Icons.payments_outlined,
            const Color(0xFFB25A21),
          ),
          (
            'Disponible',
            formatMoney(budget - spent),
            budget == 0
                ? 'Sin presupuesto'
                : '${((budget - spent) / budget * 100).clamp(0, 100).toStringAsFixed(1)}% por utilizar',
            Icons.savings_outlined,
            const Color(0xFF3567A8),
          ),
          (
            'Avance promedio',
            '${(average * 100).round()}%',
            'Según proyectos registrados',
            Icons.trending_up,
            const Color(0xFF7756A3),
          ),
        ];
        return GridView.count(
          crossAxisCount: count,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: count == 1 ? 2.8 : 2.05,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final d in data) MetricCard(data: d)],
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.data});
  final (String, String, String, IconData, Color) data;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: data.$5.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.$4, color: data.$5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.$1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.$2,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data.$3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: data.$5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BudgetPulse extends StatelessWidget {
  const BudgetPulse({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: expensesController,
    builder: (context, _) {
      final projects = expensesController.filteredProjects;
      final budget = projects.fold<int>(0, (sum, p) => sum + p.budgetCents);
      final spent = projects.fold<int>(
        0,
        (sum, p) => sum + expensesController.projectExecutedCents(p),
      );
      final used = budget == 0 ? 0.0 : spent / budget;
      final progress = projects.isEmpty
          ? 0.0
          : projects.fold<double>(0, (sum, p) => sum + p.progress) /
                projects.length;
      final projection = progress <= 0 ? spent : (spent / progress).round();
      final healthy = used <= progress || used < .8;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ritmo del presupuesto',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: healthy
                          ? const Color(0xFFE6F4EE)
                          : const Color(0xFFFFE9D5),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      healthy ? 'SALUDABLE' : 'REVISAR',
                      style: TextStyle(
                        color: healthy
                            ? const Color(0xFF176B56)
                            : const Color(0xFF8A4316),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: used.clamp(0, 1),
                  minHeight: 12,
                  backgroundColor: Color(0xFFE2E8E4),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MiniMetric(
                      'Consumido',
                      '${(used * 100).toStringAsFixed(1)}%',
                    ),
                  ),
                  Expanded(
                    child: MiniMetric(
                      'Avance de obra',
                      '${(progress * 100).round()}%',
                    ),
                  ),
                  Expanded(
                    child: MiniMetric(
                      'Proyección final',
                      formatMoney(projection),
                      end: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class MiniMetric extends StatelessWidget {
  const MiniMetric(this.label, this.value, {super.key, this.end = false});
  final String label, value;
  final bool end;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
    ],
  );
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({super.key});
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    if (wide) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: ProjectSummary()),
          SizedBox(width: 18),
          Expanded(flex: 4, child: RecentExpenses()),
        ],
      );
    }
    return const Column(
      children: [ProjectSummary(), SizedBox(height: 18), RecentExpenses()],
    );
  }
}

class ProjectSummary extends StatelessWidget {
  const ProjectSummary({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: expensesController,
    builder: (context, _) {
      final projects = expensesController.filteredProjects.take(4).toList();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SectionTitle(
                expensesController.projectFilter == 'ACTIVE'
                    ? 'Proyectos activos'
                    : expensesController.projectFilter == 'PAUSED'
                    ? 'Proyectos pausados'
                    : 'Todos los proyectos',
                'Ver todos',
              ),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No hay proyectos con este estado.'),
                ),
              for (var i = 0; i < projects.length; i++) ...[
                ProjectRow(
                  data: (
                    projects[i].name,
                    projects[i].location,
                    projects[i].progress,
                    projects[i].formattedSpent,
                    projects[i].formattedBudget,
                    const Color(0xFF176B56),
                  ),
                ),
                if (i < projects.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class ProjectRow extends StatelessWidget {
  const ProjectRow({super.key, required this.data});
  final (String, String, double, String, String, Color) data;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetail(name: data.$1, color: data.$6),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: data.$3,
                  strokeWidth: 5,
                  color: data.$6,
                  backgroundColor: data.$6.withValues(alpha: .12),
                ),
                Text(
                  '${(data.$3 * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.$1,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  data.$2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data.$4,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'de ${data.$5}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class RecentExpenses extends StatelessWidget {
  const RecentExpenses({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) {
        final expenses = expensesController.filteredExpenses.take(3);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SectionTitle('Últimos gastos', 'Historial'),
                if (expensesController.loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else
                  for (final expense in expenses)
                    ExpenseCompactRow(expense: expense),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2E5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFF934817),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pintura alcanzó el 82% de su presupuesto.',
                          style: TextStyle(
                            color: Color(0xFF743913),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ExpenseCompactRow extends StatelessWidget {
  const ExpenseCompactRow({super.key, required this.expense});

  final LocalExpense expense;

  @override
  Widget build(BuildContext context) {
    final color = expenseColor(expense.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(expenseIcon(expense.category), color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${expense.projectName} · ${expense.category.split(' · ').first}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            expense.formattedTotal,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.action, {super.key});
  final String title, action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
      TextButton(onPressed: () {}, child: Text(action)),
    ],
  );
}

class StandardPage extends StatelessWidget {
  const StandardPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: child,
      ),
    ],
  );
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});
  @override
  Widget build(BuildContext context) => StandardPage(
    title: 'Proyectos',
    subtitle: 'Crea una obra y define su presupuesto inicial.',
    child: AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const ProjectForm(),
              ),
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text('Nuevo proyecto'),
            ),
          ),
          const SizedBox(height: 14),
          for (final project in expensesController.projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LocalProjectCard(project: project),
            ),
        ],
      ),
    ),
  );
}

class LocalProjectCard extends StatelessWidget {
  const LocalProjectCard({super.key, required this.project});

  final LocalProject project;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProjectDetail(name: project.name, color: const Color(0xFF176B56)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.home_work_outlined),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        project.location.isEmpty
                            ? 'Sin ubicación registrada'
                            : project.location,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            projectStatusIcon(project.status),
                            size: 16,
                          ),
                          label: Text(projectStatusLabel(project.status)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (project.syncStatus == 'pending')
                  const Icon(Icons.cloud_upload_outlined, size: 19),
                PopupMenuButton<String>(
                  tooltip: 'Opciones del proyecto',
                  onSelected: (value) {
                    if (value == 'edit') {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => ProjectForm(project: project),
                      );
                    } else if (value == 'status') {
                      confirmProjectStatusChange(context, project);
                    } else if (value == 'delete') {
                      confirmProjectDeletion(context, project);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 10),
                          Text('Editar proyecto'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          Icon(
                            project.status == 'PAUSED'
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            project.status == 'PAUSED'
                                ? 'Reactivar proyecto'
                                : 'Pausar proyecto',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Eliminar proyecto',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: MiniMetric('Presupuesto', project.formattedBudget),
                ),
                Expanded(
                  child: MiniMetric(
                    'Gastado',
                    formatMoney(
                      expensesController.projectExecutedCents(project),
                    ),
                  ),
                ),
                MiniMetric(
                  'Disponible',
                  formatMoney(
                    project.budgetCents -
                        expensesController.projectExecutedCents(project),
                  ),
                  end: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value:
                    (project.budgetCents == 0
                            ? 0
                            : expensesController.projectExecutedCents(project) /
                                  project.budgetCents)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> confirmProjectDeletion(
  BuildContext context,
  LocalProject project,
) async {
  final expenseCount = expensesController.expenses
      .where((expense) => expense.projectName == project.name)
      .length;
  if (expenseCount > 0) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('No se puede eliminar'),
        content: Text(
          '${project.name} tiene $expenseCount gasto(s) asociado(s). '
          'Para proteger tus datos reales, mueve esos gastos a otro proyecto antes de eliminarlo.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
      title: const Text('¿Eliminar proyecto?'),
      content: Text(
        'Se eliminará “${project.name}”. Esta acción solo está disponible porque no tiene gastos asociados.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Eliminar proyecto'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final deleted = await expensesController.deleteProject(project);
  if (!context.mounted || deleted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'No se eliminó el proyecto porque ahora tiene gastos asociados.',
      ),
    ),
  );
}

class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key, this.project});
  final LocalProject? project;
  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

Future<void> confirmProjectStatusChange(
  BuildContext context,
  LocalProject project,
) async {
  final pausing = project.status != 'PAUSED';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        pausing ? Icons.pause_circle_outline : Icons.play_circle_outline,
      ),
      title: Text(pausing ? '¿Pausar proyecto?' : '¿Reactivar proyecto?'),
      content: Text(
        pausing
            ? '${project.name} dejará de aparecer en Gastos y Reportes hasta que lo reactives.'
            : '${project.name} volverá a estar disponible para registrar gastos y generar reportes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(pausing ? 'Sí, pausar' : 'Sí, reactivar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await expensesController.changeProjectStatus(
    project,
    pausing ? 'PAUSED' : 'ACTIVE',
  );
}

class _ProjectFormState extends State<ProjectForm> {
  late final TextEditingController name;
  late final TextEditingController location;
  late final TextEditingController budget;
  bool saving = false;
  late String status;

  bool get editing => widget.project != null;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.project?.name ?? '');
    location = TextEditingController(text: widget.project?.location ?? '');
    budget = TextEditingController(
      text: widget.project == null
          ? ''
          : (widget.project!.budgetCents / 100).toStringAsFixed(2),
    );
    status = widget.project?.status ?? 'ACTIVE';
  }

  @override
  void dispose() {
    name.dispose();
    location.dispose();
    budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            editing ? 'Editar proyecto' : 'Nuevo proyecto',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            editing
                ? 'Actualiza los datos y el presupuesto de la obra.'
                : 'Define el presupuesto inicial de la obra.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            autofocus: !editing,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del proyecto *',
              prefixIcon: Icon(Icons.home_work_outlined),
              hintText: 'Ej. Casa Vía a la Costa',
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(
                labelText: 'Estado',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'ACTIVE', child: Text('Activo')),
                DropdownMenuItem(value: 'PAUSED', child: Text('Pausado')),
                DropdownMenuItem(value: 'COMPLETED', child: Text('Completado')),
              ],
              onChanged: (value) => setState(() => status = value ?? status),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: location,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Ubicación',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: budget,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Presupuesto inicial *',
              prefixText: '\$ ',
              helperText: 'El valor se guardará en USD.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(editing ? 'Guardar cambios' : 'Crear proyecto'),
          ),
        ],
      ),
    ),
  );

  Future<void> save() async {
    final parsedBudget = double.tryParse(budget.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || parsedBudget == null || parsedBudget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ingresa un nombre y presupuesto válidos.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (editing) {
        await expensesController.updateProject(
          previous: widget.project!,
          name: name.text.trim(),
          location: location.text.trim(),
          budgetCents: (parsedBudget * 100).round(),
          status: status,
        );
      } else {
        await expensesController.addProject(
          name: name.text.trim(),
          location: location.text.trim(),
          budgetCents: (parsedBudget * 100).round(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing
                ? 'No se pudo actualizar el proyecto.'
                : 'No se pudo crear el proyecto.',
          ),
        ),
      );
    }
  }
}

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StandardPage(
      title: 'Gastos',
      subtitle: 'Solo proyectos activos · guardados localmente.',
      child: AnimatedBuilder(
        animation: expensesController,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar gasto, factura o proveedor...',
                  ),
                ),
                const SizedBox(height: 12),
                if (expensesController.loading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator(),
                  )
                else if (expensesController.activeExpenses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('No hay gastos en proyectos activos.'),
                  )
                else
                  for (final expense in expensesController.activeExpenses)
                    LocalExpenseTile(expense: expense),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LocalExpenseTile extends StatelessWidget {
  const LocalExpenseTile({super.key, required this.expense});

  final LocalExpense expense;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        shortDate(expense.expenseDate),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
    title: Row(
      children: [
        Expanded(
          child: Text(
            expense.description,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (expense.syncStatus == 'pending')
          const Tooltip(
            message: 'Pendiente de sincronizar con Firebase',
            child: Icon(Icons.cloud_upload_outlined, size: 17),
          ),
      ],
    ),
    subtitle: Text(
      '${expense.projectName} · ${expense.provider.isEmpty ? expense.category : expense.provider}${expense.invoiceNumber.isEmpty ? '' : ' · Factura ${expense.invoiceNumber}'}',
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              expense.formattedTotal,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              'IVA ${expense.taxRatePercent.toStringAsFixed(0)}% · ${expense.formattedTax}',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Opciones del gasto',
          onSelected: (value) async {
            if (value == 'edit') {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => ExpenseForm(expense: expense),
              );
            } else if (value == 'delete') {
              await confirmExpenseDeletion(context, expense);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 10),
                  Text('Editar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<void> confirmExpenseDeletion(
  BuildContext context,
  LocalExpense expense,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('¿Eliminar este gasto?'),
      content: Text(
        '${expense.description}\n${expense.projectName} · ${expense.formattedTotal}\n\nEsta acción descontará el valor del proyecto. El registro se conservará internamente para auditoría y futura sincronización.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sí, eliminar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await expensesController.deleteExpense(expense);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gasto eliminado correctamente.')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo eliminar el gasto.')),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? exporting;
  late DateTime endDate = _dateOnlyDay(DateTime.now());
  late DateTime startDate = _oneMonthBefore(endDate);

  List<LocalExpense> get monthlyExpenses =>
      expensesController.activeExpenses.where((expense) {
        final date = _dateOnlyDay(expense.expenseDate);
        return !date.isBefore(startDate) && !date.isAfter(endDate);
      }).toList();

  Map<String, int> get categoryTotals {
    final totals = <String, int>{};
    for (final expense in monthlyExpenses) {
      final group = expense.category.split(' · ').first;
      totals[group] = (totals[group] ?? 0) + expense.totalCents;
    }
    return totals;
  }

  int get monthlyTotal =>
      monthlyExpenses.fold(0, (total, expense) => total + expense.totalCents);

  @override
  Widget build(BuildContext context) => StandardPage(
    title: 'Reportes',
    subtitle: 'Resumen y detalle de compras entre dos fechas.',
    child: Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        context,
                        'Desde',
                        startDate,
                        () => selectDate(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                        context,
                        'Hasta',
                        endDate,
                        () => selectDate(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Distribución por categoría · ${formatMoney(monthlyTotal)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                if (categoryTotals.isEmpty)
                  const Text('No hay gastos registrados en este período.')
                else
                  for (final entry in categoryTotals.entries)
                    CategoryBar(
                      entry.key,
                      formatMoney(entry.value),
                      monthlyTotal == 0 ? 0 : entry.value / monthlyTotal,
                      entry.key == 'Materiales'
                          ? const Color(0xFF176B56)
                          : entry.key == 'Herramientas'
                          ? const Color(0xFFD97745)
                          : const Color(0xFF3567A8),
                    ),
                const Divider(height: 32),
                const Text(
                  'Exportar reporte',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Se incluirán ${monthlyExpenses.length} artículos de ${monthlyExpenses.map((e) => e.invoiceNumber).where((e) => e.isNotEmpty).toSet().length} factura(s).',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exporting == null
                            ? () => export('pdf')
                            : null,
                        icon: exporting == 'pdf'
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Exportar PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: exporting == null
                            ? () => export('xlsx')
                            : null,
                        icon: exporting == 'xlsx'
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_outlined),
                        label: const Text('Exportar Excel'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Android abrirá el menú Compartir para guardar o enviar el archivo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detalle de compras',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                for (final expense in monthlyExpenses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(expense.description),
                    subtitle: Text(
                      '${expense.invoiceNumber.isEmpty ? 'Sin factura' : 'Factura ${expense.invoiceNumber}'} · ${expense.quantity.toStringAsFixed(expense.quantity % 1 == 0 ? 0 : 2)} unidad(es) · ${expense.category}',
                    ),
                    trailing: Text(
                      formatMoney(expense.totalCents),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> selectDate(bool isStart) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isStart
          ? 'Fecha inicial del reporte'
          : 'Fecha final del reporte',
    );
    if (selected != null && mounted) {
      final normalized = _dateOnlyDay(selected);
      if (isStart && normalized.isAfter(endDate) ||
          !isStart && normalized.isBefore(startDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La fecha inicial no puede ser posterior a la fecha final.',
            ),
          ),
        );
        return;
      }
      setState(() {
        if (isStart) {
          startDate = normalized;
        } else {
          endDate = normalized;
        }
      });
    }
  }

  Future<void> export(String format) async {
    setState(() => exporting = format);
    try {
      final file = format == 'pdf'
          ? await ExportService.createPdf(
              expenses: monthlyExpenses,
              projects: expensesController.activeProjects,
              periodLabel:
                  '${formatFullDate(startDate)} - ${formatFullDate(endDate)}',
            )
          : await ExportService.createExcel(
              expenses: monthlyExpenses,
              projects: expensesController.activeProjects,
              periodLabel:
                  '${formatFullDate(startDate)} - ${formatFullDate(endDate)}',
            );
      await ExportService.shareFile(
        file,
        title: format == 'pdf'
            ? 'Reporte ObraFlow PDF'
            : 'Reporte ObraFlow Excel',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo exportar el reporte. Inténtalo nuevamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => exporting = null);
    }
  }
}

class CategoryBar extends StatelessWidget {
  const CategoryBar(
    this.label,
    this.amount,
    this.value,
    this.color, {
    super.key,
  });
  final String label, amount;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
      ],
    ),
  );
}

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.onTheme,
    required this.onSync,
    required this.onSignOut,
  });
  final VoidCallback onTheme;
  final Future<void> Function() onSync;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) {
    final syncService = firebaseSyncService;
    final animation = syncService == null
        ? expensesController
        : Listenable.merge([expensesController, syncService]);
    return StandardPage(
      title: 'Más',
      subtitle: 'Administración y preferencias.',
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Proveedores'),
              subtitle: const Text('Directorio para registrar gastos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProvidersPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.engineering_outlined),
              title: const Text('Trabajadores'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categorías'),
              subtitle: const Text('Crear y consultar categorías de gastos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Parámetros'),
              subtitle: const Text('IVA y valores generales'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ParametersPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Alertas de presupuesto'),
              trailing: const Badge(label: Text('2')),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Cambiar tema'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTheme,
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Configuración'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) => ListTile(
                leading: Icon(
                  syncService?.state == MobileSyncState.synced
                      ? Icons.cloud_done_outlined
                      : Icons.sync,
                ),
                title: const Text('Sincronización'),
                subtitle: Text(
                  expensesController.pendingSyncCount == 0
                      ? syncService?.label ?? 'Guardado en el celular'
                      : '${expensesController.pendingSyncCount} cambio(s) pendiente(s)',
                ),
                trailing: (syncService?.syncing ?? false)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onTap: (syncService?.syncing ?? false) ? null : onSync,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('¿Cerrar sesión?'),
                    content: const Text(
                      'Los datos locales permanecerán guardados en este celular.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await onSignOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  bool refreshing = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categorías'),
      actions: [
        IconButton(
          tooltip: 'Refrescar desde Firebase',
          onPressed: refreshing ? null : refresh,
          icon: refreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const CategoryForm(),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Nueva categoría'),
    ),
    body: AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              'Se cargan desde la caché durante 24 horas. Usa refrescar si hiciste cambios desde otro dispositivo.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              expensesController.categoriesFetchedAt == null
                  ? 'Caché local inicial'
                  : 'Última carga: ${formatFullDate(expensesController.categoriesFetchedAt!)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Grupo')),
                    DataColumn(label: Text('Categoría')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: [
                    for (final category in expensesController.categories)
                      DataRow(
                        cells: [
                          DataCell(Text(category.groupName)),
                          DataCell(Text(category.name)),
                          DataCell(
                            Text(
                              category.syncStatus == 'pending'
                                  ? 'Pendiente'
                                  : 'Disponible',
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Editar categoría',
                                  onPressed: () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) =>
                                        CategoryForm(category: category),
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar categoría',
                                  onPressed: () => delete(category),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => refreshing = true);
    final success = await firebaseSyncService?.sync(
      user.uid,
      forceCategories: true,
    );
    await expensesController.reload();
    if (!mounted) return;
    setState(() => refreshing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success == true
              ? 'Categorías actualizadas desde Firebase.'
              : 'No se pudo refrescar. Se conserva la caché local.',
        ),
      ),
    );
  }

  Future<void> delete(LocalCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar categoría?'),
        content: Text(
          '“${category.fullName}” dejará de aparecer en gastos nuevos. Los gastos anteriores conservarán su categoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await expensesController.deleteCategory(category);
  }
}

class ProvidersPage extends StatelessWidget {
  const ProvidersPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proveedores')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const ProviderForm(),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Nuevo proveedor'),
    ),
    body: AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text(
            'El proveedor es opcional. El selector de gastos inicia vacío.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          if (expensesController.providers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.storefront_outlined, size: 42),
                    SizedBox(height: 12),
                    Text(
                      'Todavía no hay proveedores',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 5),
                    Text('Crea el primero cuando lo necesites.'),
                  ],
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Proveedor')),
                    DataColumn(label: Text('Contacto')),
                    DataColumn(label: Text('Teléfono')),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: [
                    for (final provider in expensesController.providers)
                      DataRow(
                        cells: [
                          DataCell(Text(provider.name)),
                          DataCell(Text(provider.contact)),
                          DataCell(Text(provider.phone)),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Editar proveedor',
                                  onPressed: () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) =>
                                        ProviderForm(provider: provider),
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar proveedor',
                                  onPressed: () =>
                                      _deleteProvider(context, provider),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _deleteProvider(
    BuildContext context,
    LocalProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar proveedor?'),
        content: Text(
          '“${provider.name}” dejará de aparecer en gastos nuevos. Los gastos anteriores no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await expensesController.deleteProvider(provider);
  }
}

class ParametersPage extends StatefulWidget {
  const ParametersPage({super.key});

  @override
  State<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends State<ParametersPage> {
  late final TextEditingController vat;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    vat = TextEditingController(
      text: expensesController.vatRatePercent.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    vat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Parámetros')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Impuestos',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Este porcentaje se propone al crear un gasto. Cada gasto conserva el IVA con el que fue guardado.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: vat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'IVA predeterminado',
                    suffixText: '%',
                    prefixIcon: Icon(Icons.percent),
                    helperText: 'Admite valores entre 0 y 100.',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar parámetros'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> save() async {
    final value = double.tryParse(vat.text.trim().replaceAll(',', '.'));
    if (value == null || value < 0 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un IVA válido entre 0 y 100.')),
      );
      return;
    }
    setState(() => saving = true);
    await expensesController.setVatRatePercent(value);
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('IVA guardado en este dispositivo.')),
    );
  }
}

class CategoryForm extends StatefulWidget {
  const CategoryForm({super.key, this.category});
  final LocalCategory? category;
  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  late final TextEditingController name;
  late String group;
  bool saving = false;

  bool get editing => widget.category != null;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.category?.name ?? '');
    group = widget.category?.groupName ?? 'Materiales';
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing ? 'Editar categoría' : 'Nueva categoría',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: group,
          decoration: const InputDecoration(
            labelText: 'Grupo *',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
          items: const ['Materiales', 'Mano de obra', 'Otros']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (value) {
            if (value != null) group = value;
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            prefixIcon: Icon(Icons.category_outlined),
            hintText: 'Ej. Impermeabilizantes',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(editing ? 'Guardar cambios' : 'Guardar categoría'),
        ),
      ],
    ),
  );

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el nombre de la categoría.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (editing) {
        await expensesController.updateCategory(
          previous: widget.category!,
          name: name.text.trim(),
          groupName: group,
        );
      } else {
        await expensesController.addCategory(
          name: name.text.trim(),
          groupName: group,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La categoría ya existe o no pudo guardarse.'),
        ),
      );
    }
  }
}

class ProviderForm extends StatefulWidget {
  const ProviderForm({super.key, this.provider});
  final LocalProvider? provider;

  @override
  State<ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<ProviderForm> {
  late final TextEditingController name;
  late final TextEditingController contact;
  late final TextEditingController phone;
  bool saving = false;

  bool get editing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.provider?.name ?? '');
    contact = TextEditingController(text: widget.provider?.contact ?? '');
    phone = TextEditingController(text: widget.provider?.phone ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing ? 'Editar proveedor' : 'Nuevo proveedor',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre o razón social *',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: contact,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Persona de contacto',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(editing ? 'Guardar cambios' : 'Guardar proveedor'),
        ),
      ],
    ),
  );

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el nombre del proveedor.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (editing) {
        await expensesController.updateProvider(
          previous: widget.provider!,
          name: name.text.trim(),
          contact: contact.text.trim(),
          phone: phone.text.trim(),
        );
      } else {
        await expensesController.addProvider(
          name: name.text.trim(),
          contact: contact.text.trim(),
          phone: phone.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El proveedor ya existe o no pudo guardarse.'),
        ),
      );
    }
  }
}

class ProjectDetail extends StatelessWidget {
  const ProjectDetail({super.key, required this.name, required this.color});
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: .75)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SALUD FINANCIERA',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Dentro del presupuesto',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: LightMetric('Gastado', '\$38,420')),
                  Expanded(child: LightMetric('Disponible', '\$21,580')),
                  LightMetric('Avance', '63%'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Presupuesto por etapa',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CategoryBar('Cimentación', '\$6,230 / \$8,000', .78, color),
                CategoryBar('Estructura', '\$11,400 / \$15,000', .76, color),
                const CategoryBar(
                  'Pintura',
                  '\$3,280 / \$4,000',
                  .82,
                  Color(0xFFB25A21),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class LightMetric extends StatelessWidget {
  const LightMetric(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, this.expense});
  final LocalExpense? expense;
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  late final TextEditingController quantity;
  late final TextEditingController price;
  late final TextEditingController description;
  late final TextEditingController invoiceNumber;
  late String project;
  late String category;
  late String provider;
  late bool applyVat;
  late DateTime expenseDate;
  bool saving = false;
  bool get editing => widget.expense != null;
  double get subtotal =>
      (double.tryParse(quantity.text) ?? 0) *
      (double.tryParse(price.text) ?? 0);
  double get tax =>
      applyVat ? subtotal * expensesController.vatRatePercent / 100 : 0;
  double get total => subtotal + tax;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    quantity = TextEditingController(
      text: expense?.quantity.toString() ?? '100',
    );
    price = TextEditingController(
      text: expense == null
          ? '8.20'
          : (expense.unitPriceCents / 100).toStringAsFixed(2),
    );
    description = TextEditingController(
      text: expense?.description ?? 'Cemento Holcim',
    );
    invoiceNumber = TextEditingController(text: expense?.invoiceNumber ?? '');
    provider = expense?.provider ?? '';
    project =
        expense?.projectName ??
        expensesController.activeProjects.firstOrNull?.name ??
        '';
    category =
        expense?.category ??
        expensesController.categories.firstOrNull?.fullName ??
        '';
    applyVat = expense == null ? true : expense.taxRateBps > 0;
    final initialDate = expense?.expenseDate ?? DateTime.now();
    expenseDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );
  }

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    description.dispose();
    invoiceNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Align(
      alignment: wide ? Alignment.centerRight : Alignment.bottomCenter,
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: wide
            ? const BorderRadius.horizontal(left: Radius.circular(28))
            : const BorderRadius.vertical(top: Radius.circular(28)),
        child: SizedBox(
          width: wide ? 520 : double.infinity,
          height: wide
              ? double.infinity
              : MediaQuery.sizeOf(context).height * .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editing ? 'Editar gasto' : 'Registrar gasto',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            editing
                                ? 'Actualiza la información del movimiento'
                                : 'Completa los datos esenciales',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          expensesController.activeProjects.any(
                            (item) => item.name == project,
                          )
                          ? project
                          : expensesController.activeProjects.firstOrNull?.name,
                      decoration: const InputDecoration(
                        labelText: 'Proyecto *',
                        prefixIcon: Icon(Icons.home_work_outlined),
                      ),
                      items: expensesController.activeProjects
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.name,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) project = value;
                      },
                    ),
                    const SizedBox(height: 14),
                    SearchableSelectionField(
                      label: 'Categoría *',
                      value: category,
                      icon: Icons.category_outlined,
                      searchHint: 'Buscar categoría',
                      items: {
                        if (category.isNotEmpty) category,
                        ...expensesController.categories.map(
                          (item) => item.fullName,
                        ),
                      }.toList(),
                      onChanged: (value) => setState(() => category = value),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(
                        labelText: 'Descripción *',
                        prefixIcon: Icon(Icons.edit_note),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quantity,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                              suffixText: 'sacos',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Precio unitario',
                              prefixText: '\$ ',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SearchableSelectionField(
                      label: 'Proveedor',
                      value: provider,
                      icon: Icons.storefront_outlined,
                      searchHint: 'Buscar proveedor',
                      emptyLabel: 'Sin proveedor',
                      allowEmpty: true,
                      items: {
                        if (provider.isNotEmpty) provider,
                        ...expensesController.providers.map(
                          (item) => item.name,
                        ),
                      }.toList(),
                      onChanged: (value) => setState(() => provider = value),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: invoiceNumber,
                      decoration: const InputDecoration(
                        labelText: 'Número de factura',
                        prefixIcon: Icon(Icons.receipt_long_outlined),
                        hintText: 'Ej. 001-020-000380000',
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: pickExpenseDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha del gasto *',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(formatFullDate(expenseDate)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Tomar foto'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Adjuntar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aplicar IVA'),
                      subtitle: Text(
                        'Tasa configurada: ${expensesController.vatRatePercent.toStringAsFixed(2)}%',
                      ),
                      value: applyVat,
                      onChanged: (value) => setState(() => applyVat = value),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Subtotal: USD ${subtotal.toStringAsFixed(2)}',
                                ),
                                Text(
                                  'IVA ${applyVat ? expensesController.vatRatePercent.toStringAsFixed(2) : '0.00'}%: USD ${tax.toStringAsFixed(2)}',
                                ),
                                Text(
                                  'Total: USD ${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.calculate_outlined,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          editing ? 'Guardar cambios' : 'Guardar gasto',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> save() async {
    final parsedQuantity = double.tryParse(quantity.text.trim());
    final parsedPrice = double.tryParse(price.text.trim().replaceAll(',', '.'));
    if (project.isEmpty ||
        category.isEmpty ||
        description.text.trim().isEmpty ||
        parsedQuantity == null ||
        parsedQuantity <= 0 ||
        parsedPrice == null ||
        parsedPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa proyecto, categoría, descripción, cantidad y precio.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (editing) {
        await expensesController.updateExpense(
          previous: widget.expense!,
          projectName: project,
          category: category,
          description: description.text.trim(),
          provider: provider,
          invoiceNumber: invoiceNumber.text.trim(),
          quantity: parsedQuantity,
          unitPriceCents: (parsedPrice * 100).round(),
          taxRateBps: applyVat
              ? (expensesController.vatRatePercent * 100).round()
              : 0,
          expenseDate: expenseDate,
        );
      } else {
        await expensesController.addExpense(
          projectName: project,
          category: category,
          description: description.text.trim(),
          provider: provider,
          invoiceNumber: invoiceNumber.text.trim(),
          quantity: parsedQuantity,
          unitPriceCents: (parsedPrice * 100).round(),
          taxRateBps: applyVat
              ? (expensesController.vatRatePercent * 100).round()
              : 0,
          expenseDate: expenseDate,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            editing
                ? 'Gasto actualizado correctamente'
                : 'Gasto guardado en el celular',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el gasto. Inténtalo nuevamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> pickExpenseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Selecciona la fecha del gasto',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (selected != null && mounted) {
      setState(() => expenseDate = selected);
    }
  }
}

class SearchableSelectionField extends StatelessWidget {
  const SearchableSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
    required this.searchHint,
    this.allowEmpty = false,
    this.emptyLabel = 'Sin seleccionar',
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final IconData icon;
  final String searchHint;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _SearchableOptionsSheet(
          title: label.replaceAll(' *', ''),
          searchHint: searchHint,
          items: items,
          selected: value,
          allowEmpty: allowEmpty,
          emptyLabel: emptyLabel,
        ),
      );
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: const Icon(Icons.search),
      ),
      child: Text(
        value.isEmpty ? emptyLabel : value,
        style: value.isEmpty
            ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
            : null,
      ),
    ),
  );
}

class _SearchableOptionsSheet extends StatefulWidget {
  const _SearchableOptionsSheet({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.selected,
    required this.allowEmpty,
    required this.emptyLabel,
  });

  final String title;
  final String searchHint;
  final List<String> items;
  final String selected;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  State<_SearchableOptionsSheet> createState() =>
      _SearchableOptionsSheetState();
}

class _SearchableOptionsSheetState extends State<_SearchableOptionsSheet> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.text.trim().toLowerCase();
    final filtered =
        widget.items
            .where((item) => item.toLowerCase().contains(normalized))
            .toList()
          ..sort();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            query.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowEmpty)
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline),
                      title: Text(widget.emptyLabel),
                      trailing: widget.selected.isEmpty
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (final item in filtered)
                    ListTile(
                      leading: const Icon(Icons.label_outline),
                      title: Text(item),
                      trailing: item == widget.selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, item),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No hay coincidencias.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseSearch extends SearchDelegate<void> {
  final items = const [
    'Cemento Holcim · \$820',
    'Varillas de hierro · \$300',
    'Arena lavada · \$350',
    'Pago albañiles · \$500',
  ];
  @override
  String get searchFieldLabel => 'Buscar gastos, proveedores...';
  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => results();
  @override
  Widget buildSuggestions(BuildContext context) => results();
  Widget results() => ListView(
    children: [
      for (final e in items.where(
        (e) => e.toLowerCase().contains(query.toLowerCase()),
      ))
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(e),
          subtitle: const Text('Casa Ceibos'),
        ),
    ],
  );
}

IconData expenseIcon(String category) {
  if (category.startsWith('Mano de obra')) return Icons.engineering_outlined;
  if (category.contains('Transporte')) return Icons.local_shipping_outlined;
  return Icons.inventory_2_outlined;
}

Color expenseColor(String category) {
  if (category.startsWith('Mano de obra')) return const Color(0xFFB25A21);
  if (category.startsWith('Otros')) return const Color(0xFF7756A3);
  return const Color(0xFF3567A8);
}

String projectStatusLabel(String status) => switch (status) {
  'PAUSED' => 'Pausado',
  'COMPLETED' => 'Completado',
  _ => 'Activo',
};

IconData projectStatusIcon(String status) => switch (status) {
  'PAUSED' => Icons.pause_circle_outline,
  'COMPLETED' => Icons.check_circle_outline,
  _ => Icons.play_circle_outline,
};

String shortDate(DateTime date) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String formatFullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime _dateOnlyDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
DateTime _oneMonthBefore(DateTime value) {
  final year = value.month == 1 ? value.year - 1 : value.year;
  final month = value.month == 1 ? 12 : value.month - 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, value.day.clamp(1, lastDay));
}

Widget _dateField(
  BuildContext context,
  String label,
  DateTime value,
  VoidCallback onTap,
) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(12),
  child: InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.calendar_month_outlined),
      suffixIcon: const Icon(Icons.arrow_drop_down),
    ),
    child: Text(formatFullDate(value)),
  ),
);

String monthLabel(DateTime date) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String formatMoney(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final dollars = absolute ~/ 100;
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  final digits = dollars.toString();
  final formatted = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) formatted.write(',');
    formatted.write(digits[index]);
  }
  return '${negative ? '-' : ''}\$$formatted.$decimals';
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Image.asset(
      'assets/branding/obraflow-mark.png',
      fit: BoxFit.contain,
      semanticLabel: 'ObraFlow',
    ),
  );
}

class PersonnelPage extends StatelessWidget {
  const PersonnelPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: AnimatedBuilder(
      animation: expensesController,
      builder: (context, _) {
        final summary = expensesController.laborSummary;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal y jornales',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Text('Mano de obra devengada, anticipos y pagos'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const WorkerForm(),
                    ),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Trabajador'),
                  ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Resumen'),
                Tab(text: 'Personal'),
                Tab(text: 'Asistencia'),
                Tab(text: 'Pagos'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _LaborMetric(
                            'Activos',
                            '${expensesController.activeWorkers.length}',
                          ),
                          _LaborMetric(
                            'Devengado',
                            formatMoney(summary.earnedCents),
                          ),
                          _LaborMetric(
                            'Anticipos',
                            formatMoney(summary.advanceCents),
                          ),
                          _LaborMetric(
                            'Pendiente',
                            formatMoney(summary.pendingCents),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Separación financiera',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'La asistencia aumenta el costo ejecutado. Anticipos y pagos afectan caja, pero no vuelven a sumar el costo.',
                              ),
                              const Divider(height: 28),
                              _kv(
                                'Costo devengado',
                                formatMoney(summary.earnedCents),
                              ),
                              _kv(
                                'Pagos realizados',
                                formatMoney(summary.paymentCents),
                              ),
                              _kv(
                                'Crédito por compensar',
                                formatMoney(summary.advanceCreditCents),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  _WorkersList(),
                  _AttendanceList(),
                  _LaborPayments(summary: summary),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _LaborMetric extends StatelessWidget {
  const _LaborMetric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _kv(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  ),
);

class _WorkersList extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const RoleForm(),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Configurar oficio'),
        ),
      ),
      if (expensesController.workers.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aún no hay trabajadores. Registra el primero para comenzar.',
            ),
          ),
        ),
      for (final worker in expensesController.workers)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(worker.fullName.isEmpty ? '?' : worker.fullName[0]),
            ),
            title: Text(worker.fullName),
            subtitle: Text(
              '${expensesController.workerRoles.where((r) => r.clientId == worker.roleId).map((r) => r.name).firstOrNull ?? worker.roleId} · ${formatMoney(worker.defaultRateCents)}/día · ${worker.status == 'ACTIVE' ? 'Activo' : 'Inactivo'}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => WorkerForm(worker: worker),
                  );
                } else if (await _confirm(
                  context,
                  '¿${worker.status == 'ACTIVE' ? 'Desactivar' : 'Reactivar'} a ${worker.fullName}?',
                )) {
                  await expensesController.toggleWorker(worker);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    worker.status == 'ACTIVE' ? 'Desactivar' : 'Reactivar',
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _AttendanceList extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text('Una asistencia por trabajador, proyecto y fecha.'),
            ),
            FilledButton.icon(
              onPressed: expensesController.activeWorkers.isEmpty
                  ? null
                  : () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const AttendanceForm(),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Registrar'),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final item in expensesController.attendance)
              Card(
                child: ListTile(
                  title: Text(
                    expensesController.workers
                            .where((w) => w.clientId == item.workerId)
                            .map((w) => w.fullName)
                            .firstOrNull ??
                        'Trabajador',
                  ),
                  subtitle: Text(
                    '${formatFullDate(item.date)} · ${item.kind.name} · ${(item.allocationBps / 100).toStringAsFixed(0)}%',
                  ),
                  trailing: Text(
                    formatMoney(item.earnedCents),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _LaborPayments extends StatelessWidget {
  const _LaborPayments({required this.summary});
  final LaborSummary summary;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Wrap(
        spacing: 10,
        children: [
          FilledButton.icon(
            onPressed: expensesController.activeWorkers.isEmpty
                ? null
                : () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const AdvanceForm(),
                  ),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Anticipo'),
          ),
          OutlinedButton.icon(
            onPressed: expensesController.activeWorkers.isEmpty
                ? null
                : () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const WorkerPaymentForm(),
                  ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Pago'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _kv('Ganado', formatMoney(summary.earnedCents)),
              _kv('Anticipos aplicados', formatMoney(summary.advanceCents)),
              _kv('Pagos', formatMoney(summary.paymentCents)),
              const Divider(),
              _kv('Saldo pendiente', formatMoney(summary.pendingCents)),
            ],
          ),
        ),
      ),
      for (final p in expensesController.workerPayments)
        ListTile(
          title: Text(
            expensesController.workers
                    .where((w) => w.clientId == p.workerId)
                    .map((w) => w.fullName)
                    .firstOrNull ??
                'Trabajador',
          ),
          subtitle: Text(
            '${formatFullDate(p.date)} · ${p.method}${p.reference.isEmpty ? '' : ' · ${p.reference}'}',
          ),
          trailing: Text(formatMoney(p.amountCents)),
        ),
    ],
  );
}

class WorkerForm extends StatefulWidget {
  const WorkerForm({super.key, this.worker});
  final LocalWorker? worker;
  @override
  State<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends State<WorkerForm> {
  late final TextEditingController name = TextEditingController(
        text: widget.worker?.fullName ?? '',
      ),
      id = TextEditingController(text: widget.worker?.nationalId ?? ''),
      phone = TextEditingController(text: widget.worker?.phone ?? ''),
      rate = TextEditingController(
        text: widget.worker == null
            ? ''
            : (widget.worker!.defaultRateCents / 100).toStringAsFixed(2),
      ),
      notes = TextEditingController(text: widget.worker?.notes ?? '');
  late String role =
      expensesController.workerRoles.any(
        (r) => r.clientId == widget.worker?.roleId,
      )
      ? widget.worker!.roleId
      : expensesController.workerRoles.first.clientId;
  late DateTime start = widget.worker?.startDate ?? DateTime.now();
  late List<String> projects = [...?widget.worker?.projectIds];
  @override
  Widget build(BuildContext context) => _laborSheet(
    context,
    title: widget.worker == null ? 'Nuevo trabajador' : 'Editar trabajador',
    children: [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Nombres y apellidos *'),
      ),
      TextField(
        controller: id,
        decoration: const InputDecoration(labelText: 'Cédula (opcional)'),
      ),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Teléfono'),
      ),
      DropdownButtonFormField(
        initialValue: role,
        items: [
          for (final r in expensesController.workerRoles)
            DropdownMenuItem(value: r.clientId, child: Text(r.name)),
        ],
        onChanged: (v) => setState(() => role = v!),
        decoration: const InputDecoration(labelText: 'Oficio'),
      ),
      TextField(
        controller: rate,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Tarifa diaria USD *'),
      ),
      Text(
        'Proyectos asignados',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      for (final p in expensesController.activeProjects)
        CheckboxListTile(
          value: projects.contains(p.clientId),
          title: Text(p.name),
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(
            () => v! ? projects.add(p.clientId) : projects.remove(p.clientId),
          ),
        ),
      TextField(
        controller: notes,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Observaciones'),
      ),
      FilledButton(onPressed: save, child: const Text('Guardar trabajador')),
    ],
  );
  Future<void> save() async {
    final cents =
        ((double.tryParse(rate.text.replaceAll(',', '.')) ?? -1) * 100).round();
    if (name.text.trim().isEmpty || cents < 0) return;
    await expensesController.saveWorker(
      previous: widget.worker,
      fullName: name.text.trim(),
      nationalId: id.text.trim(),
      phone: phone.text.trim(),
      roleId: role,
      defaultRateCents: cents,
      startDate: start,
      notes: notes.text.trim(),
      projectIds: projects,
    );
    if (mounted) Navigator.pop(context);
  }
}

class RoleForm extends StatefulWidget {
  const RoleForm({super.key});
  @override
  State<RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends State<RoleForm> {
  final name = TextEditingController();
  @override
  Widget build(BuildContext context) => _laborSheet(
    context,
    title: 'Nuevo oficio',
    children: [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Nombre del oficio'),
      ),
      FilledButton(
        onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await expensesController.addWorkerRole(name.text);
          if (!context.mounted) return;
          Navigator.pop(context);
        },
        child: const Text('Guardar oficio'),
      ),
    ],
  );
}

class AttendanceForm extends StatefulWidget {
  const AttendanceForm({super.key});
  @override
  State<AttendanceForm> createState() => _AttendanceFormState();
}

class _AttendanceFormState extends State<AttendanceForm> {
  late String workerId = expensesController.activeWorkers.first.clientId,
      projectId = expensesController.activeProjects.first.clientId;
  DateTime date = DateTime.now();
  AttendanceKind kind = AttendanceKind.full;
  int allocation = 10000;
  final notes = TextEditingController();
  int get rate => expensesController.activeWorkers
      .firstWhere((w) => w.clientId == workerId)
      .defaultRateCents;
  @override
  Widget build(BuildContext context) => _laborSheet(
    context,
    title: 'Asistencia diaria',
    children: [
      DropdownButtonFormField(
        initialValue: workerId,
        items: [
          for (final w in expensesController.activeWorkers)
            DropdownMenuItem(value: w.clientId, child: Text(w.fullName)),
        ],
        onChanged: (v) => setState(() => workerId = v!),
        decoration: const InputDecoration(labelText: 'Trabajador'),
      ),
      DropdownButtonFormField(
        initialValue: projectId,
        items: [
          for (final p in expensesController.activeProjects)
            DropdownMenuItem(value: p.clientId, child: Text(p.name)),
        ],
        onChanged: (v) => setState(() => projectId = v!),
        decoration: const InputDecoration(labelText: 'Proyecto'),
      ),
      DropdownButtonFormField(
        initialValue: kind,
        items: const [
          DropdownMenuItem(
            value: AttendanceKind.full,
            child: Text('Día completo'),
          ),
          DropdownMenuItem(
            value: AttendanceKind.half,
            child: Text('Medio día'),
          ),
          DropdownMenuItem(
            value: AttendanceKind.absent,
            child: Text('Ausente'),
          ),
          DropdownMenuItem(value: AttendanceKind.rest, child: Text('Descanso')),
        ],
        onChanged: (v) => setState(() => kind = v!),
        decoration: const InputDecoration(labelText: 'Asistencia'),
      ),
      Slider(
        value: allocation / 10000,
        min: .01,
        max: 1,
        divisions: 99,
        label: '${(allocation / 100).round()}%',
        onChanged: (v) => setState(() => allocation = (v * 10000).round()),
      ),
      Text(
        'Ganado: ${formatMoney(calculateLaborCents(dailyRateCents: rate, attendance: kind, allocation: allocation / 10000))}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      TextField(
        controller: notes,
        decoration: const InputDecoration(labelText: 'Observaciones'),
      ),
      FilledButton(onPressed: save, child: const Text('Guardar asistencia')),
    ],
  );
  Future<void> save() async {
    try {
      await expensesController.saveAttendance(
        workerId: workerId,
        projectId: projectId,
        date: date,
        kind: kind,
        appliedRateCents: rate,
        allocationBps: allocation,
        notes: notes.text,
      );
      if (mounted) Navigator.pop(context);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class AdvanceForm extends StatefulWidget {
  const AdvanceForm({super.key});
  @override
  State<AdvanceForm> createState() => _AdvanceFormState();
}

class _AdvanceFormState extends State<AdvanceForm> {
  late String workerId = expensesController.activeWorkers.first.clientId,
      projectId = '';
  final amount = TextEditingController(),
      reference = TextEditingController(),
      notes = TextEditingController();
  String method = 'CASH';
  @override
  Widget build(BuildContext context) => _laborSheet(
    context,
    title: 'Registrar anticipo',
    children: [
      _workerDrop(workerId, (v) => setState(() => workerId = v)),
      _projectDrop(
        projectId,
        (v) => setState(() => projectId = v),
        optional: true,
      ),
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Monto USD'),
      ),
      DropdownButtonFormField(
        initialValue: method,
        items: const [
          DropdownMenuItem(value: 'CASH', child: Text('Efectivo')),
          DropdownMenuItem(value: 'TRANSFER', child: Text('Transferencia')),
        ],
        onChanged: (v) => setState(() => method = v!),
        decoration: const InputDecoration(labelText: 'Método'),
      ),
      TextField(
        controller: reference,
        decoration: const InputDecoration(labelText: 'Referencia'),
      ),
      TextField(
        controller: notes,
        decoration: const InputDecoration(labelText: 'Observaciones'),
      ),
      FilledButton(onPressed: save, child: const Text('Guardar anticipo')),
    ],
  );
  Future<void> save() async {
    final cents =
        ((double.tryParse(amount.text.replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (cents <= 0) return;
    await expensesController.saveAdvance(
      workerId: workerId,
      projectId: projectId,
      date: DateTime.now(),
      amountCents: cents,
      method: method,
      reference: reference.text,
      notes: notes.text,
    );
    if (mounted) Navigator.pop(context);
  }
}

class WorkerPaymentForm extends StatefulWidget {
  const WorkerPaymentForm({super.key});
  @override
  State<WorkerPaymentForm> createState() => _WorkerPaymentFormState();
}

class _WorkerPaymentFormState extends State<WorkerPaymentForm> {
  late String workerId = expensesController.activeWorkers.first.clientId,
      projectId = '';
  final amount = TextEditingController(),
      reference = TextEditingController(),
      notes = TextEditingController();
  String method = 'CASH';
  DateTime start = DateTime.now().subtract(const Duration(days: 6)),
      end = DateTime.now();
  @override
  Widget build(BuildContext context) => _laborSheet(
    context,
    title: 'Registrar pago',
    children: [
      _workerDrop(workerId, (v) => setState(() => workerId = v)),
      _projectDrop(
        projectId,
        (v) => setState(() => projectId = v),
        optional: true,
      ),
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Monto USD'),
      ),
      DropdownButtonFormField(
        initialValue: method,
        items: const [
          DropdownMenuItem(value: 'CASH', child: Text('Efectivo')),
          DropdownMenuItem(value: 'TRANSFER', child: Text('Transferencia')),
        ],
        onChanged: (v) => setState(() => method = v!),
        decoration: const InputDecoration(labelText: 'Método'),
      ),
      TextField(
        controller: reference,
        decoration: const InputDecoration(labelText: 'Referencia única'),
      ),
      TextField(
        controller: notes,
        decoration: const InputDecoration(labelText: 'Observaciones'),
      ),
      FilledButton(onPressed: save, child: const Text('Guardar pago')),
    ],
  );
  Future<void> save() async {
    final cents =
        ((double.tryParse(amount.text.replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (cents <= 0) return;
    try {
      await expensesController.saveWorkerPayment(
        workerId: workerId,
        projectId: projectId,
        periodStart: start,
        periodEnd: end,
        amountCents: cents,
        method: method,
        reference: reference.text,
        notes: notes.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La referencia de pago ya existe.')),
        );
      }
    }
  }
}

Widget _workerDrop(String value, ValueChanged<String> onChanged) =>
    DropdownButtonFormField(
      initialValue: value,
      items: [
        for (final w in expensesController.activeWorkers)
          DropdownMenuItem(value: w.clientId, child: Text(w.fullName)),
      ],
      onChanged: (v) => onChanged(v!),
      decoration: const InputDecoration(labelText: 'Trabajador'),
    );
Widget _projectDrop(
  String value,
  ValueChanged<String> onChanged, {
  bool optional = false,
}) => DropdownButtonFormField(
  initialValue: value,
  items: [
    if (optional) const DropdownMenuItem(value: '', child: Text('General')),
    for (final p in expensesController.activeProjects)
      DropdownMenuItem(value: p.clientId, child: Text(p.name)),
  ],
  onChanged: (v) => onChanged(v!),
  decoration: const InputDecoration(labelText: 'Proyecto'),
);
Widget _laborSheet(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) => Padding(
  padding: EdgeInsets.only(
    left: 20,
    right: 20,
    top: 20,
    bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
  ),
  child: SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final child in children) ...[child, const SizedBox(height: 12)],
      ],
    ),
  ),
);
Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;
