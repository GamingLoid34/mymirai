/// Dataklasser för My Mirai.

/// Roll: Barn, Förälder eller Admin.
enum UserRole {
  barn,
  foralder,
  admin;

  String get label {
    switch (this) {
      case UserRole.barn: return 'Barn';
      case UserRole.foralder: return 'Förälder';
      case UserRole.admin: return 'Admin';
    }
  }

  static UserRole? fromString(String? v) {
    if (v == null) return null;
    switch (v.toLowerCase()) {
      case 'barn': return UserRole.barn;
      case 'foralder': return UserRole.foralder;
      case 'admin': return UserRole.admin;
      default: return null;
    }
  }
}

/// Utbildningsnivå för att styra vilka moduler som visas.
enum EducationLevel {
  grundskola,
  gymnasie,
  universitet,
  vuxenutbildning;

  String get label {
    switch (this) {
      case EducationLevel.grundskola:
        return 'Grundskola';
      case EducationLevel.gymnasie:
        return 'Gymnasie';
      case EducationLevel.universitet:
        return 'Universitet';
      case EducationLevel.vuxenutbildning:
        return 'Vuxenutbildning';
    }
  }

  bool get isEligibleForStudyPrograms {
    return this == EducationLevel.gymnasie ||
        this == EducationLevel.universitet ||
        this == EducationLevel.vuxenutbildning;
  }

  static EducationLevel fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'gymnasie':
        return EducationLevel.gymnasie;
      case 'universitet':
        return EducationLevel.universitet;
      case 'vuxenutbildning':
        return EducationLevel.vuxenutbildning;
      case 'grundskola':
      default:
        return EducationLevel.grundskola;
    }
  }
}

/// Användare (Firestore: users).
class AppUser {
  static const nursingProgramId = 'nursing_rn';

  final String id;
  final String name;
  final String email;
  final String password;
  final int color;
  final UserRole role;
  final int? schoolYear; // 1–9 för barn
  final EducationLevel educationLevel;
  final List<String> activePrograms;
  final bool medcalcEnabled;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.color,
    required this.role,
    this.schoolYear,
    required this.educationLevel,
    required this.activePrograms,
    required this.medcalcEnabled,
  });

  bool get isBarn => role == UserRole.barn;
  bool get isForalder => role == UserRole.foralder;
  bool get isAdmin => role == UserRole.admin;
  bool get hasNursingProgram => activePrograms.contains(nursingProgramId);
  bool get canSeeStudyPrograms =>
      educationLevel.isEligibleForStudyPrograms &&
      medcalcEnabled &&
      hasNursingProgram;

  factory AppUser.fromMap(String id, Map<String, dynamic> m) {
    final programsRaw = m['activePrograms'];
    final programs = <String>[];
    if (programsRaw is List) {
      for (final p in programsRaw) {
        final value = p.toString().trim();
        if (value.isNotEmpty) programs.add(value);
      }
    }

    final featureFlags = m['featureFlags'];
    bool medcalcEnabled = true;
    if (featureFlags is Map<String, dynamic>) {
      final value = featureFlags['medcalc'];
      if (value is bool) medcalcEnabled = value;
    } else if (featureFlags is Map) {
      final value = featureFlags['medcalc'];
      if (value is bool) medcalcEnabled = value;
    } else if (m['medcalcEnabled'] is bool) {
      medcalcEnabled = m['medcalcEnabled'] as bool;
    }

    return AppUser(
      id: id,
      name: m['name']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      password: m['password']?.toString() ?? '',
      color: (m['color'] is int) ? m['color'] as int : 0xFF4FC3F7,
      role: UserRole.fromString(m['role']?.toString()) ?? UserRole.barn,
      schoolYear: m['schoolYear'] != null ? (m['schoolYear'] is int ? m['schoolYear'] as int : int.tryParse(m['schoolYear'].toString())) : null,
      educationLevel: EducationLevel.fromString(m['educationLevel']?.toString()),
      activePrograms: programs,
      medcalcEnabled: medcalcEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'password': password,
    'color': color,
    'role': role.name,
    if (schoolYear != null) 'schoolYear': schoolYear,
    'educationLevel': educationLevel.name,
    'activePrograms': activePrograms,
    'featureFlags': {
      'medcalc': medcalcEnabled,
    },
  };
}

/// Läxa (Firestore: homeworks).
class Homework {
  final String id;
  final String title;
  final String subject;
  final String originalText;
  final List<Flashcard> flashcards;
  final String? aiSummary;
  final List<String> substeps;
  final List<String> imagesBase64;
  final String languageCode;

  Homework({
    required this.id,
    required this.title,
    required this.subject,
    required this.originalText,
    required this.flashcards,
    this.aiSummary,
    this.substeps = const [],
    this.imagesBase64 = const [],
    this.languageCode = 'sv',
  });

  factory Homework.fromMap(String id, Map<String, dynamic> m) {
    final fc = m['flashcards'];
    List<Flashcard> list = [];
    if (fc is List) {
      for (var i = 0; i < fc.length; i++) {
        final f = fc[i];
        if (f is Map) list.add(Flashcard.fromMap(f as Map<String, dynamic>));
      }
    }
    final ss = m['substeps'];
    List<String> substeps = [];
    if (ss is List) substeps = ss.map((e) => e.toString()).toList();
    final imgs = m['imagesBase64'];
    List<String> images = [];
    if (imgs is List) images = imgs.map((e) => e.toString()).toList();
    return Homework(
      id: id,
      title: m['title']?.toString() ?? '',
      subject: m['subject']?.toString() ?? '',
      originalText: m['originalText']?.toString() ?? '',
      flashcards: list,
      aiSummary: m['aiSummary']?.toString(),
      substeps: substeps,
      imagesBase64: images,
      languageCode: m['languageCode']?.toString() ?? 'sv',
    );
  }
}

/// Glos-/frågekort (del av Homework, används i exercises).
class Flashcard {
  final String front;
  final String back;
  int level; // 0–2+ för Spaced Repetition
  DateTime? nextReview;

  Flashcard({
    required this.front,
    required this.back,
    this.level = 0,
    this.nextReview,
  });

  factory Flashcard.fromMap(Map<String, dynamic> m) {
    return Flashcard(
      front: m['front']?.toString() ?? '',
      back: m['back']?.toString() ?? '',
      level: (m['level'] is int) ? m['level'] as int : 0,
      nextReview: m['nextReview'] != null ? DateTime.tryParse(m['nextReview'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'front': front,
    'back': back,
    'level': level,
    if (nextReview != null) 'nextReview': nextReview!.toIso8601String(),
  };
}

/// Ämne (Firestore: subjects).
class Subject {
  final String id;
  final String name;
  final int color;
  final String icon;

  Subject({
    required this.id,
    required this.name,
    required this.color,
    this.icon = 'book',
  });

  factory Subject.fromMap(String id, Map<String, dynamic> m) {
    return Subject(
      id: id,
      name: m['name']?.toString() ?? '',
      color: (m['color'] is int) ? m['color'] as int : 0xFF66BB6A,
      icon: m['icon']?.toString() ?? 'book',
    );
  }
}
