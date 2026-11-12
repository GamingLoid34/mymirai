import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentChatRole { user, assistant }

class DocumentChatTurn {
  const DocumentChatTurn({
    required this.role,
    required this.content,
    required this.createdAt,
    this.id,
  });

  final String? id;
  final DocumentChatRole role;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toFirestoreMap() => {
        'role': role == DocumentChatRole.user ? 'user' : 'assistant',
        'content': content,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  static DocumentChatTurn fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final r = data['role'] as String? ?? '';
    final cr = data['createdAt'];
    DateTime when = DateTime.now();
    if (cr is Timestamp) when = cr.toDate();
    return DocumentChatTurn(
      id: doc.id,
      role: r == 'user' ? DocumentChatRole.user : DocumentChatRole.assistant,
      content: data['content'] as String? ?? '',
      createdAt: when,
    );
  }
}
