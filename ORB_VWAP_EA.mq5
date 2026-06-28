//+------------------------------------------------------------------+
//| ORB + VWAP EA — Opening Range Breakout com filtro de VWAP        |
//| Mercados: WIN, WDO, Ações B3                                     |
//+------------------------------------------------------------------+
#property copyright "EMERSON080917"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Parâmetros de entrada
input group "=== Horário de Trading ==="
input int    InpRangeStartHour   = 9;    // Hora início do range
input int    InpRangeStartMin    = 0;    // Minuto início do range
input int    InpRangeEndHour     = 9;    // Hora fim do range
input int    InpRangeEndMin      = 15;   // Minuto fim do range
input int    InpCloseHour        = 17;   // Hora de fechar todas posições
input int    InpCloseMin         = 30;   // Minuto de fechar todas posições

input group "=== Gestão de Risco ==="
input double InpLots             = 1.0;  // Volume (lotes)
input double InpStopATR          = 1.5;  // Stop Loss em múltiplos de ATR
input double InpTargetATR        = 3.0;  // Take Profit em múltiplos de ATR
input int    InpATRPeriod        = 14;   // Período do ATR

input group "=== Filtros ==="
input bool   InpUseVWAP          = true; // Usar VWAP como filtro
input int    InpMagicNumber      = 12345; // Magic number

//--- Variáveis globais
CTrade trade;
double rangeHigh = 0;
double rangeLow  = 0;
bool   rangeFormed = false;
bool   tradedToday = false;
datetime lastBarTime = 0;

int atrHandle;

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

   Print("EA iniciado — ", _Symbol);
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
   if(dt.hour == InpRangeStartHour && dt.min == InpRangeStartMin)
   {
      if(lastBarTime != now)
      {
         rangeHigh    = 0;
         rangeLow     = 0;
         rangeFormed  = false;
         tradedToday  = false;
         lastBarTime  = now;
      }
   }

   //--- Fecha todas posições no horário de encerramento
   if(dt.hour == InpCloseHour && dt.min >= InpCloseMin)
   {
      CloseAllPositions();
      return;
   }

   //--- Fase 1: construir o range (9h00 até 9h15)
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
   bool inRangeTime = (dt.hour == InpRangeStartHour && dt.min >= InpRangeStartMin) ||
                      (dt.hour == InpRangeEndHour   && dt.min <  InpRangeEndMin);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(inRangeTime)
   {
      if(rangeHigh == 0 || ask > rangeHigh) rangeHigh = ask;
      if(rangeLow  == 0 || bid < rangeLow)  rangeLow  = bid;
   }
   else if(dt.hour == InpRangeEndHour && dt.min >= InpRangeEndMin && rangeHigh > 0)
   {
      rangeFormed = true;
      PrintFormat("Range formado — High: %.2f | Low: %.2f", rangeHigh, rangeLow);
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
      bool vwapOk = !InpUseVWAP || ask > vwap;
      if(vwapOk)
      {
         double sl = ask - atr * InpStopATR;
         double tp = ask + atr * InpTargetATR;
         if(trade.Buy(InpLots, _Symbol, ask, sl, tp, "ORB Long"))
         {
            tradedToday = true;
            PrintFormat("COMPRA executada — Entry: %.2f | SL: %.2f | TP: %.2f", ask, sl, tp);
         }
      }
   }
   //--- Rompimento para BAIXO (Short)
   else if(bid < rangeLow)
   {
      bool vwapOk = !InpUseVWAP || bid < vwap;
      if(vwapOk)
      {
         double sl = bid + atr * InpStopATR;
         double tp = bid - atr * InpTargetATR;
         if(trade.Sell(InpLots, _Symbol, bid, sl, tp, "ORB Short"))
         {
            tradedToday = true;
            PrintFormat("VENDA executada — Entry: %.2f | SL: %.2f | TP: %.2f", bid, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calcula VWAP do dia (desde 9h)                                   |
//+------------------------------------------------------------------+
double CalculateVWAP()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, 500, rates);
   if(copied <= 0) return 0;

   double sumPV = 0, sumV = 0;
   MqlDateTime dt;

   for(int i = copied - 1; i >= 0; i--)
   {
      TimeToStruct(rates[i].time, dt);
      if(dt.hour < InpRangeStartHour) continue;

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
