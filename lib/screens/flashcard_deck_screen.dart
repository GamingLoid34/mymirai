import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/deck_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import '../services/spaced_repetition.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../widgets/session_duration_picker.dart';
import 'quiz_session_screen.dart';
import 'study_session_screen.dart';

class FlashcardDeckScreen extends StatelessWidget {
  const FlashcardDeckScreen({
    super.key,
    required this.deckRepository,
    required this.deckId,
    this.onStudyCompleted,
    this.onQuizCompleted,
    this.xpRepository,
    this.uid,
    this.isChildMode = false,
  });

  final DeckRepository deckRepository;
  final String deckId;

  /// AO-06: kallas när en studiesession poppar med genomförd repetition.
  final VoidCallback? onStudyCompleted;

  /// AO-06: kallas när ett förhör poppar med genomfört förhör.
  final VoidCallback? onQuizCompleted;

  final XpRepository? xpRepository;

  /// AO-10: visar tidsväljare + timer i barnläget.
  final bool isChildMode;
  final String? uid;

  Future<void> _openEditor(
    BuildContext context,
    FlashcardDeck deck,
    Flashcard? existing,
  ) async {
    final result = await showDialog<({String front, String back})>(
      context: context,
      builder: (ctx) => _CardEditDialog(
        initialFront: existing?.front ?? '',
        initialBack: existing?.back ?? '',
        title: existing == null ? 'Nytt kort' : 'Redigera kort',
      ),
    );
    if (result == null || !context.mounted) return;
    final f = result.front.trim();
    final b = result.back.trim();
    if (f.isEmpty || b.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i både fråga och svar.')),
      );
      return;
    }
    try {
      if (existing == null) {
        await deckRepository.createCard(
          deckId: deck.id,
          front: f,
          back: b,
          source: FlashcardSource.manual,
        );
      } else {
        final nextSource = existing.source == FlashcardSource.ai
            ? FlashcardSource.edited
            : existing.source;
        await deckRepository.updateCard(
          existing.copyWith(
            front: f,
            back: b,
            source: nextSource,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att spara kortet. Testa igen om en stund.',
          error: e,
        );
      }
    }
  }

  Future<void> _confirmDeleteCard(BuildContext context, Flashcard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort kort?'),
        content: const Text('Det går inte att ångra.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await deckRepository.deleteCard(card.id);
    } catch (e) {
      if (context.mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att ta bort kortet. Testa igen om en stund.',
          error: e,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<FlashcardDeck?>(
          stream: deckRepository.watchDeck(deckId),
          builder: (context, snap) {
            final t = snap.data?.title ?? 'Flashcards';
            return Text(t);
          },
        ),
      ),
      body: Center(
        child: MiraiAdaptiveBox(
          child: StreamBuilder<FlashcardDeck?>(
            stream: deckRepository.watchDeck(deckId),
            builder: (context, deckSnap) {
              if (!deckSnap.hasData || deckSnap.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final deck = deckSnap.data!;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiraiTokens.spaceLg,
                      MiraiTokens.spaceMd,
                      MiraiTokens.spaceLg,
                      MiraiTokens.spaceSm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${deck.cardCount} kort',
                            style: tt.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => _openEditor(context, deck, null),
                          icon: const Icon(Icons.add_rounded),
                          tooltip: 'Lägg till kort',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Flashcard>>(
                      stream: deckRepository.watchCardsInDeck(deckId),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final cards = snap.data!;
                        if (cards.isEmpty) {
                          return Padding(
                            padding:
                                const EdgeInsets.all(MiraiTokens.spaceLg),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Inga kort än',
                                  style: tt.bodyMedium?.copyWith(
                                    color: MiraiTokens.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: MiraiTokens.spaceMd),
                                IconButton.filled(
                                  onPressed:
                                      () => _openEditor(context, deck, null),
                                  iconSize: 40,
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            MiraiTokens.spaceLg,
                            MiraiTokens.spaceXs,
                            MiraiTokens.spaceLg,
                            140,
                          ),
                          itemBuilder: (_, i) {
                            final c = cards[i];
                            return Material(
                              color: MiraiTokens.bgRaised,
                              borderRadius:
                                  BorderRadius.circular(MiraiTokens.radiusMd),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(MiraiTokens.radiusMd),
                                onTap: () => _openEditor(context, deck, c),
                                onLongPress: () async {
                                  await HapticFeedback.mediumImpact();
                                  if (!context.mounted) return;
                                  await _confirmDeleteCard(context, c);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        MiraiTokens.radiusMd),
                                    border: Border.all(
                                      color: MiraiTokens.borderSubtle,
                                      width: MiraiTokens.borderThin,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.front,
                                              style:
                                                  tt.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              c.back,
                                              style:
                                                  tt.bodySmall?.copyWith(
                                                color: MiraiTokens.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        iconSize: 20,
                                        icon: const Icon(Icons.more_vert_rounded),
                                        color: MiraiTokens.textTertiary,
                                        onPressed: () async =>
                                            _confirmDeleteCard(context, c),
                                        tooltip: 'Ta bort kort',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: MiraiTokens.spaceSm),
                          itemCount: cards.length,
                        );
                      },
                    ),
                  ),
                  StreamBuilder<List<Flashcard>>(
                    stream: deckRepository.watchCardsInDeck(deckId),
                    builder: (context, snap) {
                      final cards = snap.data ?? const <Flashcard>[];
                      final dueCards = SpacedRepetition.sortForStudy(
                        cards,
                        DateTime.now(),
                      );
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          MiraiTokens.spaceLg,
                          MiraiTokens.spaceSm,
                          MiraiTokens.spaceLg,
                          MiraiTokens.spaceLg,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: cards.isEmpty
                                    ? null
                                    : () async {
                                        int? minutes;
                                        if (isChildMode) {
                                          minutes = await showSessionDurationPicker(context);
                                          if (!context.mounted) return;
                                        }
                                        final shuffled = List.of(cards)..shuffle();
                                        final done = await Navigator.of(context).push<bool>(
                                          MaterialPageRoute<bool>(
                                            builder: (_) => StudySessionScreen(
                                              deckRepository: deckRepository,
                                              deck: deck,
                                              cards: shuffled,
                                              xpRepository: xpRepository,
                                              uid: uid,
                                              sessionDurationMinutes: minutes,
                                              simplifiedRating: true,
                                            ),
                                          ),
                                        );
                                        if (done == true) onQuizCompleted?.call();
                                      },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: MiraiTokens.spaceMd,
                                  ),
                                ),
                                child: const Text('Starta förhör'),
                              ),
                            ),
                            const SizedBox(height: MiraiTokens.spaceSm),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: dueCards.isEmpty
                                        ? null
                                        : () async {
                                            int? minutes;
                                            if (isChildMode) {
                                              minutes = await showSessionDurationPicker(context);
                                              if (!context.mounted) return;
                                            }
                                            final done = await Navigator.of(context).push<bool>(
                                              MaterialPageRoute<bool>(
                                                builder: (_) => StudySessionScreen(
                                                  deckRepository: deckRepository,
                                                  deck: deck,
                                                  cards: dueCards,
                                                  xpRepository: xpRepository,
                                                  uid: uid,
                                                  sessionDurationMinutes: minutes,
                                                ),
                                              ),
                                            );
                                            if (done == true) onStudyCompleted?.call();
                                          },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: MiraiTokens.spaceMd,
                                      ),
                                    ),
                                    child: Text(
                                      dueCards.isEmpty
                                          ? 'Allt klart'
                                          : 'Repetera (${dueCards.length})',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: MiraiTokens.spaceSm),
                                Expanded(
                                  child: TextButton(
                                    onPressed: cards.length < 3
                                        ? null
                                        : () async {
                                            int? minutes;
                                            if (isChildMode) {
                                              minutes = await showSessionDurationPicker(context);
                                              if (!context.mounted) return;
                                            }
                                            final done = await Navigator.of(context).push<bool>(
                                              MaterialPageRoute<bool>(
                                                builder: (_) => QuizSessionScreen(
                                                  deckRepository: deckRepository,
                                                  deck: deck,
                                                  cards: cards,
                                                  xpRepository: xpRepository,
                                                  uid: uid,
                                                  sessionDurationMinutes: minutes,
                                                ),
                                              ),
                                            );
                                            if (done == true) onQuizCompleted?.call();
                                          },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: MiraiTokens.spaceMd,
                                      ),
                                    ),
                                    child: const Text('Skriftligt förhör'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: MiraiTokens.spaceXs),
                            Text(
                              'Förhör: du bedömer själv. Skriftligt: skriv svaret, AI rättar.',
                              style: tt.bodySmall?.copyWith(
                                color: MiraiTokens.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Egen dialog som äger sina TextEditingControllers så att de disposas
/// först när dialog-State:n rivs (efter stäng-animationen). Att dispose:a
/// dem manuellt direkt efter `await showDialog` orsakar
/// "TextEditingController used after disposed" eftersom dialogens
/// fade/scale-animation kör en sista build på fältet.
class _CardEditDialog extends StatefulWidget {
  const _CardEditDialog({
    required this.initialFront,
    required this.initialBack,
    required this.title,
  });

  final String initialFront;
  final String initialBack;
  final String title;

  @override
  State<_CardEditDialog> createState() => _CardEditDialogState();
}

class _CardEditDialogState extends State<_CardEditDialog> {
  late final TextEditingController _frontCtrl =
      TextEditingController(text: widget.initialFront);
  late final TextEditingController _backCtrl =
      TextEditingController(text: widget.initialBack);

  @override
  void dispose() {
    _frontCtrl.dispose();
    _backCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Fråga', style: tt.labelMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _frontCtrl,
              maxLines: 4,
              maxLength: 200,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            Text('Svar', style: tt.labelMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _backCtrl,
              maxLines: 6,
              maxLength: 500,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (front: _frontCtrl.text, back: _backCtrl.text),
          ),
          child: const Text('Spara'),
        ),
      ],
    );
  }
}
