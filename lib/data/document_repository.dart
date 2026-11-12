import '../models/document.dart';
import '../models/document_chat_turn.dart';

abstract class DocumentRepository {
  Stream<List<UserDocument>> watchForOwner(String ownerUid);

  /// Enskilt dokument eller `null` om det saknas / ingen åtkomst.
  Future<UserDocument?> getById(String docId);

  /// Direktsnapshot ett dokument (snabbare än watchForOwner + filter).
  Stream<UserDocument?> watchOne(String docId);

  Future<String> create(UserDocument draft);

  Future<void> update(UserDocument doc);

  Future<void> delete(String docId);

  Stream<List<DocumentChatTurn>> watchDocumentChatTurns(String documentId);

  Future<void> appendChatTurn(String documentId, DocumentChatTurn turn);
}
