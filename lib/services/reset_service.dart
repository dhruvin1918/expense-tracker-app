import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'user_firestore_helper.dart';

class ResetService {
  static Future<void> resetUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    final userRef = userDocumentRef(user);

    // TODO: Chunk operations into groups of <=500 writes for large datasets.
    final batch = firestore.batch();

    // 🔹 1. Delete income
    final incomeSnap =
        await userRef.collection('income').get();
    for (var doc in incomeSnap.docs) {
      batch.delete(doc.reference);
    }

    // 🔹 2. Delete expenses
    final expenseSnap =
        await userRef.collection('expenses').get();
    for (var doc in expenseSnap.docs) {
      batch.delete(doc.reference);
    }

    // 🔹 3. Delete transactions (if exists)
    final transactionSnap =
        await userRef.collection('transactions').get();
    for (var doc in transactionSnap.docs) {
      batch.delete(doc.reference);
    }

    // 🔹 4. Delete categories
    final categorySnap =
        await userRef.collection('categories').get();
    for (var doc in categorySnap.docs) {
      batch.delete(doc.reference);
    }

    // 🔹 5. Reset wallets
    final walletSnap =
        await userRef.collection('wallets').get();
    for (var doc in walletSnap.docs) {
      batch.update(doc.reference, {'balance': 0});
    }

    // 🔹 6. Clear budget fields on user document
    batch.set(
      userRef,
      {
        'monthlyBudget': FieldValue.delete(),
        'categoryBudgets': FieldValue.delete(),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('Reset batch error: $e');
      rethrow;
    }
  }
}
