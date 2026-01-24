# Real-Time State Management Guide

## Overview

Tapix uses a reactive state management pattern combining **Drift streams** with **Flutter Bloc** to automatically update the UI whenever database changes occur. This eliminates manual refresh requirements throughout the application.

## Architecture

```
Database (Drift) → DAOs → Repository → RealtimeService → RealtimeBloc → UI
                                              ↓
                                    Stream subscriptions with:
                                    - Debouncing
                                    - Error handling
                                    - Retry logic
                                    - Memory management
```

## Core Components

### 1. RealtimeService

Located at: `lib/core/services/realtime_service.dart`

The `RealtimeService` manages database streams with:
- **Debouncing**: Prevents rapid successive emissions
- **Error handling**: Catches and reports stream errors
- **Retry logic**: Automatic reconnection with exponential backoff
- **Platform adaptation**: Different configurations for Web vs Native

```dart
final service = RealtimeService(database);

// Watch all products
final stream = service.watchProducts();

// Watch specific customer
final customerStream = service.watchCustomer(customerId);

// Clean up when done
service.dispose();
```

### 2. RealtimeBloc

Located at: `lib/core/bloc/realtime_bloc.dart`

Abstract base class providing:
- Automatic stream subscription on initialization
- Stream cancellation on disposal
- Built-in loading, success, and error states
- Optimistic update support with rollback

#### States

| State | Description |
|-------|-------------|
| `RealtimeInitial` | Before any data is loaded |
| `RealtimeLoading` | Waiting for initial data or refresh |
| `RealtimeSuccess` | Data loaded successfully |
| `RealtimeError` | Stream error with optional previous data |
| `RealtimeOptimistic` | Optimistic update pending confirmation |

#### Events

| Event | Description |
|-------|-------------|
| `RealtimeDataUpdated` | Stream emitted new data |
| `RealtimeErrorOccurred` | Stream encountered an error |
| `RealtimeRefreshRequested` | Manual refresh triggered |
| `RealtimeOptimisticUpdate` | Start optimistic update |
| `RealtimeOptimisticConfirmed` | Confirm optimistic update succeeded |
| `RealtimeOptimisticRollback` | Rollback optimistic update |

## Creating a New RealtimeBloc

### Step 1: Define Your Events

```dart
abstract class ProductsEvent extends RealtimeEvent {
  const ProductsEvent();
}

class ProductCreateRequested extends ProductsEvent {
  final String name;
  const ProductCreateRequested(this.name);
}
```

### Step 2: Extend RealtimeBloc

```dart
class ProductsBloc extends RealtimeBloc<List<Product>, ProductsEvent> {
  final ProductRepository _repository;

  ProductsBloc(this._repository) : super() {
    registerEventHandlers();
  }

  @override
  Stream<List<Product>> get dataStream => _repository.watchAllProducts();

  @override
  void registerEventHandlers() {
    on<ProductCreateRequested>(_onProductCreate);
  }

  Future<void> _onProductCreate(
    ProductCreateRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    await _repository.createProduct(name: event.name);
    // Stream will automatically emit updated data
  }
}
```

### Step 3: Use in UI

```dart
BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
  builder: (context, state) {
    if (state is RealtimeLoading) {
      return CircularProgressIndicator();
    }
    if (state is RealtimeSuccess<List<Product>>) {
      return ListView.builder(
        itemCount: state.data.length,
        itemBuilder: (context, index) => ProductTile(state.data[index]),
      );
    }
    if (state is RealtimeError) {
      return ErrorWidget(state.error.toString());
    }
    return SizedBox.shrink();
  },
)
```

## Optimistic Updates

For better UX, update the UI immediately before the database operation completes:

```dart
Future<void> _onProductUpdate(
  ProductUpdateRequested event,
  Emitter<RealtimeState<List<Product>>> emit,
) async {
  final currentProducts = currentData;
  if (currentProducts == null) return;

  // Create optimistic data
  final optimisticProducts = currentProducts.map((p) {
    if (p.id == event.product.id) return event.product;
    return p;
  }).toList();

  // Perform optimistic update with automatic rollback on failure
  await performOptimisticUpdate(
    operationId: 'update_${event.product.id}',
    optimisticData: optimisticProducts,
    operation: () => _repository.updateProduct(event.product),
  );
}
```

## Performance Optimization

### 1. Debouncing

Configure debounce duration based on platform:

```dart
// Web platform (higher latency)
const webConfig = StreamConfig(
  debounceDuration: Duration(milliseconds: 100),
);

// Native platforms
const nativeConfig = StreamConfig(
  debounceDuration: Duration(milliseconds: 50),
);
```

### 2. Stream Limits

- **Web (WASM)**: Limit concurrent streams to <20
- **Native**: Can handle 50+ concurrent streams

### 3. Memory Management

Always dispose blocs when no longer needed:

```dart
@override
void dispose() {
  productsBloc.close();
  super.dispose();
}
```

## Troubleshooting

### Stream Not Emitting

1. Verify the stream source is correct
2. Check if debouncing is too aggressive
3. Ensure bloc is not disposed

### Memory Leaks

1. Always close blocs in widget dispose
2. Cancel stream subscriptions in service dispose
3. Use `RealtimeService.activeStreamCount` to monitor

### Slow Updates

1. Check debounce duration
2. Verify database indexes exist
3. Consider using `distinct()` on streams
4. Profile query performance

## Platform-Specific Notes

### Web (WASM)

- Uses OPFS/IndexedDB backend
- Higher latency for initial stream setup (~50ms vs ~10ms native)
- Fallback to polling if streams fail

### Native (Mobile/Desktop)

- Direct SQLite file streams
- Minimal latency
- Background processing supported

## Testing

Run the test suite:

```bash
flutter test test/core/services/realtime_service_test.dart
flutter test test/core/bloc/realtime_bloc_test.dart
flutter test test/integration/realtime_updates_test.dart
flutter test test/features/products/bloc/products_bloc_test.dart
```

Performance benchmarks target:
- **Update latency**: <100ms from database change to UI update
- **Memory**: <10MB overhead for active streams
