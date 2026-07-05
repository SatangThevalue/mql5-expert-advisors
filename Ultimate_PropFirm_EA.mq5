//+------------------------------------------------------------------+
//|                                     Ultimate_PropFirm_EA.mq5     |
//|                                  Copyright 2026, Satang Quant    |
//| สถาปัตยกรรมผสมผสาน: GoldBaron + Range Breakout + Quantum Emperor |
//+------------------------------------------------------------------+
#property copyright "Satang Quant"
#property link      "https://github.com/SatangThevalue"
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
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== 1. Risk & Prop Firm Compliance ==="
input double   InpRiskPerTradePct   = 1.0;         // ความเสี่ยงต่อไม้ (%)
input double   InpDailyDrawdownPct  = 4.5;         // หยุดบอทเมื่อติดลบรายวัน (%)
input bool     InpRandomizeOrders   = true;        // สุ่ม Pips เล็กน้อยป้องกันกองทุนแบน (Trade Shuffling)
input bool     InpCloseOnFriday     = true;        // ปิดออเดอร์หนีวันหยุดสุดสัปดาห์ (No Weekend Gap)
input int      InpFridayCloseHour   = 20;          // เวลาเซิร์ฟเวอร์ที่ให้ปิดออเดอร์วันศุกร์

input group "=== 2. Session Breakout Strategy ==="
input int      InpAsianStartHour    = 0;           // เริ่มจับกรอบราคา
input int      InpAsianEndHour      = 8;           // จบกรอบราคา (เริ่มตลาดยุโรป)
input int      InpBufferPips        = 5;           // ระยะเผื่อ Breakout (Pips)

input group "=== 3. Indicators & Safety Filters ==="
input int      InpMAPeriod          = 50;          // เส้น EMA กรองเทรนด์
input bool     InpUseVolatilityFlt  = true;        // หลบข่าวกระชาก (ATR Spike)
input int      InpATRPeriod         = 14;          // ค่า ATR

//--- Global Variables
int      maHandle, atrHandle;
double   startOfDayBalance;
datetime nextBarTime;
double   asianHigh = 0, asianLow = 0;
bool     breakoutTradedToday = false;
int      pipMultiplier;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(102030);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   if(symInfo.Digits() == 3 || symInfo.Digits() == 5) pipMultiplier = 10;
   else pipMultiplier = 1;
   
   startOfDayBalance = accInfo.Balance();

   maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   
   if(maHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) return(INIT_FAILED);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   DrawDashboard();
   
   if(CheckDailyDrawdown()) return;
   if(InpCloseOnFriday && CheckFridayClose()) return;
   
   datetime currentTime[1];
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);
   if(currentTime[0] == nextBarTime) return; 
   nextBarTime = currentTime[0];
   
   if(InpUseVolatilityFlt && DetectNewsShock()) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // 1. ระบบจับกรอบราคาช่วงเอเชีย (Asian Range)
   if(dt.hour >= InpAsianStartHour && dt.hour < InpAsianEndHour)
   {
      double curHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double curLow = iLow(_Symbol, PERIOD_CURRENT, 1);
      
      if(asianHigh == 0 || curHigh > asianHigh) asianHigh = curHigh;
      if(asianLow == 0 || curLow < asianLow) asianLow = curLow;
      
      breakoutTradedToday = false; // รีเซ็ตสถานะเผื่อวันใหม่
      return; // ยังอยู่ในช่วงเก็บข้อมูล ห้ามเทรด
   }
   
   // 2. ระบบเข้าเทรดช่วงยุโรป/อเมริกา (London/US Breakout)
   if(dt.hour >= InpAsianEndHour && !breakoutTradedToday && asianHigh > 0 && PositionsTotal() == 0)
   {
      double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
      double maVal[1], atrVal[1];
      CopyBuffer(maHandle, 0, 1, 1, maVal);
      CopyBuffer(atrHandle, 0, 1, 1, atrVal);
      
      double buffer = InpBufferPips * _Point * pipMultiplier;
      double slDist = atrVal[0] * 1.5;
      
      // การสุ่มเพื่อหลบ Prop Firm (Trade Shuffling)
      double randomOffset = 0;
      if(InpRandomizeOrders) randomOffset = (MathRand() % 3) * _Point * pipMultiplier; 
      
      // เงื่อนไข BUY (ราคาทะลุขอบบน + ยืนเหนือ EMA)
      if(closePrice > (asianHigh + buffer) && closePrice > maVal[0])
      {
         double sl = symInfo.Ask() - slDist - randomOffset;
         double tp = symInfo.Ask() + (slDist * 2.0) + randomOffset; // RR 1:2
         double lot = CalculateLotSize(slDist);
         
         if(lot > 0) trade.Buy(lot, _Symbol, symInfo.Ask(), sl, tp, "Breakout_Buy");
         breakoutTradedToday = true;
      }
      
      // เงื่อนไข SELL (ราคาทะลุขอบล่าง + อยู่ใต้ EMA)
      else if(closePrice < (asianLow - buffer) && closePrice < maVal[0])
      {
         double sl = symInfo.Bid() + slDist + randomOffset;
         double tp = symInfo.Bid() - (slDist * 2.0) - randomOffset;
         double lot = CalculateLotSize(slDist);
         
         if(lot > 0) trade.Sell(lot, _Symbol, symInfo.Bid(), sl, tp, "Breakout_Sell");
         breakoutTradedToday = true;
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันต่างๆ (Prop Firm Logic)                                    |
//+------------------------------------------------------------------+
bool CheckFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour)
   {
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(posInfo.SelectByIndex(i) && posInfo.Magic() == 102030)
            trade.PositionClose(posInfo.Ticket());
      }
      Comment("🛑 วันศุกร์สุดสัปดาห์: ปิดออเดอร์ทั้งหมดเพื่อป้องกัน Weekend Gap");
      return true;
   }
   return false;
}

bool CheckDailyDrawdown()
{
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day != lastDay) { startOfDayBalance = accInfo.Balance(); lastDay = dt.day; }
   
   double dailyDrawdownPct = ((accInfo.Equity() - startOfDayBalance) / startOfDayBalance) * 100.0;
   
   if(dailyDrawdownPct <= -InpDailyDrawdownPct)
   {
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(posInfo.SelectByIndex(i) && posInfo.Magic() == 102030) trade.PositionClose(posInfo.Ticket());
      }
      Comment("🚨 บอทหยุดฉุกเฉิน: พอร์ตติดลบชนขีดจำกัด Prop Firm (", DoubleToString(dailyDrawdownPct, 2), "%)");
      return true;
   }
   return false;
}

bool DetectNewsShock()
{
   double atr[2];
   CopyBuffer(atrHandle, 0, 0, 2, atr);
   if((symInfo.High() - symInfo.Low()) > (atr[1] * 3.0)) return true;
   return false;
}

double CalculateLotSize(double slDistance)
{
   double riskAmount = accInfo.Balance() * (InpRiskPerTradePct / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slDistance == 0 || tickValue == 0) return 0.0;
   double rawLot = riskAmount / ((slDistance / tickSize) * tickValue);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(rawLot / stepLot) * stepLot;
}

void DrawDashboard()
{
   double dailyPct = ((accInfo.Equity() - startOfDayBalance) / startOfDayBalance) * 100.0;
   string text = "================================\n";
   text += " 🏆 Ultimate PropFirm EA (2026)\n";
   text += "================================\n";
   text += "💰 Equity: $" + DoubleToString(accInfo.Equity(), 2) + "\n";
   text += "📊 วันนี้ทำได้: " + DoubleToString(dailyPct, 2) + " %\n";
   if(asianHigh > 0) text += "📦 Asian Range: " + DoubleToString(asianLow, 2) + " - " + DoubleToString(asianHigh, 2) + "\n";
   Comment(text);
}
//+------------------------------------------------------------------+
