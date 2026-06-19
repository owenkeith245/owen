//+------------------------------------------------------------------+
//|                                          TickScalperMachine.mq5   |
//|                     TICK SCALPER MACHINE v1.0                      |
//|       Ultra-Reliable Tick-Based Scalping for Account Growth        |
//+------------------------------------------------------------------+
#property copyright "Tick Scalper Machine"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| DESIGN PHILOSOPHY:                                                |
//| 1. Only enter on CONFIRMED micro-momentum (tick velocity burst)   |
//| 2. Take profit FAST (2-5 pips) - never hold for big moves         |
//| 3. Cut losses INSTANTLY (max 3 pips) - no hoping, no praying      |
//| 4. Scale lots ONLY because equity grew - never to recover         |
//| 5. If in doubt, DON'T TRADE - missing a trade costs nothing       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "====== GENERAL ======"
input int      InpMagic              = 950000;          // Magic Number
input string   InpSymbol             = "";              // Symbol (empty = current)

input group "====== TICK VELOCITY ENGINE ======"
input int      InpTickWindow         = 20;              // Tick analysis window
input int      InpMinTicksPerSec     = 3;              // Min ticks/sec for momentum
input int      InpConsecTicks        = 3;              // Min consecutive same-direction ticks
input double   InpAcceleration       = 1.5;            // Tick acceleration multiplier
input int      InpTickBufferSize     = 100;            // Tick buffer size

input group "====== ENTRY CONDITIONS ======"
input double   InpMaxSpreadMult      = 1.3;            // Max spread as multiple of average
input double   InpMaxSpreadPips      = 2.0;            // Absolute max spread (pips)
input double   InpMinMomentumPips    = 0.5;            // Min tick burst size (pips)
input bool     InpRequireVolConfirm  = true;           // Require volume confirmation
input int      InpMinVolMult         = 2;              // Min volume multiplier vs average

input group "====== PROFIT TARGETS ======"
input double   InpTP1Pips            = 2.0;            // First TP (pips)
input double   InpTP2Pips            = 4.0;            // Second TP (pips)
input double   InpTP3Pips            = 7.0;            // Runner TP (pips)
input double   InpPartial1Pct        = 0.40;           // Close 40% at TP1
input double   InpPartial2Pct        = 0.30;           // Close 30% at TP2
input double   InpBEPips             = 1.5;            // Move SL to BE at this profit

input group "====== LOSS PREVENTION (7 LAYERS) ======"
input double   InpMaxSLPips          = 3.0;            // Layer 3: Hard max SL (pips) NEVER widened
input int      InpReverseTicks       = 2;              // Layer 4: Exit after N reverse ticks
input double   InpDailyDDLimit       = 1.5;            // Layer 5: Daily DD halt (%)
input int      InpLossReduceCount    = 2;              // Layer 6: Reduce lot after N losses
input double   InpLossReducePct      = 0.50;           // Layer 6: Reduce to this fraction
input int      InpLossReduceDuration = 3;              // Layer 6: For next N trades
input int      InpSessionStopLosses  = 4;              // Layer 7: Stop after N losses per session

input group "====== POSITION SIZING (COMPOUNDING) ======"
input double   InpBaseRiskPct        = 0.50;           // Base risk per trade (%)
input double   InpMinLot             = 0.01;           // Min lot
input double   InpMaxLot             = 10.00;          // Max lot

input group "====== SESSION FILTER ======"
input bool     InpSessionFilter      = true;           // Enable session filter
input int      InpBestStart          = 7;              // Best hours start (UTC) - London open
input int      InpBestEnd            = 17;             // Best hours end (UTC) - NY afternoon
input int      InpOverlapStart       = 12;             // Overlap start (UTC) - highest priority
input int      InpOverlapEnd         = 16;             // Overlap end (UTC)

input group "====== DAILY TARGETS ======"
input double   InpDailyProfitTarget  = 2.0;            // Stop after X% daily profit
input int      InpMaxTradesDay       = 30;             // Max trades per day
input int      InpCooldownMs         = 5000;           // Min ms between trades

input group "====== ADVANCED ======"
input bool     InpTickDivergence     = true;           // Detect bid/ask divergence
input double   InpDivergenceThresh   = 0.5;            // Divergence threshold (pips)
input bool     InpAntiSlippage       = true;           // Slippage protection
input int      InpMaxSlippage        = 5;              // Max slippage (points)
input bool     InpCompounding        = true;           // Enable equity compounding

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct TickData
{
   double   bid;
   double   ask;
   double   spread;
   ulong    timeMs;
   long     volume;
   int      direction;     // +1 bid up, -1 bid down, 0 no change
};

struct TickStats
{
   double   ticksPerSecond;
   int      consecSameDir;
   int      lastDirection;
   double   burstSize;       // Total move in current burst (pips)
   double   avgSpread;
   double   avgVolume;
   double   bidVelocity;     // Pips per second in bid direction
   bool     accelerating;
   double   lastBidDelta;
   double   currentBidDelta;
};

struct ActiveTrade
{
   ulong       ticket;
   double      entryPrice;
   double      initialSL;
   double      initialLots;
   double      currentLots;
   bool        isBuy;
   bool        be1Done;        // BE move done
   bool        partial1Done;   // First partial done
   bool        partial2Done;   // Second partial done
   datetime    openTime;
   ulong       openTimeMs;
   int         adverseTicks;   // Count of ticks against position
   double      maxProfit;      // Max profit reached (pips)
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_position;

string         g_symbol;
double         g_point;
int            g_digits;
double         g_pipSize;     // 1 pip in price terms

// Tick buffer
TickData       g_ticks[100];
int            g_tickCount = 0;
int            g_tickHead = 0;

// Tick stats
TickStats      g_stats;

// Active trade
ActiveTrade    g_active;
bool           g_hasPosition = false;

// Performance
int            g_totalTrades = 0;
int            g_totalWins = 0;
int            g_totalLosses = 0;
double         g_totalPnL = 0;
double         g_dailyPnL = 0;
int            g_dailyTrades = 0;
int            g_sessionLosses = 0;
int            g_consecLosses = 0;
int            g_reducedTradesLeft = 0;
double         g_dayStartBalance = 0;
datetime       g_lastDay = 0;
ulong          g_lastTradeMs = 0;

// Spread tracking
double         g_spreadHistory[200];
int            g_spreadCount = 0;
double         g_avgSpread = 0;

// Halt flags
bool           g_dailyTargetHit = false;
bool           g_dailyDDHalt = false;
bool           g_sessionHalt = false;

// Log
int            g_logFile = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = (InpSymbol == "") ? Symbol() : InpSymbol;
   g_point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   
   // Pip size: for 5-digit forex pairs, 1 pip = 10 points
   if(g_digits == 5 || g_digits == 3)
      g_pipSize = g_point * 10;
   else
      g_pipSize = g_point;
   
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   g_dayStartBalance = g_account.Balance();
   g_lastDay = iTime(g_symbol, PERIOD_D1, 0);
   g_hasPosition = false;
   
   // Init tick stats
   g_stats.ticksPerSecond = 0;
   g_stats.consecSameDir = 0;
   g_stats.lastDirection = 0;
   g_stats.burstSize = 0;
   g_stats.avgSpread = 0;
   g_stats.avgVolume = 0;
   g_stats.bidVelocity = 0;
   g_stats.accelerating = false;
   g_stats.lastBidDelta = 0;
   g_stats.currentBidDelta = 0;
   
   // Open log
   g_logFile = FileOpen("TickScalper_trades.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ, ',');
   if(g_logFile != INVALID_HANDLE)
   {
      FileSeek(g_logFile, 0, SEEK_END);
      if(FileTell(g_logFile) == 0)
         FileWrite(g_logFile, "Time", "Symbol", "Dir", "Lot", "Entry", "Exit",
                   "Profit", "Win", "TickVelocity", "Spread", "BurstSize",
                   "HoldMs", "Balance");
   }
   
   Print("============================================");
   Print("  TICK SCALPER MACHINE v1.0");
   Print("  Ultra-Reliable Tick-Based Scalping");
   Print("============================================");
   Print("  Symbol: ", g_symbol);
   Print("  Pip Size: ", DoubleToString(g_pipSize, g_digits));
   Print("  Max SL: ", DoubleToString(InpMaxSLPips, 1), " pips (HARD LIMIT)");
   Print("  TP1: +", DoubleToString(InpTP1Pips, 1), " pips (40%)");
   Print("  TP2: +", DoubleToString(InpTP2Pips, 1), " pips (30%)");
   Print("  TP3: +", DoubleToString(InpTP3Pips, 1), " pips (runner)");
   Print("  Daily Target: +", DoubleToString(InpDailyProfitTarget, 1), "%");
   Print("  Daily DD Limit: -", DoubleToString(InpDailyDDLimit, 1), "%");
   Print("  >>> TICK ENGINE ARMED <<<");
   Print("============================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logFile != INVALID_HANDLE) FileClose(g_logFile);
   ObjectsDeleteAll(0, "TSM_");
   PrintReport();
}

//+------------------------------------------------------------------+
//| Expert tick function - PROCESSES EVERY TICK                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Day reset check
   CheckDayReset();
   
   // Get current tick data
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double spread = (ask - bid) / g_pipSize;
   ulong timeMs = GetTickCount64();
   long volume = (long)SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_REAL);
   if(volume <= 0) volume = (long)iVolume(g_symbol, PERIOD_M1, 0);
   
   // Store tick
   StoreTick(bid, ask, spread, timeMs, volume);
   
   // Update tick statistics
   UpdateTickStats();
   
   // Track spread
   TrackSpread(spread);
   
   // Draw dashboard
   DrawDashboard();
   
   // If we have a position, manage it FIRST (highest priority)
   if(g_hasPosition)
   {
      ManagePosition(bid, ask);
      return;  // Don't look for new entries while managing
   }
   
   // ====== HALT CHECKS ======
   if(g_dailyTargetHit || g_dailyDDHalt || g_sessionHalt) return;
   if(g_dailyTrades >= InpMaxTradesDay) return;
   
   // Daily DD check (Layer 5)
   if(g_dayStartBalance > 0)
   {
      double equity = g_account.Equity();
      double ddPct = (g_dayStartBalance - equity) / g_dayStartBalance * 100;
      if(ddPct >= InpDailyDDLimit)
      {
         g_dailyDDHalt = true;
         Print("TSM: DAILY DD HALT - ", DoubleToString(ddPct, 2), "%");
         return;
      }
   }
   
   // Daily profit target check
   if(g_dayStartBalance > 0)
   {
      double profitPct = g_dailyPnL / g_dayStartBalance * 100;
      if(profitPct >= InpDailyProfitTarget)
      {
         g_dailyTargetHit = true;
         Print("TSM: DAILY TARGET HIT +", DoubleToString(profitPct, 2), "% - LOCKING PROFITS");
         return;
      }
   }
   
   // Session loss halt (Layer 7)
   if(g_sessionLosses >= InpSessionStopLosses)
   {
      g_sessionHalt = true;
      Print("TSM: SESSION HALT - ", g_sessionLosses, " losses this session");
      return;
   }
   
   // Cooldown check
   if(timeMs - g_lastTradeMs < (ulong)InpCooldownMs) return;
   
   // ====== SESSION FILTER ======
   if(InpSessionFilter)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour < InpBestStart || dt.hour >= InpBestEnd) return;
   }
   
   // ====== ENTRY LOGIC ======
   CheckEntry(bid, ask, spread, timeMs);
}

//+------------------------------------------------------------------+
//| STORE TICK                                                        |
//+------------------------------------------------------------------+
void StoreTick(double bid, double ask, double spread, ulong timeMs, long volume)
{
   int idx = g_tickHead % InpTickBufferSize;
   
   // Calculate direction
   int dir = 0;
   if(g_tickCount > 0)
   {
      int prevIdx = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
      if(bid > g_ticks[prevIdx].bid) dir = 1;
      else if(bid < g_ticks[prevIdx].bid) dir = -1;
   }
   
   g_ticks[idx].bid = bid;
   g_ticks[idx].ask = ask;
   g_ticks[idx].spread = spread;
   g_ticks[idx].timeMs = timeMs;
   g_ticks[idx].volume = volume;
   g_ticks[idx].direction = dir;
   
   g_tickHead = (g_tickHead + 1) % InpTickBufferSize;
   if(g_tickCount < InpTickBufferSize) g_tickCount++;
}

//+------------------------------------------------------------------+
//| UPDATE TICK STATISTICS                                            |
//+------------------------------------------------------------------+
void UpdateTickStats()
{
   if(g_tickCount < 5) return;
   
   int window = MathMin(g_tickCount, InpTickWindow);
   
   // Calculate ticks per second
   int newest = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
   int oldest = (g_tickHead - window + InpTickBufferSize) % InpTickBufferSize;
   
   ulong timeDiff = g_ticks[newest].timeMs - g_ticks[oldest].timeMs;
   if(timeDiff > 0)
      g_stats.ticksPerSecond = (double)(window - 1) / (timeDiff / 1000.0);
   
   // Consecutive same direction
   int consecDir = 0;
   int lastDir = 0;
   double burstSize = 0;
   
   for(int i = 1; i <= MathMin(window, 15); i++)
   {
      int idx = (g_tickHead - i + InpTickBufferSize) % InpTickBufferSize;
      int dir = g_ticks[idx].direction;
      
      if(i == 1) { lastDir = dir; consecDir = (dir != 0) ? 1 : 0; continue; }
      
      if(dir == lastDir && dir != 0)
      {
         consecDir++;
         int prevIdx = (idx + 1) % InpTickBufferSize;
         burstSize += MathAbs(g_ticks[prevIdx].bid - g_ticks[idx].bid) / g_pipSize;
      }
      else
         break;
   }
   
   g_stats.consecSameDir = consecDir;
   g_stats.lastDirection = lastDir;
   g_stats.burstSize = burstSize;
   
   // Bid velocity (pips/second over recent window)
   if(timeDiff > 0 && window >= 3)
   {
      double priceMove = MathAbs(g_ticks[newest].bid - g_ticks[oldest].bid) / g_pipSize;
      g_stats.bidVelocity = priceMove / (timeDiff / 1000.0);
   }
   
   // Acceleration: is current tick delta larger than previous?
   if(g_tickCount >= 3)
   {
      int idx1 = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
      int idx2 = (g_tickHead - 2 + InpTickBufferSize) % InpTickBufferSize;
      int idx3 = (g_tickHead - 3 + InpTickBufferSize) % InpTickBufferSize;
      
      g_stats.currentBidDelta = MathAbs(g_ticks[idx1].bid - g_ticks[idx2].bid);
      g_stats.lastBidDelta = MathAbs(g_ticks[idx2].bid - g_ticks[idx3].bid);
      g_stats.accelerating = (g_stats.currentBidDelta > g_stats.lastBidDelta * InpAcceleration);
   }
   
   // Average volume
   double volSum = 0;
   int volCount = 0;
   for(int i = 0; i < window; i++)
   {
      int idx = (g_tickHead - 1 - i + InpTickBufferSize) % InpTickBufferSize;
      if(g_ticks[idx].volume > 0) { volSum += g_ticks[idx].volume; volCount++; }
   }
   g_stats.avgVolume = (volCount > 0) ? volSum / volCount : 0;
}

//+------------------------------------------------------------------+
//| TRACK SPREAD                                                      |
//+------------------------------------------------------------------+
void TrackSpread(double spread)
{
   if(g_spreadCount < 200)
   {
      g_spreadHistory[g_spreadCount] = spread;
      g_spreadCount++;
   }
   else
   {
      // Shift
      for(int i = 0; i < 199; i++) g_spreadHistory[i] = g_spreadHistory[i+1];
      g_spreadHistory[199] = spread;
   }
   
   // Calculate average
   double sum = 0;
   for(int i = 0; i < g_spreadCount; i++) sum += g_spreadHistory[i];
   g_avgSpread = (g_spreadCount > 0) ? sum / g_spreadCount : spread;
}

//+------------------------------------------------------------------+
//| CHECK ENTRY                                                       |
//+------------------------------------------------------------------+
void CheckEntry(double bid, double ask, double spread, ulong timeMs)
{
   // ====== LAYER 1: Spread filter ======
   if(spread > InpMaxSpreadPips)
      return;
   if(g_avgSpread > 0 && spread > g_avgSpread * InpMaxSpreadMult)
      return;
   
   // ====== LAYER 2: Tick velocity filter ======
   if(g_stats.ticksPerSecond < InpMinTicksPerSec)
      return;
   
   // ====== TICK DIVERGENCE CHECK ======
   if(InpTickDivergence && g_tickCount >= 3)
   {
      int idx1 = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
      int idx2 = (g_tickHead - 2 + InpTickBufferSize) % InpTickBufferSize;
      double bidDelta = MathAbs(g_ticks[idx1].bid - g_ticks[idx2].bid) / g_pipSize;
      double askDelta = MathAbs(g_ticks[idx1].ask - g_ticks[idx2].ask) / g_pipSize;
      
      // If bid moves but ask doesn't (or vice versa) = suspicious
      if(bidDelta > InpDivergenceThresh && askDelta < 0.1)
         return;
      if(askDelta > InpDivergenceThresh && bidDelta < 0.1)
         return;
   }
   
   // ====== MOMENTUM BURST DETECTION ======
   bool buySignal = false;
   bool sellSignal = false;
   
   // Condition 1: Consecutive ticks in same direction
   if(g_stats.consecSameDir < InpConsecTicks)
      return;
   
   // Condition 2: Burst size minimum
   if(g_stats.burstSize < InpMinMomentumPips)
      return;
   
   // Condition 3: Acceleration (optional but preferred)
   // Not required but boosts confidence
   
   // Determine direction
   if(g_stats.lastDirection > 0)
      buySignal = true;
   else if(g_stats.lastDirection < 0)
      sellSignal = true;
   
   if(!buySignal && !sellSignal) return;
   
   // ====== VOLUME CONFIRMATION ======
   if(InpRequireVolConfirm && g_stats.avgVolume > 0)
   {
      int latestIdx = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
      if(g_ticks[latestIdx].volume < g_stats.avgVolume * InpMinVolMult)
         return;  // Volume too low - not institutional
   }
   
   // ====== OVERLAP BOOST ======
   double riskMult = 1.0;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour >= InpOverlapStart && dt.hour < InpOverlapEnd)
      riskMult = 1.25;  // Slightly larger during overlap
   
   // ====== EXECUTE ======
   if(buySignal)
      ExecuteEntry(true, ask, riskMult, timeMs);
   else if(sellSignal)
      ExecuteEntry(false, bid, riskMult, timeMs);
}

//+------------------------------------------------------------------+
//| EXECUTE ENTRY                                                     |
//+------------------------------------------------------------------+
void ExecuteEntry(bool isBuy, double price, double riskMult, ulong timeMs)
{
   // Calculate lot
   double lot = CalcLot(riskMult);
   if(lot <= 0) return;
   
   // SL/TP
   double sl, tp;
   if(isBuy)
   {
      sl = price - InpMaxSLPips * g_pipSize;
      tp = price + InpTP3Pips * g_pipSize;
   }
   else
   {
      sl = price + InpMaxSLPips * g_pipSize;
      tp = price - InpTP3Pips * g_pipSize;
   }
   
   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);
   
   string comment = "TSM|" + (isBuy ? "BUY" : "SELL") + "|V" + 
                    DoubleToString(g_stats.ticksPerSecond, 1) +
                    "|B" + DoubleToString(g_stats.burstSize, 1);
   
   bool result = false;
   if(isBuy)
      result = g_trade.Buy(lot, g_symbol, 0, sl, tp, comment);
   else
      result = g_trade.Sell(lot, g_symbol, 0, sl, tp, comment);
   
   if(result)
   {
      // Check slippage
      double fillPrice = g_trade.ResultPrice();
      if(InpAntiSlippage && fillPrice > 0)
      {
         double slip = MathAbs(fillPrice - price) / g_point;
         if(slip > InpMaxSlippage)
         {
            // Close immediately - execution quality bad
            g_trade.PositionClose(g_trade.ResultOrder());
            Print("TSM: SLIPPAGE REJECT - ", DoubleToString(slip, 0), " pts");
            return;
         }
      }
      
      g_active.ticket = g_trade.ResultOrder();
      g_active.entryPrice = (fillPrice > 0) ? fillPrice : price;
      g_active.initialSL = sl;
      g_active.initialLots = lot;
      g_active.currentLots = lot;
      g_active.isBuy = isBuy;
      g_active.be1Done = false;
      g_active.partial1Done = false;
      g_active.partial2Done = false;
      g_active.openTime = TimeCurrent();
      g_active.openTimeMs = timeMs;
      g_active.adverseTicks = 0;
      g_active.maxProfit = 0;
      g_hasPosition = true;
      
      g_lastTradeMs = timeMs;
      g_dailyTrades++;
      
      Print("TSM: ", (isBuy ? "BUY" : "SELL"), " ", g_symbol,
            " @", DoubleToString(g_active.entryPrice, g_digits),
            " Lot=", DoubleToString(lot, 2),
            " Vel=", DoubleToString(g_stats.ticksPerSecond, 1), "t/s",
            " Burst=", DoubleToString(g_stats.burstSize, 1), "p",
            " Sprd=", DoubleToString(g_ticks[(g_tickHead-1+InpTickBufferSize)%InpTickBufferSize].spread, 1));
   }
}

//+------------------------------------------------------------------+
//| MANAGE POSITION - Called every tick when position is open          |
//+------------------------------------------------------------------+
void ManagePosition(double bid, double ask)
{
   if(!PositionSelectByTicket(g_active.ticket))
   {
      g_hasPosition = false;
      return;
   }
   
   double entry = g_active.entryPrice;
   bool isBuy = g_active.isBuy;
   
   // Current profit in pips
   double profitPips = 0;
   if(isBuy)
      profitPips = (bid - entry) / g_pipSize;
   else
      profitPips = (entry - ask) / g_pipSize;
   
   if(profitPips > g_active.maxProfit)
      g_active.maxProfit = profitPips;
   
   // ====== LAYER 4: Reverse tick detection ======
   if(g_tickCount >= 2)
   {
      int latestIdx = (g_tickHead - 1 + InpTickBufferSize) % InpTickBufferSize;
      int dir = g_ticks[latestIdx].direction;
      
      if(isBuy && dir < 0)
         g_active.adverseTicks++;
      else if(!isBuy && dir > 0)
         g_active.adverseTicks++;
      else if((isBuy && dir > 0) || (!isBuy && dir < 0))
         g_active.adverseTicks = 0;  // Reset on favorable tick
      
      // If multiple adverse ticks right after entry (before profit)
      if(g_active.adverseTicks >= InpReverseTicks && profitPips <= 0.5)
      {
         g_trade.PositionClose(g_active.ticket);
         Print("TSM: REVERSE TICK EXIT - ", g_active.adverseTicks, " adverse ticks");
         g_hasPosition = false;
         return;
      }
   }
   
   // ====== PROFIT MANAGEMENT ======
   
   // Move to breakeven
   if(!g_active.be1Done && profitPips >= InpBEPips)
   {
      double newSL;
      if(isBuy) newSL = entry + 0.3 * g_pipSize;  // BE + 0.3 pips
      else newSL = entry - 0.3 * g_pipSize;
      newSL = NormalizeDouble(newSL, g_digits);
      
      if(g_trade.PositionModify(g_active.ticket, newSL, PositionGetDouble(POSITION_TP)))
         g_active.be1Done = true;
   }
   
   // Partial close 1 (40% at TP1)
   if(!g_active.partial1Done && profitPips >= InpTP1Pips)
   {
      double closeVol = NormalizeDouble(g_active.initialLots * InpPartial1Pct, 2);
      double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
      
      if(closeVol >= minVol && g_active.currentLots > closeVol)
      {
         if(g_trade.PositionClosePartial(g_active.ticket, closeVol))
         {
            g_active.partial1Done = true;
            g_active.currentLots -= closeVol;
         }
      }
      else g_active.partial1Done = true;
   }
   
   // Partial close 2 (30% at TP2)
   if(!g_active.partial2Done && profitPips >= InpTP2Pips)
   {
      double closeVol = NormalizeDouble(g_active.initialLots * InpPartial2Pct, 2);
      double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
      
      if(closeVol >= minVol && g_active.currentLots > closeVol)
      {
         if(g_trade.PositionClosePartial(g_active.ticket, closeVol))
         {
            g_active.partial2Done = true;
            g_active.currentLots -= closeVol;
         }
      }
      else g_active.partial2Done = true;
   }
   
   // Trailing stop on runner (after TP2)
   if(g_active.partial2Done && profitPips > InpTP2Pips)
   {
      double trailDist = 1.5 * g_pipSize;  // Trail 1.5 pips behind
      double newSL;
      
      if(isBuy)
      {
         newSL = bid - trailDist;
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newSL > currentSL)
            g_trade.PositionModify(g_active.ticket, NormalizeDouble(newSL, g_digits), PositionGetDouble(POSITION_TP));
      }
      else
      {
         newSL = ask + trailDist;
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newSL < currentSL || currentSL == 0)
            g_trade.PositionModify(g_active.ticket, NormalizeDouble(newSL, g_digits), PositionGetDouble(POSITION_TP));
      }
   }
   
   // ====== MOMENTUM FADE EXIT ======
   // If profit was good but momentum died, close remaining
   if(g_active.partial1Done && profitPips > 0)
   {
      // If we had significant profit and it's fading back
      if(g_active.maxProfit > InpTP1Pips && profitPips < g_active.maxProfit * 0.5)
      {
         g_trade.PositionClose(g_active.ticket);
         Print("TSM: MOMENTUM FADE EXIT at +", DoubleToString(profitPips, 1), "p (was +", DoubleToString(g_active.maxProfit, 1), "p)");
         g_hasPosition = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   if(!HistoryDealSelect(dealTicket)) return;
   
   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != InpMagic) return;
   
   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) return;
   
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                   HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                   HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   
   bool isWin = (profit > 0);
   
   g_totalTrades++;
   g_totalPnL += profit;
   g_dailyPnL += profit;
   
   if(isWin)
   {
      g_totalWins++;
      g_consecLosses = 0;
   }
   else
   {
      g_totalLosses++;
      g_consecLosses++;
      g_sessionLosses++;
      
      // Layer 6: Reduce lot after consecutive losses
      if(g_consecLosses >= InpLossReduceCount)
         g_reducedTradesLeft = InpLossReduceDuration;
   }
   
   // Log
   if(g_logFile != INVALID_HANDLE)
   {
      FileWrite(g_logFile, TimeToString(TimeCurrent()), g_symbol,
                isWin ? "WIN" : "LOSS",
                DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PRICE), g_digits),
                "", DoubleToString(profit, 2), isWin ? "1" : "0",
                DoubleToString(g_stats.ticksPerSecond, 1),
                DoubleToString(g_avgSpread, 1),
                DoubleToString(g_stats.burstSize, 1),
                "", DoubleToString(g_account.Balance(), 2));
      FileFlush(g_logFile);
   }
   
   g_hasPosition = false;
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE (COMPOUNDING)                                  |
//+------------------------------------------------------------------+
double CalcLot(double riskMult)
{
   double equity = g_account.Equity();
   double lot = InpMinLot;
   
   if(InpCompounding)
   {
      // Equity-tier compounding for small accounts
      if(equity < 50) lot = 0.01;
      else if(equity < 100) lot = 0.02;
      else if(equity < 200) lot = 0.03;
      else if(equity < 500) lot = 0.05;
      else if(equity < 1000) lot = 0.10;
      else if(equity < 2500) lot = 0.20;
      else if(equity < 5000) lot = 0.30;
      else if(equity < 10000) lot = 0.50;
      else
      {
         // Risk-based for larger accounts
         double riskAmount = equity * InpBaseRiskPct / 100.0;
         double slDist = InpMaxSLPips * g_pipSize;
         double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
         
         if(tickValue > 0 && tickSize > 0 && slDist > 0)
         {
            double slTicks = slDist / tickSize;
            lot = riskAmount / (slTicks * tickValue);
         }
      }
   }
   else
   {
      double riskAmount = equity * InpBaseRiskPct / 100.0;
      double slDist = InpMaxSLPips * g_pipSize;
      double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue > 0 && tickSize > 0 && slDist > 0)
      {
         double slTicks = slDist / tickSize;
         lot = riskAmount / (slTicks * tickValue);
      }
   }
   
   // Apply risk multiplier
   lot *= riskMult;
   
   // Layer 6: Reduce if in reduced mode
   if(g_reducedTradesLeft > 0)
   {
      lot *= InpLossReducePct;
      g_reducedTradesLeft--;
   }
   
   // Normalize
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, InpMaxLot));
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| CHECK DAY RESET                                                   |
//+------------------------------------------------------------------+
void CheckDayReset()
{
   datetime currentDay = iTime(g_symbol, PERIOD_D1, 0);
   if(currentDay != g_lastDay)
   {
      g_lastDay = currentDay;
      g_dailyPnL = 0;
      g_dailyTrades = 0;
      g_sessionLosses = 0;
      g_dayStartBalance = g_account.Balance();
      g_dailyTargetHit = false;
      g_dailyDDHalt = false;
      g_sessionHalt = false;
      g_reducedTradesLeft = 0;
      Print("TSM: === NEW TRADING DAY === Balance: $", DoubleToString(g_dayStartBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| DRAW DASHBOARD                                                    |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   string pfx = "TSM_";
   
   // Status
   string status = "SCANNING";
   color sClr = clrLime;
   if(g_dailyTargetHit) { status = "TARGET HIT"; sClr = clrGold; }
   else if(g_dailyDDHalt) { status = "DD HALT"; sClr = clrRed; }
   else if(g_sessionHalt) { status = "SESSION HALT"; sClr = clrRed; }
   else if(g_hasPosition) { status = "IN TRADE"; sClr = clrCyan; }
   else if(g_stats.ticksPerSecond >= InpMinTicksPerSec) { status = "MOMENTUM"; sClr = clrYellow; }
   
   CreateLabel(pfx+"h", x, y, "=== TICK SCALPER MACHINE v1.0 ===", clrGold, 11); y += 18;
   CreateLabel(pfx+"st", x, y, "Status: " + status, sClr, 10); y += 16;
   CreateLabel(pfx+"sy", x, y, "Symbol: " + g_symbol, clrWhite, 9); y += 14;
   
   // Tick engine
   CreateLabel(pfx+"tv", x, y, "Velocity: " + DoubleToString(g_stats.ticksPerSecond, 1) + " t/s",
               g_stats.ticksPerSecond >= InpMinTicksPerSec ? clrLime : clrGray, 9); y += 14;
   CreateLabel(pfx+"cd", x, y, "Consec: " + IntegerToString(g_stats.consecSameDir) + 
               " " + (g_stats.lastDirection > 0 ? "UP" : (g_stats.lastDirection < 0 ? "DN" : "--")),
               g_stats.consecSameDir >= InpConsecTicks ? clrLime : clrGray, 9); y += 14;
   CreateLabel(pfx+"bs", x, y, "Burst: " + DoubleToString(g_stats.burstSize, 1) + "p",
               g_stats.burstSize >= InpMinMomentumPips ? clrLime : clrGray, 9); y += 14;
   CreateLabel(pfx+"sp", x, y, "Spread: " + DoubleToString(g_avgSpread > 0 ? g_avgSpread : 0, 1) + "p avg",
               clrWhite, 9); y += 16;
   
   // Performance
   double equity = g_account.Equity();
   double dailyPct = (g_dayStartBalance > 0) ? g_dailyPnL / g_dayStartBalance * 100 : 0;
   double wr = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   
   CreateLabel(pfx+"eq", x, y, "Equity: $" + DoubleToString(equity, 2), clrWhite, 9); y += 14;
   CreateLabel(pfx+"dp", x, y, "Today: " + (dailyPct >= 0 ? "+" : "") + DoubleToString(dailyPct, 2) + "%",
               dailyPct >= 0 ? clrLime : clrRed, 9); y += 14;
   CreateLabel(pfx+"wr", x, y, "WR: " + DoubleToString(wr, 1) + "% (" + IntegerToString(g_totalTrades) + ")",
               wr >= 65 ? clrLime : (wr >= 50 ? clrOrange : clrRed), 9); y += 14;
   CreateLabel(pfx+"pn", x, y, "PnL: $" + DoubleToString(g_totalPnL, 2),
               g_totalPnL >= 0 ? clrLime : clrRed, 9); y += 14;
   
   // Streaks and protection
   CreateLabel(pfx+"cl", x, y, "Losses: " + IntegerToString(g_consecLosses) + " consec | " +
               IntegerToString(g_sessionLosses) + " session",
               g_consecLosses >= 2 ? clrOrange : clrWhite, 9); y += 14;
   
   if(g_reducedTradesLeft > 0)
      CreateLabel(pfx+"rd", x, y, "!! LOT REDUCED for " + IntegerToString(g_reducedTradesLeft) + " trades", clrOrange, 9);
   else
      CreateLabel(pfx+"rd", x, y, "Trades today: " + IntegerToString(g_dailyTrades) + "/" + IntegerToString(InpMaxTradesDay), clrWhite, 9);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| CREATE LABEL                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

//+------------------------------------------------------------------+
//| PERFORMANCE REPORT                                                |
//+------------------------------------------------------------------+
void PrintReport()
{
   Print("============================================");
   Print("  TICK SCALPER MACHINE - SESSION REPORT");
   Print("============================================");
   double wr = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   Print("Total Trades: ", g_totalTrades);
   Print("Wins: ", g_totalWins, " | Losses: ", g_totalLosses);
   Print("Win Rate: ", DoubleToString(wr, 1), "%");
   Print("Total PnL: $", DoubleToString(g_totalPnL, 2));
   Print("Final Equity: $", DoubleToString(g_account.Equity(), 2));
   Print("============================================");
}
//+------------------------------------------------------------------+
