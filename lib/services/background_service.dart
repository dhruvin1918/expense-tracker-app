import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'notification_service.dart';

const budgetCheckTask = 'budgetCheckTask';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await NotificationService.initialize();

      final prefs = await SharedPreferences.getInstance();
      final alertEnabled =
          prefs.getBool('budgetAlertEnabled') ?? false;
      if (!alertEnabled) return true;

      // In background isolate, FirebaseAuth.currentUser is often null.
      final userId = inputData?['userId'] as String?;
      if (userId == null || userId.isEmpty) return true;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final monthlyBudget =
          (userDoc.data()?['monthlyBudget'] ?? 0)
              .toDouble();
      final categoryBudgets =
          (userDoc.data()?['categoryBudgets']
                  as Map<String, dynamic>?) ??
              {};

      final expenseSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: monthStart)
          .get();

      if (monthlyBudget > 0) {
        double monthlyExpense = 0;
        for (var doc in expenseSnap.docs) {
          monthlyExpense +=
              (doc['amount'] as num).toDouble();
        }

        final percent =
            (monthlyExpense / monthlyBudget) * 100;

        if (monthlyExpense >= monthlyBudget) {
          await NotificationService.showBudgetAlert(
            id: 0,
            title: '⚠️ Monthly Budget Exceeded!',
            body:
                'You spent ₹${monthlyExpense.toStringAsFixed(0)} of your ₹${monthlyBudget.toStringAsFixed(0)} budget.',
          );
        } else if (percent >= 80) {
          await NotificationService.showBudgetAlert(
            id: 0,
            title: '📊 Monthly Budget Alert',
            body:
                'You have used ${percent.toStringAsFixed(0)}% of your ₹${monthlyBudget.toStringAsFixed(0)} monthly budget.',
          );
        }
      }

      if (categoryBudgets.isNotEmpty) {
        final Map<String, double> categoryExpenses = {};
        for (var doc in expenseSnap.docs) {
          final category =
              doc['category'] as String? ?? 'Uncategorized';
          final amount = (doc['amount'] as num).toDouble();
          categoryExpenses[category] =
              (categoryExpenses[category] ?? 0) + amount;
        }

        int notifId = 1;
        for (var entry in categoryBudgets.entries) {
          final category = entry.key;
          final limit = (entry.value as num).toDouble();
          if (limit <= 0) {
            notifId++;
            continue;
          }

          final spent = categoryExpenses[category] ?? 0;
          final percent = (spent / limit) * 100;

          if (spent >= limit) {
            await NotificationService.showBudgetAlert(
              id: notifId,
              title: '⚠️ $category Budget Exceeded!',
              body:
                  'You spent ₹${spent.toStringAsFixed(0)} of your ₹${limit.toStringAsFixed(0)} $category budget.',
            );
          } else if (percent >= 80) {
            await NotificationService.showBudgetAlert(
              id: notifId,
              title: '📊 $category Budget Alert',
              body:
                  '$category is ${percent.toStringAsFixed(0)}% used — ₹${spent.toStringAsFixed(0)} of ₹${limit.toStringAsFixed(0)}.',
            );
          }
          notifId++;
        }
      }
    } catch (e) {
      debugPrint('Background task error: $e');
    }

    return true;
  });
}

class BackgroundService {
  static Future<void>
      requestBatteryOptimizationExemption() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final status =
        await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> registerPeriodicTask(
      String userId) async {
    await Workmanager().registerPeriodicTask(
      'budget-check-periodic',
      budgetCheckTask,
      frequency: const Duration(hours: 2),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      inputData: {'userId': userId},
      existingWorkPolicy:
          ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Future<void> registerOneOffTestTask(
      String userId) async {
    await Workmanager().registerOneOffTask(
      'test-${DateTime.now().millisecondsSinceEpoch}',
      budgetCheckTask,
      initialDelay: Duration.zero,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
      ),
      inputData: {'userId': userId},
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
