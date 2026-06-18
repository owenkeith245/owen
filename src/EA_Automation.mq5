//+------------------------------------------------------------------+
//|                                          EA_Automation.mq5        |
//|             Progressive Grid Scalper - Compound Growth            |
//|                         Version 1.00                              |
//+------------------------------------------------------------------+
//| Replica of TikTok @tasha_2110 "EA automation" trading bot.        |
//| Strategy:                                                         |
//|   1. Opens positions one at a time at regular intervals           |
//|   2. All same direction, same lot size                            |
//|   3. Holds through drawdown (no stop loss)                        |
//|   4. Closes ALL when total floating profit hits target            |
//|   5. Lot size compounds with balance growth                       |
//|   6. Repeats forever                                              |
//|                                                                   |
//| Install: Copy to MT5/MQL5/Experts/ → Compile → Attach to chart   |
//+------------------------------------------------------------------+
#property copyright "EA Automation v1.0"
#property link      ""
#property version   "1.00"
#property strict
#property description "Progressive Grid Scalper with Compound Growth"
#property description "Opens positions at intervals, closes all at profit target"
#property description "Designed for XAUUSDm (Gold micro) - Small account compound"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════════ ENTRY SETTINGS ══════════"
input int      InpMaxPositions       = 6;            // Max positions to open per cycle
input int      InpEntryIntervalSec   = 10;           // Seconds between adding new positions
input double   InpMinPriceGap        = 0;            // Min price gap to add position (0=time only)

input group "══════════ LOT SIZING ══════════"
input bool     InpCompound           = true;         // Auto-increase lots with balance
input double   InpFixedLot           = 0.01;         // Fixed lot (when compound OFF)
input double   InpLotPerDollar       = 0.01;         // Lot per $X balance (compound mode)
input double   InpBalancePerLotStep  = 50.0;         // Balance needed per lot step increase
input double   InpMinLot             = 0.01;         // Minimum lot size
input double   InpMaxLot             = 10.0;         // Maximum lot size

input group "══════════ PROFIT TARGET ══════════"
input double   InpTPPercent          = 100.0;        // Close all when profit = X% of balance
input double   InpTPDollars          = 0;            // OR close when profit >= $X (0=use %)
input double   InpMinProfit          = 0.50;         // Minimum $ profit to close (safety)

input group "══════════ RISK / SAFETY ══════════"
input double   InpMaxDDPercent       = 80.0;         // Max drawdown % before emergency close
input bool     InpUseSL              = false;        // Use stop loss per position
input double   InpSLPoints           = 0;            // SL in points (0=no SL)
input bool     InpCloseOnFriday      = false;        // Force close Friday evening

input group "══════════ DIRECTION ══════════"
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_M5;    // Timeframe for trend
input int      InpFastMA             = 9;            // Fast MA period
input int      InpSlowMA             = 21;           // Slow MA period
input bool     InpAutoDirection      = true;         // Auto-detect direction
input int      InpForceDirection     = 0;            // Force: 0=auto, 1=buy only, -1=sell only

input group "══════════ SYSTEM ══════════"
input int      InpMagicNumber        = 888888;       // Magic Number
input int      InpSlippage           = 50;           // Max slippage (points)
input int      InpCooldownSec        = 5;            // Cooldown after closing all (seconds)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CSymbolInfo    g_symbol;
CPositionInfo  g_posInfo;

int            g_hFastMA;
int            g_hSlowMA;
datetime       g_lastEntryTime;
datetime       g_lastCloseTime;
bool           g_currentDirectionBuy;
double         g_cycleStartBalance;
int            g_cycleNumber;
double         g_lotStep;
double         g_lotMin;
double         g_lotMax;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol.Name(_Symbol);
   g_symbol.Refresh();
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Indicators for direction
   g_hFastMA = iMA(_Symbol, InpTrendTF, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hSlowMA = iMA(_Symbol, InpTrendTF, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_hFastMA == INVALID_HANDLE || g_hSlowMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MA indicators");
      return INIT_FAILED;
   }
   
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   g_lastEntryTime = 0;
   g_lastCloseTime = 0;
   g_currentDirectionBuy = true;
   g_cycleStartBalance = g_account.Balance();
   g_cycleNumber = 0;
   
   // Detect initial direction
   g_currentDirectionBuy = DetectDirection();
   
   Print("═══════════════════════════════════════════════");
   Print("       EA AUTOMATION v1.0 - STARTED");
   Print("═══════════════════════════════════════════════");
   Print("Symbol:         ", _Symbol);
   Print("Balance:        $", DoubleToString(g_account.Balance(), 2));
   Print("Lot Size:       ", DoubleToString(CalculateLot(), 2));
   Print("Max Positions:  ", InpMaxPositions);
   Print("Entry Interval: ", InpEntryIntervalSec, " sec");
   Print("TP Target:      ", InpTPPercent, "% of balance");
   Print("Direction:      ", g_currentDirectionBuy ? "BUY" : "SELL");
   Print("Compound:       ", InpCompound ? "ON" : "OFF");
   Print("═══════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_hFastMA);
   IndicatorRelease(g_hSlowMA);
   Print("EA Automation stopped. Cycles completed: ", g_cycleNumber);
}

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   g_symbol.Refresh();
   
   int openCount = CountPositions();
   double floatingPnL = GetFloatingProfit();
   double balance = g_account.Balance();
   
   //=== CHECK 1: Emergency drawdown ===
   if(openCount > 0 && InpMaxDDPercent > 0 && balance > 0)
   {
      double ddPct = MathAbs(floatingPnL) / balance * 100.0;
      if(floatingPnL < 0 && ddPct >= InpMaxDDPercent)
      {
         Print("⚠ EMERGENCY DD: ", DoubleToString(ddPct, 1), "% - Closing all");
         CloseAll();
         g_lastCloseTime = TimeCurrent();
         return;
      }
   }
   
   //=== CHECK 2: Friday close ===
   if(InpCloseOnFriday && openCount > 0)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.day_of_week == 5 && dt.hour >= 20)
      {
         Print("Friday close - closing all positions");
         CloseAll();
         g_lastCloseTime = TimeCurrent();
         return;
      }
   }
   
   //=== CHECK 3: Profit target reached - CLOSE ALL ===
   if(openCount > 0 && floatingPnL > 0)
   {
      bool shouldClose = false;
      
      // Dollar target
      if(InpTPDollars > 0 && floatingPnL >= InpTPDollars)
         shouldClose = true;
      
      // Percent target
      if(!shouldClose && InpTPPercent > 0 && balance > 0)
      {
         double profitPct = floatingPnL / balance * 100.0;
         if(profitPct >= InpTPPercent)
            shouldClose = true;
      }
      
      // Minimum profit safety
      if(shouldClose && floatingPnL < InpMinProfit)
         shouldClose = false;
      
      if(shouldClose)
      {
         Print("═══════════════════════════════════════════════");
         Print("  ✓ PROFIT TARGET HIT!");
         Print("    Floating P/L: $", DoubleToString(floatingPnL, 2));
         Print("    Positions:    ", openCount);
         
         CloseAll();
         g_cycleNumber++;
         g_lastCloseTime = TimeCurrent();
         
         double newBal = g_account.Balance();
         Print("    New Balance:  $", DoubleToString(newBal, 2));
         Print("    Growth:       +$", DoubleToString(newBal - g_cycleStartBalance, 2));
         Print("    Next Lot:     ", DoubleToString(CalculateLot(), 2));
         Print("    Cycle #:      ", g_cycleNumber);
         Print("═══════════════════════════════════════════════");
         
         g_cycleStartBalance = newBal;
         
         // Update direction for next cycle
         g_currentDirectionBuy = DetectDirection();
         return;
      }
   }
   
   //=== CHECK 4: Add new position if conditions met ===
   if(openCount < InpMaxPositions)
   {
      // Cooldown after close
      if(g_lastCloseTime > 0 && (TimeCurrent() - g_lastCloseTime) < InpCooldownSec)
         return;
      
      // Time interval between entries
      if(g_lastEntryTime > 0 && (TimeCurrent() - g_lastEntryTime) < InpEntryIntervalSec)
         return;
      
      // If no positions yet, detect fresh direction
      if(openCount == 0)
         g_currentDirectionBuy = DetectDirection();
      
      // Price gap filter (optional)
      if(InpMinPriceGap > 0 && openCount > 0)
      {
         double lastEntry = GetLastEntryPrice();
         double currentPrice = g_currentDirectionBuy ? g_symbol.Ask() : g_symbol.Bid();
         double gap = MathAbs(currentPrice - lastEntry) / _Point;
         if(gap < InpMinPriceGap)
            return;
      }
      
      // Open position
      OpenPosition();
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on balance                               |
//+------------------------------------------------------------------+
double CalculateLot()
{
   if(!InpCompound)
      return NormalizeLot(InpFixedLot);
   
   double balance = g_account.Balance();
   
   // Simple compound: lot increases per balance threshold
   // $0-50 = 0.01, $50-100 = 0.02, $100-150 = 0.03, etc.
   double lots = MathFloor(balance / InpBalancePerLotStep) * g_lotStep;
   
   // Ensure minimum
   if(lots < InpMinLot) lots = InpMinLot;
   
   return NormalizeLot(lots);
}

double NormalizeLot(double lots)
{
   lots = MathFloor(lots / g_lotStep) * g_lotStep;
   lots = MathMax(lots, g_lotMin);
   lots = MathMin(lots, g_lotMax);
   lots = MathMax(lots, InpMinLot);
   lots = MathMin(lots, InpMaxLot);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Detect trade direction using MA crossover                         |
//+------------------------------------------------------------------+
bool DetectDirection()
{
   if(InpForceDirection == 1) return true;
   if(InpForceDirection == -1) return false;
   
   if(!InpAutoDirection) return g_currentDirectionBuy;
   
   double fast[], slow[];
   if(CopyBuffer(g_hFastMA, 0, 0, 3, fast) < 3) return g_currentDirectionBuy;
   if(CopyBuffer(g_hSlowMA, 0, 0, 3, slow) < 3) return g_currentDirectionBuy;
   
   // Fast MA above slow = buy, below = sell
   return (fast[0] > slow[0]);
}

//+------------------------------------------------------------------+
//| Open a single position in current direction                       |
//+------------------------------------------------------------------+
void OpenPosition()
{
   double lots = CalculateLot();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double price, sl = 0;
   
   if(g_currentDirectionBuy)
   {
      price = g_symbol.Ask();
      if(InpUseSL && InpSLPoints > 0)
         sl = NormalizeDouble(price - InpSLPoints * _Point, digits);
   }
   else
   {
      price = g_symbol.Bid();
      if(InpUseSL && InpSLPoints > 0)
         sl = NormalizeDouble(price + InpSLPoints * _Point, digits);
   }
   
   string comment = StringFormat("EA_Auto_%d_%d", g_cycleNumber, CountPositions() + 1);
   ENUM_ORDER_TYPE type = g_currentDirectionBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   // No individual TP - we close all at batch profit target
   bool result = g_trade.PositionOpen(_Symbol, type, lots, price, sl, 0, comment);
   
   if(result)
   {
      g_lastEntryTime = TimeCurrent();
      int count = CountPositions();
      Print(StringFormat("  + %s #%d | Lot: %.2f | Price: %.3f | Balance: $%.2f",
            g_currentDirectionBuy ? "BUY" : "SELL", count, lots, price, g_account.Balance()));
   }
   else
   {
      Print("Order failed: ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close all positions belonging to this EA                          |
//+------------------------------------------------------------------+
void CloseAll()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
            g_trade.PositionClose(g_posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Get total floating profit for our positions                       |
//+------------------------------------------------------------------+
double GetFloatingProfit()
{
   double profit = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
            profit += g_posInfo.Profit() + g_posInfo.Swap() + g_posInfo.Commission();
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Count our open positions                                          |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get the entry price of the last opened position                   |
//+------------------------------------------------------------------+
double GetLastEntryPrice()
{
   double lastPrice = 0;
   datetime lastTime = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
         {
            if(g_posInfo.Time() > lastTime)
            {
               lastTime = g_posInfo.Time();
               lastPrice = g_posInfo.PriceOpen();
            }
         }
      }
   }
   return lastPrice;
}
//+------------------------------------------------------------------+
