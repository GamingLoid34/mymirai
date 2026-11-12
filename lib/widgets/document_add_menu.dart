import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/document_repository.dart';
import '../screens/document_create_flow_screen.dart';
import '../screens/note_capture_screen.dart';
import '../screens/recording_capture_screen.dart';

/// VO-04: +-meny för att lägga till dokument utan friktion.
void showDocumentAddMenu(
  BuildContext context, {
  required DocumentRepository repository,
  required String ownerUid,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Snabb anteckning'),
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NoteCaptureScreen(
                    repository: repository,
                    ownerUid: ownerUid,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Fota eller välj fil'),
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentCreateFlowScreen(
                    repository: repository,
                    ownerUid: ownerUid,
                    initialAction: DocumentCreateInitialAction.pickFile,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Importera länk'),
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentCreateFlowScreen(
                    repository: repository,
                    ownerUid: ownerUid,
                    initialAction: DocumentCreateInitialAction.importLink,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Skriv eller klistra text'),
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentCreateFlowScreen(
                    repository: repository,
                    ownerUid: ownerUid,
                    initialAction: DocumentCreateInitialAction.writeText,
                  ),
                ),
              );
            },
          ),
          // Inspelning transkriberas/sammanfattas i molnet och kräver att
          // dokumentet finns i Firestore — visas avstängd i demo-läget.
          if (!kIsWeb)
            if (kUseFirestoreHomework)
              ListTile(
                leading: const Icon(Icons.mic_none_rounded),
                title: const Text('Spela in'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordingCaptureScreen(
                        repository: repository,
                        ownerUid: ownerUid,
                      ),
                    ),
                  );
                },
              )
            else
              const ListTile(
                enabled: false,
                leading: Icon(Icons.mic_off_outlined),
                title: Text('Spela in'),
                subtitle: Text('Kräver molnläge (Firestore) — avstängt i demo-läget.'),
              ),
        ],
      ),
    ),
  );
}
