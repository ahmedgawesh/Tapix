import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth.dart';
import '../../features/auth/domain/entities/user_entity.dart';
import '../di/injection_container.dart';
import 'route_permissions.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final authBloc = sl<AuthBloc>();
      final authState = authBloc.state;
      
      // Check authentication status
      if (authState is! AuthAuthenticated) {
        // Allow access to login and setup routes
        if (state.uri.path == '/login' || state.uri.path == '/setup') {
          return null;
        }
        return '/login';
      }

      final user = authState.user;
      
      // Check permissions for the route
      final requiredRoles = RoutePermissions.map[state.uri.path];
      if (requiredRoles != null) {
        final permissionService = sl<PermissionService>();
        if (!permissionService.isRoleAtLeast(user, requiredRoles.last)) { // Simplified check, ideally check exact role match or min level
           // Better check: does user have ANY of the allowed roles?
           bool hasAccess = false;
           for (final role in requiredRoles) {
             if (user.role == role) {
               hasAccess = true;
               break;
             }
           }
           if (!hasAccess) {
             // Check if it's a hierarchy check (e.g. manager+ can access)
             // For simplicity in this implementation, we use the list as "allowed roles".
             // If the list is [Owner, Manager], then only they can access.
             return '/access-denied';
           }
        }
      }

      // If user is authenticated but trying to access login/setup
      if (state.uri.path == '/login' || state.uri.path == '/setup') {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
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
        builder: (context, state) => const PlaceholderScreen(title: 'Dashboard'),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const PlaceholderScreen(title: 'Products'),
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

  // Single source of truth for route permissions
  static final Map<String, List<UserRole>> _routePermissions = {
    '/dashboard': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/products': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/sales': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/customers': [UserRole.owner, UserRole.manager, UserRole.cashier],
    '/suppliers': [UserRole.owner, UserRole.manager],
    '/purchases': [UserRole.owner, UserRole.manager],
    '/expenses': [UserRole.owner, UserRole.manager],
    '/reports': [UserRole.owner, UserRole.manager],
    '/settings': [UserRole.owner],
    '/users': [UserRole.owner],
    '/employees': [UserRole.owner, UserRole.manager],
    '/accounting': [UserRole.owner],
    '/audit': [UserRole.owner],
  };
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

// Temporary Home Page wrapper until full migration
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tapix Home')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NavButton(title: 'Dashboard', route: '/dashboard'),
          _NavButton(title: 'Products', route: '/products'),
          _NavButton(title: 'Sales', route: '/sales'),
          _NavButton(title: 'Settings', route: '/settings'),
          const Divider(),
          ListTile(
            title: const Text('Logout'),
            leading: const Icon(Icons.logout),
            onTap: () {
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String title;
  final String route;
  
  const _NavButton({required this.title, required this.route});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () => context.go(route),
      ),
    );
  }
}
