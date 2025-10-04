# Database Error Recovery Documentation

## Overview
The DatabaseService has been enhanced with comprehensive error recovery mechanisms to handle transient failures, connection issues, and database corruption scenarios.

## Features Added

### 1. Automatic Retry with Exponential Backoff
All database operations now automatically retry on transient failures:

- **Max Retries**: 3 attempts
- **Base Delay**: 100ms
- **Max Delay**: 2000ms
- **Strategy**: Exponential backoff with jitter to prevent thundering herd

#### Retriable Errors
The system automatically retries on:
- Database locked/busy errors
- Timeout errors
- Transient I/O errors
- File system exceptions

```dart
// Example: Operations automatically retry
await dbService.insertGeofence(db, geofenceData);
// If this fails due to "database is locked", it will retry up to 3 times
```

### 2. Connection Health Checks
Every database operation now includes automatic connection health verification:

- Validates database is open and responsive
- Executes test queries to verify connectivity
- Automatically attempts reconnection on failure

```dart
// Automatically used in all operations
final geofences = await dbService.getAllGeofences(db);
// The connection is verified healthy before fetching data
```

### 3. Connection Recovery
If a database connection becomes invalid, the service automatically attempts recovery:

- **Max Recovery Attempts**: 5
- **Recovery Strategy**: Progressive delay between attempts
- **Actions**: Closes stale connections, reopens database

```dart
// Automatically triggered when connection issues detected
// No manual intervention required
```

### 4. Transaction Support with Rollback
Complex multi-step operations can now use transactions with automatic rollback:

```dart
// Example: Atomic multi-step operation
await dbService.executeInTransaction(db, (txn) async {
  await txn.insert('tasks', taskData);
  await txn.update('geofences', geofenceData, 
    where: 'id = ?', whereArgs: [geofenceId]);
  // If any step fails, entire transaction is rolled back
}, operationName: 'CreateTaskWithGeofence');
```

### 5. Database Integrity Checking and Repair
Check and repair database corruption:

```dart
// Check database integrity
final isHealthy = await dbService.checkAndRepairDatabaseIntegrity();

if (!isHealthy) {
  print('Database corruption detected and repair attempted');
}
```

**Integrity Check Process**:
1. Runs SQLite `PRAGMA integrity_check`
2. If corruption detected, creates backup of corrupted database
3. Deletes corrupted database
4. Recreates fresh database with current schema
5. Verifies new database integrity

### 6. Batch Operations
Execute multiple operations atomically with error recovery:

```dart
await dbService.executeBatch(db, (batch) {
  batch.insert('tasks', task1);
  batch.insert('tasks', task2);
  batch.delete('tasks', where: 'id = ?', whereArgs: [oldTaskId]);
}, operationName: 'BulkTaskUpdate');
```

## Updated Methods

All database operation methods now include error recovery:

### Notification History
- `insertNotificationHistory()` - Auto-retry on failure
- `getAllNotificationHistory()` - Connection health check
- `clearAllNotificationHistory()` - Retry logic

### Task History
- `insertTaskHistory()` - Auto-retry on failure
- `getAllTaskHistory()` - Connection health check
- `getTaskHistoryByDateRange()` - Retry logic
- `getTaskHistoryByTaskId()` - Connection validation
- `getTaskStatistics()` - Multi-query with recovery
- `clearAllTaskHistory()` - Retry logic

### Geofences
- `insertGeofence()` - Auto-retry on failure
- `getAllGeofences()` - Connection health check
- `getGeofenceById()` - Retry logic
- `deleteGeofence()` - Connection validation
- `clearAllGeofences()` - Retry logic

## Error Handling Best Practices

### 1. Let the System Handle Transient Errors
```dart
// ❌ Don't manually catch and retry
try {
  await dbService.insertTask(db, taskData);
} catch (e) {
  // Manual retry logic - NOT NEEDED
}

// ✅ Do let the service handle it
await dbService.insertTask(db, taskData);
// Automatically retries on transient failures
```

### 2. Handle Non-Retriable Errors
```dart
try {
  await dbService.insertGeofence(db, geofenceData);
} catch (e) {
  // This error has already been retried 3 times
  // It's a non-transient error (e.g., constraint violation)
  logger.error('Failed to insert geofence after retries: $e');
  showErrorToUser('Unable to save geofence');
}
```

### 3. Use Transactions for Multi-Step Operations
```dart
// ✅ Atomic operation with automatic rollback
try {
  await dbService.executeInTransaction(db, (txn) async {
    // Multiple related operations
    final taskId = await txn.insert('tasks', taskData);
    await txn.update('geofences', {'task_id': taskId}, 
      where: 'id = ?', whereArgs: [geofenceId]);
  });
} catch (e) {
  // Transaction failed and was rolled back
  logger.error('Transaction failed: $e');
}
```

### 4. Periodic Integrity Checks
```dart
// Run during app startup or maintenance windows
Future<void> performMaintenanceCheck() async {
  final isHealthy = await dbService.checkAndRepairDatabaseIntegrity();
  
  if (!isHealthy) {
    // Log the issue and notify user if appropriate
    logger.warning('Database integrity issue detected and repaired');
  }
}
```

## Configuration

Error recovery settings can be adjusted in `database_service.dart`:

```dart
// Current configuration
static const int _maxRetries = 3;              // Number of retry attempts
static const int _baseRetryDelayMs = 100;      // Initial retry delay
static const int _maxRetryDelayMs = 2000;      // Maximum retry delay
static const int _connectionRetryAttempts = 5; // Connection recovery attempts
```

## Logging

All error recovery operations are logged with appropriate severity:

- **Info (900)**: Retry attempts in progress
- **Warning (1000)**: Non-retriable errors, max retries reached
- **Error**: Critical failures requiring attention

Monitor logs for patterns:
```
[insertGeofence] Attempt 1/3 failed: database is locked
[insertGeofence] Retrying after 120ms...
[insertGeofence] Attempt 2/3 succeeded
```

## Performance Impact

Error recovery mechanisms are designed for minimal performance impact:

- **Health checks**: Single lightweight query (SELECT 1)
- **Retry delays**: Progressive, starting at 100ms
- **Connection recovery**: Only triggered on actual failures
- **Integrity checks**: Manual invocation, not automatic

## Migration Notes

Existing code will automatically benefit from error recovery without changes:

```dart
// Before: No error recovery
await db.insert('tasks', taskData);

// After: Automatic error recovery (no code changes needed)
await dbService.insertTask(db, taskData);
```

## Troubleshooting

### Persistent "Database Locked" Errors
If you see repeated database locked errors:
1. Check for long-running transactions
2. Verify WAL mode is enabled (automatically configured)
3. Review busy_timeout setting (currently 5000ms)

### Connection Recovery Failures
If connection recovery consistently fails:
1. Check disk space availability
2. Verify database file permissions
3. Look for file system corruption
4. Review logs for underlying error patterns

### Integrity Check Failures
If integrity checks fail:
1. Database backup is automatically created (.backup extension)
2. Corrupted database is deleted
3. Fresh database is created
4. Review backup file to attempt data recovery if needed

## Future Enhancements

Potential additions to error recovery:
- Automatic data recovery from backups
- Circuit breaker pattern for cascading failures
- Metrics and monitoring integration
- Configurable retry strategies per operation type

## Testing

To test error recovery mechanisms:

```dart
// Simulate transient failure
test('Retry on database locked error', () async {
  // Test implementation would inject failure
});

// Test connection recovery
test('Recover from invalid connection', () async {
  // Test implementation would close connection
});

// Test integrity repair
test('Repair corrupted database', () async {
  // Test implementation would corrupt database
});
```

## Support

For issues or questions about error recovery:
1. Check logs for detailed error information
2. Review this documentation
3. Check database status with `getDatabaseStatus()`
4. Verify integrity with `checkAndRepairDatabaseIntegrity()`
