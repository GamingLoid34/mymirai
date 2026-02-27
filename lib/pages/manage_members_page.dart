import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';

/// Admin-sida: Föräldrar kan lägga till barn (namn, e-post, lösenord, årskurs 1–9).
class ManageMembersPage extends StatefulWidget {
  final AppUser currentUser;

  const ManageMembersPage({super.key, required this.currentUser});

  @override
  State<ManageMembersPage> createState() => _ManageMembersPageState();
}

class _ManageMembersPageState extends State<ManageMembersPage> {
  final _firestore = FirebaseFirestore.instance;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  int _schoolYear = 5;
  UserRole _role = UserRole.barn;
  EducationLevel _educationLevel = EducationLevel.grundskola;
  bool _enableNursingProgram = false;
  bool _medcalcEnabled = true;
  int _color = 0xFF4FC3F7;
  bool _loading = false;

  static const _colors = [
    0xFF4FC3F7, 0xFF66BB6A, 0xFFFFB74D, 0xFF7E57C2,
    0xFFE57373, 0xFF64B5F6, 0xFF81C784, 0xFFFFB74D,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i namn, e-post och lösenord')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final effectiveEducationLevel =
          _role == UserRole.barn ? EducationLevel.grundskola : _educationLevel;
      final canEnableStudyPrograms = effectiveEducationLevel.isEligibleForStudyPrograms;

      await _firestore.collection('users').add({
        'name': name,
        'email': email,
        'password': password,
        'color': _color,
        'role': _role.name,
        if (_role == UserRole.barn) 'schoolYear': _schoolYear,
        'educationLevel': effectiveEducationLevel.name,
        'activePrograms': canEnableStudyPrograms && _enableNursingProgram
            ? [AppUser.nursingProgramId]
            : <String>[],
        'featureFlags': {
          'medcalc': canEnableStudyPrograms ? _medcalcEnabled : false,
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medlem tillagd')),
        );
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hantera medlemmar'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lägg till medlem',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Namn',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-post',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Lösenord',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Roll
            DropdownButtonFormField<UserRole>(
              value: _role,
              decoration: const InputDecoration(
                labelText: 'Roll',
                border: OutlineInputBorder(),
              ),
              items: UserRole.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _role = v ?? UserRole.barn;
                  if (_role == UserRole.barn) {
                    _educationLevel = EducationLevel.grundskola;
                    _enableNursingProgram = false;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EducationLevel>(
              value: _educationLevel,
              decoration: const InputDecoration(
                labelText: 'Utbildningsnivå',
                border: OutlineInputBorder(),
              ),
              items: EducationLevel.values
                  .map(
                    (level) => DropdownMenuItem(
                      value: level,
                      child: Text(level.label),
                    ),
                  )
                  .toList(),
              onChanged: _role == UserRole.barn
                  ? null
                  : (level) => setState(
                        () => _educationLevel = level ?? EducationLevel.grundskola,
                      ),
            ),
            if (_role == UserRole.barn) ...[
              const SizedBox(height: 16),
              Text('Årskurs: $_schoolYear'),
              Slider(
                value: _schoolYear.toDouble(),
                min: 1,
                max: 9,
                divisions: 8,
                label: '$_schoolYear',
                onChanged: (v) => setState(() => _schoolYear = v.round()),
              ),
            ],
            if (_educationLevel.isEligibleForStudyPrograms) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktivera Sjuksköterskeprogrammet'),
                value: _enableNursingProgram,
                onChanged: (value) =>
                    setState(() => _enableNursingProgram = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktivera Läkemedelsberäkning'),
                value: _medcalcEnabled,
                onChanged: (value) => setState(() => _medcalcEnabled = value),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _colors.map((c) {
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: _color == c ? Border.all(width: 3, color: Colors.black) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _addMember,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Lägg till'),
            ),
            const SizedBox(height: 32),
            Text(
              'Nuvarande medlemmar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.glassCard(context: context),
                    child: const Text('Inga medlemmar ännu'),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final u = AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>);
                    final level = u.educationLevel.label;
                    final nursing = u.hasNursingProgram ? ' • Sjuksköterska' : '';
                    final initial = u.name.isNotEmpty ? u.name[0].toUpperCase() : '?';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(u.color),
                        child: Text(initial),
                      ),
                      title: Text(u.name),
                      subtitle: Text(
                        '${u.role.label}${u.schoolYear != null ? " • Årskurs ${u.schoolYear}" : ""} • $level$nursing',
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
