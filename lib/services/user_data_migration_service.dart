import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserDataMigrationService {
  static const List<String> _subcollections = [
    'income',
    'expenses',
    'transactions',
    'categories',
    'wallets',
  ];

  static Future<void> migrateSignedInUserData(
      User user) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final legacyRef = firestore
        .collection('users')
        .doc(user.email!.trim());

    final targetRef =
        firestore.collection('users').doc(user.uid);

    if (legacyRef.id == targetRef.id) {
      return;
    }

    final legacySnap = await legacyRef.get();
    if (!legacySnap.exists) {
      return;
    }

    final targetSnap = await targetRef.get();
    if (targetSnap.exists) {
      return;
    }

    final legacyData = legacySnap.data();
    if (legacyData == null) {
      return;
    }

    final rootBatch = firestore.batch();
    rootBatch.set(
        targetRef, legacyData, SetOptions(merge: true));
    await rootBatch.commit();

    for (final collectionName in _subcollections) {
      final snapshot =
          await legacyRef.collection(collectionName).get();
      if (snapshot.docs.isEmpty) {
        continue;
      }

      const chunkSize = 400;
      for (var index = 0;
          index < snapshot.docs.length;
          index += chunkSize) {
        final batch = firestore.batch();
        final end = index + chunkSize > snapshot.docs.length
            ? snapshot.docs.length
            : index + chunkSize;
        for (final doc
            in snapshot.docs.sublist(index, end)) {
          batch.set(
              targetRef
                  .collection(collectionName)
                  .doc(doc.id),
              doc.data());
        }
        await batch.commit();
      }
    }
  }
}
