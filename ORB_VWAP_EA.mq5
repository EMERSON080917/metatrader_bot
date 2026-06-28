//+------------------------------------------------------------------+
//| ORB + VWAP EA - Opening Range Breakout com filtro de VWAP        |
//| Mercados: Forex (EURUSD, GBPUSD, XAUUSD, etc.)                  |
//| Servidor GMT+3 (MetaQuotes Demo)                                 |
//| v1.04 - Filtro de range minimo + confirmacao por candle fechado  |
//+------------------------------------------------------------------+
#property copyright "EMERSON080917"
#property version   "1.04"
#property strict

#include <Trade\Trade.mqh>

//--- Sessoes disponiveis
enum ENUM_SESSION
{
   SESSION_LONDON   = 0, // London  (11h servidor GMT+3 = 08h GMT)
   SESSION_NEW_YORK = 1, // NY      (16h30 servidor GMT+3 = 13h30 GMT)
   SESSION_CUSTOM   = 2  // Personalizado
};

//--- Parametros de entrada
input group "=== Sessao de Trading ==="
input ENUM_SESSION InpSession         = SESSION_LONDON; // Sessao de operacao
input int          InpCustomStartHour = 11; // Hora inicio (apenas se Personalizado)
input int          InpCustomStartMin  = 0;  // Minuto inicio (apenas se Personalizado)
input int          InpRangeDuration   = 15; // Duracao do range em minutos

input group "=== Encerramento ==="
input bool         InpUseCloseTime   = true;  // Fechar posicoes no horario fixo?
input int          InpCloseHour      = 22;    // Hora de encerramento (servidor)
input int          InpCloseMin       = 0;     // Minuto de encerramento

input group "=== Gestao de Risco ==="
input double       InpLots           = 0.10;  // Volume (lotes)
input double       InpStopATR        = 1.5;   // Stop Loss em multiplos de ATR
input double       InpTargetATR      = 3.0;   // Take Profit em multiplos de ATR
input int          InpATRPeriod      = 14;    // Periodo do ATR

input group "=== Filtros ==="
input bool         InpUseVWAP        = true;  // Usar VWAP como filtro
input double       InpMinRangePips   = 10.0;  // Range minimo em pips (0 = desativado)
input bool         InpUseCandleClose = true;  // Confirmar por candle fechado fora do range
input int          InpMagicNumber    = 99999; // Magic number

//--- Variaveis globais
CTrade   trade;
double   rangeHigh     = 0;
double   rangeLow      = 0;
bool     rangeFormed   = false;
bool     tradedToday   = false;
datetime lastResetTime = 0;
datetime lastBarTime   = 0;
int      atrHandle;

//+------------------------------------------------------------------+
void GetSessionStart(int &hour, int &min)
{
   switch(InpSession)
   {
      case SESSION_LONDON:    hour = 11; min = 0;  break;
      case SESSION_NEW_YORK:  hour = 16; min = 30; break;
      default:                hour = InpCustomStartHour; min = InpCustomStartMin; break;
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) { Print("Erro ATR"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);

   int h, m;
   GetSessionStart(h, m);
   PrintFormat("EA v1.04 iniciado - %s | Sessao: %02d:%02d GMT+3 | MinRange: %.1f pips | CandleClose: %s",
               _Symbol, h, m, InpMinRangePips, InpUseCandleClose ? "SIM" : "NAO");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { IndicatorRelease(atrHandle); }

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   //--- Reseta no inicio de cada dia
   MqlDateTime dtLast;
   TimeToStruct(lastResetTime, dtLast);
   if(dt.day != dtLast.day)
   {
      rangeHigh     = 0;
      rangeLow      = 0;
      rangeFormed   = false;
      tradedToday   = false;
      lastResetTime = now;
   }

   //--- Encerramento por horario
   if(InpUseCloseTime && dt.hour == InpCloseHour && dt.min >= InpCloseMin)
   {
      CloseAllPositions();
      return;
   }

   if(!rangeFormed)
   {
      BuildRange(dt);
      return;
   }

   if(!tradedToday && PositionsTotal() == 0)
   {
      //--- Confirmacao por candle fechado: so verifica na abertura de nova vela
      if(InpUseCandleClose)
      {
         datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
         if(barTime == lastBarTime) return;
         lastBarTime = barTime;
         CheckBreakoutByCandle();
      }
      else
      {
         CheckBreakoutByTick();
      }
   }
}

//+------------------------------------------------------------------+
void BuildRange(MqlDateTime &dt)
{
   int startH, startM;
   GetSessionStart(startH, startM);

   int nowMins   = dt.hour * 60 + dt.min;
   int startMins = startH  * 60 + startM;
   int endMins   = startMins + InpRangeDuration;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(nowMins >= startMins && nowMins < endMins)
   {
      if(rangeHigh == 0 || ask > rangeHigh) rangeHigh = ask;
      if(rangeLow  == 0 || bid < rangeLow)  rangeLow  = bid;
   }
   else if(nowMins >= endMins && rangeHigh > 0)
   {
      double rangePips = (rangeHigh - rangeLow) / _Point / 10.0;

      //--- Filtro de range minimo
      if(InpMinRangePips > 0 && rangePips < InpMinRangePips)
      {
         PrintFormat("Range ignorado - muito pequeno: %.1f pips (minimo: %.1f)", rangePips, InpMinRangePips);
         tradedToday = true; // pula o dia
         return;
      }

      rangeFormed = true;
      PrintFormat("Range formado - High: %.5f | Low: %.5f | %.1f pips", rangeHigh, rangeLow, rangePips);
   }
}

//+------------------------------------------------------------------+
//| Entrada por candle fechado fora do range (mais seguro)           |
//+------------------------------------------------------------------+
void CheckBreakoutByCandle()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, rates) <= 0) return;

   double closePrice = rates[0].close;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) <= 0) return;
   double atr = atrBuf[0];

   double vwap = CalculateVWAP();
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Candle fechou ACIMA do range (Long)
   if(closePrice > rangeHigh)
   {
      bool vwapOk = !InpUseVWAP || vwap == 0 || ask > vwap;
      if(vwapOk)
      {
         double sl = NormalizeDouble(ask - atr * InpStopATR, _Digits);
         double tp = NormalizeDouble(ask + atr * InpTargetATR, _Digits);
         if(trade.Buy(InpLots, _Symbol, ask, sl, tp, "ORB Long"))
         {
            tradedToday = true;
            PrintFormat("COMPRA (candle) - Entry: %.5f | SL: %.5f | TP: %.5f", ask, sl, tp);
         }
      }
   }
   //--- Candle fechou ABAIXO do range (Short)
   else if(closePrice < rangeLow)
   {
      bool vwapOk = !InpUseVWAP || vwap == 0 || bid < vwap;
      if(vwapOk)
      {
         double sl = NormalizeDouble(bid + atr * InpStopATR, _Digits);
         double tp = NormalizeDouble(bid - atr * InpTargetATR, _Digits);
         if(trade.Sell(InpLots, _Symbol, bid, sl, tp, "ORB Short"))
         {
            tradedToday = true;
            PrintFormat("VENDA (candle) - Entry: %.5f | SL: %.5f | TP: %.5f", bid, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Entrada por tick (mais rapido, mais falsos sinais)               |
//+------------------------------------------------------------------+
void CheckBreakoutByTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0) return;
   double atr = atrBuf[0];

   double vwap = CalculateVWAP();

   if(ask > rangeHigh)
   {
      bool vwapOk = !InpUseVWAP || vwap == 0 || ask > vwap;
      if(vwapOk)
      {
         double sl = NormalizeDouble(ask - atr * InpStopATR, _Digits);
         double tp = NormalizeDouble(ask + atr * InpTargetATR, _Digits);
         if(trade.Buy(InpLots, _Symbol, ask, sl, tp, "ORB Long"))
         {
            tradedToday = true;
            PrintFormat("COMPRA (tick) - Entry: %.5f | SL: %.5f | TP: %.5f", ask, sl, tp);
         }
      }
   }
   else if(bid < rangeLow)
   {
      bool vwapOk = !InpUseVWAP || vwap == 0 || bid < vwap;
      if(vwapOk)
      {
         double sl = NormalizeDouble(bid + atr * InpStopATR, _Digits);
         double tp = NormalizeDouble(bid - atr * InpTargetATR, _Digits);
         if(trade.Sell(InpLots, _Symbol, bid, sl, tp, "ORB Short"))
         {
            tradedToday = true;
            PrintFormat("VENDA (tick) - Entry: %.5f | SL: %.5f | TP: %.5f", bid, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
double CalculateVWAP()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, 600, rates);
   if(copied <= 0) return 0;

   int startH, startM;
   GetSessionStart(startH, startM);
   int startMins = startH * 60 + startM;

   double sumPV = 0, sumV = 0;
   for(int i = copied - 1; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      if((dt.hour * 60 + dt.min) < startMins) continue;
      double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol     = (double)rates[i].tick_volume;
      sumPV += typical * vol;
      sumV  += vol;
   }
   return sumV > 0 ? sumPV / sumV : 0;
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         trade.PositionClose(ticket);
   }
}
