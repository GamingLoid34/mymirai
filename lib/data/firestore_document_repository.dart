import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/document.dart';
import '../models/document_chat_turn.dart';
import 'document_repository.dart';

class FirestoreDocumentRepository implements DocumentRepository {
  FirestoreDocumentRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('documents');

  @override
  Future<UserDocument?> getById(String docId) async {
    final snap = await _col.doc(docId).get();
    if (!snap.exists) return null;
    return UserDocument.fromFirestore(snap);
  }

  @override
  Stream<UserDocument?> watchOne(String docId) {
    return _col.doc(docId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserDocument.fromFirestore(snap);
    });
  }

  @override
  Stream<List<UserDocument>> watchForOwner(String ownerUid) {
    final q = _col.where('ownerUid', isEqualTo: ownerUid);
    return q.snapshots().map((snap) {
      final docs = snap.docs.map(UserDocument.fromFirestore).toList();
      docs.sort((a, b) {
        final au = a.updatedAt;
        final bu = b.updatedAt;
        if (au == null && bu == null) return 0;
        if (au == null) return 1;
        if (bu == null) return -1;
        return bu.compareTo(au);
      });
      return docs;
    });
  }

  @override
  Future<String> create(UserDocument draft) async {
    final now = DateTime.now();
    final ref = await _col.add(draft.toCreateMap(now));
    return ref.id;
  }

  @override
  Future<void> update(UserDocument doc) async {
    await _col.doc(doc.id).update(doc.toUpdateMap(DateTime.now()));
  }

  CollectionReference<Map<String, dynamic>> _chatCol(String docId) =>
      _col.doc(docId).collection('chat_turns');

  @override
  Stream<List<DocumentChatTurn>> watchDocumentChatTurns(String documentId) {
    return _chatCol(documentId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(DocumentChatTurn.fromFirestore).toList());
  }

  @override
  Future<void> appendChatTurn(String documentId, DocumentChatTurn turn) async {
    await _chatCol(documentId).add(turn.toFirestoreMap());
  }

  @override
  Future<void> delete(String docId) async {
    final snap = await _col.doc(docId).get();
    if (snap.exists) {
      final doc = UserDocument.fromFirestore(snap);
      final path = doc.attachment?.storagePath.trim();
      if (path != null && path.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {
          // Fortsätt radera dokumentet även om filen saknas eller regler nekade delete.
        }
      }
    }
    await _col.doc(docId).delete();
  }
}
