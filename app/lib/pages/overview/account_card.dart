import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import 'section_card.dart';

/// Estado da conexão com o Gmail: servidor offline, credenciais ausentes,
/// login ou conta conectada.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key, required this.state});

  final AppState state;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _permanentDelete = false;
  bool _loggingIn = false;
  Timer? _loginPoll;

  AppState get state => widget.state;

  @override
  void dispose() {
    _loginPoll?.cancel();
    super.dispose();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _loggingIn = false);
    }
  }

  Future<void> _logout() async {
    await state.api.post('/api/auth/logout');
    await state.refreshAuth();
  }

  @override
  Widget build(BuildContext context) {
    final auth = state.auth;

    if (state.connectionError != null) {
      return SectionCard(
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
      return const SectionCard(
        icon: Icons.key_off,
        title: 'Credenciais do Google não encontradas',
        children: [
          Text(
            'Coloque o arquivo client_secret.json em server/data/ e reinicie '
            'o servidor. O passo a passo está no README do projeto.',
          ),
        ],
      );
    }

    if (!state.authenticated) {
      return SectionCard(
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
              if (_loggingIn) ...const [
                SizedBox(width: 16),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Aguardando a autorização na outra aba…'),
              ],
            ],
          ),
        ],
      );
    }

    return SectionCard(
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
}
