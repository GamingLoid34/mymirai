import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/pages/exercises_page.dart';
import 'package:my_mirai/pages/login_page.dart';
import 'package:my_mirai/pages/manage_members_page.dart';
import 'package:my_mirai/pages/math_page.dart';
import 'package:my_mirai/pages/work_page.dart';

class HomePage extends StatefulWidget {
  final AppUser currentUser;

  const HomePage({super.key, required this.currentUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppUser? _selectedChild;
  final List<AppUser> _children = []; // TODO: hämta från Firestore
  int _navIndex = 0;

  AppUser get _activeProfile {
    if (widget.currentUser.isBarn) return widget.currentUser;
    if (_selectedChild != null) return _selectedChild!;
    if (_children.isNotEmpty) return _children.first;
    return widget.currentUser;
  }

  @override
  Widget build(BuildContext context) {
    final profile = _activeProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Mirai'),
        actions: [
          if (widget.currentUser.isForalder || widget.currentUser.isAdmin)
            IconButton(
              icon: const Icon(Icons.people_alt_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManageMembersPage(currentUser: widget.currentUser),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildDashboard(profile),
          WorkPage(
            currentUser: widget.currentUser,
            selectedChild: widget.currentUser.isBarn ? widget.currentUser : _selectedChild,
          ),
          ExercisesPage(
            currentUser: widget.currentUser,
            selectedChild: widget.currentUser.isBarn ? widget.currentUser : _selectedChild,
          ),
          MathPage(
            currentUser: widget.currentUser,
            selectedChild: widget.currentUser.isBarn ? widget.currentUser : _selectedChild,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Hem'),
          NavigationDestination(icon: Icon(Icons.assignment_rounded), label: 'Läxor'),
          NavigationDestination(icon: Icon(Icons.style_rounded), label: 'Kort'),
          NavigationDestination(icon: Icon(Icons.calculate_rounded), label: 'Matte'),
        ],
        selectedIndex: _navIndex,
        onDestinationSelected: (index) => setState(() => _navIndex = index),
      ),
    );
  }

  Widget _buildDashboard(AppUser profile) {
    final firstName = profile.name.trim().isEmpty
        ? 'vän'
        : profile.name.trim().split(' ').first;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.pageGradient),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hej, $firstName!',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bygg upp dina kunskaper steg för steg.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black.withOpacity(0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF2D2A45),
                  child: Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lär smartare med\nAI-driven guidning',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => setState(() => _navIndex = 1),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Starta nu'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildProfileSelector(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      _buildMetricCard('1.5', 'timmar'),
                      const SizedBox(height: 10),
                      _buildMetricCard('10', 'lektioner'),
                      const SizedBox(height: 10),
                      _buildMetricCard('0', 'slutförda läxor'),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _buildMetricCard('1.5', 'timmar')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildMetricCard('10', 'lektioner')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildMetricCard('0', 'slutförda läxor')),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: AppTheme.glassCard(context: context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Mitt schema',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.more_horiz, color: Colors.black.withOpacity(0.45)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      _DayPill(day: 'Mån', date: '12'),
                      SizedBox(width: 8),
                      _DayPill(day: 'Tis', date: '13'),
                      SizedBox(width: 8),
                      _DayPill(day: 'Ons', date: '14', selected: true),
                      SizedBox(width: 8),
                      _DayPill(day: 'Tor', date: '15'),
                      SizedBox(width: 8),
                      _DayPill(day: 'Fre', date: '16'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _scheduleItem(
                    time: '08:00',
                    title: 'Svenska - läsförståelse',
                    subtitle: '08:00 till 08:45',
                    color: const Color(0xFF8D80FF),
                  ),
                  const SizedBox(height: 10),
                  _scheduleItem(
                    time: '10:00',
                    title: 'Matte - bråk och procent',
                    subtitle: '10:00 till 10:45',
                    color: const Color(0xFFB59DFF),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ämnen',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSubjectChip('Matte', Icons.calculate_rounded, const Color(0xFF6FCF97)),
                _buildSubjectChip('Svenska', Icons.menu_book_rounded, const Color(0xFF56CCF2)),
                _buildSubjectChip('Engelska', Icons.translate_rounded, const Color(0xFFBB6BD9)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSelector() {
    final dropdownValue = widget.currentUser.isBarn
        ? widget.currentUser
        : (_selectedChild ?? (_children.isNotEmpty ? _children.first : widget.currentUser));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: AppTheme.glassCard(context: context),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppUser>(
          value: dropdownValue,
          isExpanded: true,
          hint: const Text('Välj profil'),
          items: [
            if (widget.currentUser.isBarn)
              DropdownMenuItem(
                value: widget.currentUser,
                child: _profileTile(widget.currentUser),
              ),
            if (!widget.currentUser.isBarn && _children.isEmpty)
              DropdownMenuItem(
                value: widget.currentUser,
                child: const Text('Inga barn ännu - lägg till under Admin'),
              ),
            if (!widget.currentUser.isBarn && _children.isNotEmpty)
              ..._children.map(
                (child) => DropdownMenuItem(
                  value: child,
                  child: _profileTile(child),
                ),
              ),
          ],
          onChanged: widget.currentUser.isBarn
              ? null
              : (next) => setState(() => _selectedChild = next),
        ),
      ),
    );
  }

  Widget _profileTile(AppUser user) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Color(user.color),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Text(user.name.isNotEmpty ? user.name : 'Okänd'),
      ],
    );
  }

  Widget _buildMetricCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: AppTheme.glassCard(context: context),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insights_rounded, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black.withOpacity(0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleItem({
    required String time,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            time,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.black.withOpacity(0.68),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.black.withOpacity(0.62), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  final String day;
  final String date;
  final bool selected;

  const _DayPill({
    required this.day,
    required this.date,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppTheme.primary : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : Colors.black.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Colors.black.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
