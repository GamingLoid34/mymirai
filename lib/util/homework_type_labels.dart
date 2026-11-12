/// Hjälptexter och förklaringar för läxtyper (AP4).
String homeworkTypeLabel(String type) {
  switch (type) {
    case 'vocabulary':
      return 'Glosor';
    case 'math':
      return 'Matte';
    case 'text':
    default:
      return 'Text';
  }
}

String homeworkTypeExplanation(String type) {
  switch (type) {
    case 'vocabulary':
      return 'Glosor → förhörskort per ord, redo att förhöras på.';
    case 'math':
      return 'Matte → uppgifterna listas med förklaringar och övningsvarianter.';
    case 'text':
    default:
      return 'Text → sammanfattning att lyssna på + AI-frågor att träna med.';
  }
}
