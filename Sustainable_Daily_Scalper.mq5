//+------------------------------------------------------------------+
//|                                  Sustainable_Daily_Scalper.mq5   |
//|                                  Copyright 2026, Satang Quant    |
//|                                                                  |
//| สถาปัตยกรรม: Session-based Mean Reversion + Break-Even + Daily Limit |
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
input group "=== 1. Session Filter (กรองเวลาเทรด) ==="
input int      InpStartHour         = 2;           // เวลาเริ่มทำงาน (Server Time) เช่น 02:00
input int      InpEndHour           = 10;          // เวลาหยุดทำงาน (Server Time) เช่น 10:00 (ก่อนตลาดยุโรปเปิด)

input group "=== 2. Risk & Money Management ==="
input double   InpRiskPerTradePct   = 1.0;         // เสี่ยงกี่ % ของพอร์ตต่อ 1 ออเดอร์
input double   InpDailyDrawdownPct  = 2.0;         // พอร์ตลบกี่ % ของวันให้หยุดทำงาน (คัตเอาท์)
input double   InpDailyTargetPct    = 1.0;         // กำไรกี่ % ของวันให้หยุดทำงาน (ป้องกันความโลภ)

input group "=== 3. Execution & Protections ==="
input double   InpStopLossATR       = 1.5;         // Stop Loss ห่างกี่เท่าของ ATR
input double   InpTakeProfitATR     = 1.0;         // Take Profit ห่างกี่เท่าของ ATR
input bool     InpUseBreakEven      = true;        // เปิดใช้ระบบ "กันหน้าทุน"
input double   InpBreakEvenTriggerR = 0.5;         // ถ้ากำไรวิ่งไปถึง 0.5 เท่าของเป้าหมาย ให้เลื่อน SL มากันทุน

input group "=== 4. Indicators Settings ==="
input int      InpBBPeriod          = 20;
input double   InpBBDeviation       = 2.0;
input int      InpRSIPeriod         = 14;
input int      InpATRPeriod         = 14;
input double   InpMaxADX            = 20.0;        // ค่า ADX สูงสุดที่ยอมให้เทรด (ต้องเป็น Sideways)

//--- Global Variables
int      bbHandle, rsiHandle, atrHandle, adxHandle;
double   startOfDayBalance;
datetime nextBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(777888);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   // บันทึกเงินทุนเริ่มต้นของวัน
   startOfDayBalance = accInfo.Balance();

   // โหลด Indicators ลงในหน่วยความจำ
   bbHandle = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   adxHandle = iADX(_Symbol, PERIOD_CURRENT, 14); // ใช้ค่า Default 14 สำหรับหาเทรนด์
   
   if(bbHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
   {
      Print("❌ Error: โหลด Indicator ไม่สำเร็จ");
      return(INIT_FAILED);
   }

   Print("✅ Sustainable Scalper เริ่มทำงาน...");
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
   IndicatorRelease(adxHandle);
   Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (หัวใจหลักทำงานทุกๆ การขยับของราคา)             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. วาด Dashboard โชว์สถานะ
   DrawDashboard();
   
   // 2. เช็คเป้าหมายรายวัน (Daily Limit) - ถ้าลบเกินหรือบวกเกินเป้า บอทจะหยุด
   if(CheckDailyLimits()) return;
   
   // 3. ระบบกันหน้าทุน (Break-Even) ทำงานตลอดเวลา ไม่ต้องรอจบแท่งเทียน
   if(InpUseBreakEven) ApplyBreakEven();
   
   // ========================================================
   // ส่วนการวิเคราะห์หาจุดเข้า จะทำเฉพาะ "เมื่อเกิดแท่งเทียนใหม่" เท่านั้น
   // เพื่อลดการกิน CPU และป้องกันสัญญาณกระพริบหลอก (Repaint)
   // ========================================================
   datetime currentTime[1];
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);
   if(currentTime[0] == nextBarTime) return; // ถ้ายังเป็นแท่งเดิม ให้ออกไปเลย
   
   // ถ้าผ่านบรรทัดบนมาได้ แสดงว่าขึ้นแท่งเทียนใหม่แล้ว
   nextBarTime = currentTime[0];
   
   // 4. กรองเวลา (Session Filter) - เทรดเฉพาะช่วงที่กำหนด
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;
   
   // 5. ดึงค่า Indicator (ใช้แท่งที่เพิ่งปิดไป หรือ index 1)
   double bbUpper[1], bbLower[1], rsiVal[1], atrVal[1], adxVal[1];
   CopyBuffer(bbHandle, 1, 1, 1, bbUpper);
   CopyBuffer(bbHandle, 2, 1, 1, bbLower);
   CopyBuffer(rsiHandle, 0, 1, 1, rsiVal);
   CopyBuffer(atrHandle, 0, 1, 1, atrVal);
   CopyBuffer(adxHandle, 0, 1, 1, adxVal);
   
   // 6. กรองสภาวะตลาด (Market Regime)
   // ถ้า ADX > 20 แปลว่าตลาดกำลังมีเทรนด์แรง ห้ามทำ Mean Reversion เด็ดขาด!
   if(adxVal[0] > InpMaxADX) return;
   
   // 7. สัญญาณการเข้าเทรด (Entry Logic)
   // ระบบนี้จะเปิดทีละ 1 ไม้เท่านั้น (No Grid, No Martingale)
   if(PositionsTotal() == 0)
   {
      double ask = symInfo.Ask();
      double bid = symInfo.Bid();
      
      // สัญญาณ BUY: ราคาปิดแท่งที่แล้วหลุดขอบล่าง + RSI Oversold
      double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
      
      if(closePrice < bbLower[0] && rsiVal[0] < 30.0)
      {
         double slDistance = atrVal[0] * InpStopLossATR;
         double tpDistance = atrVal[0] * InpTakeProfitATR;
         
         double sl = ask - slDistance;
         double tp = ask + tpDistance;
         
         double lot = CalculateLotSize(slDistance);
         if(lot > 0) trade.Buy(lot, _Symbol, ask, sl, tp, "MR_BUY");
      }
      
      // สัญญาณ SELL: ราคาปิดแท่งที่แล้วทะลุขอบบน + RSI Overbought
      else if(closePrice > bbUpper[0] && rsiVal[0] > 70.0)
      {
         double slDistance = atrVal[0] * InpStopLossATR;
         double tpDistance = atrVal[0] * InpTakeProfitATR;
         
         double sl = bid + slDistance;
         double tp = bid - tpDistance;
         
         double lot = CalculateLotSize(slDistance);
         if(lot > 0) trade.Sell(lot, _Symbol, bid, sl, tp, "MR_SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชัน Break-Even (กันหน้าทุนทันทีเมื่อกำไรถึงเป้า)                      |
//+------------------------------------------------------------------+
void ApplyBreakEven()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == 777888)
         {
            double openPrice = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            double currentTP = posInfo.TakeProfit();
            
            // คำนวณระยะกำไรที่ต้องได้ก่อนจะเริ่มกันหน้าทุน
            double requiredProfitDist = MathAbs(currentTP - openPrice) * InpBreakEvenTriggerR;
            
            if(posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               // ถ้ายังไม่ได้กันทุน (SL อยู่ต่ำกว่าจุดเข้า) และราคาปัจจุบันวิ่งไปเกินระยะที่กำหนด
               if(currentSL < openPrice && symInfo.Bid() > (openPrice + requiredProfitDist))
               {
                  // ขยับ SL มาไว้ที่จุดเข้า + เผื่อค่าคอม/สเปรดนิดหน่อย (เช่น 10 points)
                  double newSL = openPrice + (10 * _Point);
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  Print("🛡️ Break-Even Activated: เลื่อน SL มากันทุนเรียบร้อย (Buy)");
               }
            }
            else if(posInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if((currentSL > openPrice || currentSL == 0) && symInfo.Ask() < (openPrice - requiredProfitDist))
               {
                  double newSL = openPrice - (10 * _Point);
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  Print("🛡️ Break-Even Activated: เลื่อน SL มากันทุนเรียบร้อย (Sell)");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันตรวจเป้าหมายและตัดขาดทุนรายวัน (Daily Drawdown Limiter)         |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // ถัาขึ้นวันใหม่ ให้รีเซ็ตยอดเงินเริ่มต้นของวันใหม่
   if(dt.day != lastDay)
   {
      startOfDayBalance = accInfo.Balance();
      lastDay = dt.day;
   }
   
   double currentEquity = accInfo.Equity();
   double dailyProfitPct = ((currentEquity - startOfDayBalance) / startOfDayBalance) * 100.0;
   
   // ถ้ากำไรถึงเป้า -> ปิดออเดอร์ ไปนอน
   if(dailyProfitPct >= InpDailyTargetPct)
   {
      CloseAllPositions();
      Comment("🛑 บอทหยุดทำงาน: ชนะตลาดแล้ววันนี้! (+", DoubleToString(dailyProfitPct, 2), "%)");
      return true;
   }
   
   // ถ้าติดลบถึงเกณฑ์ -> สับคัตเอาท์ ปิดออเดอร์หนีตาย
   if(dailyProfitPct <= -InpDailyDrawdownPct)
   {
      CloseAllPositions();
      Comment("🚨 บอทหยุดทำงานฉุกเฉิน: พอร์ตติดลบรายวันถึงขีดจำกัด (", DoubleToString(dailyProfitPct, 2), "%)");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ฟังก์ชันคำนวณ Lot Size ให้เสี่ยงแค่ 1% ของพอร์ต                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double riskAmount = accInfo.Balance() * (InpRiskPerTradePct / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(slDistance == 0 || tickValue == 0) return 0.0;
   
   double slTicks = slDistance / tickSize;
   double rawLot = riskAmount / (slTicks * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double finalLot = MathFloor(rawLot / stepLot) * stepLot;
   
   if(finalLot < minLot) finalLot = minLot;
   if(finalLot > maxLot) finalLot = maxLot;
   
   return finalLot;
}

//+------------------------------------------------------------------+
//| ฟังก์ชันปิดออเดอร์ทั้งหมด (กรณีฉุกเฉิน)                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == 777888)
         {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| แสดงหน้าปัด (Dashboard)                                          |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   double currentEquity = accInfo.Equity();
   double dailyProfitPct = ((currentEquity - startOfDayBalance) / startOfDayBalance) * 100.0;
   
   string text = "================================\\n";
   text += " 🛡️ Sustainable Daily Scalper\\n";
   text += "================================\\n";
   text += "💰 Equity: $" + DoubleToString(currentEquity, 2) + "\\n";
   text += "📊 วันนี้ทำได้: " + DoubleToString(dailyProfitPct, 2) + " %\\n";
   text += "🎯 เป้าหยุดกำไร: " + DoubleToString(InpDailyTargetPct, 2) + " %\\n";
   text += "🛑 เป้าหยุดขาดทุน: -" + DoubleToString(InpDailyDrawdownPct, 2) + " %\\n";
   text += "--------------------------------\\n";
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
      text += "💤 สถานะ: อยู่นอกเวลาเทรด (Waiting)\\n";
   else
      text += "⚡ สถานะ: ตลาดเปิด (Running)\\n";
      
   Comment(text);
}
//+------------------------------------------------------------------+
