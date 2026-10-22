import 'package:flutter/material.dart';

import 'api.dart';
import 'pages/history_page.dart';
import 'pages/overview_page.dart';
import 'pages/senders_page.dart';
import 'pages/unsubscribe_page.dart';
import 'widgets/job_banner.dart';

void main() => runApp(const SilverMailApp());

class SilverMailApp extends StatelessWidget {
  const SilverMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF607D8B),
        brightness: b,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Silver Mail',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _state = AppState(Api());
  int _index = 0;

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Visão geral'),
    (Icons.people_outline, Icons.people, 'Remetentes'),
    (Icons.unsubscribe_outlined, Icons.unsubscribe, 'Descadastro'),
    (Icons.history_outlined, Icons.history, 'Histórico'),
  ];

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final locked = !_state.authenticated;
        final page = switch (locked ? 0 : _index) {
          1 => SendersPage(state: _state),
          2 => UnsubscribePage(state: _state),
          3 => HistoryPage(state: _state),
          _ => OverviewPage(state: _state),
        };
        final wide = MediaQuery.sizeOf(context).width >= 720;

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JobBanner(state: _state),
            Expanded(child: page),
          ],
        );

        return Scaffold(
          appBar: wide ? null : AppBar(title: const Text('Silver Mail')),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      extended: MediaQuery.sizeOf(context).width >= 1100,
                      selectedIndex: locked ? 0 : _index,
                      onDestinationSelected: locked
                          ? null
                          : (i) => setState(() => _index = i),
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Icon(Icons.mail_lock_outlined, size: 32),
                      ),
                      destinations: [
                        for (final (icon, selected, label) in _destinations)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selected),
                            label: Text(label),
                            disabled: locked && label != 'Visão geral',
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: locked ? 0 : _index,
                  onDestinationSelected: locked
                      ? null
                      : (i) => setState(() => _index = i),
                  destinations: [
                    for (final (icon, selected, label) in _destinations)
                      NavigationDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
