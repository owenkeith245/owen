//+------------------------------------------------------------------+
//|                                     GoldAIScalper_Full.mq5        |
//|        Commercial-Grade AI Scalping Bot for MT5 XAUUSD            |
//|                         Version 2.00                              |
//+------------------------------------------------------------------+
//| SINGLE-FILE EA: All modules included inline.                      |
//| Copy this file to: MT5/MQL5/Experts/GoldAIScalper_Full.mq5       |
//| Compile in MetaEditor and attach to XAUUSD chart.                 |
//+------------------------------------------------------------------+
#property copyright "Gold AI Scalper v2.0"
#property link      ""
#property version   "2.00"
#property strict
#property description "Tick-Based AI Scalping System for XAUUSD (Gold)"
#property description "Multi-Module Architecture with Weighted Confluence Scoring"
#property description "Processes every tick for order flow, momentum, structure analysis"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════════ AI CONFIGURATION ══════════"
input double   InpMinConfidence      = 85.0;         // Minimum AI confidence to trade (%)
input double   InpWeightTrend        = 0.20;         // AI Weight: Trend
input double   InpWeightLiquidity    = 0.20;         // AI Weight: Liquidity
input double   InpWeightMomentum     = 0.15;         // AI Weight: Momentum
input double   InpWeightVolume       = 0.15;         // AI Weight: Volume
input double   InpWeightStructure    = 0.15;         // AI Weight: Market Structure
input double   InpWeightVolatility   = 0.10;         // AI Weight: Volatility
input double   InpWeightSpread       = 0.05;         // AI Weight: Spread Quality

input group "══════════ RISK MANAGEMENT ══════════"
input double   InpMaxDailyRisk       = 2.0;          // Max daily risk (% of balance)
input double   InpMaxTradeRisk       = 0.5;          // Max risk per trade (%)
input int      InpMaxOpenTrades      = 5;            // Max simultaneous trades
input double   InpMaxWeeklyDD        = 5.0;          // Max weekly drawdown (%)
input double   InpEmergencyDD        = 5.0;          // Emergency stop drawdown (%)
input int      InpMaxConsecLosses    = 5;            // Halt after N consecutive losses
input double   InpMaxSpreadMult      = 2.5;          // Max spread multiplier (vs avg)

input group "══════════ TRADE MANAGEMENT ══════════"
input double   InpRR1                = 2.0;          // TP1 Risk:Reward ratio
input double   InpRR2                = 3.0;          // TP2 Risk:Reward ratio
input double   InpRR3                = 5.0;          // TP3 Risk:Reward ratio
input double   InpBreakEvenR         = 1.0;          // Move SL to breakeven at X R profit
input double   InpTrailStartR        = 2.0;          // Start trailing at X R profit
input double   InpPartialClose1      = 0.40;         // Close % of position at TP1
input double   InpPartialClose2      = 0.30;         // Close % of position at TP2
input double   InpTrailATRMult       = 0.5;          // Trailing distance = ATR * this
input double   InpSLATRMult          = 1.5;          // SL distance = ATR * this

input group "══════════ SESSION FILTER ══════════"
input int      InpLondonStart        = 9;            // London session open (server hour)
input int      InpLondonEnd          = 12;           // London session close
input int      InpNewYorkStart       = 15;           // New York session open
input int      InpNewYorkEnd         = 18;           // New York session close
input bool     InpTradeAsian         = false;        // Allow trading in Asian session

input group "══════════ NEWS FILTER ══════════"
input bool     InpUseNewsFilter      = true;         // Enable high-impact news filter
input int      InpNewsQuietMin       = 15;           // Quiet period before/after news (min)

input group "══════════ DISPLAY ══════════"
input bool     InpShowDashboard      = true;         // Show live dashboard on chart
input bool     InpDrawZones          = true;         // Draw liquidity/FVG/OB zones
input bool     InpLogTrades          = true;         // Log trades to CSV file

input group "══════════ SYSTEM ══════════"
input int      InpMagicNumber        = 202500;       // EA Magic Number
input int      InpSlippage           = 30;           // Max slippage (points)
input int      InpTickBuffer         = 500;          // Tick buffer size
input int      InpMinTicksSignal     = 50;           // Min ticks between signals

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAX_POSITIONS       10
#define MAX_ZONES           20
#define MAX_LOG_ENTRIES     1000
#define OBJ_PREFIX          "GoldAI_"

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_TRADE_STATE
{
   TRADE_STATE_OPEN,
   TRADE_STATE_BREAKEVEN,
   TRADE_STATE_TRAILING,
   TRADE_STATE_PARTIAL_CLOSED
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+

// --- Tick Engine ---
struct TickData
{
   double   bid;
   double   ask;
   double   spread;
   double   volume;
   long     timeMs;
};

struct TickMetrics
{
   double   buyPressure;
   double   sellPressure;
   double   netFlow;
   double   tickSpeed;
   double   priceVelocity;
   double   acceleration;
   double   currentSpread;
   double   avgSpread;
   double   spreadRatio;
   bool     spreadNormal;
   double   bidDepth;
   double   askDepth;
   double   liquidityImbalance;
   double   highSinceReset;
   double   lowSinceReset;
   double   vwap;
   double   tickVolatility;
   double   rangePercent;
};

// --- AI Analysis ---
struct ModuleScores
{
   double   trend;
   double   liquidity;
   double   momentum;
   double   volume;
   double   structure;
   double   volatility;
   double   spread;
};

struct AISignal
{
   double   buyScore;
   double   sellScore;
   double   confidence;
   string   direction;
   int      quality;
   ModuleScores modules;
   datetime signalTime;
};

// --- Risk Manager ---
struct RiskState
{
   double   dailyRiskUsed;
   double   dailyRiskBudget;
   double   weeklyDrawdown;
   double   weekStartBalance;
   double   todayStartBalance;
   int      openTradeCount;
   int      todayTradeCount;
   int      todayWins;
   int      todayLosses;
   int      consecutiveLosses;
   bool     haltDaily;
   bool     haltWeekly;
   bool     haltEmergency;
   bool     haltConsecutive;
   datetime lastTradeDay;
};

struct RiskAllocation
{
   double   riskMoney;
   double   lotSize;
   bool     approved;
   string   rejectReason;
};

// --- Position Manager ---
struct ManagedPosition
{
   ulong    ticket;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   double   initialLots;
   double   currentLots;
   double   riskAmount;
   bool     isBuy;
   ENUM_TRADE_STATE state;
   bool     tp1Hit;
   bool     tp2Hit;
   datetime openTime;
   double   maxProfit;
   double   trailingSL;
};

// --- Signal Detector ---
struct LiquidityZone
{
   double   price;
   bool     isHigh;
   int      touches;
   bool     swept;
};

struct FairValueGap
{
   double   top;
   double   bottom;
   bool     isBullish;
   bool     filled;
   double   midpoint;
};

struct OrderBlock
{
   double   top;
   double   bottom;
   bool     isBullish;
   bool     mitigated;
   int      strength;
};

struct SignalState
{
   bool     liquiditySweepBull;
   bool     liquiditySweepBear;
   double   nearestLiqHigh;
   double   nearestLiqLow;
   bool     fvgBullPresent;
   bool     fvgBearPresent;
   double   fvgBullEntry;
   double   fvgBearEntry;
   bool     obBullPresent;
   bool     obBearPresent;
   double   obBullTop;
   double   obBullBottom;
   double   obBearTop;
   double   obBearBottom;
   bool     mssBull;
   bool     mssBear;
   bool     bosBull;
   bool     bosBear;
   double   structureScore;
};

// --- Trade Logger ---
struct TradeRecord
{
   int      id;
   datetime openTime;
   datetime closeTime;
   string   direction;
   double   entryPrice;
   double   exitPrice;
   double   lots;
   double   profit;
   double   profitPercent;
   double   rMultiple;
   double   confidence;
   string   session;
   int      durationSec;
   bool     isWin;
};

struct PerformanceStats
{
   int      totalTrades;
   int      wins;
   int      losses;
   double   winRate;
   double   avgWin;
   double   avgLoss;
   double   profitFactor;
   double   avgRMultiple;
   int      maxConsecutiveWins;
   int      maxConsecutiveLosses;
   double   totalProfit;
   double   maxDrawdown;
   double   sharpeRatio;
   double   londonWinRate;
   double   nyWinRate;
   int      londonTrades;
   int      nyTrades;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Standard library objects
CTrade         g_trade;
CAccountInfo   g_account;
CSymbolInfo    g_symbolInfo;
CPositionInfo  g_posInfo;

// Tick Engine
TickData       g_tickBuffer[];
double         g_priceChanges[];
int            g_tickBufPos;
int            g_tickCount;
int            g_totalTicks;
double         g_upticks;
double         g_downticks;
double         g_lastBid;
double         g_lastAsk;
long           g_lastTickMs;
double         g_spreadSum;
double         g_priceSum;
double         g_bidVolSum;
double         g_askVolSum;
double         g_highPrice;
double         g_lowPrice;
double         g_lastVelocity;
int            g_changePos;
datetime       g_resetTime;
TickMetrics    g_metrics;

// AI Analysis
int            g_hEmaFast;
int            g_hEmaSlow;
int            g_hAtr;
int            g_hRsi;
int            g_hMacd;
int            g_hAdx;
int            g_hAtrM1;
AISignal       g_signal;

// Risk Manager
RiskState      g_riskState;
double         g_lotStep;
double         g_lotMin;
double         g_lotMax;
double         g_pointValue;

// Position Manager
ManagedPosition g_positions[];
int            g_posCount;

// Signal Detector
LiquidityZone  g_liqZones[];
FairValueGap   g_fvgZones[];
OrderBlock     g_obZones[];
int            g_liqCount;
int            g_fvgCount;
int            g_obCount;
SignalState     g_signalState;

// Trade Logger
TradeRecord    g_records[];
int            g_recordCount;
int            g_nextTradeId;
PerformanceStats g_stats;
string         g_logFile;

// Timing
datetime       g_lastStructureUpdate;
int            g_ticksSinceSignal;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_symbolInfo.Name(_Symbol))
   {
      Print("ERROR: Cannot initialize symbol info");
      return INIT_FAILED;
   }
   g_symbolInfo.Refresh();
   
   //--- Tick Engine Init
   ArrayResize(g_tickBuffer, InpTickBuffer);
   ArrayResize(g_priceChanges, InpTickBuffer);
   ArrayInitialize(g_priceChanges, 0);
   g_tickBufPos = 0;
   g_tickCount = 0;
   g_totalTicks = 0;
   g_upticks = 0;
   g_downticks = 0;
   g_lastBid = 0;
   g_lastAsk = 0;
   g_lastTickMs = 0;
   g_spreadSum = 0;
   g_priceSum = 0;
   g_bidVolSum = 0;
   g_askVolSum = 0;
   g_highPrice = 0;
   g_lowPrice = DBL_MAX;
   g_lastVelocity = 0;
   g_changePos = 0;
   g_resetTime = TimeCurrent();
   ZeroMemory(g_metrics);
   
   //--- AI Analysis Init (indicators on M1 for scalping context)
   g_hEmaFast = iMA(_Symbol, PERIOD_M1, 9, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaSlow = iMA(_Symbol, PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtr = iATR(_Symbol, PERIOD_M5, 14);
   g_hRsi = iRSI(_Symbol, PERIOD_M1, 7, PRICE_CLOSE);
   g_hMacd = iMACD(_Symbol, PERIOD_M1, 12, 26, 9, PRICE_CLOSE);
   g_hAdx = iADX(_Symbol, PERIOD_M5, 14);
   g_hAtrM1 = iATR(_Symbol, PERIOD_M1, 14);
   
   if(g_hEmaFast == INVALID_HANDLE || g_hEmaSlow == INVALID_HANDLE || 
      g_hAtr == INVALID_HANDLE || g_hRsi == INVALID_HANDLE ||
      g_hMacd == INVALID_HANDLE || g_hAdx == INVALID_HANDLE || g_hAtrM1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   ZeroMemory(g_signal);
   
   //--- Risk Manager Init
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_pointValue = (tickSize > 0) ? tickValue / tickSize : 1.0;
   
   ZeroMemory(g_riskState);
   g_riskState.weekStartBalance = g_account.Balance();
   g_riskState.todayStartBalance = g_account.Balance();
   g_riskState.dailyRiskBudget = g_account.Balance() * InpMaxDailyRisk / 100.0;
   
   //--- Position Manager Init
   ArrayResize(g_positions, MAX_POSITIONS);
   g_posCount = 0;
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- Signal Detector Init
   ArrayResize(g_liqZones, MAX_ZONES);
   ArrayResize(g_fvgZones, MAX_ZONES);
   ArrayResize(g_obZones, MAX_ZONES);
   g_liqCount = 0;
   g_fvgCount = 0;
   g_obCount = 0;
   ZeroMemory(g_signalState);
   
   //--- Trade Logger Init
   ArrayResize(g_records, MAX_LOG_ENTRIES);
   g_recordCount = 0;
   g_nextTradeId = 1;
   g_logFile = "GoldAI_" + _Symbol + "_trades.csv";
   ZeroMemory(g_stats);
   if(InpLogTrades) WriteLogHeader();
   
   //--- Timing
   g_lastStructureUpdate = 0;
   g_ticksSinceSignal = 0;
   
   Print("═══════════════════════════════════════════════════");
   Print("   GOLD AI SCALPER v2.0 - INITIALIZED");
   Print("═══════════════════════════════════════════════════");
   Print("Symbol:          ", _Symbol);
   Print("Min Confidence:  ", InpMinConfidence, "%");
   Print("Max Daily Risk:  ", InpMaxDailyRisk, "%");
   Print("Max Trades:      ", InpMaxOpenTrades);
   Print("TP Ratios:       ", InpRR1, " / ", InpRR2, " / ", InpRR3);
   Print("Lot Step:        ", g_lotStep, " | Min: ", g_lotMin, " | Max: ", g_lotMax);
   Print("Point Value:     ", g_pointValue);
   Print("═══════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(g_hEmaFast);
   IndicatorRelease(g_hEmaSlow);
   IndicatorRelease(g_hAtr);
   IndicatorRelease(g_hRsi);
   IndicatorRelease(g_hMacd);
   IndicatorRelease(g_hAdx);
   IndicatorRelease(g_hAtrM1);
   
   // Clean chart objects
   ObjectsDeleteAll(0, OBJ_PREFIX);
   
   Print("Gold AI Scalper stopped. Trades logged: ", g_recordCount);
   Print("Performance: Win Rate ", DoubleToString(g_stats.winRate, 1), "% | PF ", DoubleToString(g_stats.profitFactor, 2));
}

//+------------------------------------------------------------------+
//|                    MAIN TICK HANDLER                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //=== STEP 1: Process incoming tick ===
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   ProcessTick(tick);
   g_symbolInfo.Refresh();
   
   //=== STEP 2: Daily/Weekly risk checks ===
   CheckDayReset();
   g_riskState.openTradeCount = g_posCount;
   
   //=== STEP 3: Manage existing positions (always) ===
   ManagePositions(tick.bid, tick.ask);
   
   //=== STEP 4: Check if new trades allowed ===
   if(!CanOpenTrade())
   {
      UpdateDashboard();
      return;
   }
   
   //=== STEP 5: Session filter ===
   if(!IsActiveSession())
   {
      UpdateDashboard();
      return;
   }
   
   //=== STEP 6: News filter ===
   if(InpUseNewsFilter && IsNewsTime())
   {
      UpdateDashboard();
      return;
   }
   
   //=== STEP 7: Spread filter ===
   if(!IsSpreadAcceptable())
   {
      UpdateDashboard();
      return;
   }
   
   //=== STEP 8: Structure analysis (throttled to every 5 seconds) ===
   if(TimeCurrent() - g_lastStructureUpdate >= 5)
   {
      AnalyzeStructure(tick.bid, tick.ask);
      g_lastStructureUpdate = TimeCurrent();
   }
   
   //=== STEP 9: AI Analysis ===
   AnalyzeMarket();
   
   //=== STEP 10: Trade execution ===
   if(g_signal.direction != "NONE" && g_signal.confidence >= InpMinConfidence && g_ticksSinceSignal > InpMinTicksSignal)
   {
      ExecuteTrade(tick);
      g_ticksSinceSignal = 0;
   }
   else
   {
      g_ticksSinceSignal++;
   }
   
   //=== STEP 11: Update display ===
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//|                    TICK ENGINE                                     |
//+------------------------------------------------------------------+
void ProcessTick(MqlTick &tick)
{
   TickData td;
   td.bid = tick.bid;
   td.ask = tick.ask;
   td.spread = (tick.ask - tick.bid) / _Point;
   td.volume = (double)tick.volume_real;
   td.timeMs = tick.time_msc;
   
   // Store in circular buffer
   g_tickBuffer[g_tickBufPos] = td;
   g_tickBufPos = (g_tickBufPos + 1) % InpTickBuffer;
   g_tickCount = MathMin(g_tickCount + 1, InpTickBuffer);
   g_totalTicks++;
   
   // Order flow
   if(g_lastBid > 0)
   {
      double change = tick.bid - g_lastBid;
      if(change > 0) g_upticks++;
      else if(change < 0) g_downticks++;
      g_priceChanges[g_changePos] = change;
      g_changePos = (g_changePos + 1) % InpTickBuffer;
   }
   
   // Running sums
   g_spreadSum += td.spread;
   g_priceSum += tick.bid;
   g_bidVolSum += td.volume;
   g_askVolSum += td.volume;
   
   if(tick.bid > g_highPrice) g_highPrice = tick.bid;
   if(tick.bid < g_lowPrice) g_lowPrice = tick.bid;
   
   // Update metrics
   UpdateTickMetrics(td);
   
   g_lastBid = tick.bid;
   g_lastAsk = tick.ask;
   g_lastTickMs = tick.time_msc;
}

void UpdateTickMetrics(TickData &td)
{
   double totalTicks = g_upticks + g_downticks;
   if(totalTicks > 0)
   {
      g_metrics.buyPressure = g_upticks / totalTicks;
      g_metrics.sellPressure = g_downticks / totalTicks;
      g_metrics.netFlow = g_metrics.buyPressure - g_metrics.sellPressure;
   }
   
   // Tick speed
   if(g_lastTickMs > 0 && td.timeMs > g_lastTickMs)
   {
      double elapsed = (td.timeMs - g_lastTickMs) / 1000.0;
      if(elapsed > 0) g_metrics.tickSpeed = 1.0 / elapsed;
   }
   
   // Velocity
   long totalElapsed = (long)(TimeCurrent() - g_resetTime);
   if(totalElapsed > 0 && g_totalTicks > 1)
   {
      double firstBid = g_tickBuffer[0].bid;
      if(firstBid > 0)
      {
         double newVel = (td.bid - firstBid) / (double)totalElapsed;
         g_metrics.acceleration = newVel - g_lastVelocity;
         g_metrics.priceVelocity = newVel;
         g_lastVelocity = newVel;
      }
   }
   
   // Spread
   g_metrics.currentSpread = td.spread;
   if(g_totalTicks > 0) g_metrics.avgSpread = g_spreadSum / g_totalTicks;
   if(g_metrics.avgSpread > 0) g_metrics.spreadRatio = g_metrics.currentSpread / g_metrics.avgSpread;
   g_metrics.spreadNormal = (g_metrics.spreadRatio < 2.0);
   
   // Liquidity
   g_metrics.bidDepth = g_bidVolSum;
   g_metrics.askDepth = g_askVolSum;
   double totalDepth = g_metrics.bidDepth + g_metrics.askDepth;
   if(totalDepth > 0) g_metrics.liquidityImbalance = (g_metrics.bidDepth - g_metrics.askDepth) / totalDepth;
   
   // Price range
   g_metrics.highSinceReset = g_highPrice;
   g_metrics.lowSinceReset = g_lowPrice;
   if(g_totalTicks > 0) g_metrics.vwap = g_priceSum / g_totalTicks;
   
   // Volatility
   g_metrics.tickVolatility = CalcTickVolatility();
   double avgPrice = (g_highPrice + g_lowPrice) / 2.0;
   if(avgPrice > 0) g_metrics.rangePercent = (g_highPrice - g_lowPrice) / avgPrice * 100.0;
}

double CalcTickVolatility()
{
   if(g_tickCount < 10) return 0;
   int count = MathMin(g_tickCount, 100);
   double sum = 0, sumSq = 0;
   for(int i = 0; i < count; i++)
   {
      sum += g_priceChanges[i];
      sumSq += g_priceChanges[i] * g_priceChanges[i];
   }
   double mean = sum / count;
   double variance = (sumSq / count) - (mean * mean);
   return MathSqrt(MathAbs(variance));
}

//+------------------------------------------------------------------+
//|                    AI MARKET ANALYSIS                              |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
   double emaFast[], emaSlow[], atr[], rsi[], macd[], macdSig[], adx[], adxPlus[], adxMinus[];
   
   if(CopyBuffer(g_hEmaFast, 0, 0, 5, emaFast) < 5) return;
   if(CopyBuffer(g_hEmaSlow, 0, 0, 5, emaSlow) < 5) return;
   if(CopyBuffer(g_hAtr, 0, 0, 5, atr) < 3) return;
   if(CopyBuffer(g_hRsi, 0, 0, 5, rsi) < 3) return;
   if(CopyBuffer(g_hMacd, 0, 0, 5, macd) < 3) return;
   if(CopyBuffer(g_hMacd, 1, 0, 5, macdSig) < 3) return;
   if(CopyBuffer(g_hAdx, 0, 0, 3, adx) < 1) return;
   if(CopyBuffer(g_hAdx, 1, 0, 3, adxPlus) < 1) return;
   if(CopyBuffer(g_hAdx, 2, 0, 3, adxMinus) < 1) return;
   
   // Score each analysis module
   g_signal.modules.trend = ScoreTrend(emaFast, emaSlow, adx[0], adxPlus[0], adxMinus[0]);
   g_signal.modules.liquidity = ScoreLiquidity();
   g_signal.modules.momentum = ScoreMomentum(rsi, macd, macdSig);
   g_signal.modules.volume = ScoreVolume();
   g_signal.modules.structure = ScoreStructure(emaFast, emaSlow);
   g_signal.modules.volatility = ScoreVolatility(atr);
   g_signal.modules.spread = ScoreSpread();
   
   // Calculate directional scores
   bool trendBull = (emaFast[0] > emaSlow[0]);
   bool flowBull = (g_metrics.netFlow > 0);
   bool rsiBull = (rsi[0] > 50);
   
   double buyScore = CalcDirectionalScore(true, trendBull, flowBull, rsiBull);
   double sellScore = CalcDirectionalScore(false, trendBull, flowBull, rsiBull);
   
   g_signal.buyScore = buyScore;
   g_signal.sellScore = sellScore;
   
   // Determine direction
   if(buyScore > sellScore && buyScore >= InpMinConfidence)
   {
      g_signal.direction = "BUY";
      g_signal.confidence = buyScore;
   }
   else if(sellScore > buyScore && sellScore >= InpMinConfidence)
   {
      g_signal.direction = "SELL";
      g_signal.confidence = sellScore;
   }
   else
   {
      g_signal.direction = "NONE";
      g_signal.confidence = MathMax(buyScore, sellScore);
   }
   
   g_signal.quality = (int)MathFloor(g_signal.confidence / 20.0);
   g_signal.signalTime = TimeCurrent();
}

double ScoreTrend(double &emaFast[], double &emaSlow[], double adx, double adxPlus, double adxMinus)
{
   double score = 50.0;
   
   // EMA alignment
   if(emaFast[0] > emaSlow[0]) score += 20.0;
   else score -= 20.0;
   
   // EMA slope (fast)
   if(ArraySize(emaFast) >= 3)
   {
      double slope = emaFast[0] - emaFast[2];
      if(slope > 0) score += MathMin(slope * 500, 15.0);
      else score -= MathMin(MathAbs(slope) * 500, 15.0);
   }
   
   // ADX trend strength
   if(adx > 25) score += MathMin((adx - 25) * 0.5, 15.0);
   
   return MathMax(0, MathMin(100, score));
}

double ScoreLiquidity()
{
   double score = 50.0;
   score += g_metrics.liquidityImbalance * 30.0;
   if(g_metrics.buyPressure > 0.6)
      score += (g_metrics.buyPressure - 0.5) * 40.0;
   else if(g_metrics.sellPressure > 0.6)
      score -= (g_metrics.sellPressure - 0.5) * 40.0;
   return MathMax(0, MathMin(100, score));
}

double ScoreMomentum(double &rsi[], double &macd[], double &macdSig[])
{
   double score = 50.0;
   
   if(rsi[0] > 50 && rsi[0] < 80)
      score += (rsi[0] - 50) * 0.5;
   else if(rsi[0] < 50 && rsi[0] > 20)
      score -= (50 - rsi[0]) * 0.5;
   
   double hist = macd[0] - macdSig[0];
   score += MathMin(MathMax(hist * 100, -20), 20);
   score += MathMin(g_metrics.priceVelocity * 50, 15.0);
   
   return MathMax(0, MathMin(100, score));
}

double ScoreVolume()
{
   double score = 50.0;
   if(g_metrics.tickSpeed > 5.0)
      score += MathMin((g_metrics.tickSpeed - 5.0) * 3.0, 25.0);
   else if(g_metrics.tickSpeed < 1.0)
      score -= 20.0;
   double totalDepth = g_metrics.bidDepth + g_metrics.askDepth;
   if(totalDepth > 0) score += MathMin(totalDepth * 0.001, 25.0);
   return MathMax(0, MathMin(100, score));
}

double ScoreStructure(double &emaFast[], double &emaSlow[])
{
   double score = 50.0;
   
   if(ArraySize(emaFast) >= 5)
   {
      bool trending = true;
      bool uptrend = emaFast[0] > emaFast[1];
      for(int i = 1; i < 4; i++)
      {
         if(uptrend && emaFast[i] < emaFast[i+1]) { trending = false; break; }
         if(!uptrend && emaFast[i] > emaFast[i+1]) { trending = false; break; }
      }
      if(trending) score += 25.0;
   }
   
   double gap = MathAbs(emaFast[0] - emaSlow[0]);
   score += MathMin(gap * 200, 25.0);
   
   return MathMax(0, MathMin(100, score));
}

double ScoreVolatility(double &atr[])
{
   double score = 50.0;
   if(ArraySize(atr) >= 3)
   {
      double avgAtr = (atr[0] + atr[1] + atr[2]) / 3.0;
      double ratio = (avgAtr > 0) ? atr[0] / avgAtr : 1.0;
      if(ratio >= 0.8 && ratio <= 1.5) score += 25.0;
      else if(ratio > 2.0) score -= 25.0;
      else if(ratio < 0.5) score -= 15.0;
   }
   if(g_metrics.tickVolatility > 0 && g_metrics.tickVolatility < 2.0)
      score += 15.0;
   else if(g_metrics.tickVolatility > 5.0)
      score -= 15.0;
   return MathMax(0, MathMin(100, score));
}

double ScoreSpread()
{
   double score = 100.0;
   if(!g_metrics.spreadNormal) score -= 50.0;
   if(g_metrics.spreadRatio > 1.5)
      score -= (g_metrics.spreadRatio - 1.0) * 20.0;
   else if(g_metrics.spreadRatio < 1.2)
      score += 10.0;
   return MathMax(0, MathMin(100, score));
}

double CalcDirectionalScore(bool isBuy, bool trendBull, bool flowBull, bool rsiBull)
{
   double trendScore = isBuy == trendBull ? g_signal.modules.trend : 100.0 - g_signal.modules.trend;
   double liqScore = isBuy == flowBull ? g_signal.modules.liquidity : 100.0 - g_signal.modules.liquidity;
   double momScore = isBuy == rsiBull ? g_signal.modules.momentum : 100.0 - g_signal.modules.momentum;
   
   double weighted = trendScore * InpWeightTrend
                   + liqScore * InpWeightLiquidity
                   + momScore * InpWeightMomentum
                   + g_signal.modules.volume * InpWeightVolume
                   + g_signal.modules.structure * InpWeightStructure
                   + g_signal.modules.volatility * InpWeightVolatility
                   + g_signal.modules.spread * InpWeightSpread;
   
   return MathMax(0, MathMin(100, weighted));
}

//+------------------------------------------------------------------+
//|                    RISK MANAGER                                    |
//+------------------------------------------------------------------+
void CheckDayReset()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   MqlDateTime lastDt;
   TimeToStruct(g_riskState.lastTradeDay, lastDt);
   
   if(dt.day != lastDt.day || g_riskState.lastTradeDay == 0)
   {
      g_riskState.lastTradeDay = TimeCurrent();
      g_riskState.dailyRiskUsed = 0;
      g_riskState.todayStartBalance = g_account.Balance();
      g_riskState.dailyRiskBudget = g_account.Balance() * InpMaxDailyRisk / 100.0;
      g_riskState.todayTradeCount = 0;
      g_riskState.todayWins = 0;
      g_riskState.todayLosses = 0;
      g_riskState.haltDaily = false;
      g_riskState.consecutiveLosses = 0;
      g_riskState.haltConsecutive = false;
   }
   
   // Monday reset for weekly
   if(dt.day_of_week == 1 && g_riskState.weekStartBalance == 0)
      g_riskState.weekStartBalance = g_account.Balance();
   
   // Weekly drawdown check
   if(g_riskState.weekStartBalance > 0)
   {
      g_riskState.weeklyDrawdown = (g_riskState.weekStartBalance - g_account.Balance()) / g_riskState.weekStartBalance * 100;
      if(g_riskState.weeklyDrawdown > InpMaxWeeklyDD)
         g_riskState.haltWeekly = true;
   }
   
   // Emergency check
   if(g_riskState.todayStartBalance > 0)
   {
      double dailyDD = (g_riskState.todayStartBalance - g_account.Balance()) / g_riskState.todayStartBalance * 100;
      if(dailyDD > InpEmergencyDD)
         g_riskState.haltEmergency = true;
   }
}

bool CanOpenTrade()
{
   if(g_riskState.haltDaily || g_riskState.haltWeekly || g_riskState.haltEmergency || g_riskState.haltConsecutive)
      return false;
   if(g_posCount >= InpMaxOpenTrades)
      return false;
   if(g_riskState.dailyRiskBudget > 0 && g_riskState.dailyRiskUsed >= g_riskState.dailyRiskBudget)
      return false;
   return true;
}

RiskAllocation AllocateRisk(double slPoints, double confidence)
{
   RiskAllocation alloc;
   ZeroMemory(alloc);
   
   double availableRisk = g_riskState.dailyRiskBudget - g_riskState.dailyRiskUsed;
   double maxTradeRisk = g_account.Balance() * InpMaxTradeRisk / 100.0;
   double confScale = MathMin(confidence / 100.0, 1.0);
   double riskMoney = MathMin(maxTradeRisk * confScale, availableRisk);
   
   if(riskMoney <= 0)
   {
      alloc.approved = false;
      alloc.rejectReason = "NO RISK BUDGET";
      return alloc;
   }
   
   if(slPoints <= 0 || g_pointValue <= 0)
   {
      alloc.approved = false;
      alloc.rejectReason = "INVALID SL/POINT";
      return alloc;
   }
   
   double lotSize = riskMoney / (slPoints * g_pointValue);
   lotSize = MathFloor(lotSize / g_lotStep) * g_lotStep;
   
   if(lotSize < g_lotMin)
   {
      alloc.approved = false;
      alloc.rejectReason = "LOT TOO SMALL";
      return alloc;
   }
   if(lotSize > g_lotMax) lotSize = g_lotMax;
   
   alloc.riskMoney = riskMoney;
   alloc.lotSize = lotSize;
   alloc.approved = true;
   return alloc;
}

//+------------------------------------------------------------------+
//|                    TRADE EXECUTION                                 |
//+------------------------------------------------------------------+
void ExecuteTrade(MqlTick &tick)
{
   bool isBuy = (g_signal.direction == "BUY");
   
   // Get ATR for stop loss
   double atrBuf[];
   if(CopyBuffer(g_hAtrM1, 0, 0, 1, atrBuf) < 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;
   
   double slDistance = atr * InpSLATRMult;
   
   // Use structure levels for smarter SL
   if(isBuy && g_signalState.nearestLiqLow > 0)
   {
      double structDist = tick.bid - g_signalState.nearestLiqLow;
      if(structDist > 0 && structDist < slDistance * 2)
         slDistance = structDist + atr * 0.2;
   }
   else if(!isBuy && g_signalState.nearestLiqHigh > 0 && g_signalState.nearestLiqHigh < DBL_MAX)
   {
      double structDist = g_signalState.nearestLiqHigh - tick.ask;
      if(structDist > 0 && structDist < slDistance * 2)
         slDistance = structDist + atr * 0.2;
   }
   
   double slPoints = slDistance / _Point;
   
   // Allocate risk
   RiskAllocation alloc = AllocateRisk(slPoints, g_signal.confidence);
   if(!alloc.approved)
   {
      Print("Trade rejected: ", alloc.rejectReason);
      return;
   }
   
   // Entry and SL
   double entry = isBuy ? tick.ask : tick.bid;
   double sl = isBuy ? entry - slDistance : entry + slDistance;
   
   // Take profits
   double risk = MathAbs(entry - sl);
   double tp1 = isBuy ? entry + risk * InpRR1 : entry - risk * InpRR1;
   double tp2 = isBuy ? entry + risk * InpRR2 : entry - risk * InpRR2;
   double tp3 = isBuy ? entry + risk * InpRR3 : entry - risk * InpRR3;
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   entry = NormalizeDouble(entry, digits);
   sl = NormalizeDouble(sl, digits);
   tp1 = NormalizeDouble(tp1, digits);
   tp2 = NormalizeDouble(tp2, digits);
   tp3 = NormalizeDouble(tp3, digits);
   
   // Execute order
   string comment = StringFormat("GoldAI|%.0f|%.2f", g_signal.confidence, alloc.riskMoney);
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   bool result = g_trade.PositionOpen(_Symbol, orderType, alloc.lotSize, entry, sl, tp1, comment);
   
   if(result)
   {
      // Register position
      if(g_posCount < MAX_POSITIONS)
      {
         ManagedPosition pos;
         ZeroMemory(pos);
         pos.ticket = g_trade.ResultOrder();
         pos.entryPrice = entry;
         pos.stopLoss = sl;
         pos.takeProfit1 = tp1;
         pos.takeProfit2 = tp2;
         pos.takeProfit3 = tp3;
         pos.initialLots = alloc.lotSize;
         pos.currentLots = alloc.lotSize;
         pos.riskAmount = alloc.riskMoney;
         pos.isBuy = isBuy;
         pos.state = TRADE_STATE_OPEN;
         pos.tp1Hit = false;
         pos.tp2Hit = false;
         pos.openTime = TimeCurrent();
         pos.maxProfit = 0;
         pos.trailingSL = sl;
         
         g_positions[g_posCount] = pos;
         g_posCount++;
      }
      
      // Update risk
      g_riskState.dailyRiskUsed += alloc.riskMoney;
      g_riskState.todayTradeCount++;
      
      // Draw entry on chart
      if(InpDrawZones)
         DrawEntry(entry, sl, tp1, isBuy);
      
      Print(StringFormat("▶ %s | Conf: %.0f%% ★%d | Lots: %.2f | Risk: $%.2f | SL: %.0f pts | TP1: %.2f",
            isBuy ? "BUY" : "SELL", g_signal.confidence, g_signal.quality,
            alloc.lotSize, alloc.riskMoney, slPoints, tp1));
   }
   else
   {
      Print("Trade failed: ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//|                    POSITION MANAGEMENT                             |
//+------------------------------------------------------------------+
void ManagePositions(double bid, double ask)
{
   double atrBuf[];
   CopyBuffer(g_hAtrM1, 0, 0, 1, atrBuf);
   double atr = (ArraySize(atrBuf) > 0) ? atrBuf[0] : 0;
   
   for(int i = g_posCount - 1; i >= 0; i--)
   {
      // Check if position still exists
      if(!g_posInfo.SelectByTicket(g_positions[i].ticket))
      {
         RemovePosition(i);
         continue;
      }
      
      ManageSinglePosition(g_positions[i], bid, ask, atr);
   }
}

void ManageSinglePosition(ManagedPosition &pos, double bid, double ask, double atr)
{
   double currentPrice = pos.isBuy ? bid : ask;
   double risk = MathAbs(pos.entryPrice - pos.stopLoss);
   if(risk <= 0) return;
   
   double profitPoints = pos.isBuy ? (currentPrice - pos.entryPrice) : (pos.entryPrice - currentPrice);
   double profitR = profitPoints / risk;
   
   if(profitPoints > pos.maxProfit) pos.maxProfit = profitPoints;
   
   //--- Move to Breakeven ---
   if(pos.state == TRADE_STATE_OPEN && profitR >= InpBreakEvenR)
   {
      double newSL = pos.entryPrice + (pos.isBuy ? _Point : -_Point);
      newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      if(ModifyPositionSL(pos.ticket, newSL))
      {
         pos.stopLoss = newSL;
         pos.trailingSL = newSL;
         pos.state = TRADE_STATE_BREAKEVEN;
      }
   }
   
   //--- Partial Close at TP1 ---
   if(!pos.tp1Hit)
   {
      bool tp1Reached = pos.isBuy ? (currentPrice >= pos.takeProfit1) : (currentPrice <= pos.takeProfit1);
      if(tp1Reached)
      {
         double closeVol = MathFloor(pos.initialLots * InpPartialClose1 / g_lotStep) * g_lotStep;
         if(closeVol >= g_lotMin)
         {
            if(g_trade.PositionClosePartial(pos.ticket, closeVol))
            {
               pos.currentLots -= closeVol;
               pos.tp1Hit = true;
               pos.state = TRADE_STATE_PARTIAL_CLOSED;
               Print(StringFormat("  TP1 hit: Closed %.2f lots (%.0f%%) | Remaining: %.2f", 
                     closeVol, InpPartialClose1 * 100, pos.currentLots));
            }
         }
      }
   }
   
   //--- Partial Close at TP2 ---
   if(pos.tp1Hit && !pos.tp2Hit)
   {
      bool tp2Reached = pos.isBuy ? (currentPrice >= pos.takeProfit2) : (currentPrice <= pos.takeProfit2);
      if(tp2Reached)
      {
         double closeVol = MathFloor(pos.initialLots * InpPartialClose2 / g_lotStep) * g_lotStep;
         if(closeVol >= g_lotMin)
         {
            if(g_trade.PositionClosePartial(pos.ticket, closeVol))
            {
               pos.currentLots -= closeVol;
               pos.tp2Hit = true;
               Print(StringFormat("  TP2 hit: Closed %.2f lots (%.0f%%)", closeVol, InpPartialClose2 * 100));
            }
         }
      }
   }
   
   //--- Trailing Stop ---
   if(profitR >= InpTrailStartR && atr > 0)
   {
      double trailDist = atr * InpTrailATRMult;
      double newSL;
      
      if(pos.isBuy)
      {
         newSL = currentPrice - trailDist;
         newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         if(newSL > pos.trailingSL)
         {
            if(ModifyPositionSL(pos.ticket, newSL))
            {
               pos.trailingSL = newSL;
               pos.stopLoss = newSL;
               pos.state = TRADE_STATE_TRAILING;
            }
         }
      }
      else
      {
         newSL = currentPrice + trailDist;
         newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         if(newSL < pos.trailingSL)
         {
            if(ModifyPositionSL(pos.ticket, newSL))
            {
               pos.trailingSL = newSL;
               pos.stopLoss = newSL;
               pos.state = TRADE_STATE_TRAILING;
            }
         }
      }
   }
}

bool ModifyPositionSL(ulong ticket, double newSL)
{
   if(g_posInfo.SelectByTicket(ticket))
      return g_trade.PositionModify(ticket, newSL, g_posInfo.TakeProfit());
   return false;
}

void RemovePosition(int index)
{
   for(int i = index; i < g_posCount - 1; i++)
      g_positions[i] = g_positions[i + 1];
   g_posCount--;
}

//+------------------------------------------------------------------+
//|                    SIGNAL DETECTOR                                 |
//+------------------------------------------------------------------+
void AnalyzeStructure(double bid, double ask)
{
   ZeroMemory(g_signalState);
   
   double h1High[], h1Low[], h1Close[];
   double m15High[], m15Low[], m15Close[], m15Open[];
   double m5High[], m5Low[], m5Close[], m5Open[];
   
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 30, h1High) < 20) return;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 30, h1Low) < 20) return;
   if(CopyClose(_Symbol, PERIOD_H1, 0, 30, h1Close) < 20) return;
   if(CopyHigh(_Symbol, PERIOD_M15, 0, 30, m15High) < 20) return;
   if(CopyLow(_Symbol, PERIOD_M15, 0, 30, m15Low) < 20) return;
   if(CopyClose(_Symbol, PERIOD_M15, 0, 30, m15Close) < 20) return;
   if(CopyOpen(_Symbol, PERIOD_M15, 0, 30, m15Open) < 20) return;
   if(CopyHigh(_Symbol, PERIOD_M5, 0, 30, m5High) < 20) return;
   if(CopyLow(_Symbol, PERIOD_M5, 0, 30, m5Low) < 20) return;
   if(CopyClose(_Symbol, PERIOD_M5, 0, 30, m5Close) < 20) return;
   if(CopyOpen(_Symbol, PERIOD_M5, 0, 30, m5Open) < 20) return;
   
   DetectLiquidityZones(h1High, h1Low, bid);
   DetectLiquiditySweeps(m15High, m15Low, m15Close, bid);
   DetectFVG(m5High, m5Low, m5Close, m5Open, bid, ask);
   DetectOrderBlocks(m15High, m15Low, m15Close, m15Open, bid);
   DetectMarketStructure(h1High, h1Low, h1Close, bid);
   
   // Combined structure score
   double score = 0;
   if(g_signalState.liquiditySweepBull || g_signalState.liquiditySweepBear) score += 25;
   if(g_signalState.fvgBullPresent || g_signalState.fvgBearPresent) score += 20;
   if(g_signalState.obBullPresent || g_signalState.obBearPresent) score += 20;
   if(g_signalState.mssBull || g_signalState.mssBear) score += 20;
   if(g_signalState.bosBull || g_signalState.bosBear) score += 15;
   g_signalState.structureScore = MathMin(score, 100);
}

void DetectLiquidityZones(double &highs[], double &lows[], double currentPrice)
{
   g_liqCount = 0;
   int size = ArraySize(highs);
   
   for(int i = 2; i < size - 2 && g_liqCount < MAX_ZONES; i++)
   {
      if(highs[i] > highs[i-1] && highs[i] > highs[i-2] && highs[i] > highs[i+1] && highs[i] > highs[i+2])
      {
         g_liqZones[g_liqCount].price = highs[i];
         g_liqZones[g_liqCount].isHigh = true;
         g_liqZones[g_liqCount].swept = (currentPrice > highs[i]);
         g_liqCount++;
      }
      if(lows[i] < lows[i-1] && lows[i] < lows[i-2] && lows[i] < lows[i+1] && lows[i] < lows[i+2])
      {
         if(g_liqCount < MAX_ZONES)
         {
            g_liqZones[g_liqCount].price = lows[i];
            g_liqZones[g_liqCount].isHigh = false;
            g_liqZones[g_liqCount].swept = (currentPrice < lows[i]);
            g_liqCount++;
         }
      }
   }
   
   g_signalState.nearestLiqHigh = DBL_MAX;
   g_signalState.nearestLiqLow = 0;
   for(int i = 0; i < g_liqCount; i++)
   {
      if(g_liqZones[i].isHigh && !g_liqZones[i].swept && g_liqZones[i].price > currentPrice && g_liqZones[i].price < g_signalState.nearestLiqHigh)
         g_signalState.nearestLiqHigh = g_liqZones[i].price;
      if(!g_liqZones[i].isHigh && !g_liqZones[i].swept && g_liqZones[i].price < currentPrice && g_liqZones[i].price > g_signalState.nearestLiqLow)
         g_signalState.nearestLiqLow = g_liqZones[i].price;
   }
}

void DetectLiquiditySweeps(double &highs[], double &lows[], double &closes[], double currentPrice)
{
   if(ArraySize(highs) < 5) return;
   
   double prevDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   double prevDayLow = iLow(_Symbol, PERIOD_D1, 1);
   
   if(lows[1] < prevDayLow && closes[1] > prevDayLow)
      g_signalState.liquiditySweepBull = true;
   if(highs[1] > prevDayHigh && closes[1] < prevDayHigh)
      g_signalState.liquiditySweepBear = true;
}

void DetectFVG(double &highs[], double &lows[], double &closes[], double &opens[], double bid, double ask)
{
   g_fvgCount = 0;
   int size = ArraySize(highs);
   
   for(int i = 2; i < size - 1 && g_fvgCount < MAX_ZONES; i++)
   {
      // Bullish FVG
      if(lows[i-1] > highs[i+1])
      {
         g_fvgZones[g_fvgCount].top = lows[i-1];
         g_fvgZones[g_fvgCount].bottom = highs[i+1];
         g_fvgZones[g_fvgCount].isBullish = true;
         g_fvgZones[g_fvgCount].midpoint = (lows[i-1] + highs[i+1]) / 2.0;
         g_fvgZones[g_fvgCount].filled = (bid <= g_fvgZones[g_fvgCount].midpoint);
         g_fvgCount++;
         
         if(bid >= highs[i+1] && bid <= lows[i-1])
         {
            g_signalState.fvgBullPresent = true;
            g_signalState.fvgBullEntry = (lows[i-1] + highs[i+1]) / 2.0;
         }
      }
      
      // Bearish FVG
      if(highs[i-1] < lows[i+1] && g_fvgCount < MAX_ZONES)
      {
         g_fvgZones[g_fvgCount].top = lows[i+1];
         g_fvgZones[g_fvgCount].bottom = highs[i-1];
         g_fvgZones[g_fvgCount].isBullish = false;
         g_fvgZones[g_fvgCount].midpoint = (lows[i+1] + highs[i-1]) / 2.0;
         g_fvgZones[g_fvgCount].filled = (ask >= g_fvgZones[g_fvgCount].midpoint);
         g_fvgCount++;
         
         if(ask >= highs[i-1] && ask <= lows[i+1])
         {
            g_signalState.fvgBearPresent = true;
            g_signalState.fvgBearEntry = (lows[i+1] + highs[i-1]) / 2.0;
         }
      }
   }
}

void DetectOrderBlocks(double &highs[], double &lows[], double &closes[], double &opens[], double currentPrice)
{
   g_obCount = 0;
   int size = ArraySize(highs);
   
   for(int i = 3; i < size - 1 && g_obCount < MAX_ZONES; i++)
   {
      // Bullish OB: bearish candle before strong bullish displacement
      if(closes[i] < opens[i])
      {
         double nextBody = MathAbs(closes[i-1] - opens[i-1]);
         double nextRange = highs[i-1] - lows[i-1];
         if(nextRange > 0 && closes[i-1] > opens[i-1] && nextBody > nextRange * 0.6 && closes[i-1] > highs[i])
         {
            g_obZones[g_obCount].top = highs[i];
            g_obZones[g_obCount].bottom = lows[i];
            g_obZones[g_obCount].isBullish = true;
            g_obZones[g_obCount].mitigated = (currentPrice < lows[i]);
            g_obCount++;
            
            if(currentPrice >= lows[i] && currentPrice <= highs[i])
            {
               g_signalState.obBullPresent = true;
               g_signalState.obBullTop = highs[i];
               g_signalState.obBullBottom = lows[i];
            }
         }
      }
      
      // Bearish OB: bullish candle before strong bearish displacement
      if(closes[i] > opens[i] && g_obCount < MAX_ZONES)
      {
         double nextBody = MathAbs(closes[i-1] - opens[i-1]);
         double nextRange = highs[i-1] - lows[i-1];
         if(nextRange > 0 && closes[i-1] < opens[i-1] && nextBody > nextRange * 0.6 && closes[i-1] < lows[i])
         {
            g_obZones[g_obCount].top = highs[i];
            g_obZones[g_obCount].bottom = lows[i];
            g_obZones[g_obCount].isBullish = false;
            g_obZones[g_obCount].mitigated = (currentPrice > highs[i]);
            g_obCount++;
            
            if(currentPrice >= lows[i] && currentPrice <= highs[i])
            {
               g_signalState.obBearPresent = true;
               g_signalState.obBearTop = highs[i];
               g_signalState.obBearBottom = lows[i];
            }
         }
      }
   }
}

void DetectMarketStructure(double &highs[], double &lows[], double &closes[], double currentPrice)
{
   int size = ArraySize(highs);
   if(size < 15) return;
   
   double swingHighs[];
   double swingLows[];
   ArrayResize(swingHighs, 10);
   ArrayResize(swingLows, 10);
   int shCount = 0, slCount = 0;
   
   for(int i = 2; i < MathMin(size - 2, 15); i++)
   {
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1] && shCount < 10)
         swingHighs[shCount++] = highs[i];
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1] && slCount < 10)
         swingLows[slCount++] = lows[i];
   }
   
   if(shCount >= 2 && slCount >= 2)
   {
      // MSS
      if(closes[1] > swingHighs[1] && swingHighs[0] < swingHighs[1])
         g_signalState.mssBull = true;
      if(closes[1] < swingLows[1] && swingLows[0] > swingLows[1])
         g_signalState.mssBear = true;
      
      // BOS
      if(closes[1] > swingHighs[0])
         g_signalState.bosBull = true;
      if(closes[1] < swingLows[0])
         g_signalState.bosBear = true;
   }
}

//+------------------------------------------------------------------+
//|                    SESSION & NEWS FILTER                           |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(hour >= InpLondonStart && hour < InpLondonEnd) return true;
   if(hour >= InpNewYorkStart && hour < InpNewYorkEnd) return true;
   if(InpTradeAsian && hour >= 2 && hour < 9) return true;
   
   return false;
}

bool IsNewsTime()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // NFP: 1st Friday, 15:30
   if(dt.day_of_week == 5 && dt.day <= 7)
      if(IsWithinWindow(dt, 15, 30)) return true;
   
   // FOMC: 3rd Wednesday, 21:00
   if(dt.day_of_week == 3 && dt.day >= 15 && dt.day <= 21)
      if(IsWithinWindow(dt, 21, 0)) return true;
   
   // CPI: mid-month Tue/Wed, 15:30
   if((dt.day_of_week == 2 || dt.day_of_week == 3) && dt.day >= 10 && dt.day <= 14)
      if(IsWithinWindow(dt, 15, 30)) return true;
   
   // Jobless Claims: every Thursday, 15:30
   if(dt.day_of_week == 4)
      if(IsWithinWindow(dt, 15, 30)) return true;
   
   return false;
}

bool IsWithinWindow(MqlDateTime &dt, int eventHour, int eventMin)
{
   int currentMin = dt.hour * 60 + dt.min;
   int eventMinTotal = eventHour * 60 + eventMin;
   return (currentMin >= eventMinTotal - InpNewsQuietMin && currentMin <= eventMinTotal + InpNewsQuietMin);
}

bool IsSpreadAcceptable()
{
   if(g_metrics.avgSpread <= 0) return true;
   return (g_metrics.currentSpread / g_metrics.avgSpread) <= InpMaxSpreadMult;
}

//+------------------------------------------------------------------+
//|                    CHART DASHBOARD                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   
   int x = 20, y = 30, h = 18;
   
   DrawLabel("hdr", x, y, "═══════ GOLD AI SCALPER v2.0 ═══════", clrGold, 10); y += h + 5;
   
   color stClr = g_signal.direction != "NONE" ? clrLime : clrYellow;
   string stTxt = g_signal.direction != "NONE" ? "● ACTIVE" : "● SCANNING";
   DrawLabel("status", x, y, "STATUS: " + stTxt, stClr, 9); y += h;
   DrawLabel("s1", x, y, "──────────────────────────────────", clrDarkGray, 8); y += h;
   
   string trend = g_signal.direction == "BUY" ? "TRENDING UP" : g_signal.direction == "SELL" ? "TRENDING DOWN" : "RANGING";
   DrawLabel("market", x, y, "Market:      " + trend, clrWhite, 9); y += h;
   
   color cClr = g_signal.confidence >= 85 ? clrLime : g_signal.confidence >= 70 ? clrYellow : clrOrange;
   DrawLabel("conf", x, y, StringFormat("Confidence:  %.0f%% ★%d", g_signal.confidence, g_signal.quality), cClr, 9); y += h;
   
   string sprStr = g_metrics.spreadNormal ? "Normal" : "WIDE!";
   DrawLabel("spr", x, y, StringFormat("Spread:      %s (%.1f)", sprStr, g_metrics.currentSpread), g_metrics.spreadNormal ? clrWhite : clrRed, 9); y += h;
   DrawLabel("sess", x, y, "Session:     " + GetSessionName(), clrWhite, 9); y += h;
   DrawLabel("s2", x, y, "──────────────────────────────────", clrDarkGray, 8); y += h;
   
   DrawLabel("bal", x, y, StringFormat("Balance:     $%.2f", g_account.Balance()), clrWhite, 9); y += h;
   DrawLabel("eq", x, y, StringFormat("Equity:      $%.2f", g_account.Equity()), clrWhite, 9); y += h;
   
   double pnl = g_riskState.todayStartBalance > 0 ? (g_account.Balance() - g_riskState.todayStartBalance) / g_riskState.todayStartBalance * 100 : 0;
   DrawLabel("pnl", x, y, StringFormat("Today PnL:   %+.2f%%", pnl), pnl >= 0 ? clrLime : clrRed, 9); y += h;
   DrawLabel("trades", x, y, StringFormat("Open Trades: %d / %d", g_posCount, InpMaxOpenTrades), clrWhite, 9); y += h;
   DrawLabel("wr", x, y, StringFormat("Win Rate:    %.0f%% (%d/%d)", g_stats.winRate, g_stats.wins, g_stats.totalTrades), g_stats.winRate >= 70 ? clrLime : g_stats.winRate >= 50 ? clrYellow : clrRed, 9); y += h;
   
   double riskPct = g_riskState.dailyRiskBudget > 0 ? g_riskState.dailyRiskUsed / g_riskState.dailyRiskBudget * 100 : 0;
   DrawLabel("risk", x, y, StringFormat("Risk Used:   %.1f%% of %.0f%%", riskPct, InpMaxDailyRisk), riskPct < 50 ? clrLime : riskPct < 80 ? clrYellow : clrRed, 9); y += h;
   DrawLabel("s3", x, y, "──────────────────────────────────", clrDarkGray, 8); y += h;
   
   DrawLabel("mt", x, y, StringFormat("Trend:       %.0f%%", g_signal.modules.trend), clrWhite, 8); y += h - 2;
   DrawLabel("ml", x, y, StringFormat("Liquidity:   %.0f%%", g_signal.modules.liquidity), clrWhite, 8); y += h - 2;
   DrawLabel("mm", x, y, StringFormat("Momentum:    %.0f%%", g_signal.modules.momentum), clrWhite, 8); y += h - 2;
   DrawLabel("mv", x, y, StringFormat("Volume:      %.0f%%", g_signal.modules.volume), clrWhite, 8); y += h - 2;
   DrawLabel("ms", x, y, StringFormat("Structure:   %.0f%%", g_signal.modules.structure), clrWhite, 8); y += h - 2;
   DrawLabel("mvo", x, y, StringFormat("Volatility:  %.0f%%", g_signal.modules.volatility), clrWhite, 8); y += h - 2;
   DrawLabel("msp", x, y, StringFormat("Spread:      %.0f%%", g_signal.modules.spread), clrWhite, 8); y += h;
   
   DrawLabel("s4", x, y, "═══════════════════════════════════", clrGold, 8); y += h;
   
   if(g_signalState.nearestLiqHigh < DBL_MAX)
      DrawLabel("lh", x, y, StringFormat("Next Resist: %.2f", g_signalState.nearestLiqHigh), clrGold, 8);
   y += h - 2;
   if(g_signalState.nearestLiqLow > 0)
      DrawLabel("ll", x, y, StringFormat("Next Support:%.2f", g_signalState.nearestLiqLow), clrGold, 8);
   
   // Draw zones
   if(InpDrawZones)
   {
      DrawLiquidityZones();
      DrawFVGZones();
      DrawOrderBlocks();
   }
}

void DrawLabel(string id, int x, int y, string text, color clr, int fontSize)
{
   string name = OBJ_PREFIX + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void DrawEntry(double entry, double sl, double tp, bool isBuy)
{
   color clr = isBuy ? clrLime : clrRed;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   string eName = OBJ_PREFIX + "entry_" + IntegerToString(g_posCount);
   ObjectCreate(0, eName, OBJ_HLINE, 0, 0, entry);
   ObjectSetInteger(0, eName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, eName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, eName, OBJPROP_WIDTH, 2);
   
   string sName = OBJ_PREFIX + "sl_" + IntegerToString(g_posCount);
   ObjectCreate(0, sName, OBJ_HLINE, 0, 0, sl);
   ObjectSetInteger(0, sName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, sName, OBJPROP_STYLE, STYLE_DASH);
   
   string tName = OBJ_PREFIX + "tp_" + IntegerToString(g_posCount);
   ObjectCreate(0, tName, OBJ_HLINE, 0, 0, tp);
   ObjectSetInteger(0, tName, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, tName, OBJPROP_STYLE, STYLE_DASH);
}

void DrawLiquidityZones()
{
   ObjectsDeleteAll(0, OBJ_PREFIX + "liq_");
   for(int i = 0; i < g_liqCount; i++)
   {
      if(g_liqZones[i].swept) continue;
      string name = OBJ_PREFIX + "liq_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, g_liqZones[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}

void DrawFVGZones()
{
   ObjectsDeleteAll(0, OBJ_PREFIX + "fvg_");
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(g_fvgZones[i].filled) continue;
      string name = OBJ_PREFIX + "fvg_" + IntegerToString(i);
      datetime t1 = TimeCurrent() - 3600 * 2;
      datetime t2 = TimeCurrent() + 1800;
      color clr = g_fvgZones[i].isBullish ? C'0,100,50' : C'100,0,50';
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, g_fvgZones[i].bottom, t2, g_fvgZones[i].top);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}

void DrawOrderBlocks()
{
   ObjectsDeleteAll(0, OBJ_PREFIX + "ob_");
   for(int i = 0; i < g_obCount; i++)
   {
      if(g_obZones[i].mitigated) continue;
      string name = OBJ_PREFIX + "ob_" + IntegerToString(i);
      datetime t1 = TimeCurrent() - 3600 * 3;
      datetime t2 = TimeCurrent() + 1800;
      color clr = g_obZones[i].isBullish ? C'0,80,150' : C'150,80,0';
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, g_obZones[i].bottom, t2, g_obZones[i].top);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}

string GetSessionName()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour >= InpLondonStart && dt.hour < InpLondonEnd) return "London";
   if(dt.hour >= InpNewYorkStart && dt.hour < InpNewYorkEnd) return "New York";
   if(dt.hour >= 2 && dt.hour < 9) return "Asian";
   return "Off-Hours";
}

//+------------------------------------------------------------------+
//|                    TRADE LOGGER                                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   
   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic != InpMagicNumber) return;
   
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   
   // Update risk state
   if(profit > 0)
   {
      g_riskState.todayWins++;
      g_riskState.consecutiveLosses = 0;
   }
   else
   {
      g_riskState.todayLosses++;
      g_riskState.consecutiveLosses++;
      if(g_riskState.consecutiveLosses >= InpMaxConsecLosses)
         g_riskState.haltConsecutive = true;
   }
   
   // Check daily halt
   double dailyPnL = g_account.Balance() - g_riskState.todayStartBalance;
   if(dailyPnL < -(g_riskState.dailyRiskBudget))
      g_riskState.haltDaily = true;
   
   // Log trade
   if(g_recordCount < MAX_LOG_ENTRIES)
   {
      TradeRecord rec;
      ZeroMemory(rec);
      rec.id = g_nextTradeId++;
      rec.closeTime = TimeCurrent();
      rec.direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "SELL" : "BUY";
      rec.exitPrice = exitPrice;
      rec.lots = volume;
      rec.profit = profit;
      rec.profitPercent = (g_account.Balance() > 0) ? profit / g_account.Balance() * 100 : 0;
      rec.confidence = g_signal.confidence;
      rec.session = GetSessionName();
      rec.isWin = (profit > 0);
      
      g_records[g_recordCount] = rec;
      g_recordCount++;
      
      UpdatePerformanceStats();
      
      if(InpLogTrades) WriteLogRecord(rec);
      
      Print(StringFormat("◀ CLOSED: %s | P/L: $%.2f (%+.2f%%) | WR: %.0f%% | PF: %.2f",
            rec.direction, profit, rec.profitPercent, g_stats.winRate, g_stats.profitFactor));
   }
}

void UpdatePerformanceStats()
{
   g_stats.totalTrades = g_recordCount;
   g_stats.wins = 0;
   g_stats.losses = 0;
   g_stats.totalProfit = 0;
   double totalWin = 0, totalLoss = 0, totalR = 0;
   
   for(int i = 0; i < g_recordCount; i++)
   {
      g_stats.totalProfit += g_records[i].profit;
      if(g_records[i].isWin)
      {
         g_stats.wins++;
         totalWin += g_records[i].profit;
      }
      else
      {
         g_stats.losses++;
         totalLoss += MathAbs(g_records[i].profit);
      }
   }
   
   g_stats.winRate = (g_recordCount > 0) ? (double)g_stats.wins / g_recordCount * 100 : 0;
   g_stats.avgWin = (g_stats.wins > 0) ? totalWin / g_stats.wins : 0;
   g_stats.avgLoss = (g_stats.losses > 0) ? totalLoss / g_stats.losses : 0;
   g_stats.profitFactor = (totalLoss > 0) ? totalWin / totalLoss : 999;
}

void WriteLogHeader()
{
   int handle = FileOpen(g_logFile, FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, "ID", "CloseTime", "Direction", "Exit", "Lots", "Profit", "ProfitPct", "Confidence", "Session");
      FileClose(handle);
   }
}

void WriteLogRecord(TradeRecord &rec)
{
   int handle = FileOpen(g_logFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, rec.id, TimeToString(rec.closeTime), rec.direction, rec.exitPrice,
                rec.lots, rec.profit, rec.profitPercent, rec.confidence, rec.session);
      FileClose(handle);
   }
}
//+------------------------------------------------------------------+
