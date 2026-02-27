import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';

/// Flashcards med Spaced Repetition (nivå 0–2+).
/// Öva på "Nya", "Svåra" eller "Alla".
class ExercisesPage extends StatefulWidget {
  final AppUser currentUser;
  final AppUser? selectedChild;

  const ExercisesPage({super.key, required this.currentUser, this.selectedChild});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  int _filterIndex = 0; // 0=Nya, 1=Svåra, 2=Alla
  int _currentIndex = 0;
  bool _showBack = false;

  List<MapEntry<String, Flashcard>> _filter(List<MapEntry<String, Flashcard>> all) {
    final now = DateTime.now();
    List<MapEntry<String, Flashcard>> filtered;
    switch (_filterIndex) {
      case 0:
        filtered = all.where((e) => e.value.level == 0).toList();
        break;
      case 1:
        filtered = all.where((e) => e.value.level < 2).toList();
        break;
      default:
        filtered = all;
    }
    return filtered.where((e) {
      if (e.value.nextReview == null) return true;
      return !e.value.nextReview!.isAfter(now);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kort')),
      body: Column(
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Nya'), icon: Icon(Icons.fiber_new)),
              ButtonSegment(value: 1, label: Text('Svåra'), icon: Icon(Icons.warning)),
              ButtonSegment(value: 2, label: Text('Alla'), icon: Icon(Icons.apps)),
            ],
            selected: {_filterIndex},
            onSelectionChanged: (s) => setState(() {
              _filterIndex = s.first;
              _currentIndex = 0;
            }),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('homeworks').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final allCards = <MapEntry<String, Flashcard>>[];
                for (final doc in snapshot.data!.docs) {
                  final hw = Homework.fromMap(doc.id, doc.data() as Map<String, dynamic>);
                  for (var i = 0; i < hw.flashcards.length; i++) {
                    allCards.add(MapEntry('${doc.id}_$i', hw.flashcards[i]));
                  }
                }
                final cards = _filter(allCards);
                if (cards.isEmpty) {
                  return Center(
                    child: Text(
                      'Inga kort att öva på',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }
                final idx = _currentIndex.clamp(0, cards.length - 1);
                return _buildCardView(cards, idx);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardView(List<MapEntry<String, Flashcard>> cards, int idx) {
    if (idx >= cards.length) return const SizedBox();
    final entry = cards[idx];
    final card = entry.value;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showBack = !_showBack),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassCard(context: context),
              child: Column(
                children: [
                  Text(
                    _showBack ? card.back : card.front,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (!_showBack) Text('Tryck för att vända', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          if (_showBack) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton.icon(
                  onPressed: () => _rate(cards, idx, entry, false),
                  icon: const Icon(Icons.close),
                  label: const Text('Svår'),
                ),
                FilledButton.icon(
                  onPressed: () => _rate(cards, idx, entry, true),
                  icon: const Icon(Icons.check),
                  label: const Text('Lätt'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _rate(List<MapEntry<String, Flashcard>> cards, int idx, MapEntry<String, Flashcard> entry, bool easy) {
    final card = entry.value;
    if (easy) {
      card.level = (card.level + 1).clamp(0, 3);
      card.nextReview = DateTime.now().add(Duration(days: card.level == 1 ? 1 : card.level == 2 ? 3 : 7));
    } else {
      card.level = 0;
      card.nextReview = DateTime.now();
    }
    // TODO: Spara tillbaka till Firestore homework flashcard
    setState(() {
      _showBack = false;
      _currentIndex = (idx + 1) % cards.length;
    });
  }
}
