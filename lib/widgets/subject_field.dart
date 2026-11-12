import 'package:flutter/material.dart';

import '../theme/mirai_tokens.dart';

/// RawAutocomplete med familjens + standardämnen (Chunk M).
class SubjectField extends StatefulWidget {
  const SubjectField({
    super.key,
    required this.controller,
    required this.options,
    required this.label,
    this.hint,
    this.denseBox = true,
  });

  final TextEditingController controller;
  final List<String> options;
  final String label;
  final String? hint;
  final bool denseBox;

  @override
  State<SubjectField> createState() => _SubjectFieldState();
}

class _SubjectFieldState extends State<SubjectField> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<String> _filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.options.take(16);
    return widget.options
        .where((o) => o.toLowerCase().contains(q))
        .take(40);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (o) => o,
      optionsBuilder: (v) => _filtered(v.text),
      optionsViewBuilder: (context, onSelected, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            color: MiraiTokens.bgRaised,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, i) {
                  final o = opts.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, c, focusNode, onSubmit) {
        if (widget.denseBox) {
          return Container(
            decoration: BoxDecoration(
              color: MiraiTokens.bgRaised,
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: c,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: InputBorder.none,
              ),
            ),
          );
        }
        return TextField(
          controller: c,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
          ),
        );
      },
    );
  }
}
