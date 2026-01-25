import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/auth.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../di/injection_container.dart';
import 'route_permissions.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final AuthBloc _authBloc = sl<AuthBloc>();
  
  // Keys for tracking onboarding state
  static const String _hasSeenWelcomeKey = 'has_seen_welcome';
  
  // Session state (resets on app restart)
  static bool _hasCompletedSplash = false;
  static bool? _hasSeenWelcome;
  
  static Future<bool> hasSeenWelcome() async {
    if (_hasSeenWelcome != null) return _hasSeenWelcome!;
    final prefs = sl<SharedPreferences>();
    _hasSeenWelcome = prefs.getBool(_hasSeenWelcomeKey) ?? false;
    return _hasSeenWelcome!;
  }
  
  static Future<void> markWelcomeSeen() async {
    final prefs = sl<SharedPreferences>();
    await prefs.setBool(_hasSeenWelcomeKey, true);
    _hasSeenWelcome = true;
  }
  
  static void markSplashCompleted() {
    _hasCompletedSplash = true;
  }

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(_authBloc.stream),
    redirect: (context, state) async {
      final currentPath = state.uri.path;
      final authState = _authBloc.state;
      
      // Show splash on first app launch (session-based)
      if (!_hasCompletedSplash && currentPath != '/splash') {
        return '/splash';
      }
      
      // Allow splash route
      if (currentPath == '/splash') {
        return null;
      }
      
      // After splash, check if user has seen welcome screen
      final seenWelcome = await hasSeenWelcome();
      if (!seenWelcome && currentPath != '/welcome') {
        return '/welcome';
      }
      
      // Allow welcome route
      if (currentPath == '/welcome') {
        return null;
      }

      // After welcome, handle auth states
      // If still loading, stay on current route (will re-redirect when state changes)
      if (authState is AuthInitial || authState is AuthLoading) {
        // Don't show HomePage while loading - stay on a loading state
        // The GoRouterRefreshStream will trigger redirect when auth state changes
        return null;
      }

      // No users exist - go to setup screen to create first owner
      if (authState is AuthNeedsSetup) {
        if (currentPath == '/setup') {
          return null;
        }
        return '/setup';
      }

      // User is authenticated - go to dashboard
      if (authState is AuthAuthenticated) {
        final user = authState.user;
        final requiredRoles = RoutePermissions.map[currentPath];
        if (requiredRoles != null) {
          final hasAccess = requiredRoles.contains(user.role);
          if (!hasAccess) {
            return '/access-denied';
          }
        }

        // Redirect away from auth screens to dashboard
        if (currentPath == '/login' || currentPath == '/setup' || currentPath == '/') {
          return '/dashboard';
        }

        return null;
      }

      // AuthUnauthenticated or AuthError - go to login
      if (currentPath == '/login') {
        return null;
      }

      return '/login';
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => SplashScreen(
          onComplete: () {
            markSplashCompleted();
            router.go('/');
          },
        ),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => WelcomeScreen(
          onComplete: () async {
            await markWelcomeSeen();
            router.go('/');
          },
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: '/sales',
        builder: (context, state) => const PlaceholderScreen(title: 'Sales'),
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => const PlaceholderScreen(title: 'Customers'),
      ),
      GoRoute(
        path: '/suppliers',
        builder: (context, state) => const PlaceholderScreen(title: 'Suppliers'),
      ),
      GoRoute(
        path: '/purchases',
        builder: (context, state) => const PlaceholderScreen(title: 'Purchases'),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const PlaceholderScreen(title: 'Expenses'),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const PlaceholderScreen(title: 'Reports'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const PlaceholderScreen(title: 'Settings'),
      ),
      GoRoute(
        path: '/users',
        builder: (context, state) => const PlaceholderScreen(title: 'Users'),
      ),
      GoRoute(
        path: '/employees',
        builder: (context, state) => const PlaceholderScreen(title: 'Employees'),
      ),
      GoRoute(
        path: '/accounting',
        builder: (context, state) => const PlaceholderScreen(title: 'Accounting'),
      ),
      GoRoute(
        path: '/audit',
        builder: (context, state) => const PlaceholderScreen(title: 'Audit Logs'),
      ),
      GoRoute(
        path: '/access-denied',
        builder: (context, state) => const AccessDeniedScreen(
          message: 'You do not have permission to access this page.',
        ),
      ),
    ],
  );

}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title Screen')),
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Loading screen shown while auth state is being determined
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logos/logo.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
