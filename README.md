# Silver Mail

Painel web **local** para faxinar seu Gmail: veja quem mais lota sua caixa, mande
remetentes inteiros para a lixeira, apague em massa e reúna os links de
descadastro num só lugar.

Tudo roda na sua máquina. Seus e-mails não passam por nenhum servidor além do
próprio Google.

```
┌──────────────── sua máquina (127.0.0.1:8787) ───────────────┐
│  Painel Flutter Web  ⇄  Servidor Dart (shelf)                │
│                           ├─ Gmail API (googleapis)          │
│                           └─ SQLite (cache + histórico)      │
└──────────────────────────────────────────────────────────────┘
```

## Funcionalidades

| Tela | O que faz |
| --- | --- |
| **Visão geral** | Login com Google, sincronização do cache, números gerais e **limpeza por busca** (qualquer busca do Gmail, com atalhos como “Promoções > 1 ano”). |
| **Remetentes** | Ranking por quantidade, espaço, **% de não lidos** e último envio. Selecione vários e mande para a lixeira ou apague de vez. |
| **Descadastro** | Links do cabeçalho `List-Unsubscribe` (indicando quando é “1 clique”), busca de links no corpo do e-mail quando não há cabeçalho, checklist de “feito” e **exportação CSV/Markdown**. |
| **Histórico** | Todas as ações executadas, com **desfazer** para o que foi para a lixeira. |

Toda ação em massa passa por uma **prévia**: o servidor consulta o Gmail ao
vivo, mostra quantas mensagens e quanto espaço serão afetados com exemplos, e só
executa exatamente aquela lista depois da sua confirmação.

---

## 1. Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.47+ (já inclui o Dart 3.13+).
- Uma conta Google com Gmail.

## 2. Configurar o Google Cloud (uma vez só)

O Silver Mail usa a Gmail API em nome da sua conta, então você precisa criar um
“app” seu no Google Cloud. É gratuito.

1. **Criar o projeto**
   Acesse <https://console.cloud.google.com/>, clique no seletor de projetos
   (topo da página) → **Novo projeto** → nome `silver-mail` → **Criar**.
   Confira que ele ficou selecionado.

2. **Ativar a Gmail API**
   Menu ☰ → **APIs e serviços** → **Biblioteca** → busque **Gmail API** →
   **Ativar**.

3. **Configurar a tela de consentimento**
   Menu ☰ → **APIs e serviços** → **Tela de permissão OAuth** (em contas
   novas aparece como **Google Auth Platform** → **Começar**).
   - **Informações do app:** nome `Silver Mail` e seu e-mail como suporte.
   - **Público-alvo:** **Externo**.
   - **Dados de contato:** seu e-mail → aceite a política → **Criar**.
   - Em **Público-alvo** → **Usuários de teste** → **Adicionar usuários** →
     adicione o seu próprio Gmail.
   - (Opcional) Em **Acesso a dados** → **Adicionar ou remover escopos**, inclua
     `https://www.googleapis.com/auth/gmail.modify` e, se quiser exclusão
     permanente, `https://mail.google.com/`. Isso só deixa a tela de
     consentimento mais clara; o app pede os escopos de qualquer forma.

4. **Criar a credencial**
   Em **Clientes** (ou **APIs e serviços → Credenciais → Criar credenciais →
   ID do cliente OAuth**):
   - Tipo de aplicativo: **App para computador** (*Desktop app*).
   - Nome: `Silver Mail local` → **Criar**.
   - Clique em **Baixar JSON**.

5. **Colocar o arquivo no projeto**
   Renomeie o arquivo baixado para `client_secret.json` e coloque em:

   ```
   server/data/client_secret.json
   ```

   A pasta `server/data/` está no `.gitignore` — nada dali vai para o GitHub.

### Sobre a validade do login (importante)

Enquanto o app estiver com status **Em teste**, o Google **expira o login a cada
7 dias** e você precisará clicar em “Entrar com Google” de novo.

Para evitar isso, em **Público-alvo** clique em **Publicar app** (status
**Em produção**). Como o app não passa pela verificação do Google, na hora do
login aparece o aviso *“O Google não verificou este app”* — clique em
**Avançado → Acessar Silver Mail (não seguro)**. Isso é esperado para um app
pessoal: o “desenvolvedor não verificado” é você mesmo.

## 3. Rodar

```bash
# Linux/macOS
./scripts/start.sh            # use --rebuild depois de alterar o app

# Windows (PowerShell)
./scripts/start.ps1           # use -Rebuild depois de alterar o app
```

Ou manualmente:

```bash
cd app && flutter pub get && flutter build web --release --no-web-resources-cdn
cd ../server && dart pub get && dart run bin/server.dart
```

Abra <http://127.0.0.1:8787> no navegador (funciona no Floorp/Firefox).

> `--no-web-resources-cdn` empacota o motor de renderização do Flutter junto
> com o app, em vez de baixá-lo do CDN do Google. O painel abre mesmo offline
> e não faz requisições externas.

### Primeiro uso

1. **Entrar com Google** — marque “Permitir exclusão permanente” só se quiser
   essa opção (pede acesso total ao Gmail). Sem ela, o app apenas move para a
   lixeira, que o Gmail esvazia sozinho após 30 dias.
2. **Sincronizar** — baixa só os *metadados* (remetente, assunto, data,
   tamanho e cabeçalhos de descadastro) para um SQLite local. Referência: a Gmail
   API permite ~50 mensagens/s por usuário, então 10 mil e-mails levam por volta
   de 4–5 minutos. As próximas sincronizações só baixam o que é novo.
3. Explore **Remetentes** e **Descadastro**.

## Desenvolvimento

Com hot reload no painel:

```bash
# terminal 1
cd server && dart run bin/server.dart

# terminal 2 — abra a URL impressa no Floorp
cd app && flutter run -d web-server --web-port 5000 \
  --dart-define=API_BASE=http://127.0.0.1:8787
```

Testes do servidor:

```bash
cd server && dart test
```

### Estrutura

```
server/
  bin/server.dart             # ponto de entrada (porta, pastas, middlewares)
  lib/src/auth.dart           # OAuth (loopback), token salvo em data/token.json
  lib/src/gmail_service.dart  # sincronização, lixeira, exclusão, varredura do corpo
  lib/src/database.dart       # SQLite: cache, histórico, status de descadastro
  lib/src/parsing.dart        # From, List-Unsubscribe e links no corpo
  lib/src/api.dart            # rotas HTTP + proteções do servidor local
app/
  lib/pages/                  # Visão geral, Remetentes, Descadastro, Histórico
  lib/widgets/                # prévia de ações e barra de progresso
```

### Variáveis de ambiente

| Variável | Padrão | Uso |
| --- | --- | --- |
| `SILVER_MAIL_PORT` | `8787` | Porta do servidor. |
| `SILVER_MAIL_HOME` | `server/data` | Onde ficam `client_secret.json`, `token.json` e o banco. |
| `SILVER_MAIL_WEB` | `app/build/web` | Pasta do painel compilado. |

## Segurança

- O servidor só escuta em `127.0.0.1`. Ninguém na sua rede acessa o painel.
- Requisições com `Host` diferente de localhost são recusadas, o que protege
  contra *DNS rebinding*.
- Toda requisição que altera algo exige o cabeçalho `X-Silver-Mail`, e o CORS só
  libera origens locais. Assim, um site aberto em outra aba não consegue disparar
  ações no seu e-mail.
- O token OAuth fica em `server/data/token.json`, legível só pelo seu usuário
  (Linux/macOS).
- Para revogar o acesso a qualquer momento: <https://myaccount.google.com/permissions>.

## Limitações conhecidas

- Apagar permanentemente não tem volta: as mensagens não passam pela lixeira.
- O “desfazer” só funciona enquanto as mensagens estão na lixeira (30 dias).
- A busca de links no corpo usa heurística por palavras-chave (português, inglês
  e espanhol) e pode deixar passar links fora do padrão.
- Descadastro automático com um clique ainda não foi implementado: o painel
  apenas lista os links.
