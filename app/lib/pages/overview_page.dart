import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../widgets/action_preview.dart';

/// Conta, sincronização, números gerais e limpeza por busca.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.state});

  final AppState state;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _stats;
  bool _permanentDelete = false;
  bool _loggingIn = false;
  Timer? _loginPoll;
  int _seenVersion = -1;
  final _syncQuery = TextEditingController();
  final _cleanQuery = TextEditingController();

  AppState get state => widget.state;

  static const _presets = {
    'Promoções > 1 ano': 'category:promotions older_than:1y',
    'Redes sociais > 6 meses': 'category:social older_than:6m',
    'Maiores que 10 MB': 'larger:10M',
    'Não lidos > 2 anos': 'is:unread older_than:2y',
  };

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    _loadStats();
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _loginPoll?.cancel();
    _syncQuery.dispose();
    _cleanQuery.dispose();
    super.dispose();
  }

  void _onState() {
    if (state.dataVersion != _seenVersion) _loadStats();
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    _seenVersion = state.dataVersion;
    try {
      final stats = await state.api.get('/api/stats');
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _login() async {
    setState(() => _loggingIn = true);
    try {
      final res = await state.api.post('/api/auth/login', {
        'permanentDelete': _permanentDelete,
      });
      await launchUrl(
        Uri.parse(res['url'] as String),
        webOnlyWindowName: '_blank',
      );
      _loginPoll?.cancel();
      var ticks = 0;
      _loginPoll = Timer.periodic(const Duration(seconds: 2), (t) async {
        await state.refreshAuth();
        if (state.authenticated || ++ticks > 150) {
          t.cancel();
          if (mounted) setState(() => _loggingIn = false);
        }
      });
    } catch (e) {
      _show(e.toString());
      setState(() => _loggingIn = false);
    }
  }

  Future<void> _logout() async {
    await state.api.post('/api/auth/logout');
    await state.refreshAuth();
  }

  Future<void> _sync() async {
    try {
      final res = await state.api.post('/api/sync', {'query': _syncQuery.text});
      state.trackJob(res['job'] as Map<String, dynamic>);
    } catch (e) {
      _show(e.toString());
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Visão geral', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _accountCard(context),
        if (state.authenticated) ...[
          const SizedBox(height: 16),
          _statsGrid(context),
          const SizedBox(height: 16),
          _syncCard(context),
          const SizedBox(height: 16),
          _cleanupCard(context),
        ],
      ],
    );
  }

  Widget _accountCard(BuildContext context) {
    final auth = state.auth;
    if (state.connectionError != null) {
      return _card(
        context,
        icon: Icons.cloud_off,
        title: 'Servidor offline',
        children: [
          Text(state.connectionError!),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: state.refreshAuth,
            child: const Text('Tentar de novo'),
          ),
        ],
      );
    }
    if (auth == null) return const Center(child: CircularProgressIndicator());

    if (auth['configured'] != true) {
      return _card(
        context,
        icon: Icons.key_off,
        title: 'Credenciais do Google não encontradas',
        children: const [
          Text(
            'Coloque o arquivo client_secret.json em server/data/ e reinicie o servidor. '
            'O passo a passo está no README do projeto.',
          ),
        ],
      );
    }

    if (!state.authenticated) {
      return _card(
        context,
        icon: Icons.login,
        title: 'Conectar ao Gmail',
        children: [
          if (auth['lastError'] != null) ...[
            Text(
              auth['lastError'] as String,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _permanentDelete,
            onChanged: _loggingIn
                ? null
                : (v) => setState(() => _permanentDelete = v ?? false),
            title: const Text('Permitir exclusão permanente'),
            subtitle: const Text(
              'Pede acesso total ao Gmail (escopo https://mail.google.com/). '
              'Sem isso, o Silver Mail só move para a lixeira.',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loggingIn ? null : _login,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Entrar com Google'),
              ),
              if (_loggingIn) ...[
                const SizedBox(width: 16),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('Aguardando a autorização na outra aba…'),
              ],
            ],
          ),
        ],
      );
    }

    return _card(
      context,
      icon: Icons.verified_user_outlined,
      title: auth['email'] as String? ?? 'Conectado',
      trailing: TextButton(onPressed: _logout, child: const Text('Sair')),
      children: [
        Wrap(
          spacing: 8,
          children: [
            const Chip(
              avatar: Icon(Icons.delete_outline, size: 18),
              label: Text('Lixeira'),
            ),
            Chip(
              avatar: Icon(
                state.canDeletePermanently ? Icons.check : Icons.block,
                size: 18,
              ),
              label: Text(
                state.canDeletePermanently
                    ? 'Exclusão permanente liberada'
                    : 'Exclusão permanente bloqueada',
              ),
            ),
          ],
        ),
        if (!state.canDeletePermanently)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Para liberar, clique em "Sair" e entre de novo marcando a opção.',
            ),
          ),
      ],
    );
  }

  Widget _statsGrid(BuildContext context) {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();
    final tiles = [
      (
        'Mensagens no cache',
        formatCount(s['totalMessages'] as num),
        Icons.mail_outline,
      ),
      ('Espaço ocupado', formatBytes(s['totalSize'] as num), Icons.storage),
      (
        'Não lidas',
        formatCount(s['unread'] as num),
        Icons.mark_email_unread_outlined,
      ),
      ('Remetentes', formatCount(s['senders'] as num), Icons.people_outline),
      (
        'Com link de descadastro',
        formatCount(s['sendersWithUnsubscribe'] as num),
        Icons.unsubscribe_outlined,
      ),
      (
        'Última sincronização',
        formatDateTime(s['lastSyncMs'] as num?),
        Icons.schedule,
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, value, icon) in tiles)
          SizedBox(
            width: 220,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _syncCard(BuildContext context) {
    final never = _stats?['lastSyncMs'] == null;
    return _card(
      context,
      icon: Icons.sync,
      title: 'Sincronizar',
      children: [
        Text(
          never
              ? 'Primeiro passo: baixar os metadados (remetente, assunto, data, tamanho) para o cache local. '
                    'Caixas grandes podem levar alguns minutos — o conteúdo dos e-mails não é baixado.'
              : 'Busca novidades e remove do cache o que foi apagado fora do Silver Mail.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _syncQuery,
                decoration: const InputDecoration(
                  labelText: 'Filtro opcional (sintaxe de busca do Gmail)',
                  hintText: 'ex.: newer_than:1y  — vazio = caixa inteira',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: state.jobRunning ? null : _sync,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cleanupCard(BuildContext context) {
    return _card(
      context,
      icon: Icons.cleaning_services_outlined,
      title: 'Limpeza por busca',
      children: [
        const Text(
          'Use qualquer busca do Gmail. Você sempre vê uma prévia antes de confirmar.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _presets.entries)
              ActionChip(
                label: Text(e.key),
                onPressed: () => setState(() => _cleanQuery.text = e.value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cleanQuery,
          decoration: const InputDecoration(
            labelText: 'Busca',
            hintText: 'ex.: from:loja.com older_than:6m',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.jobRunning ? null : () => _clean('trash'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Mover para a lixeira…'),
            ),
            OutlinedButton.icon(
              onPressed: state.jobRunning || !state.canDeletePermanently
                  ? null
                  : () => _clean('delete'),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Apagar permanentemente…'),
            ),
          ],
        ),
      ],
    );
  }

  void _clean(String action) {
    final q = _cleanQuery.text.trim();
    if (q.isEmpty) return _show('Digite uma busca.');
    previewAndRun(context, state, action: action, target: {'query': q});
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
