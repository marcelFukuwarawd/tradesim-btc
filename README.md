# TradeSim BTC ₿

**Simulador de trade automático de BTC/USDT (paper trading) para Android** — começando com **US$ 100** de caixa, **sem alavancagem**, com **preços reais públicos da Binance** (sem login, sem chave de API, **nenhuma ordem real é enviada**) e **relatório diário às 21h** via notificação no celular.

> ⚠️ **Aviso honesto**: isto é uma **simulação**. Nenhuma ordem real é executada e os resultados não garantem nada. Nada aqui é conselho financeiro. Estratégias rendem dinheiro no passado e podem perder no futuro — por isso o app tem backtester e controles de risco.

---

## ✨ O que tem no app

| Recurso | Detalhe |
|---|---|
| 📉 **Gráfico de candles** (5m) estilo Binance/TradingView | Candles, EMA-9, EMA-21, volume, preço ao vivo (atualiza a cada 15s) |
| 🤖 **Trade automático** | Compra/vende BTC/USDT **na simulação** pela estratégia balanceada (regras abaixo) |
| 💰 **US$ 100 iniciais, sem alavancagem** | Posição spot limitada pelo caixa, com taxa de 0,1% e 0,05% de slippage |
| 🔔 **Relatório diário às 21h** (America/Sao_Paulo) | Notificação local com ganho/perda do dia, nº de trades e caixa — **sem Firebase, sem login** |
| 📊 **Backtest 90 dias** | Roda a estratégia nas velas de 1h da Binance (ou offline com série sintética) e mostra winrate, P&L, drawdown máximo, profit factor, expectância e curva de patrimônio |
| 🧾 **Histórico de relatórios e operações** | Tela de relatórios (um por dia) + lista de todas as operações fechadas |
| 🔲 **Widget 5×5** | Caixa, preço BTC/USDT, P&L do dia, ROI total e posição — direto na tela inicial |
| 🔒 **Zero login** | Sem conta, sem cadastro, sem API key. Só leitura de dados públicos de mercado |

---

## 🧠 A estratégia "Balanceada" (o que o robô faz)

Baseada no consenso dos clássicos (Murphy — tendências; Wilder — RSI/ATR; Van Tharp & Schwager — dimensionamento de posição):

1. **Só a favor da tendência** — compra quando a **EMA-9 cruza acima da EMA-21** **e** o preço está **acima da EMA-50**.
2. **Momento confirmado (Wilder)** — exige **RSI-14 entre 52 e 72** na entrada; **saída se RSI > 80**.
3. **Risco por operação (Van Tharp / Schwager)** — arrisca no máximo **2% do patrimônio** por trade (ajustável em Ajustes: 0,5%–5%). Posição calculada pelo stop → nunca fica "all in" por impulso; limitada pelo caixa real.
4. **Stop e alvo por ATR (Wilder)** — **Stop = 1,8×ATR-14**, **Alvo = 3,0×ATR-14** (ganho médio ≈ 1,67× a perda média). Sai também no cruzamento inverso EMA-9/EMA-21.
5. **Custos reais** — **0,1% de taxa** (taker, padrão Binance) + **0,05% de slippage** por lado.
6. **Juros compostos** — os lucros aumentam o patrimônio e, portanto, o tamanho dos próximos trades.

> Ajuste fino em **Ajustes**: risco/trade, stop (×ATR) e alvo (×ATR).
> **Backtest** roda em velas de 1h; **ao vivo** usa 5m — por isso os números diferem um pouco.

---

## 📁 Estrutura de arquivos (47 arquivos — mínimo possível)

```
btc_trader_sim/
├── .github/workflows/build.yml   ← gera o APK sozinho no GitHub (não mexa)
├── lib/                          ← TODA a lógica e UI (Dart/Flutter)
│   ├── main.dart                 ← ponto de entrada + navegação inferior
│   ├── state.dart                ← cérebro: feed, robô, relatório 21h, widget
│   ├── engine.dart               ← estratégia, indicadores, backtest, sintético
│   ├── api.dart                  ← Binance pública (somente leitura)
│   ├── db.dart                   ← SQLite local (conta, trades, relatórios)
│   ├── notifications.dart        ← notificação local das 21h
│   ├── fmt.dart / theme.dart     ← formatação + visual Binance/TradingView
│   └── screens/                  ← home (gráfico), backtest, relatórios, ajustes
├── android/                      ← casca Android (ícone, widget 5×5, manifesto)
├── test/engine_test.dart         ← testes (rodam no GitHub Actions)
├── pubspec.yaml                  ← dependências
└── README.md                     ← você está aqui
```

---

# 🚀 Passo a passo: subir no GitHub e gerar o APK

Escolha **uma** das três opções (a A é a mais fácil para iniciantes):

### Opção A — Pelo navegador (sem instalar nada)

1. Acesse **https://github.com/new** (logado na sua conta GitHub).
2. Em **Repository name**, digite: `tradesim-btc` → deixe **Public** → clique em **Create repository**.
3. Na página seguinte, clique em **…uploading an existing file** (link no meio da página) ou no botão **Add file → Upload files**.
4. Abra a pasta `btc_trader_sim` no seu computador e **arraste TODOS os arquivos e pastas** para a área de upload do navegador (o Chrome aceita pastas inteiras). São só **47 arquivos, ~450 KB** — cabe de boa.
5. Aguarde o upload terminar e clique no botão verde **Commit changes**.

> 💡 Se o navegador não aceitar pastas: use a Opção B ou C (recomendado se você tiver Git instalado).

### Opção B — Com o Git (recomendado)

```bash
# 1) Crie o repositório vazio em https://github.com/new (nome: tradesim-btc) — NÃO marque "Add README"
# 2) No terminal, dentro da pasta btc_trader_sim:
cd btc_trader_sim
git init
git add .
git commit -m "TradeSim BTC v1.0.0"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/tradesim-btc.git
git push -u origin main
```

Se pedir usuário/senha: a "senha" é um **Personal Access Token** (GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → marque `repo`). Cole o token no lugar da senha.

### Opção C — Com o GitHub CLI

```bash
cd btc_trader_sim
gh auth login          # siga o assistente (uma vez só)
gh repo create tradesim-btc --public --source=. --push
```

---

## 📲 Como gerar o APK no GitHub (automático)

Depois do upload (push):

1. Abra seu repositório no GitHub → aba **Actions** (no topo).
2. Se aparecer um aviso amarelo de permissão ("Workflows aren't being run"), clique em **I understand my workflows, go ahead and enable them**.
3. Você verá o workflow **"Build APK"** rodando (bolinha amarela girando). Aguarde **~4 a 6 minutos**. Quando ficar ✅ verde, terminou.
4. Clique na execução (run) → role até **Artifacts** → baixe **`tradesim-btc-apk`**.
5. Descompacte o `.zip` baixado → dentro dele está **`app-release.apk`**.

> 💡 Dica: dá para baixar o APK de qualquer execução passada (aba Actions → execução → Artifacts). Envie o `app-release.apk` para o celular (USB, cabo OTG, Drive, e-mail, WhatsApp…).

### Instalar no celular

1. Toque no `app-release.apk` no celular.
2. O Android vai pedir permissão de **"Instalar apps desconhecidos"** para o gerenciador de arquivos/navegador → **Permitir/Instalar**.
3. Pronto: ícone **TradeSim BTC** na tela inicial.

---

## 🕹️ Como usar

**Primeira abertura**
- O app já nasce com a conta de **US$ 100**. O robô só passa a operar a partir das velas **fechadas após a instalação** (não "compra o passado").
- A estratégia fica **LIGADA** por padrão (dá para desligar no card "Operação automática"). Puxe a tela do gráfico para baixo para forçar a atualização.

**Widget 5×5 na tela inicial**
1. Segure um espaço vazio da tela inicial → **Widgets** (ou **Papel de parede e estilo → Widgets**, varia por fabricante: Samsung, Xiaomi, Motorola…).
2. Procure **TradeSim BTC** → arraste o widget **5×5** para a tela inicial.
3. Ele mostra preço BTC/USDT, P&L do dia (verde/vermelho), caixa, ROI total e se há posição — e **atualiza ao abrir/usar o app**.

**Relatório diário das 21h**
- Todo dia às **21h (America/Sao_Paulo)** chega a notificação **"TradeSim BTC — Relatório das 21h"** com: P&L do dia, nº de trades (vitórias/derrotas) e o caixa final.
- O app também salva o relatório na aba **Relatórios** (histórico completo + resultado acumulado) e dá o botão **"Gerar hoje"** para gerar sob demanda.
- **Importante (Android):** desligue a **otimização de bateria** para o TradeSim (Configurações → Apps → TradeSim BTC → Bateria → Sem restrição) e **abra o app ao menos 1× por dia** — assim o relatório vem com os números do momento. O agendamento das 21h é garantido pelo alarme do Android, mas o conteúdo é tão fresco quanto a última vez que o app rodou.

**Backtest**
- Aba **Backtest**: roda sozinho ao abrir. Mostra resultado do período (US$ 100 → X), ROI, winrate, profit factor, expectância, **drawdown máximo**, curva de patrimônio e comparação com "comprar e segurar". Funciona até offline (com série sintética) e aceita **RODAR DE NOVO** quando quiser.

**Zerar a simulação**
- **Ajustes → Zerar simulação (US$ 100)** apaga tudo e recomeça de US$ 100.

---

## ❓ Problemas comuns

| Problema | Solução |
|---|---|
| Actions marcou ❌ vermelho | Abra o run → veja o log do passo que falhou → geralmente basta **"Re-run jobs"** (botão no canto). O build é o mesmo `flutter build apk --release` que gera qualquer app Flutter |
| APK não instala: "app não instalado" | Desinstale a versão anterior antes (assinatura muda a cada build) e permita **fontes desconhecidas** |
| Gráfico mostra "OFFLINE" | Sem internet naquele momento → o app exibe candles **sintéticos** e **pausa os trades** (assim o histórico não mistura dados reais e falsos). Volte para o Wi-Fi/dados e puxe para atualizar |
| Não chegou a notificação das 21h | Configurações → Apps → TradeSim BTC → **Notificações: ativadas**; **Bateria: sem restrição**; **Alarmes e lembretes: permitir** (Android 12+); abra o app ao menos 1× no dia |
| Quero o APK assinado com minha chave | Só para publicar na Play Store: gere um keystore, adicione-o em `android/app/` e ajuste o `signingConfig` do `android/app/build.gradle.kts`. Para uso pessoal, o APK do Actions já instala normalmente |
| Quero mudar parâmetros | **Ajustes** → risco por trade, stop e alvo ×ATR |

---

## 🔐 Privacidade e dados

- **Sem login, sem cadastro, sem coleta.** O app só faz requisições **GET** públicas para a Binance (`data-api.binance.vision` e espelhos `api*.binance.com`) para ler preço/candles de BTC/USDT.
- Todos os trades, relatórios e configurações ficam **somente no SQLite local do aparelho** (`tradesim_btc.db`).
- **Nenhuma ordem real é enviada à Binance em hipótese alguma.** Não há chave de API no código.

---

## ⚖️ Licença e créditos

MIT — use, modifique e compartilhe como quiser (veja `LICENSE`).

Estratégia inspirada em: John J. Murphy (análise técnica), J. Welles Wilder (RSI, ATR), Van K. Tharp (dimensionamento por risco), Jack Schwager (Market Wizards), Michael Covel (trend following). Visual inspirado nas plataformas Binance e TradingView.

**Este software é educacional e NÃO é conselho financeiro, de investimento ou de trading. Operar criptomoedas envolve risco total de perda. Resultados passados (reais ou simulados) não garantem resultados futuros.**
