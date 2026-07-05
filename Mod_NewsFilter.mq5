//+------------------------------------------------------------------+
//|                                             Mod_NewsFilter.mq5   |
//| โมดูลแยก: ระบบหยุดการทำงานเมื่อเกิดความผันผวน (ATR Spike News Filter)  |
//+------------------------------------------------------------------+
#property strict
#include <Trade\SymbolInfo.mqh>
CSymbolInfo symInfo;
input int InpATRPeriod = 14;
input double InpSpikeMultiplier = 3.0;
input int InpPauseMinutes = 30;

int atrHandle;
datetime pauseUntil = 0;

int OnInit() {
   symInfo.Name(_Symbol); symInfo.Refresh();
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   return(INIT_SUCCEEDED);
}

void OnTick() {
   if(TimeCurrent() < pauseUntil) {
      Comment("⚠️ System Paused due to News Spike until: ", TimeToString(pauseUntil));
      return;
   }
   
   double atr[2];
   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0) return;
   
   symInfo.RefreshRates();
   double currentCandleLength = symInfo.High() - symInfo.Low();
   
   if(currentCandleLength > (atr[1] * InpSpikeMultiplier)) {
      pauseUntil = TimeCurrent() + (InpPauseMinutes * 60);
      Print("🚨 ATR Spike Detected! Pausing for ", InpPauseMinutes, " minutes.");
   } else {
      Comment("✅ Normal Market Conditions");
   }
}
