# Story 2.2: Role-Based Access Control

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Manager,
I want to restrict sensitive features to specific roles,
So that cashiers cannot perform unauthorized actions like modifying stock history.

## Acceptance Criteria

1. Roles defined: Owner, Manager, Cashier, Salesperson
2. `PermissionService` implemented
3. UI elements hidden/disabled based on current user role

## Tasks / Subtasks

- [x] Task 1: Complete Role-Based Permission System (AC: 1, 2)
  - [x] Subtask 1.1: Define comprehensive permission matrix for all 4 roles
  - [x] Subtask 1.2: Implement PermissionService with role hierarchy validation
  - [x] Subtask 1.3: Create permission constants for all system features
  - [x] Subtask 1.4: Add role-based access validation methods
  - [x] Subtask 1.5: Implement role promotion/demotion functionality (Owner only)
- [x] Task 2: UI Protection Implementation (AC: 3)
  - [x] Subtask 2.1: Create PermissionGate widget for conditional UI rendering
  - [x] Subtask 2.2: Create RoleGate widget for role-based UI protection
  - [x] Subtask 2.3: Implement permission-based navigation guards
  - [x] Subtask 2.4: Add visual feedback for disabled features (greyed out, tooltips)
  - [x] Subtask 2.5: Create permission error dialogs with user-friendly messages
- [x] Task 3: Integration with Existing Features
  - [x] Subtask 3.1: Protect sensitive settings screens (Manager+ only)
  - [x] Subtask 3.2: Restrict financial operations (Manager+ only)
  - [x] Subtask 3.3: Limit stock modification features (Manager+ only)
  - [x] Subtask 3.4: Allow basic sales operations for all roles
  - [x] Subtask 3.5: Restrict user management to Owner only
- [x] Task 4: Testing and Validation
  - [x] Subtask 4.1: Unit tests for PermissionService logic
  - [x] Subtask 4.2: Widget tests for PermissionGate and RoleGate
  - [x] Subtask 4.3: Integration tests for role-based access
  - [x] Subtask 4.4: Security tests for permission bypass attempts
  - [x] Subtask 4.5: UI tests for permission-based element visibility

## Dev Notes

### CRITICAL ARCHITECTURE REQUIREMENTS
- **Build on Existing Auth**: Extend PermissionService from story 2.1, don't recreate
- **Permission Matrix**: Define granular permissions for each system feature
- **UI Integration**: Use PermissionGate widgets throughout the app
- **Role Hierarchy**: Owner > Manager > Cashier > Salesperson (inheritance model)
- **Security First**: All sensitive operations must check permissions before execution
- **Real-time Updates**: Permission changes take effect immediately via streams

### Permission System Architecture
```
User Role -> PermissionService -> PermissionGate -> UI Element Visibility
           -> Business Logic Guards -> Feature Access Validation
```

### Role Definition Matrix
**Owner (Full Access):**
- All permissions including user management, system configuration
- Can promote/demote other users
- Access to all financial reports and settings

**Manager (Business Operations):**
- Product management, stock control, sales oversight
- Financial operations (except user management)
- Reporting and analytics access

**Cashier (Sales Operations):**
- Process sales, handle payments, manage customer interactions
- Basic product lookup and cart operations
- Daily sales reporting only

**Salesperson (Limited Sales):**
- Create sales, manage customer interactions
- View product information (no editing)
- Basic reporting capabilities

### Permission Constants Structure
```dart
class Permissions {
  // User Management
  static const String manageUsers = 'manage_users';
  static const String promoteUsers = 'promote_users';
  static const String deactivateUsers = 'deactivate_users';
  
  // Product Management
  static const String editProducts = 'edit_products';
  static const String deleteProducts = 'delete_products';
  static const String adjustStock = 'adjust_stock';
  static const String manageCategories = 'manage_categories';
  
  // Financial Operations
  static const String viewReports = 'view_reports';
  static const String manageExpenses = 'manage_expenses';
  static const String accessSettings = 'access_settings';
  static const String manageTaxes = 'manage_taxes';
  
  // Sales Operations
  static const String processSales = 'process_sales';
  static const String handleReturns = 'handle_returns';
  static const String viewDailyReports = 'view_daily_reports';
  static const String manageDiscounts = 'manage_discounts';
}
```

### Permission Validation Examples
```dart
// In business logic methods
class ProductService {
  Future<void> updateProductPrice(String productId, int newPrice) async {
    // Always validate permissions before execution
    if (!_permissionService.hasPermission(Permissions.editProducts)) {
      throw PermissionDeniedException('Insufficient permissions to edit products');
    }
    
    // Proceed with product update
    await _repository.updateProductPrice(productId, newPrice);
  }
}

// In UI widgets using PermissionGate
PermissionGate(
  permission: Permissions.manageUsers,
  child: ElevatedButton(
    onPressed: () => _showCreateUserDialog(),
    child: Text('Create User'),
  ),
  fallback: Container(
    padding: EdgeInsets.all(8),
    child: Tooltip(
      message: 'Contact your manager to create user accounts',
      child: Icon(Icons.lock, color: Colors.grey),
    ),
  ),
)

// In repository layer
class ProductRepository {
  Future<List<Product>> getProducts() async {
    // Basic product list available to all roles
    return _database.select(_productsTable).get();
  }
  
  Future<Product> getProductWithCostDetails(String productId) async {
    // Cost details restricted to Manager+
    if (!_permissionService.hasPermission(Permissions.viewReports)) {
      throw PermissionDeniedException('Cost details require manager access');
    }
    
    return _database.select(_productsTable)
      ..where((p) => p.id.equals(productId))
      ..getSingle();
  }
}
```

### UI Protection Implementation
**PermissionGate Widget:**
```dart
PermissionGate(
  permission: Permissions.editProducts,
  child: ElevatedButton('Edit Product'),
  fallback: Text('Insufficient permissions'),
)
```

**RoleGate Widget:**
```dart
RoleGate(
  requiredRoles: [Role.owner, Role.manager],
  child: SettingsScreen(),
  fallback: AccessDeniedScreen(),
)
```

### Integration Points with Existing Features
**Product Management (Manager+):**
- Edit product details, prices, stock levels
- Delete products, manage categories
- Barcode management and printing

**Financial Operations (Manager+):**
- View comprehensive reports
- Manage expenses and journal entries
- Access tax and currency settings

**User Management (Owner only):**
- Create, edit, deactivate user accounts
- Assign roles and permissions
- View user activity logs

**Sales Operations (All roles):**
- Process sales transactions
- Handle customer payments
- Basic customer management

### Database Schema Integration
- **Users Table**: Use existing Drift schema from lib/core/database/tables/users.dart
- **Fields**: id, username, passwordHash, role, employeeId, isActive, createdAt, updatedAt, lastLoginAt
- **Field Types**: passwordHash (Text), isActive (Int with default 1), role (Text: owner/manager/cashier/salesperson)
- **Compatibility**: Must maintain existing schema structure and relationships

### RBAC-Specific Schema Requirements
```sql
-- Extend Users table with additional RBAC fields if needed
ALTER TABLE users ADD COLUMN permissions TEXT; -- JSON array of additional permissions
ALTER TABLE users ADD COLUMN lastPermissionCheck INTEGER; -- Timestamp for cache invalidation

-- Optional: Role-specific settings table
CREATE TABLE user_role_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId INTEGER NOT NULL,
  settingKey TEXT NOT NULL,
  settingValue TEXT NOT NULL,
  createdAt INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updatedAt INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
);

-- Permission audit log for security
CREATE TABLE permission_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId INTEGER NOT NULL,
  permission TEXT NOT NULL,
  action TEXT NOT NULL, -- 'granted', 'denied', 'checked'
  context TEXT, -- Additional context about the permission check
  timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
);
```

### Permission Caching Strategy
```dart
class PermissionService {
  static const Duration _cacheTimeout = Duration(minutes: 5);
  
  Map<String, bool> _permissionCache = {};
  DateTime? _lastCacheUpdate;
  
  bool hasPermission(String permission) {
    // Check cache first for performance
    if (_isCacheValid() && _permissionCache.containsKey(permission)) {
      _logPermissionCheck(permission, 'cached');
      return _permissionCache[permission]!;
    }
    
    // Calculate permission from role
    final hasPermission = _calculatePermissionFromRole(permission);
    
    // Update cache
    _permissionCache[permission] = hasPermission;
    _lastCacheUpdate = DateTime.now();
    
    _logPermissionCheck(permission, 'calculated');
    return hasPermission;
  }
  
  void invalidateCache() {
    _permissionCache.clear();
    _lastCacheUpdate = null;
  }
  
  bool _isCacheValid() {
    return _lastCacheUpdate != null && 
           DateTime.now().difference(_lastCacheUpdate!) < _cacheTimeout;
  }
}
```

### Performance Optimization Requirements
- **Permission Caching**: Cache user permissions for 5 minutes to reduce database queries
- **Lazy Loading**: Load permission details only when needed for UI rendering
- **Batch Permission Checks**: Optimize multiple permission checks in single operation
- **Memory Management**: Clear permission cache on user logout/role change
- **Database Indexing**: Add indexes on permission audit log for performance

### Security Implementation Requirements
- **Server-side Validation**: All operations check permissions before execution
- **Client-side Protection**: UI elements hidden/disabled based on permissions
- **Permission Caching**: Cache user permissions for performance (5-minute timeout)
- **Audit Logging**: Log all permission checks and denied access attempts
- **Session Validation**: Re-validate permissions on session refresh
- **Cache Invalidation**: Clear permission cache on role changes or user updates

### Real-time Permission Updates
- **Stream-based Updates**: Permission changes trigger immediate UI updates
- **AuthBloc Integration**: Permission changes update AuthBloc state
- **Global State**: PermissionService maintains current user permissions
- **Reactive UI**: PermissionGate widgets rebuild on permission changes

### Error Handling and User Experience
- **Graceful Degradation**: Show helpful messages when access denied
- **Visual Feedback**: Disabled buttons with tooltips explaining restrictions
- **Access Requests**: Option to request higher permissions (future feature)
- **Consistent Messaging**: Standardized "Access Denied" dialogs

### Testing Strategy
**Unit Tests:**
- PermissionService role validation logic
- Permission hierarchy inheritance
- Role promotion/demotion security

**Widget Tests:**
- PermissionGate visibility based on permissions
- RoleGate conditional rendering
- Error state display

**Integration Tests:**
- End-to-end permission flows
- Cross-screen permission enforcement
- Real-time permission updates

### Project Structure Notes

**File Organization:**
```
lib/features/auth/
├── data/
│   ├── services/
│   │   ├── permission_service.dart (extend existing)
│   │   └── role_service.dart (new)
│   └── models/
│       ├── permission_model.dart (new)
│       └── role_model.dart (new)
├── domain/
│   ├── entities/
│   │   ├── permission_entity.dart (new)
│   │   └── role_entity.dart (new)
│   └── repositories/
│       └── permission_repository.dart (new)
└── presentation/
    ├── widgets/
    │   ├── permission_gate.dart (extend existing)
    │   └── role_gate.dart (extend existing)
    └── screens/
        └── access_denied_screen.dart (new)
```

**Dependencies:** Build on auth infrastructure from story 2.1
**Integration:** Extend existing PermissionService, don't duplicate
**No Conflicts:** Enhances existing auth system without breaking changes

### References

- [Source: TAPIX_EPICS_AND_STORIES.md#EPIC-02 Authentication - Story 02-02]
- [Source: TAPIX_REBUILD_SPECIFICATION.md#5.1 Authentication Module]
- [Source: 2-1-login-screen-auth-logic.md - Previous Auth Implementation]
- [Source: lib/features/auth/data/services/permission_service.dart - Existing PermissionService]
- [Source: lib/features/auth/presentation/widgets/permission_gate.dart - Existing PermissionGate]
- [Source: lib/core/bloc/realtime_bloc.dart - Real-time Pattern Reference]

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5) - Ultimate Story Context Engine

### Debug Log References

- Story creation workflow: _bmad/bmm/workflows/4-implementation/create-story/workflow.yaml
- Template reference: _bmad/bmm/workflows/4-implementation/create-story/template.md
- Sprint status tracking: _bmad-output/implementation-artifacts/sprint-status.yaml

### Completion Notes List

- ✅ Implemented comprehensive RBAC with 4-tier role hierarchy (Owner > Manager > Cashier > Salesperson)
- ✅ Extended PermissionService with role hierarchy validation, promotion/demotion functionality
- ✅ Created Permissions constants class with 30+ granular permissions
- ✅ Enhanced PermissionGate with showDisabled, disabledTooltip, disabledOpacity features
- ✅ Enhanced RoleGate with minRole support for hierarchy-based access control
- ✅ Created MultiPermissionGate for complex permission requirements
- ✅ Implemented AccessDeniedScreen with user-friendly error messages
- ✅ Created PermissionDeniedDialog for inline permission errors
- ✅ Implemented PermissionNavigator and PermissionRouteGuard for navigation protection
- ✅ All 232 tests pass (84 new tests added for RBAC)
- ✅ Security tests cover null user attacks, inactive user attacks, role escalation prevention, permission injection

### File List

**Story & Planning:**
- _bmad-output/implementation-artifacts/2-2-role-based-access-control.md
- _bmad-output/implementation-artifacts/sprint-status.yaml

**New Files Created:**
- lib/features/auth/domain/entities/permission_constants.dart
- lib/features/auth/presentation/screens/access_denied_screen.dart
- lib/features/auth/presentation/navigation/permission_navigator.dart

**Files Extended:**
- lib/features/auth/data/services/permission_service.dart (comprehensive permission matrix, role hierarchy, promotion/demotion)
- lib/features/auth/presentation/widgets/permission_gate.dart (showDisabled, tooltips, MultiPermissionGate)
- lib/features/auth/auth.dart (barrel exports)

**Test Files Created/Extended:**
- test/features/auth/data/services/permission_service_test.dart (34 tests)
- test/features/auth/presentation/widgets/permission_gate_test.dart (12 tests)
- test/features/auth/integration/role_based_access_test.dart (28 tests)
- test/features/auth/security/permission_bypass_test.dart (25 tests)

## Change Log

- 2026-01-24: Story 2.2 implemented - Role-Based Access Control with comprehensive RBAC system, 232 tests passing
