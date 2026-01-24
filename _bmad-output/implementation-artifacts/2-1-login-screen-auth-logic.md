# Story 2.1: Login Screen & Auth Logic

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a User,
I want to log in with my username and password,
So that I can access the system securely.

## Acceptance Criteria

1. Login UI matches design specs (modern, clean)
2. Password hashing implemented (no plain text storage)
3. Session management with secure storage
4. Error handling for invalid credentials

## Tasks / Subtasks

- [x] Task 1: Create Login Screen UI (AC: 1)
  - [x] Subtask 1.1: Design modern login interface with username/password fields
  - [x] Subtask 1.2: Add remember me checkbox
  - [x] Subtask 1.3: Implement loading states during authentication
  - [x] Subtask 1.4: Add forgot password link (placeholder for future)
  - [x] Subtask 1.5: Configure AuthWrapper with smart first-account flow (shows Setup screen if no users exist)
- [x] Task 2: Implement Authentication Logic (AC: 2, 3, 4)
  - [x] Subtask 2.1: Create password hashing service using bcrypt (v1.2.0)
  - [x] Subtask 2.2: Implement secure session storage using flutter_secure_storage (v9.2.4)
  - [x] Subtask 2.3: Create AuthBloc with login state management (AuthInitial, AuthLoading, AuthNeedsSetup, AuthUnauthenticated, AuthAuthenticated, AuthError)
  - [x] Subtask 2.4: Add error handling for invalid credentials with SnackBar feedback
  - [x] Subtask 2.5: Implement session timeout validation (24h configurable)
  - [x] Subtask 2.6: Register AuthBloc, AuthRepository, PasswordService, SessionService in DI container
- [x] Task 3: Integration with Real-time Architecture (AC: 3)
  - [x] Subtask 3.1: AuthRepository uses StreamController for reactive user state
  - [x] Subtask 3.2: AuthBloc subscribes to user stream for cross-app updates
  - [x] Subtask 3.3: SessionService validates session on app restart
- [x] Task 4: Role-Based Access Control Integration
  - [x] Subtask 4.1: Implement PermissionService with role matrix (Owner/Manager/Cashier/Salesperson)
  - [x] Subtask 4.2: Create PermissionGate and RoleGate widgets for protected UI
  - [x] Subtask 4.3: Test role-based permissions (19 permission tests passing)
- [x] Task 5: Testing Implementation
  - [x] Subtask 5.1: Unit tests for AuthBloc login/logout flows (8 bloc tests)
  - [x] Subtask 5.2: Widget tests for AuthWrapper states (3 tests)
  - [x] Subtask 5.3: Unit tests for PasswordService and PermissionService (36 auth tests total)

## Dev Notes

### CRITICAL ARCHITECTURE REQUIREMENTS
- **Clean Architecture**: lib/features/auth/ with data/domain/presentation layers
- **Bloc Pattern**: AuthBloc extends RealtimeBloc with stream subscriptions
- **Database**: Use existing Users table schema (id, username, passwordHash, role, employeeId, isActive, createdAt, updatedAt, lastLoginAt)
- **DI Integration**: Register services in lib/core/di/injection_container.dart
- **Router**: GoRouter integration with '/login' route and auth guards
- **Multi-platform**: Android, iOS, Windows, Web, Linux, macOS support
- **Languages**: English, Arabic (RTL), French with easy_localization
- **Themes**: Light/Dark with flex_color_scheme semantic colors

### Authentication Flow Architecture
```
LoginScreen -> AuthBloc -> AuthRepository -> Drift Database -> RealtimeService -> UI Updates
```

### Security Implementation Requirements
- **Password Hashing**: bcrypt package v1.0.0+ with proper salt rounds
- **Session Storage**: flutter_secure_storage v9.0.0+ for token persistence
- **Auto-logout**: Configurable timeout with background detection
- **Error Messages**: Generic messages without revealing system details
- **Field Mapping**: Use exact Users table fields (passwordHash, isActive as integer)
- **Package Versions**: Validate all packages against TAPIX_REBUILD_SPECIFICATION.md

### Database Schema Integration
- **Users Table**: Use existing Drift schema from lib/core/database/tables/users.dart
- **Fields**: id, username, passwordHash, role, employeeId, isActive, createdAt, updatedAt, lastLoginAt
- **Field Types**: passwordHash (Text), isActive (Int with default 1), role (Text: owner/manager/cashier/salesperson)
- **Compatibility**: Must maintain existing schema structure and relationships

### Real-time State Management
- **AuthBloc Pattern**: Extend RealtimeBloc<User, AuthEvent> with constructor: `AuthBloc(this._repository) : super(const RealtimeLoading())`
- **Stream Subscription**: Override `get dataStream` to watch user session changes
- **State Updates**: Session changes trigger immediate UI updates across all screens
- **Reference**: Follow lib/core/bloc/realtime_bloc.dart established pattern

### UI/UX Requirements
- **Design**: Modern, clean interface matching app theme
- **Responsive**: Mobile/tablet/desktop layouts (320px+, 768px+, 1024px+)
- **Themes**: Light/Dark with semantic colors (Green=Success, Red=Error, Orange=Warning)
- **Localization**: Arabic RTL support with easy_localization keys (auth.login_title, auth.username_hint, etc.)
- **States**: Loading skeletons, error states, success feedback
- **Navigation**: Integrate with GoRouter for protected routes

### Project Structure Notes

**File Organization:**
```
lib/features/auth/
├── data/
│   ├── repositories/auth_repository.dart
│   ├── datasources/auth_local_datasource.dart
│   └── models/user_model.dart
├── domain/
│   ├── entities/user.dart
│   ├── repositories/auth_repository.dart
│   └── usecases/login_usecase.dart
└── presentation/
    ├── bloc/auth_bloc.dart
    ├── screens/login_screen.dart
    └── widgets/auth_form.dart
```

**Dependencies:** EPIC-01 infrastructure complete
**Integration:** DI container registration following existing pattern
**No Conflicts**: Builds upon established architecture

### References

- [Source: TAPIX_REBUILD_SPECIFICATION.md#5.1 Authentication Module]
- [Source: TAPIX_IMPLEMENTATION_CHECKLIST.md#Phase 3 AUTH MODULE]
- [Source: TAPIX_EPICS_AND_STORIES.md#EPIC-02 Authentication]
- [Source: TAPIX_REBUILD_SPECIFICATION.md#4.1 Core Dependencies]
- [Source: lib/core/database/tables/users.dart - Schema Reference]
- [Source: lib/core/bloc/realtime_bloc.dart - RealtimeBloc Pattern]
- [Source: lib/core/di/injection_container.dart - DI Pattern]

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5) - Ultimate Story Context Engine

### Debug Log References

- Story creation workflow: _bmad/bmm/workflows/4-implementation/create-story/workflow.yaml
- Template reference: _bmad/bmm/workflows/4-implementation/create-story/template.md
- Sprint status tracking: _bmad-output/implementation-artifacts/sprint-status.yaml

### Completion Notes List

- Comprehensive analysis of EPIC-01 infrastructure completed
- Authentication requirements extracted from multiple source documents
- Real-time architecture integration points identified
- Multi-platform and localization requirements documented
- Security best practices integrated from specification
- **SMART FIRST-ACCOUNT FLOW**: App checks if users exist; shows Setup screen to create owner account if none exist
- **IMPLEMENTATION COMPLETED (2026-01-24)**:
  - Login/Setup screens with modern UI, theme support, RTL support
  - bcrypt password hashing (12 salt rounds)
  - flutter_secure_storage for session persistence
  - AuthBloc with 6 states for complete auth flow
  - PermissionService with 4-tier role hierarchy
  - PermissionGate/RoleGate widgets for UI protection
  - 36 auth-specific tests + 148 total tests passing

### File List

**Story & Planning:**
- Story file: _bmad-output/implementation-artifacts/2-1-login-screen-auth-logic.md
- Sprint tracking: _bmad-output/implementation-artifacts/sprint-status.yaml

**New Auth Feature Files:**
- lib/features/auth/auth.dart (barrel export)
- lib/features/auth/domain/entities/user_entity.dart
- lib/features/auth/domain/repositories/auth_repository_interface.dart
- lib/features/auth/data/repositories/auth_repository.dart
- lib/features/auth/data/services/password_service.dart
- lib/features/auth/data/services/session_service.dart
- lib/features/auth/data/services/permission_service.dart
- lib/features/auth/presentation/bloc/auth_bloc.dart
- lib/features/auth/presentation/bloc/auth_event.dart
- lib/features/auth/presentation/bloc/auth_state.dart
- lib/features/auth/presentation/screens/login_screen.dart
- lib/features/auth/presentation/screens/setup_screen.dart
- lib/features/auth/presentation/widgets/auth_text_field.dart
- lib/features/auth/presentation/widgets/auth_wrapper.dart
- lib/features/auth/presentation/widgets/permission_gate.dart

**Modified Files:**
- lib/core/di/injection_container.dart (added auth DI)
- lib/main.dart (added AuthBloc provider and AuthWrapper)
- pubspec.yaml (added bcrypt, flutter_secure_storage, equatable)
- assets/translations/en.json (auth translations)
- assets/translations/ar.json (auth translations)
- assets/translations/fr.json (auth translations)

**Test Files:**
- test/features/auth/presentation/bloc/auth_bloc_test.dart
- test/features/auth/data/services/password_service_test.dart
- test/features/auth/data/services/permission_service_test.dart
- test/features/auth/domain/entities/user_entity_test.dart
- test/widget_test.dart (updated for auth flow)
