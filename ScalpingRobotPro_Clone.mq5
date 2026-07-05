//+------------------------------------------------------------------+
//|                                     ScalpingRobotPro_Clone.mq5   |
//|                                  Copyright 2026, Satang Quant    |
//|                                             https://example.com  |
//+------------------------------------------------------------------+
#property copyright "Satang Quant"
#property link      "https://example.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;
CAccountInfo   accInfo;

//+------------------------------------------------------------------+
//| Input Parameters (หน้าตั้งค่า)                                      |
//+------------------------------------------------------------------+
input group "=== 1. Core Trading Setup ==="
input int      InpMagicNumber       = 123456;      // Magic Number
input double   InpBaseLot           = 0.01;        // หลอดเริ่มต้น (Base Lot)
input string   InpTradeMode         = "BOTH";      // ทิศทาง (BUY, SELL, BOTH)

input group "=== 2. Risk & Money Management ==="
input double   InpDailyTargetUSD    = 50.0;        // เป้าหมายกำไรต่อวัน (USD)
input double   InpDailyStopLossUSD  = 150.0;       // ตัดขาดทุนสูงสุดต่อวัน (USD)
input double   InpLotMultiplier     = 1.5;         // ตัวคูณหลอดไม้ถัดไป (Martingale/Grid)
input int      InpMaxGridLevels     = 5;           // เปิดไม้แก้พอร์ตสูงสุดกี่ไม้
input double   InpGridDistancePips  = 30.0;        // ระยะห่างขั้นต่ำก่อนเปิดไม้แก้ (Pips)

input group "=== 3. Execution (M1 Scalping) ==="
input double   InpTakeProfitPips    = 20.0;        // เป้ากำไรรวมของวงจร (Pips)
input bool     InpUseTrailingStop   = true;        // เปิดใช้ Trailing Stop
input double   InpTrailingStartPips = 15.0;        // เริ่มกันหน้าทุนเมื่อกำไร (Pips)
input double   InpTrailingStepPips  = 5.0;         // ขยับ SL ตามทีละ (Pips)

input group "=== 4. Protection Filters ==="
input int      InpMaxSpreadPoints   = 30;          // สเปรดสูงสุดที่ยอมรับได้ (Points)
input bool     InpNewsFilterEnabled = true;        // เปิดระบบหลบข่าว (ATR Spike)
input int      InpPauseAfterShock   = 30;          // หยุดพักหลังเจอข่าวกระชาก (Minutes)

//--- Global Variables
int      bbHandle, rsiHandle, atrHandle;
double   startOfDayBalance;
datetime pauseUntilTime = 0;
double   pipMultiplier;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   // คำนวณ Point/Pip Multiplier สำหรับทองคำ (XAUUSD) หรือคู่เงิน
   if(symInfo.Digits() == 3 || symInfo.Digits() == 5) pipMultiplier = 10.0;
   else pipMultiplier = 1.0;
   
   // บันทึกเงินทุนเริ่มต้นของวัน
   startOfDayBalance = accInfo.Balance();

   // โหลด Indicators
   bbHandle = iBands(_Symbol, PERIOD_M1, 20, 0, 2.5, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   
   if(bbHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(bbHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
   Comment(""); // Clear Dashboard
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//| ฟังก์ชันนี้จะถูกเรียกทำงาน "ทุกๆ ครั้งที่ราคาขยับ (Tick)"               |
//| เปรียบเสมือนหัวใจที่เต้นอยู่ตลอดเวลาของ EA                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. วาด Dashboard
   DrawDashboard();
   
   // 2. เช็คเวลาว่าบอทติดสถานะ "พักเบรกหลบข่าว" หรือไม่
   if(TimeCurrent() < pauseUntilTime) return;

   // 3. เช็คเป้าหมายรายวัน (Daily Limit)
   if(CheckDailyLimits()) return;
   
   // 4. เช็ค Spread (ไม่ให้เทรดตอนถ่าง)
   symInfo.RefreshRates();
   if(symInfo.Spread() > InpMaxSpreadPoints) return;

   // 5. ระบบตรวจจับข่าวกระชาก (ATR Spike News Filter)
   if(InpNewsFilterEnabled && DetectNewsShock())
   {
      pauseUntilTime = TimeCurrent() + (InpPauseAfterShock * 60);
      Print("⚠️ ตรวจพบข่าวแรง! บอทจะหยุดทำงานถึงเวลา: ", TimeToString(pauseUntilTime));
      return;
   }
   
   // ดึงข้อมูล Indicators
   double bbUpper[1], bbLower[1], rsiVal[1];
   CopyBuffer(bbHandle, 1, 0, 1, bbUpper);
   CopyBuffer(bbHandle, 2, 0, 1, bbLower);
   CopyBuffer(rsiHandle, 0, 0, 1, rsiVal);
   
   // นับจำนวนและทิศทางของไม้ที่เปิดอยู่
   int openBuys = 0, openSells = 0;
   CountOpenPositions(openBuys, openSells);
   
   // 6. การออกออเดอร์ใหม่ (Signal Module)
   if(openBuys == 0 && openSells == 0) // พอร์ตว่าง
   {
      // สัญญาณ BUY: ราคาปิดทะลุขอบล่าง และ RSI ต่ำกว่า 30 (Oversold)
      if((InpTradeMode == "BOTH" || InpTradeMode == "BUY") && 
         symInfo.Ask() < bbLower[0] && rsiVal[0] < 30.0)
      {
         trade.Buy(InpBaseLot, _Symbol, symInfo.Ask(), 0, 0, "Initial Buy");
      }
      
      // สัญญาณ SELL: ราคาปิดทะลุขอบบน และ RSI สูงกว่า 70 (Overbought)
      else if((InpTradeMode == "BOTH" || InpTradeMode == "SELL") && 
              symInfo.Bid() > bbUpper[0] && rsiVal[0] > 70.0)
      {
         trade.Sell(InpBaseLot, _Symbol, symInfo.Bid(), 0, 0, "Initial Sell");
      }
   }
   
   // 7. ระบบแก้พอร์ต (Selective Grid Module)
   else 
   {
      ManageGridAndTakeProfit(openBuys, openSells, rsiVal[0]);
   }
   
   // 8. ระบบล็อคกำไร (Trailing Stop)
   if(InpUseTrailingStop)
   {
      ApplyTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันบริหาร Grid และปิดรวบทำกำไร                                 |
//| หัวใจของระบบ: เมื่อไม้แรกผิดทาง เราจะไม่ยอม Cut Loss ทันที         |
//| แต่จะใช้การ "เปิดไม้ใหม่เพื่อดึงต้นทุนเฉลี่ย" (Grid)                   |
//| ความฉลาดคือ มันจะไม่เปิดมั่วๆ (ระยะห่างต้องเกินกำหนด + กราฟต้อง Oversold ซ้ำ) |
//+------------------------------------------------------------------+
void ManageGridAndTakeProfit(int openBuys, int openSells, double currentRsi)
{
   double totalVolume = 0;
   double averagePrice = 0;
   double totalProfit = 0;
   double lastPrice = 0;
   double lastLot = 0;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            totalVolume += posInfo.Volume();
            averagePrice += posInfo.PriceOpen() * posInfo.Volume();
            totalProfit += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            
            if(lastPrice == 0) // จำค่าไม้ล่าสุดที่เปิด
            {
               lastPrice = posInfo.PriceOpen();
               lastLot = posInfo.Volume();
            }
         }
      }
   }
   if(totalVolume > 0) averagePrice = averagePrice / totalVolume;
   
   double targetProfitCurrency = (InpTakeProfitPips * pipMultiplier * _Point) * totalVolume * 100000; // คร่าวๆ ขึ้นอยู่กับ contract size โบรกเกอร์
   // วิธีง่ายกว่า: เช็คจาก Average Price
   
   if(openBuys > 0)
   {
      // 1. เช็ค Take Profit รวบยอด
      double targetPrice = averagePrice + (InpTakeProfitPips * pipMultiplier * _Point);
      if(symInfo.Bid() >= targetPrice)
      {
         CloseAllPositions();
         return;
      }
      
      // 2. เช็คเปิด Grid ไม้ถัดไป (ถ้าผิดทางเกิน Grid Distance และมีสัญญาณ Oversold ซ้ำ)
      double pipsDrawdown = (lastPrice - symInfo.Ask()) / (_Point * pipMultiplier);
      if(pipsDrawdown >= InpGridDistancePips && currentRsi < 30.0 && openBuys < InpMaxGridLevels)
      {
         double newLot = NormalizeDouble(lastLot * InpLotMultiplier, 2);
         trade.Buy(newLot, _Symbol, symInfo.Ask(), 0, 0, "Grid Buy");
      }
   }
   else if(openSells > 0)
   {
      // 1. เช็ค Take Profit รวบยอด
      double targetPrice = averagePrice - (InpTakeProfitPips * pipMultiplier * _Point);
      if(symInfo.Ask() <= targetPrice)
      {
         CloseAllPositions();
         return;
      }
      
      // 2. เช็คเปิด Grid ไม้ถัดไป
      double pipsDrawdown = (symInfo.Bid() - lastPrice) / (_Point * pipMultiplier);
      if(pipsDrawdown >= InpGridDistancePips && currentRsi > 70.0 && openSells < InpMaxGridLevels)
      {
         double newLot = NormalizeDouble(lastLot * InpLotMultiplier, 2);
         trade.Sell(newLot, _Symbol, symInfo.Bid(), 0, 0, "Grid Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันตรวจจับข่าว (ATR Spike)                                    |
//| ทำไมถึงใช้แบบนี้? แทนที่จะดึง API ปฏิทินข่าว (เช่น ForexFactory)   |
//| ซึ่งยุ่งยากและอาจจะดีเลย์ เราสามารถ "จับความผิดปกติของกราฟ" ได้เลย |
//| ถ้าราคาแท่งปัจจุบัน (High - Low) ยาวกว่าค่าเฉลี่ยการแกว่ง (ATR) ถึง 3 เท่า |
//| แสดงว่ามีข่าวออกแน่นอน ให้บอทหนีทันที!                            |
//+------------------------------------------------------------------+
bool DetectNewsShock()
{
   double atr[2];
   CopyBuffer(atrHandle, 0, 0, 2, atr);
   
   double currentCandleLength = symInfo.High() - symInfo.Low();
   
   // ถ้ายาวกว่า 3 เท่าของค่าเฉลี่ย = มีข่าว
   if(currentCandleLength > (atr[1] * 3.0)) 
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| ฟังก์ชันตรวจเป้าหมายรายวัน (Daily Limit)                           |
//| ป้องกันความโลภ: กำไรถึงเป้า -> บอทปิดจอไปนอน                        |
//| ป้องกันพอร์ตแตก: ขาดทุนเกินเป้า -> บอทสั่ง Cut All แล้วหยุดทันที        |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   // เช็คว่าขึ้นวันใหม่หรือยัง ถัาขึ้นแล้วให้รีเซ็ต startOfDayBalance
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day != lastDay)
   {
      startOfDayBalance = accInfo.Balance();
      lastDay = dt.day;
   }
   
   double currentEquity = accInfo.Equity();
   double dailyProfit = currentEquity - startOfDayBalance;
   
   if(dailyProfit >= InpDailyTargetUSD)
   {
      CloseAllPositions();
      Comment("🛑 บอทหยุดทำงาน: ถึงเป้าหมายกำไรรายวันแล้ว ($", DoubleToString(dailyProfit,2), ")");
      return true;
   }
   if(dailyProfit <= -InpDailyStopLossUSD)
   {
      CloseAllPositions();
      Comment("🚨 บอทหยุดทำงาน: ตัดขาดทุนสูงสุดประจำวันแล้ว ($", DoubleToString(dailyProfit,2), ")");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Utility Functions                                                |
//+------------------------------------------------------------------+
void CountOpenPositions(int &buys, int &sells)
{
   buys = 0; sells = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY) buys++;
            else if(posInfo.PositionType() == POSITION_TYPE_SELL) sells++;
         }
      }
   }
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

void ApplyTrailingStop()
{
   // (ย่อโค้ดเพื่อความกระชับ) วนลูปเช็คกำไร ถ้าระยะห่างเกิน StartPips ค่อยดึง SL บังหน้าทุน
}

void DrawDashboard()
{
   double currentEquity = accInfo.Equity();
   double dailyProfit = currentEquity - startOfDayBalance;
   
   string text = "================================\\n";
   text += " 🤖 Scalping Robot Pro (Clone)\\n";
   text += "================================\\n";
   text += "💰 Equity: $" + DoubleToString(currentEquity, 2) + "\\n";
   text += "📊 Daily P/L: $" + DoubleToString(dailyProfit, 2) + "\\n";
   text += "🎯 Daily Target: $" + DoubleToString(InpDailyTargetUSD, 2) + "\\n";
   text += "🛑 Daily StopLoss: -$" + DoubleToString(InpDailyStopLossUSD, 2) + "\\n";
   text += "--------------------------------\\n";
   text += "📈 Spread: " + IntegerToString(symInfo.Spread()) + " points\\n";
   
   if(TimeCurrent() < pauseUntilTime)
      text += "⚠️ สถานะ: หยุดพักหนีข่าว (PAUSED)\\n";
   else
      text += "✅ สถานะ: ปกติ (RUNNING)\\n";
      
   Comment(text);
}
//+------------------------------------------------------------------+
