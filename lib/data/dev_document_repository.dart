import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/document.dart';
import '../models/document_chat_turn.dart';
import 'document_repository.dart';

class DevDocumentRepository implements DocumentRepository {
  DevDocumentRepository() {
    final now = DateTime.now();
    _items.add(
      UserDocument(
        id: 'dev-doc-1',
        ownerUid: 'demo-child',
        title: 'Neurala nätverk i praktiken',
        extractedText:
            'Neurala nätverk används för klassificering, prediktion och generativ AI...',
        summary:
            'Texten beskriver grunderna i neurala nätverk och hur de tränas.',
        sourceType: 'text',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  final List<UserDocument> _items = [];
  final Map<String, List<DocumentChatTurn>> _chatTurns = {};
  final StreamController<void> _tick = StreamController<void>.broadcast();

  void _emit() {
    if (!_tick.isClosed) _tick.add(null);
  }

  @override
  Future<UserDocument?> getById(String docId) async {
    try {
      return _items.firstWhere((d) => d.id == docId);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<UserDocument?> watchOne(String docId) {
    return Stream<UserDocument?>.multi((listener) {
      UserDocument? one() {
        try {
          return _items.firstWhere((d) => d.id == docId);
        } catch (_) {
          return null;
        }
      }

      listener.add(one());
      final sub = _tick.stream.listen((_) {
        listener.add(one());
      });
      listener.onCancel = () => sub.cancel();
    });
  }

  @override
  Stream<List<UserDocument>> watchForOwner(String ownerUid) {
    List<UserDocument> build() {
      final out = _items.where((d) => d.ownerUid == ownerUid).toList();
      out.sort((a, b) {
        final au = a.updatedAt;
        final bu = b.updatedAt;
        if (au == null && bu == null) return 0;
        if (au == null) return 1;
        if (bu == null) return -1;
        return bu.compareTo(au);
      });
      return out;
    }

    return Stream<List<UserDocument>>.multi((listener) {
      listener.add(build());
      final sub = _tick.stream.listen((_) => listener.add(build()));
      listener.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<String> create(UserDocument draft) async {
    final now = DateTime.now();
    final id = 'dev-doc-${now.microsecondsSinceEpoch}';
    _items.add(
      UserDocument(
        id: id,
        ownerUid: draft.ownerUid,
        title: draft.title,
        summary: draft.summary,
        extractedText: draft.extractedText,
        audioCachedAt: draft.audioCachedAt,
        audioStoragePath: draft.audioStoragePath,
        sourceUrl: draft.sourceUrl,
        attachment: draft.attachment,
        attachmentStorageUrl: draft.attachmentStorageUrl,
        sourceType: draft.sourceType,
        highlights: draft.highlights,
        createdAt: now,
        updatedAt: now,
        lastReadAt: draft.lastReadAt,
        readingProgress: draft.readingProgress,
        userNotes: draft.userNotes,
      ),
    );
    _emit();
    return id;
  }

  @override
  Stream<List<DocumentChatTurn>> watchDocumentChatTurns(String documentId) {
    return Stream<List<DocumentChatTurn>>.multi((listener) {
      void emit() =>
          listener.add(List.from(_chatTurns[documentId] ?? []));
      emit();
      final sub = _tick.stream.listen((_) => emit());
      listener.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<void> appendChatTurn(String documentId, DocumentChatTurn turn) async {
    _chatTurns.putIfAbsent(documentId, () => []).add(turn);
    _emit();
  }

  @override
  Future<void> update(UserDocument doc) async {
    final idx = _items.indexWhere((d) => d.id == doc.id);
    if (idx < 0) return;
    _items[idx] = doc.copyWith();
    _emit();
  }

  @override
  Future<void> delete(String docId) async {
    DocumentAttachment? attachment;
    for (final d in _items) {
      if (d.id == docId) {
        attachment = d.attachment;
        break;
      }
    }
    final path = attachment?.storagePath.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
    _items.removeWhere((d) => d.id == docId);
    _chatTurns.remove(docId);
    _emit();
  }
}
