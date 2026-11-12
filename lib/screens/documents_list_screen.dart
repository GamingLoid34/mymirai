import 'package:flutter/material.dart';

import '../data/document_repository.dart';
import '../models/document.dart';
import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/document_labels.dart';
import '../widgets/document_add_menu.dart';
import 'document_detail_screen.dart';

enum _DocFilter { recent, unread }

class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
    this.authService,
  });

  final DocumentRepository repository;
  final String ownerUid;
  final AuthService? authService;

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _DocFilter _filter = _DocFilter.recent;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserDocument> _visible(List<UserDocument> docs) {
    var out = docs;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((d) {
        final haystack = '${d.title} ${d.summary ?? ''} ${d.userNotes ?? ''}'.toLowerCase();
        return haystack.contains(q);
      }).toList();
    }
    if (_filter == _DocFilter.unread) {
      out = out.where((d) => d.readingProgress < 0.02).toList();
    }
    out = [...out]
      ..sort((a, b) {
        DateTime? sortKey(UserDocument d) => d.lastReadAt ?? d.updatedAt ?? d.createdAt;
        final ak = sortKey(a);
        final bk = sortKey(b);
        if (ak == null && bk == null) return 0;
        if (ak == null) return 1;
        if (bk == null) return -1;
        return bk.compareTo(ak);
      });
    return out;
  }

  String _rowSubtitle(UserDocument d) {
    final visual = documentTypeVisual(d.sourceType);
    final progressPart = d.readingProgress >= 0.02
        ? 'Lyssnat ${(d.readingProgress.clamp(0.0, 1.0) * 100).round()}%'
        : 'Oläst';
    final dateSource = d.lastReadAt ?? d.updatedAt ?? d.createdAt;
    final datePart = dateSource == null ? '' : ' · ${dateSource.day}/${dateSource.month}';
    return '${visual.label} · $progressPart$datePart';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final auth = widget.authService;
    final showPersonaSwitcher = auth != null && auth.savedPersona == UserPersona.both;

    Widget? personaStrip;
    if (showPersonaSwitcher) {
      personaStrip = Padding(
        padding: const EdgeInsets.only(bottom: MiraiTokens.spaceMd),
        child: SegmentedButton<UserPersona>(
          segments: const [
            ButtonSegment(value: UserPersona.child, label: Text('Barn')),
            ButtonSegment(value: UserPersona.adult, label: Text('Vuxen')),
          ],
          selected: {auth.activePersona},
          onSelectionChanged: (next) {
            auth.setActivePersona(next.first);
          },
        ),
      );
    }

    return Scaffold(
      body: StreamBuilder<List<UserDocument>>(
        stream: widget.repository.watchForOwner(widget.ownerUid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return SafeArea(
              child: Center(
                child: MiraiAdaptiveBox(
                  child: ListView(
                    padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                    children: [
                      ?personaStrip,
                      const SizedBox(height: MiraiTokens.spaceLg),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
              ),
            );
          }
          final allDocs = snap.data!;
          if (allDocs.isEmpty) {
            return SafeArea(
              child: Center(
                child: MiraiAdaptiveBox(
                  child: ListView(
                    padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                    children: [
                      ?personaStrip,
                      Text(
                        'Inga dokument än',
                        style: tt.bodyLarge?.copyWith(color: MiraiTokens.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final docs = _visible(allDocs);

          return SafeArea(
            child: Center(
              child: MiraiAdaptiveBox(
                child: ListView(
                  padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                  children: [
                    ?personaStrip,
                    Text(
                      'Dokument',
                      style: tt.headlineLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: MiraiTokens.spaceMd),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Sök i titel, sammanfattning, anteckningar…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: MiraiTokens.spaceSm),
                    Wrap(
                      spacing: MiraiTokens.spaceXs,
                      children: [
                        ChoiceChip(
                          label: const Text('Senaste'),
                          selected: _filter == _DocFilter.recent,
                          onSelected: (_) => setState(() => _filter = _DocFilter.recent),
                        ),
                        ChoiceChip(
                          label: const Text('Olästa'),
                          selected: _filter == _DocFilter.unread,
                          onSelected: (_) => setState(() => _filter = _DocFilter.unread),
                        ),
                      ],
                    ),
                    const SizedBox(height: MiraiTokens.spaceLg),
                    if (docs.isEmpty)
                      Text(
                        'Inga dokument matchar.',
                        style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
                      )
                    else
                      for (final d in docs) ...[
                        Material(
                          color: MiraiTokens.bgRaised,
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DocumentDetailScreen(
                                    repository: widget.repository,
                                    ownerUid: widget.ownerUid,
                                    documentId: d.id,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                                border: Border.all(color: MiraiTokens.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Icon(documentTypeVisual(d.sourceType).icon),
                                  const SizedBox(width: MiraiTokens.spaceSm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d.title, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _rowSubtitle(d),
                                          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: MiraiTokens.spaceSm),
                      ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDocumentAddMenu(
          context,
          repository: widget.repository,
          ownerUid: widget.ownerUid,
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nytt dokument'),
      ),
    );
  }
}
