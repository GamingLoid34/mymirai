import 'package:flutter/material.dart';

import '../data/deck_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import '../services/exam_builder.dart';
import '../services/spaced_repetition.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import 'quiz_session_screen.dart';
import 'study_session_screen.dart';
import 'test_setup_screen.dart';

class ExamSetupScreen extends StatefulWidget {
  const ExamSetupScreen({
    super.key,
    required this.deckRepository,
    this.xpRepository,
    this.uid,
  });

  final DeckRepository deckRepository;
  final XpRepository? xpRepository;
  final String? uid;

  @override
  State<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends State<ExamSetupScreen> {
  final Set<String> _selectedDeckIds = {};
  int _count = 20;
  static const _options = [10, 20, 30, 50];

  Future<List<Flashcard>> _loadAllCards(List<FlashcardDeck> decks) async {
    final out = <Flashcard>[];
    for (final d in decks) {
      final cards = await widget.deckRepository.watchCardsInDeck(d.id).first;
      out.addAll(cards);
    }
    return out;
  }

  Future<void> _start(List<FlashcardDeck> decks, ExamMode mode) async {
    if (_selectedDeckIds.isEmpty) return;
    final selected = decks.where((d) => _selectedDeckIds.contains(d.id)).toList();
    final allCards = await _loadAllCards(selected);
    final cards = ExamBuilder.buildExamCards(
      decks: selected,
      allCards: allCards,
      count: _count,
      mode: mode,
    );
    if (!mounted || cards.isEmpty) return;
    final subjectByDeckId = <String, String>{};
    for (final d in selected) {
      final s = d.subject?.trim();
      subjectByDeckId[d.id] = (s == null || s.isEmpty) ? 'Okänt ämne' : s;
    }
    if (mode == ExamMode.study) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudySessionScreen(
            deckRepository: widget.deckRepository,
            cards: cards,
            deck: null,
            subjectByDeckId: subjectByDeckId,
            examDeckCount: selected.length,
            xpRepository: widget.xpRepository,
            uid: widget.uid,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen(
          deckRepository: widget.deckRepository,
          cards: cards,
          deck: null,
          subjectByDeckId: subjectByDeckId,
          examDeckCount: selected.length,
          xpRepository: widget.xpRepository,
          uid: widget.uid,
          simplifiedRating: true,
        ),
      ),
    );
  }

  Future<void> _startWrittenQuiz(List<FlashcardDeck> decks) async {
    final selected =
        decks.where((d) => _selectedDeckIds.contains(d.id)).toList();
    if (selected.isEmpty) return;
    final allCards = <Flashcard>[];
    for (final d in selected) {
      final snap = await widget.deckRepository.watchCardsInDeck(d.id).first;
      allCards.addAll(snap);
    }
    final cards = ExamBuilder.buildExamCards(
      decks: selected,
      allCards: allCards,
      count: _count,
      mode: ExamMode.quiz,
    );
    if (!mounted || cards.isEmpty) return;
    final subjectByDeckId = <String, String>{};
    for (final d in selected) {
      final s = d.subject?.trim();
      subjectByDeckId[d.id] = (s == null || s.isEmpty) ? 'Okänt ämne' : s;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizSessionScreen(
          deckRepository: widget.deckRepository,
          cards: cards,
          deck: null,
          subjectByDeckId: subjectByDeckId,
          examDeckCount: selected.length,
          xpRepository: widget.xpRepository,
          uid: widget.uid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Plugga inför prov')),
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
                    'Välj vilka lekar som ska ingå så blandar vi ett träningspass av korten.',
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Text('Välj lekar', style: tt.titleMedium),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  for (final deck in decks) ...[
                    _DeckPickRow(
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
                  Text('Antal kort i provet', style: tt.titleMedium),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final opt in _options)
                        ChoiceChip(
                          label: Text('$opt'),
                          selected: _count == opt,
                          onSelected: (_) => setState(() => _count = opt),
                        ),
                    ],
                  ),
                  const SizedBox(height: MiraiTokens.spaceLg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedDeckIds.isEmpty
                          ? null
                          : () => _start(decks, ExamMode.study),
                      icon: const Icon(Icons.style_rounded),
                      label: const Text('Studera valda'),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _selectedDeckIds.isEmpty
                          ? null
                          : () => _start(decks, ExamMode.quiz),
                      icon: const Icon(Icons.quiz_outlined),
                      label: const Text('Förhör valda'),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _selectedDeckIds.isEmpty
                          ? null
                          : () => _startWrittenQuiz(decks),
                      child: const Text('Skriftligt förhör (skriv svaren)'),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TestSetupScreen(
                              deckRepository: widget.deckRepository,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Gör ett slumpat test istället'),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Avbryt'),
                    ),
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

class _DeckPickRow extends StatelessWidget {
  const _DeckPickRow({
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
                      Text(deck.title, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
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
