//+------------------------------------------------------------------+
//|                                           Mod_GridRecovery.mq5   |
//| โมดูลแยก: ระบบแก้พอร์ตด้วย Selective Grid ผสม RSI Filter             |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade trade; CPositionInfo posInfo; CSymbolInfo symInfo;
input double InpGridDistancePips = 30.0;
input double InpLotMultiplier = 1.5;
input int InpMaxLevels = 5;
input double InpTakeProfitPips = 10.0;

int rsiHandle; int pipMult;

int OnInit() {
   trade.SetExpertMagicNumber(112233);
   symInfo.Name(_Symbol); symInfo.Refresh();
   pipMult = (symInfo.Digits()==3||symInfo.Digits()==5) ? 10 : 1;
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

void OnTick() {
   symInfo.RefreshRates();
   double rsi[1]; CopyBuffer(rsiHandle, 0, 0, 1, rsi);
   
   int buys=0, sells=0; double lastBuyPrice=0, lastSellPrice=0, lastBuyLot=0, lastSellLot=0;
   double avgBuyPrice=0, totalBuyLot=0, avgSellPrice=0, totalSellLot=0;
   
   for(int i=0; i<PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 112233) {
         if(posInfo.PositionType() == POSITION_TYPE_BUY) {
            buys++; totalBuyLot += posInfo.Volume();
            avgBuyPrice += posInfo.PriceOpen() * posInfo.Volume();
            lastBuyPrice = posInfo.PriceOpen(); lastBuyLot = posInfo.Volume();
         } else {
            sells++; totalSellLot += posInfo.Volume();
            avgSellPrice += posInfo.PriceOpen() * posInfo.Volume();
            lastSellPrice = posInfo.PriceOpen(); lastSellLot = posInfo.Volume();
         }
      }
   }
   if(totalBuyLot>0) avgBuyPrice /= totalBuyLot;
   if(totalSellLot>0) avgSellPrice /= totalSellLot;
   
   // Logic
   if(buys > 0) {
      if(symInfo.Bid() >= avgBuyPrice + (InpTakeProfitPips * pipMult * _Point)) { CloseAll(); return; }
      if(buys < InpMaxLevels && (lastBuyPrice - symInfo.Ask()) / (_Point*pipMult) >= InpGridDistancePips && rsi[0] < 30) {
         trade.Buy(NormalizeDouble(lastBuyLot * InpLotMultiplier, 2), _Symbol, symInfo.Ask());
      }
   } else if(sells > 0) {
      if(symInfo.Ask() <= avgSellPrice - (InpTakeProfitPips * pipMult * _Point)) { CloseAll(); return; }
      if(sells < InpMaxLevels && (symInfo.Bid() - lastSellPrice) / (_Point*pipMult) >= InpGridDistancePips && rsi[0] > 70) {
         trade.Sell(NormalizeDouble(lastSellLot * InpLotMultiplier, 2), _Symbol, symInfo.Bid());
      }
   }
}
void CloseAll() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 112233) trade.PositionClose(posInfo.Ticket());
   }
}
