import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String userDocumentIdFor(User user) {
  return user.uid;
}

DocumentReference<Map<String, dynamic>> userDocumentRef(
    User user) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userDocumentIdFor(user));
}
