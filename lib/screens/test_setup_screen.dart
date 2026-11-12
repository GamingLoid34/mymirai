import 'package:flutter/material.dart';

import '../data/deck_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import '../models/test_question_item.dart';
import '../services/ai_service.dart';
import '../services/spaced_repetition.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import 'test_session_screen.dart';

/// Barnläge: välj lekar och skapa slumpat flervals-/öppet prov (`generateTest`).
class TestSetupScreen extends StatefulWidget {
  const TestSetupScreen({
    super.key,
    required this.deckRepository,
    this.xpRepository,
    this.uid,
  });

  final DeckRepository deckRepository;
  final XpRepository? xpRepository;
  final String? uid;

  @override
  State<TestSetupScreen> createState() => _TestSetupScreenState();
}

class _TestSetupScreenState extends State<TestSetupScreen> {
  final Set<String> _selectedDeckIds = {};
  int _count = 15;
  static const _countOptions = [10, 15, 20];
  bool _mixMultipleChoice = true;
  bool _busy = false;

  Future<Map<String, Flashcard>> _cardsForQuestions(
    List<TestQuestionItem> lite,
  ) async {
    final wantIds = lite.map((q) => q.cardId).toSet();
    final deckIds = lite.map((q) => q.deckId).toSet();
    final map = <String, Flashcard>{};
    for (final did in deckIds) {
      final cards = await widget.deckRepository.watchCardsInDeck(did).first;
      for (final c in cards) {
        if (wantIds.contains(c.id)) map[c.id] = c;
      }
    }
    return map;
  }

  Future<void> _start(List<FlashcardDeck> decks) async {
    if (_selectedDeckIds.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ai = AiService();
    try {
      final qs = await ai.generateTest(
        deckIds: _selectedDeckIds.toList(growable: false),
        count: _count,
        mixWithMultipleChoice: _mixMultipleChoice,
      );
      if (!mounted) return;
      final cardsById = await _cardsForQuestions(qs);
      if (!mounted) return;
      for (final q in qs) {
        if (cardsById[q.cardId] == null) {
          throw AiInvalidInputException('Kunde inte hämta kortdata för ett prov.');
        }
      }
      final subjectByDeckId = <String, String>{};
      for (final d in decks.where((x) => _selectedDeckIds.contains(x.id))) {
        final s = d.subject?.trim();
        subjectByDeckId[d.id] = (s == null || s.isEmpty) ? 'Okänt ämne' : s;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TestSessionScreen(
            deckRepository: widget.deckRepository,
            questions: qs,
            cardsById: cardsById,
            subjectByDeckId: subjectByDeckId,
            xpRepository: widget.xpRepository,
            uid: widget.uid,
          ),
        ),
      );
    } on AiAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiInvalidInputException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiUnavailableException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att starta provet. Testa igen om en stund.',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Gör ett test')),
      body: Center(
        child: MiraiAdaptiveBox(
          child: StreamBuilder<List<FlashcardDeck>>(
            stream: widget.deckRepository.watchDecksForFamily(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final decks = snap.data!;
              if (decks.isEmpty) {
                return Center(
                  child: Text(
                    'Inga lekar hittades än.',
                    style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                children: [
                  Text(
                    'Välj lekar och antal frågor. Du får inte se om svaren är '
                    'rätt förrän du lämnar in hela provet.',
                    style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Text('Lekar', style: tt.titleMedium),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  for (final deck in decks) ...[
                    _TestDeckPickRow(
                      deck: deck,
                      repo: widget.deckRepository,
                      selected: _selectedDeckIds.contains(deck.id),
                      onChanged: (v) {
                        setState(() {
                          if (v) {
                            _selectedDeckIds.add(deck.id);
                          } else {
                            _selectedDeckIds.remove(deck.id);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: MiraiTokens.spaceSm),
                  ],
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Text('Antal frågor', style: tt.titleMedium),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final opt in _countOptions)
                        ChoiceChip(
                          label: Text('$opt'),
                          selected: _count == opt,
                          onSelected: (_) => setState(() => _count = opt),
                        ),
                    ],
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  SwitchListTile(
                    value: _mixMultipleChoice,
                    title: const Text('Blanda med flerval'),
                    subtitle: Text(
                      'Ca 40 % av frågorna blir flerval (om du har tillräckligt många kort).',
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    ),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _mixMultipleChoice = v),
                  ),
                  const SizedBox(height: MiraiTokens.spaceLg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedDeckIds.isEmpty || _busy
                          ? null
                          : () => _start(decks),
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(_busy ? 'Skapar prov…' : 'Starta test'),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Avbryt'),
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

class _TestDeckPickRow extends StatelessWidget {
  const _TestDeckPickRow({
    required this.deck,
    required this.repo,
    required this.selected,
    required this.onChanged,
  });

  final FlashcardDeck deck;
  final DeckRepository repo;
  final bool selected;
  final void Function(bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<Flashcard>>(
      stream: repo.watchCardsInDeck(deck.id),
      builder: (context, snap) {
        final cards = snap.data ?? const <Flashcard>[];
        final due = SpacedRepetition.filterDue(cards, DateTime.now()).length;
        final subject = (deck.subject ?? '').trim();
        return InkWell(
          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
          onTap: () => onChanged(!selected),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MiraiTokens.bgRaised,
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
              border: Border.all(color: MiraiTokens.borderSubtle),
            ),
            child: Row(
              children: [
                Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.title,
                        style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${subject.isEmpty ? 'Ämne saknas' : subject} · ${cards.length} kort · $due due',
                        style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
