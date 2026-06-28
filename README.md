# 🤖 ORB + VWAP EA — MetaTrader 5

Expert Advisor para MetaTrader 5 que opera a estratégia **Opening Range Breakout (ORB)** filtrada pelo **VWAP**.

Desenvolvido para **WIN** (Mini Índice), **WDO** (Mini Dólar) e **Ações da B3**.

---

## 📁 Arquivos

| Arquivo | Descrição |
|---|---|
| `ORB_VWAP_EA.mq5` | Expert Advisor principal |

---

## 📊 Estratégia

### Opening Range Breakout (ORB)

```
1. Das 9h00 às 9h15 → registra a máxima e mínima do período (o "range")
2. Após 9h15 → aguarda rompimento da faixa
3. Rompimento para CIMA + preço acima do VWAP → COMPRA (Long)
4. Rompimento para BAIXO + preço abaixo do VWAP → VENDA (Short)
5. Stop Loss  : 1.5x ATR
6. Take Profit: 3.0x ATR (relação risco/retorno 1:2)
7. Às 17h30   → fecha tudo automaticamente
```

### Por que funciona no WIN/WDO
- Alta volatilidade na abertura cria rompimentos fortes e direcionais
- O VWAP filtra entradas contra a tendência do dia
- ATR adapta o stop ao volatilidade atual do ativo

---

## ⚙️ Instalação

1. Copie `ORB_VWAP_EA.mq5` para a pasta:
   ```
   C:\Users\<seu_usuario>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Experts\
   ```
2. Abra o MetaEditor (F4 no MT5) e compile o arquivo
3. No gráfico do ativo, arraste o EA da aba **Navegador → Expert Advisors**
4. Habilite **"Permitir trading automatizado"** nas propriedades do EA

---

## 🔧 Parâmetros

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `InpRangeStartHour/Min` | 9:00 | Início do range |
| `InpRangeEndHour/Min` | 9:15 | Fim do range |
| `InpCloseHour/Min` | 17:30 | Encerramento diário |
| `InpLots` | 1.0 | Volume por operação |
| `InpStopATR` | 1.5 | Stop Loss em múltiplos de ATR |
| `InpTargetATR` | 3.0 | Take Profit em múltiplos de ATR |
| `InpATRPeriod` | 14 | Período do ATR |
| `InpUseVWAP` | true | Ativa filtro de VWAP |

### Configurações recomendadas por ativo

| Ativo | Timeframe | Lotes | Stop ATR | TP ATR |
|---|---|---|---|---|
| WIN (Mini Índice) | 5min | 1 | 1.5 | 3.0 |
| WDO (Mini Dólar) | 5min | 1 | 1.5 | 3.0 |
| Ações B3 | 15min | — | 2.0 | 4.0 |

---

## 🧪 Como testar (Backtest)

1. No MT5, abra o **Strategy Tester** (Ctrl+R)
2. Selecione `ORB_VWAP_EA`
3. Configure:
   - Símbolo: `WIN$` ou `WDO$`
   - Timeframe: `M5`
   - Período: últimos 6 meses
   - Modelagem: **Every tick based on real ticks**
4. Clique em **Iniciar**

---

## ⚠️ Avisos Importantes

- **Sempre teste no Strategy Tester antes de usar conta real**
- Resultados passados não garantem resultados futuros
- Use apenas capital que você pode perder
- Ajuste o tamanho de lote de acordo com sua margem disponível
