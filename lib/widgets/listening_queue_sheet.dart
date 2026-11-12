import 'package:flutter/material.dart';

import '../data/document_repository.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../util/continue_listening.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/tts_player_sheet.dart';

/// VO-09: spelar upp en kö av dokument i följd. Molnläge förgenererar nästa
/// dokuments ljud medan nuvarande spelar (sömlöst byte); enhetsröst-läge
/// spelar dokument för dokument via TtsPlayerSheet.
Future<void> showListeningQueueSheet(
  BuildContext context, {
  required List<UserDocument> queue,
  required DocumentRepository repository,
  required bool useCloudVoice,
  int startIndex = 0,
}) async {
  if (queue.isEmpty) return;
  await _playQueueFrom(context, queue, repository, useCloudVoice, startIndex);
}

Future<void> _playQueueFrom(
  BuildContext context,
  List<UserDocument> queue,
  DocumentRepository repository,
  bool useCloudVoice,
  int index,
) async {
  if (index < 0 || index >= queue.length || !context.mounted) return;
  final doc = queue[index];
  final text = (doc.summary ?? doc.extractedText ?? '').trim();
  if (text.isEmpty) {
    // Hoppa över dokument utan lyssningsbar text.
    await _playQueueFrom(context, queue, repository, useCloudVoice, index + 1);
    return;
  }
  final label = '${index + 1} av ${queue.length}';
  final ai = AiService();

  Future<void> onDone(double progress, bool completed) async {
    await repository.update(
      doc.copyWith(
        readingProgress: completed ? 1.0 : progress,
        lastReadAt: DateTime.now(),
      ),
    );
  }

  if (useCloudVoice) {
    await showAudioPlayerSheet(
      context,
      title: doc.title,
      docId: doc.id,
      load: () => ai.documentAudio(documentId: doc.id),
      initialProgress: doc.readingProgress,
      queueLabel: label,
      onPositionChanged: (position, duration, completed) {
        final progress = completed
            ? 1.0
            : computeReadingProgress(position: position, duration: duration);
        onDone(progress, completed);
      },
      onNext: index + 1 < queue.length
          ? () {
              if (context.mounted) Navigator.of(context).pop();
              _playQueueFrom(context, queue, repository, useCloudVoice, index + 1);
            }
          : null,
      nextLoad: index + 1 < queue.length
          ? () => ai.documentAudio(documentId: queue[index + 1].id)
          : null,
    );
  } else {
    if (!context.mounted) return;
    showTtsPlayer(
      context,
      text: text,
      title: doc.title,
      subject: label,
      onFinished: () {
        onDone(1.0, true);
        if (index + 1 < queue.length && context.mounted) {
          Navigator.of(context).pop();
          _playQueueFrom(context, queue, repository, useCloudVoice, index + 1);
        }
      },
      onProgressChanged: (progress) => onDone(progress, false),
    );
  }
}
