import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'user_firestore_helper.dart';

class TransactionService {
  // DELETE TRANSACTION
  static Future<void> deleteTransaction({
    required String transactionId,
    required String walletId,
    required double amount,
    required String type, // income / expense
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
          'User must be authenticated to delete a transaction.');
    }

    final collection =
        type == 'income' ? 'income' : 'expenses';

    final walletRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection('wallets')
        .doc(walletId);

    final transactionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection(collection)
        .doc(transactionId);

    final auditRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection('transactions')
        .doc(transactionId);

    try {
      await FirebaseFirestore.instance
          .runTransaction((tx) async {
        final walletSnap = await tx.get(walletRef);
        final currentBalance =
            (walletSnap.data()?['balance'] ?? 0).toDouble();

        if (type == 'income' && currentBalance < amount) {
          throw Exception(
            'Deleting this income would result in negative balance.',
          );
        }

        final newBalance = type == 'income'
            ? currentBalance - amount
            : currentBalance + amount;

        tx.update(walletRef, {'balance': newBalance});
        tx.delete(transactionRef);
        tx.delete(auditRef);
      });
    } catch (e) {
      debugPrint(
          'TransactionService.deleteTransaction error: $e');
      rethrow;
    }
  }

  // UPDATE TRANSACTION
  static Future<void> updateTransaction({
    required String transactionId,
    required String walletId,
    required double oldAmount,
    required double newAmount,
    required String description,
    required String type, // income / expense
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
          'User must be authenticated to update a transaction.');
    }

    final collection =
        type == 'income' ? 'income' : 'expenses';

    final walletRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection('wallets')
        .doc(walletId);

    final transactionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection(collection)
        .doc(transactionId);

    final auditRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocumentIdFor(user))
        .collection('transactions')
        .doc(transactionId);

    try {
      await FirebaseFirestore.instance
          .runTransaction((tx) async {
        final walletSnap = await tx.get(walletRef);
        final currentBalance =
            (walletSnap.data()?['balance'] ?? 0).toDouble();

        double updatedBalance;
        if (type == 'income') {
          updatedBalance =
              currentBalance - oldAmount + newAmount;
        } else {
          updatedBalance =
              currentBalance + oldAmount - newAmount;
        }

        tx.update(walletRef, {'balance': updatedBalance});
        tx.update(transactionRef, {
          'amount': newAmount,
          'description': description,
        });
        tx.update(auditRef, {
          'amount': newAmount,
          'description': description,
        });
      });
    } catch (e) {
      debugPrint(
          'TransactionService.updateTransaction error: $e');
      rethrow;
    }
  }
}
