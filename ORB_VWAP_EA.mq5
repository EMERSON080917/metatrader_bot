//+------------------------------------------------------------------+
//| ORB + VWAP EA — Opening Range Breakout com filtro de VWAP        |
//| Mercados: Forex (EURUSD, GBPUSD, XAUUSD, etc.)                  |
//+------------------------------------------------------------------+
#property copyright "EMERSON080917"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>

//--- Sessões disponíveis
enum ENUM_SESSION
{
   SESSION_LONDON   = 0, // London (10h BRT / 08h GMT)
   SESSION_NEW_YORK = 1, // Nova York (14h30 BRT / 12h30 GMT)
   SESSION_CUSTOM   = 2  // Personalizado
};

//--- Parâmetros de entrada
input group "=== Sessão de Trading ==="
input ENUM_SESSION InpSession         = SESSION_LONDON; // Sessão de operação
input int          InpCustomStartHour = 10; // Hora início (apenas se Personalizado)
input int          InpCustomStartMin  = 0;  // Minuto início (apenas se Personalizado)
input int          InpRangeDuration   = 15; // Duração do range em minutos

input group "=== Encerramento ==="
input bool         InpUseCloseTime   = true;  // Fechar posições no fim da sessão?
input int          InpCloseHour      = 22;    // Hora de encerramento (BRT)
input int          InpCloseMin       = 0;     // Minuto de encerramento

input group "=== Gestão de Risco ==="
input double       InpLots           = 0.10;  // Volume (lotes)
input double       InpStopATR        = 1.5;   // Stop Loss em múltiplos de ATR
input double       InpTargetATR      = 3.0;   // Take Profit em múltiplos de ATR
input int          InpATRPeriod      = 14;    // Período do ATR

input group "=== Filtros ==="
input bool         InpUseVWAP        = true;  // Usar VWAP como filtro
input int          InpMagicNumber    = 99999; // Magic number

//--- Variáveis globais
CTrade   trade;
double   rangeHigh    = 0;
double   rangeLow     = 0;
bool     rangeFormed  = false;
bool     tradedToday  = false;
datetime lastResetTime = 0;
int      atrHandle;

//+------------------------------------------------------------------+
//| Retorna hora/minuto de início da sessão escolhida                |
//+------------------------------------------------------------------+
void GetSessionStart(int &hour, int &min)
{
   switch(InpSession)
   {
      case SESSION_LONDON:    hour = 10; min = 0;  break; // 10h BRT
      case SESSION_NEW_YORK:  hour = 14; min = 30; break; // 14h30 BRT
      default:                hour = InpCustomStartHour; min = InpCustomStartMin; break;
   }
}

//+------------------------------------------------------------------+
//| Inicialização                                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Erro ao criar indicador ATR");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);

   int h, m;
   GetSessionStart(h, m);
   PrintFormat("EA iniciado — %s | Sessão: %02d:%02d | Range: %d min | Lots: %.2f",
               _Symbol, h, m, InpRangeDuration, InpLots);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Finalização                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Tick principal                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   //--- Reseta no início de cada dia
   MqlDateTime dtLast;
   TimeToStruct(lastResetTime, dtLast);
   if(dt.day != dtLast.day)
   {
      rangeHigh     = 0;
      rangeLow      = 0;
      rangeFormed   = false;
      tradedToday   = false;
      lastResetTime = now;
      Print("Novo dia — range resetado");
   }

   //--- Encerramento por horário
   if(InpUseCloseTime && dt.hour == InpCloseHour && dt.min >= InpCloseMin)
   {
      CloseAllPositions();
      return;
   }

   //--- Fase 1: construir o range
   if(!rangeFormed)
   {
      BuildRange(dt);
      return;
   }

   //--- Fase 2: aguardar rompimento
   if(!tradedToday && PositionsTotal() == 0)
      CheckBreakout();
}

//+------------------------------------------------------------------+
//| Constrói o range de abertura                                     |
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
      rangeFormed = true;
      PrintFormat("Range formado — High: %.5f | Low: %.5f | Amplitude: %.5f pips",
                  rangeHigh, rangeLow, (rangeHigh - rangeLow) / _Point / 10.0);
   }
}

//+------------------------------------------------------------------+
//| Verifica rompimento e entra na operação                          |
//+------------------------------------------------------------------+
void CheckBreakout()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0) return;
   double atr = atrBuf[0];

   double vwap = CalculateVWAP();

   //--- Rompimento para CIMA (Long)
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
            PrintFormat("COMPRA — Entry: %.5f | SL: %.5f | TP: %.5f", ask, sl, tp);
         }
      }
   }
   //--- Rompimento para BAIXO (Short)
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
            PrintFormat("VENDA — Entry: %.5f | SL: %.5f | TP: %.5f", bid, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calcula VWAP desde o início da sessão                            |
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
//| Fecha todas as posições abertas pelo EA                          |
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
