import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/pages/login_page.dart';
import 'package:my_mirai/pages/manage_members_page.dart';
import 'package:my_mirai/pages/work_page.dart';
import 'package:my_mirai/pages/exercises_page.dart';
import 'package:my_mirai/pages/math_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Mirai'),
        actions: [
          if (widget.currentUser.isForalder || widget.currentUser.isAdmin)
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManageMembersPage(currentUser: widget.currentUser),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
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
          _buildHomeContent(),
          WorkPage(currentUser: widget.currentUser, selectedChild: _selectedChild ?? (widget.currentUser.isBarn ? widget.currentUser : null)),
          ExercisesPage(currentUser: widget.currentUser, selectedChild: _selectedChild ?? (widget.currentUser.isBarn ? widget.currentUser : null)),
          MathPage(currentUser: widget.currentUser, selectedChild: _selectedChild ?? (widget.currentUser.isBarn ? widget.currentUser : null)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Hem'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Läxor'),
          NavigationDestination(icon: Icon(Icons.style), label: 'Kort'),
          NavigationDestination(icon: Icon(Icons.calculate), label: 'Matte'),
        ],
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
      ),
    );
  }

  Widget _buildHomeContent() {
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.dayColor.withOpacity(0.15),
              Colors.transparent,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ryggsäcken – dropdown för barnprofil
              Text(
                'Ryggsäcken',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: AppTheme.glassCard(context: context),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AppUser>(
                    value: widget.currentUser.isBarn
                        ? widget.currentUser
                        : (_selectedChild ?? _children.firstOrNull ?? widget.currentUser),
                    isExpanded: true,
                    hint: const Text('Välj barn'),
                    items: [
                      if (widget.currentUser.isBarn)
                        DropdownMenuItem(
                          value: widget.currentUser,
                          child: _profileTile(widget.currentUser),
                        ),
                      if (!widget.currentUser.isBarn && _children.isEmpty)
                        DropdownMenuItem(
                          value: widget.currentUser,
                          child: const Text('Inga barn – lägg till under Admin'),
                        ),
                      if (!widget.currentUser.isBarn && _children.isNotEmpty)
                        ..._children.map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: _profileTile(c),
                          ),
                        ),
                    ],
                    onChanged: widget.currentUser.isBarn ? null : (v) => setState(() => _selectedChild = v),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Energipoäng
              Text(
                'Energipoäng',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppTheme.glassCard(context: context),
                child: Row(
                  children: [
                    Icon(Icons.bolt, color: AppTheme.dayColor, size: 32),
                    const SizedBox(width: 16),
                    Text(
                      '0',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.dayColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'poäng',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Senaste läxorna
              Text(
                'Senaste läxorna',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppTheme.glassCard(context: context),
                child: Text(
                  'Inga läxor ännu',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Ämnesmappar
              Text(
                'Ämnen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              // TODO: Lista subjects från Firestore
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildSubjectChip('Matte', Icons.calculate, 0xFF66BB6A),
                  _buildSubjectChip('Svenska', Icons.menu_book, 0xFF42A5F5),
                  _buildSubjectChip('Engelska', Icons.translate, 0xFFAB47BC),
                ],
              ),
            ],
          ),
        ),
    );
  }

  Widget _profileTile(AppUser u) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Color(u.color),
          child: Text(
            u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Text(u.name.isNotEmpty ? u.name : 'Okänd'),
      ],
    );
  }

  Widget _buildSubjectChip(String label, IconData icon, int color) {
    return ActionChip(
      avatar: Icon(icon, size: 20, color: Color(color)),
      label: Text(label),
      onPressed: () {},
    );
  }
}
