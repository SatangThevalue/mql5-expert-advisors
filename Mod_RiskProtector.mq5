//+------------------------------------------------------------------+
//|                                           Mod_RiskProtector.mq5  |
//| โมดูลแยก: ระบบจัดการความเสี่ยงและปกป้องพอร์ต (Utility EA)             |
//| หน้าที่: จัดการออเดอร์ที่เปิดด้วยมือหรือบอทตัวอื่น (Trailing, DD Limit)  |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade; CPositionInfo posInfo; CAccountInfo accInfo;
input double InpDailyDrawdownPct = 4.5;
input bool InpCloseOnFriday = true;
input int InpFridayCloseHour = 20;
input bool InpUseBreakEven = true;
input double InpBreakEvenPips = 15.0;

double startOfDayBalance;
int lastDay = -1;

int OnInit() {
   startOfDayBalance = accInfo.Balance();
   return(INIT_SUCCEEDED);
}

void OnTick() {
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day != lastDay) { startOfDayBalance = accInfo.Balance(); lastDay = dt.day; }
   
   // 1. Daily Drawdown Limiter
   double dailyDD = ((accInfo.Equity() - startOfDayBalance) / startOfDayBalance) * 100.0;
   if(dailyDD <= -InpDailyDrawdownPct) {
      CloseAll();
      Print("🚨 พอร์ตติดลบเกินกำหนด ตัดขาดทุนฉุกเฉินทั้งหมด!");
      return;
   }
   
   // 2. Friday Close
   if(InpCloseOnFriday && dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour) {
      CloseAll();
      Print("🛑 ปิดออเดอร์ทั้งหมดก่อนสุดสัปดาห์ (Friday Close)");
   }
   
   // 3. Break-Even System
   if(InpUseBreakEven) {
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(posInfo.SelectByIndex(i)) {
            double openPrice = posInfo.PriceOpen();
            double sl = posInfo.StopLoss();
            double beDist = InpBreakEvenPips * _Point * (SymbolInfoInteger(posInfo.Symbol(), SYMBOL_DIGITS)==3||SymbolInfoInteger(posInfo.Symbol(), SYMBOL_DIGITS)==5?10:1);
            if(posInfo.PositionType() == POSITION_TYPE_BUY && SymbolInfoDouble(posInfo.Symbol(), SYMBOL_BID) > openPrice + beDist) {
               if(sl < openPrice) trade.PositionModify(posInfo.Ticket(), openPrice + (2*_Point), posInfo.TakeProfit());
            } else if(posInfo.PositionType() == POSITION_TYPE_SELL && SymbolInfoDouble(posInfo.Symbol(), SYMBOL_ASK) < openPrice - beDist) {
               if(sl > openPrice || sl == 0) trade.PositionModify(posInfo.Ticket(), openPrice - (2*_Point), posInfo.TakeProfit());
            }
         }
      }
   }
}

void CloseAll() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i)) trade.PositionClose(posInfo.Ticket());
   }
}
