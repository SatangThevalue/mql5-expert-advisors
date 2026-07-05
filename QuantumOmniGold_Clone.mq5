//+------------------------------------------------------------------+
//|                                     QuantumOmniGold_Clone.mq5    |
//|                                  Copyright 2026, Satang Quant    |
//| สถาปัตยกรรม: ZigZag + MA + Stoch | No Grid | Dual TP | Prop Firm |
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
input group "=== 1. Risk Management (Prop Firm Ready) ==="
input double   InpRiskPerTradePct   = 1.0;         // เสี่ยงกี่ % ของพอร์ตต่อ 1 ออเดอร์
input double   InpDailyDrawdownPct  = 4.0;         // พอร์ตลบกี่ % ของวันให้คัตเอาท์ (Prop Firm Limit)
input int      InpMaxSpreadPoints   = 30;          // สเปรดสูงสุดที่ยอมรับได้ (Points)

input group "=== 2. Trade Execution & Exits ==="
input double   InpStopLossATR       = 2.0;         // Stop Loss ห่างกี่เท่าของ ATR
input double   InpTakeProfit1ATR    = 2.0;         // TP 1 (ปิดครึ่งนึง แล้วกันหน้าทุน)
input double   InpTakeProfit2ATR    = 4.0;         // TP 2 (จุดปิดทั้งหมด)
input bool     InpUseTrailingStop   = true;        // เปิดใช้ Trailing Stop หลังจากผ่าน TP1

input group "=== 3. Indicators Settings ==="
input int      InpMAPeriod          = 50;          // เส้นค่าเฉลี่ยบอกเทรนด์
input int      InpStochK            = 5;           // Stochastic K
input int      InpStochD            = 3;           // Stochastic D
input int      InpStochSlowing      = 3;           // Stochastic Slowing
input int      InpATRPeriod         = 14;          // ATR สำหรับคำนวณ SL/TP

//--- Global Variables
int      maHandle, stochHandle, atrHandle;
double   startOfDayBalance;
datetime nextBarTime;

// สถานะการปิดออเดอร์ครึ่งนึง (Partial Close State)
bool     tp1Hit = false; 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(999111);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   startOfDayBalance = accInfo.Balance();

   // โหลด Indicators (MA, Stoch, ATR)
   maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   
   if(maHandle == INVALID_HANDLE || stochHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("❌ Error: โหลด Indicator ไม่สำเร็จ");
      return(INIT_FAILED);
   }

   Print("✅ Quantum OmniGold (Clone) เริ่มทำงาน...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(maHandle);
   IndicatorRelease(stochHandle);
   IndicatorRelease(atrHandle);
   Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (ทำทุกๆ Tick)                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. วาด Dashboard
   DrawDashboard();
   
   // 2. เช็ค Drawdown ประจำวัน (Prop Firm Rule)
   if(CheckDailyDrawdown()) return;
   
   // 3. ระบบจัดการออเดอร์ระหว่างทาง (In-flight Management)
   // อัพเดต Trailing Stop และเช็ค Partial Close ตลอดเวลา
   ManageOpenTrades();
   
   // ========================================================
   // ส่วนวิเคราะห์หาจุดเข้า จะทำเฉพาะ "เมื่อเกิดแท่งเทียนใหม่" เท่านั้น
   // ========================================================
   datetime currentTime[1];
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);
   if(currentTime[0] == nextBarTime) return; 
   nextBarTime = currentTime[0];
   
   // 4. เช็ค Spread ก่อนวิเคราะห์สัญญาณ
   symInfo.RefreshRates();
   if(symInfo.Spread() > InpMaxSpreadPoints) return;
   
   // 5. ดึงค่า Indicator (ใช้แท่งที่เพิ่งปิดไป index 1, และแท่งก่อนหน้า index 2)
   double maVal[1], stochMain[2], stochSignal[2], atrVal[1];
   CopyBuffer(maHandle, 0, 1, 1, maVal);
   CopyBuffer(stochHandle, MAIN_LINE, 1, 2, stochMain);
   CopyBuffer(stochHandle, SIGNAL_LINE, 1, 2, stochSignal);
   CopyBuffer(atrHandle, 0, 1, 1, atrVal);
   
   // 6. Signal Module (หาจุดเข้าเทรด)
   // กฎเหล็ก: No Grid, No Martingale -> มีออเดอร์แล้วห้ามเข้าเพิ่ม
   if(PositionsTotal() == 0)
   {
      tp1Hit = false; // รีเซ็ตสถานะ Partial Close
      
      double ask = symInfo.Ask();
      double bid = symInfo.Bid();
      double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
      
      // เงื่อนไข BUY: ราคาอยู่เหนือ MA + Stoch ตัดกันขึ้นในโซน Oversold (< 20)
      bool isUptrend = (closePrice > maVal[0]);
      bool isStochCrossUp = (stochMain[1] <= stochSignal[1] && stochMain[0] > stochSignal[0] && stochMain[0] < 20.0);
      
      if(isUptrend && isStochCrossUp)
      {
         double slDist = atrVal[0] * InpStopLossATR;
         double tpDist = atrVal[0] * InpTakeProfit2ATR; // TP ใหญ่สุด
         
         double sl = ask - slDist;
         double tp = ask + tpDist;
         double lot = CalculateLotSize(slDist);
         
         if(lot > 0) trade.Buy(lot, _Symbol, ask, sl, tp, "Quantum_Buy");
      }
      
      // เงื่อนไข SELL: ราคาอยู่ใต้ MA + Stoch ตัดกันลงในโซน Overbought (> 80)
      bool isDowntrend = (closePrice < maVal[0]);
      bool isStochCrossDown = (stochMain[1] >= stochSignal[1] && stochMain[0] < stochSignal[0] && stochMain[0] > 80.0);
      
      if(isDowntrend && isStochCrossDown)
      {
         double slDist = atrVal[0] * InpStopLossATR;
         double tpDist = atrVal[0] * InpTakeProfit2ATR;
         
         double sl = bid + slDist;
         double tp = bid - tpDist;
         double lot = CalculateLotSize(slDist);
         
         if(lot > 0) trade.Sell(lot, _Symbol, bid, sl, tp, "Quantum_Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| การจัดการออเดอร์ (Partial Close & Trailing Stop)                   |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == 999111)
         {
            double openPrice = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            double currentVolume = posInfo.Volume();
            
            // ดึงค่า ATR เพื่อคำนวณระยะ TP1
            double atrVal[1];
            CopyBuffer(atrHandle, 0, 0, 1, atrVal);
            double tp1Distance = atrVal[0] * InpTakeProfit1ATR;
            
            // 1. ระบบ Dual TP (Partial Close ที่ TP1)
            if(!tp1Hit)
            {
               if(posInfo.PositionType() == POSITION_TYPE_BUY && symInfo.Bid() >= (openPrice + tp1Distance))
               {
                  // ปิดทำกำไรครึ่งนึง (ถ้า lot มากพอ)
                  double closeVolume = NormalizeDouble(currentVolume / 2.0, 2);
                  if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
                  {
                     trade.PositionClosePartial(posInfo.Ticket(), closeVolume);
                     Print("💰 ชน TP 1: ทยอยปิดทำกำไร 50% เรียบร้อย (Buy)");
                  }
                  
                  // กันหน้าทุน (Break-Even) ให้ส่วนที่เหลือ
                  double newSL = openPrice + (10 * _Point);
                  trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                  
                  tp1Hit = true;
               }
               else if(posInfo.PositionType() == POSITION_TYPE_SELL && symInfo.Ask() <= (openPrice - tp1Distance))
               {
                  double closeVolume = NormalizeDouble(currentVolume / 2.0, 2);
                  if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
                  {
                     trade.PositionClosePartial(posInfo.Ticket(), closeVolume);
                     Print("💰 ชน TP 1: ทยอยปิดทำกำไร 50% เรียบร้อย (Sell)");
                  }
                  
                  double newSL = openPrice - (10 * _Point);
                  trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                  
                  tp1Hit = true;
               }
            }
            
            // 2. ระบบ Adaptive Trailing Stop (จะทำงานหลังจากชน TP1 และกันทุนไปแล้วเท่านั้น)
            if(tp1Hit && InpUseTrailingStop)
            {
               double trailDistance = atrVal[0] * 1.5; // ขยับตามหลังราคา 1.5 ATR
               
               if(posInfo.PositionType() == POSITION_TYPE_BUY)
               {
                  double newSL = symInfo.Bid() - trailDistance;
                  // ขยับ SL ขึ้นไปเรื่อยๆ (แต่ห้ามถอยหลัง)
                  if(newSL > currentSL) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
               }
               else if(posInfo.PositionType() == POSITION_TYPE_SELL)
               {
                  double newSL = symInfo.Ask() + trailDistance;
                  // ขยับ SL ลงมาเรื่อยๆ
                  if(newSL < currentSL || currentSL == 0) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันคัตเอาท์รายวัน (Prop Firm Daily Drawdown Limiter)             |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day != lastDay)
   {
      startOfDayBalance = accInfo.Balance();
      lastDay = dt.day;
   }
   
   double currentEquity = accInfo.Equity();
   double dailyDrawdownPct = ((currentEquity - startOfDayBalance) / startOfDayBalance) * 100.0;
   
   if(dailyDrawdownPct <= -InpDailyDrawdownPct)
   {
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(posInfo.SelectByIndex(i) && posInfo.Magic() == 999111)
            trade.PositionClose(posInfo.Ticket());
      }
      Comment("🚨 บอทหยุดทำงานฉุกเฉิน: พอร์ตติดลบชนขีดจำกัด Prop Firm (", DoubleToString(dailyDrawdownPct, 2), "%)");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| คำนวณ Lot Size (Risk-based Sizing)                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double riskAmount = accInfo.Balance() * (InpRiskPerTradePct / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(slDistance == 0 || tickValue == 0) return 0.0;
   
   double slTicks = slDistance / tickSize;
   double rawLot = riskAmount / (slTicks * tickValue);
   
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(rawLot / stepLot) * stepLot;
}

//+------------------------------------------------------------------+
//| แสดงหน้าปัด (Dashboard)                                          |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   double dailyProfitPct = ((accInfo.Equity() - startOfDayBalance) / startOfDayBalance) * 100.0;
   
   string text = "================================\n";
   text += " 🛡️ Quantum OmniGold (Clone)\n";
   text += "================================\n";
   text += "💰 Equity: $" + DoubleToString(accInfo.Equity(), 2) + "\n";
   text += "📊 Daily Drawdown: " + DoubleToString(dailyProfitPct, 2) + " %\n";
   text += "🛑 Prop Firm Limit: -" + DoubleToString(InpDailyDrawdownPct, 2) + " %\n";
   text += "--------------------------------\n";
   text += "⚡ สถานะ: Running\n";
      
   Comment(text);
}
//+------------------------------------------------------------------+