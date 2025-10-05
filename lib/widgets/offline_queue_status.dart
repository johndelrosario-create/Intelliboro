import 'package:flutter/material.dart';
import '../services/offline_operation_queue.dart';

/// Widget to display offline operation queue status
class OfflineQueueStatus extends StatefulWidget {
  const OfflineQueueStatus({super.key});

  @override
  State<OfflineQueueStatus> createState() => _OfflineQueueStatusState();
}

class _OfflineQueueStatusState extends State<OfflineQueueStatus> {
  final _queue = OfflineOperationQueue();

  @override
  Widget build(BuildContext context) {
    final hasQueue = _queue.hasPendingOperations;
    final isOnline = _queue.isOnline;
    final queueSize = _queue.queueSize;

    if (!hasQueue) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      color: isOnline ? Colors.blue.shade50 : Colors.orange.shade50,
      child: ExpansionTile(
        leading: Icon(
          isOnline ? Icons.cloud_queue : Icons.cloud_off,
          color: isOnline ? Colors.blue : Colors.orange,
        ),
        title: Text(
          isOnline
              ? 'Syncing $queueSize operation${queueSize > 1 ? 's' : ''}...'
              : '$queueSize operation${queueSize > 1 ? 's' : ''} pending (offline)',
          style: TextStyle(
            color: isOnline ? Colors.blue.shade900 : Colors.orange.shade900,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          isOnline
              ? 'Operations will sync automatically'
              : 'Will sync when connection is restored',
          style: TextStyle(
            color: isOnline ? Colors.blue.shade700 : Colors.orange.shade700,
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Queued operations will be executed when online.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isOnline)
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _queue.processQueueManually();
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('Sync Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('Clear Queue'),
                                content: Text(
                                  'Are you sure you want to clear $queueSize pending operation${queueSize > 1 ? 's' : ''}? This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                        );

                        if (confirm == true && mounted) {
                          await _queue.clearQueue();
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Queue cleared'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear Queue'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
