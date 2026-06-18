//+------------------------------------------------------------------+
//|                                       GridBatchScalper.mq5        |
//|          Grid Batch Scalper - Compound Growth Strategy             |
//|                         Version 1.00                              |
//+------------------------------------------------------------------+
//| Opens batches of identical positions at market, holds until        |
//| target profit, closes all, re-enters with compounded lot size.    |
//| Designed for XAUUSDm (Gold micro).                                |
//+------------------------------------------------------------------+
#property copyright "Grid Batch Scalper v1.0"
#property link      ""
#property version   "1.00"
#property strict
#property description "Grid Batch Scalper for XAUUSD (Gold)"
#property description "Opens batches of positions, compounds lot size with balance growth"
#property description "Matches robot trading style: batch entries, hold, close all, repeat"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════════ BATCH SETTINGS ══════════"
input int      InpBatchSize          = 10;           // Number of positions per batch
input int      InpMaxBatches         = 1;            // Max batches open simultaneously
input double   InpSpacingPoints      = 0;            // Spacing between entries (0=all at market)
input int      InpEntryDelayMs       = 500;          // Delay between entries (ms, 0=instant)

input group "══════════ LOT SIZING ══════════"
input double   InpRiskPercent        = 10.0;         // % of balance to risk per batch
input double   InpMinLot             = 0.01;         // Minimum lot size
input double   InpMaxLot             = 100.0;        // Maximum lot size
input bool     InpCompound           = true;         // Enable compound growth (auto-increase lots)
input double   InpFixedLot           = 0.01;         // Fixed lot (used when compound is OFF)

input group "══════════ TAKE PROFIT ══════════"
input double   InpTPPoints           = 100;          // Take profit per position (points)
input double   InpBatchTPMoney       = 0;            // Close all if batch $ profit >= this (0=off)
input double   InpBatchTPPercent     = 5.0;          // Close all if batch profit >= X% of balance
input bool     InpUsePointTP         = true;         // Use per-position point TP on broker side

input group "══════════ STOP LOSS ══════════"
input double   InpSLPoints           = 0;            // Stop loss per position (0=no SL)
input double   InpMaxDrawdownPercent = 30.0;         // Emergency close if DD exceeds X% of balance
input double   InpBatchSLMoney       = 0;            // Close batch if $ loss >= this (0=off)

input group "══════════ DIRECTION LOGIC ══════════"
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_M5;    // Timeframe for direction
input int      InpEMAPeriod          = 21;           // EMA period for trend detection
input bool     InpAutoDirection      = true;         // Auto-detect direction (EMA-based)
input bool     InpForceBuy           = false;        // Force BUY only (manual override)
input bool     InpForceSell          = false;        // Force SELL only (manual override)
input bool     InpAlternate          = false;        // Alternate direction each batch

input group "══════════ TIMING ══════════"
input int      InpCooldownSec        = 30;           // Seconds between closing batch and opening new
input int      InpStartHour          = 0;            // Trading start hour (server time, 0=any)
input int      InpEndHour            = 0;            // Trading end hour (0=any)
input bool     InpCloseOnFriday      = false;        // Close all positions Friday evening

input group "══════════ SYSTEM ══════════"
input int      InpMagicNumber        = 777777;       // EA Magic Number
input int      InpSlippage           = 50;           // Max slippage (points)
input string   InpComment            = "GridBatch";  // Trade comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CSymbolInfo    g_symbol;
CPositionInfo  g_posInfo;

int            g_emaHandle;
datetime       g_lastBatchClose;
bool           g_lastDirectionBuy;
int            g_batchCount;
bool           g_initialized;

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
   
   g_emaHandle = iMA(_Symbol, InpTrendTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create EMA indicator");
      return INIT_FAILED;
   }
   
   g_lastBatchClose = 0;
   g_lastDirectionBuy = false;
   g_batchCount = 0;
   g_initialized = true;
   
   // Count existing positions on startup
   g_batchCount = CountOurPositions();
   
   Print("═══════════════════════════════════════════════════");
   Print("     GRID BATCH SCALPER v1.0 - INITIALIZED");
   Print("═══════════════════════════════════════════════════");
   Print("Symbol:        ", _Symbol);
   Print("Batch Size:    ", InpBatchSize, " positions");
   Print("Compound:      ", InpCompound ? "ON" : "OFF");
   Print("Risk %:        ", InpRiskPercent, "%");
   Print("TP Points:     ", InpTPPoints);
   Print("Batch TP %:    ", InpBatchTPPercent, "%");
   Print("Max DD %:      ", InpMaxDrawdownPercent, "%");
   Print("Direction:     ", InpAutoDirection ? "AUTO (EMA)" : InpForceBuy ? "FORCE BUY" : InpForceSell ? "FORCE SELL" : "ALTERNATE");
   Print("Balance:       $", DoubleToString(g_account.Balance(), 2));
   Print("Calculated Lot:", DoubleToString(CalculateLotSize(), 2));
   Print("═══════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_emaHandle);
   Print("Grid Batch Scalper stopped.");
}

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;
   g_symbol.Refresh();
   
   int openCount = CountOurPositions();
   
   //=== STEP 1: Emergency drawdown check ===
   if(openCount > 0 && InpMaxDrawdownPercent > 0)
   {
      double dd = GetBatchDrawdownPercent();
      if(dd >= InpMaxDrawdownPercent)
      {
         Print("⚠ EMERGENCY: Drawdown ", DoubleToString(dd, 1), "% exceeds limit. Closing all.");
         CloseAllPositions();
         g_lastBatchClose = TimeCurrent();
         return;
      }
   }
   
   //=== STEP 2: Check batch $ SL ===
   if(openCount > 0 && InpBatchSLMoney > 0)
   {
      double batchPnL = GetBatchProfit();
      if(batchPnL <= -InpBatchSLMoney)
      {
         Print("⚠ Batch SL hit: $", DoubleToString(batchPnL, 2));
         CloseAllPositions();
         g_lastBatchClose = TimeCurrent();
         return;
      }
   }
   
   //=== STEP 3: Check batch profit target ===
   if(openCount > 0)
   {
      double batchPnL = GetBatchProfit();
      bool closeAll = false;
      
      // Money target
      if(InpBatchTPMoney > 0 && batchPnL >= InpBatchTPMoney)
      {
         Print("✓ Batch TP (money) hit: $", DoubleToString(batchPnL, 2));
         closeAll = true;
      }
      
      // Percent target
      if(!closeAll && InpBatchTPPercent > 0)
      {
         double balance = g_account.Balance();
         if(balance > 0 && (batchPnL / balance * 100.0) >= InpBatchTPPercent)
         {
            Print("✓ Batch TP (%) hit: ", DoubleToString(batchPnL / balance * 100.0, 1), "%");
            closeAll = true;
         }
      }
      
      if(closeAll)
      {
         CloseAllPositions();
         g_lastBatchClose = TimeCurrent();
         g_batchCount = 0;
         Print("✓ Balance after close: $", DoubleToString(g_account.Balance(), 2));
         Print("  Next lot size: ", DoubleToString(CalculateLotSize(), 2));
         return;
      }
   }
   
   //=== STEP 4: Friday close ===
   if(InpCloseOnFriday && openCount > 0)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.day_of_week == 5 && dt.hour >= 20)
      {
         Print("Friday close triggered.");
         CloseAllPositions();
         g_lastBatchClose = TimeCurrent();
         return;
      }
   }
   
   //=== STEP 5: Open new batch if none active ===
   if(openCount == 0)
   {
      // Cooldown check
      if(g_lastBatchClose > 0 && (TimeCurrent() - g_lastBatchClose) < InpCooldownSec)
         return;
      
      // Hour filter
      if(!IsTradeHour())
         return;
      
      // Determine direction
      bool isBuy = GetDirection();
      
      // Calculate lot size
      double lots = CalculateLotSize();
      
      // Open batch
      OpenBatch(isBuy, lots);
   }
}

//+------------------------------------------------------------------+
//| Calculate compounding lot size                                    |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!InpCompound)
      return NormalizeLot(InpFixedLot);
   
   double balance = g_account.Balance();
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Risk-based: allocate InpRiskPercent of balance across batch
   // For gold: 1 lot = $100 per point (standard), micro lot = $0.01 per point
   // Approximate: use tick value for calculation
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double riskMoney = balance * InpRiskPercent / 100.0;
   double riskPerPosition = riskMoney / InpBatchSize;
   
   // If SL is set, size based on SL distance
   double lots;
   if(InpSLPoints > 0 && tickValue > 0 && tickSize > 0)
   {
      double pointValue = tickValue / tickSize * _Point;
      lots = riskPerPosition / (InpSLPoints * pointValue);
   }
   else
   {
      // No SL: use balance-proportional sizing
      // Target: roughly balance / 1000 for micro accounts, scale up
      lots = balance * InpRiskPercent / 100.0 / 1000.0;
      if(lots < 0.01) lots = balance / 1500.0;  // Very small accounts
   }
   
   return NormalizeLot(lots);
}

double NormalizeLot(double lots)
{
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, lotMin);
   lots = MathMin(lots, lotMax);
   lots = MathMin(lots, InpMaxLot);
   lots = MathMax(lots, InpMinLot);
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Determine trade direction                                         |
//+------------------------------------------------------------------+
bool GetDirection()
{
   if(InpForceBuy) return true;
   if(InpForceSell) return false;
   
   if(InpAlternate)
   {
      g_lastDirectionBuy = !g_lastDirectionBuy;
      return g_lastDirectionBuy;
   }
   
   if(InpAutoDirection)
   {
      double ema[];
      double close[];
      if(CopyBuffer(g_emaHandle, 0, 0, 3, ema) < 3) return true;
      if(CopyClose(_Symbol, InpTrendTF, 0, 3, close) < 3) return true;
      
      // Price above EMA = buy, below = sell
      bool isBuy = (close[0] > ema[0]);
      
      // Confirm with EMA slope
      if(ema[0] > ema[1] && ema[1] > ema[2]) isBuy = true;
      else if(ema[0] < ema[1] && ema[1] < ema[2]) isBuy = false;
      
      g_lastDirectionBuy = isBuy;
      return isBuy;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open a batch of positions                                         |
//+------------------------------------------------------------------+
void OpenBatch(bool isBuy, double lots)
{
   int opened = 0;
   double entryPrice;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   for(int i = 0; i < InpBatchSize; i++)
   {
      g_symbol.Refresh();
      
      if(isBuy)
         entryPrice = g_symbol.Ask();
      else
         entryPrice = g_symbol.Bid();
      
      // Apply spacing offset for grid entries
      if(InpSpacingPoints > 0 && i > 0)
      {
         double offset = InpSpacingPoints * _Point * i;
         if(isBuy)
            entryPrice -= offset;  // Grid below for buys (limit-style)
         else
            entryPrice += offset;  // Grid above for sells
      }
      
      entryPrice = NormalizeDouble(entryPrice, digits);
      
      // Calculate SL and TP
      double sl = 0, tp = 0;
      
      if(InpSLPoints > 0)
      {
         if(isBuy) sl = entryPrice - InpSLPoints * _Point;
         else      sl = entryPrice + InpSLPoints * _Point;
         sl = NormalizeDouble(sl, digits);
      }
      
      if(InpUsePointTP && InpTPPoints > 0)
      {
         if(isBuy) tp = entryPrice + InpTPPoints * _Point;
         else      tp = entryPrice - InpTPPoints * _Point;
         tp = NormalizeDouble(tp, digits);
      }
      
      // Open the position
      string comment = InpComment + "_" + IntegerToString(i + 1);
      ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      bool result;
      if(InpSpacingPoints > 0 && i > 0)
      {
         // Use pending orders for grid spacing
         if(isBuy)
            result = g_trade.BuyLimit(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         else
            result = g_trade.SellLimit(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      }
      else
      {
         // Market order (all at same price)
         result = g_trade.PositionOpen(_Symbol, orderType, lots, entryPrice, sl, tp, comment);
      }
      
      if(result)
         opened++;
      else
         Print("Order ", i + 1, " failed: ", g_trade.ResultRetcodeDescription());
      
      // Small delay between entries if configured
      if(InpEntryDelayMs > 0 && i < InpBatchSize - 1)
         Sleep(InpEntryDelayMs);
   }
   
   g_batchCount = opened;
   
   Print("═══════════════════════════════════════════════════");
   Print("  ▶ BATCH OPENED: ", isBuy ? "BUY" : "SELL", " x", opened);
   Print("    Lot Size: ", DoubleToString(lots, 2));
   Print("    Balance:  $", DoubleToString(g_account.Balance(), 2));
   Print("    Target:   ", InpBatchTPPercent, "% ($", DoubleToString(g_account.Balance() * InpBatchTPPercent / 100.0, 2), ")");
   Print("═══════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Close all positions belonging to this EA                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
         {
            g_trade.PositionClose(g_posInfo.Ticket());
         }
      }
   }
   
   // Also delete any pending orders
   int orders = OrdersTotal();
   for(int i = orders - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
            g_trade.OrderDelete(ticket);
      }
   }
   
   g_batchCount = 0;
}

//+------------------------------------------------------------------+
//| Get total unrealized profit for our positions                     |
//+------------------------------------------------------------------+
double GetBatchProfit()
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
//| Get drawdown percentage relative to balance                       |
//+------------------------------------------------------------------+
double GetBatchDrawdownPercent()
{
   double profit = GetBatchProfit();
   double balance = g_account.Balance();
   if(balance <= 0) return 0;
   if(profit >= 0) return 0;
   return MathAbs(profit) / balance * 100.0;
}

//+------------------------------------------------------------------+
//| Count positions belonging to this EA                              |
//+------------------------------------------------------------------+
int CountOurPositions()
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
//| Check if current hour is within trading window                    |
//+------------------------------------------------------------------+
bool IsTradeHour()
{
   if(InpStartHour == 0 && InpEndHour == 0) return true;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(InpStartHour < InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   else
      return (hour >= InpStartHour || hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Trade transaction handler - track closes for stats                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   
   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic != InpMagicNumber) return;
   
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      
      // Individual position closed (either by TP/SL or our CloseAll)
      // Just track for logging purposes
   }
}
//+------------------------------------------------------------------+
