import 'package:flutter/material.dart';

({String label, IconData icon}) documentTypeVisual(String sourceType) {
  switch (sourceType.trim().toLowerCase()) {
    case 'file':
    case 'pdf':
      return (label: 'Fil', icon: Icons.description_outlined);
    case 'article':
    case 'url':
      return (label: 'Artikel', icon: Icons.link_rounded);
    case 'text':
      return (label: 'Text', icon: Icons.edit_outlined);
    case 'note':
      return (label: 'Anteckning', icon: Icons.sticky_note_2_outlined);
    case 'recording':
    case 'audio':
    case 'voice':
      return (label: 'Inspelning', icon: Icons.mic_none_rounded);
    default:
      return (label: 'Dokument', icon: Icons.description_outlined);
  }
}
