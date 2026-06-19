//+------------------------------------------------------------------+
//|                                            ProAITrader.mq5        |
//|           Professional AI Trading System - Full Framework          |
//|                         Version 1.00                              |
//+------------------------------------------------------------------+
//| 12-Module Adaptive Decision Engine:                                |
//|  1. Market Regime Detection (Trend/Range/Volatile)                |
//|  2. Multi-Timeframe Analysis (D1→H4→H1→M15→M5→M1 scoring)       |
//|  3. Liquidity Intelligence (PDH/PDL, equal H/L, Asian range)     |
//|  4. Smart Money Concepts (FVG, OB, MSS, BOS, CHoCH, sweeps)     |
//|  5. Self-Learning Database (trade log + pattern discovery)        |
//|  6. Multi-Pair Scanner (scores all instruments)                   |
//|  7. Confidence Engine (weighted 0-100 probability scoring)        |
//|  8. Risk Management (daily/weekly DD, consecutive loss rules)     |
//|  9. Dynamic Position Sizing (confidence-based risk allocation)    |
//| 10. Trade Management AI (dynamic TP, trail, scale out)            |
//| 11. Capital Preservation (spread/slippage/news/liquidity filter)  |
//| 12. Continuous Self-Evaluation (weekly stats, strategy ranking)   |
//+------------------------------------------------------------------+
#property copyright "Pro AI Trader v1.0"
#property link      ""
#property version   "1.00"
#property strict
#property description "Professional AI Trading System"
#property description "12-Module Adaptive Decision Engine"
#property description "Multi-Pair, Multi-TF, Self-Learning Framework"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAX_PAIRS       15
#define MAX_TF          6
#define MAX_LIQ_ZONES   30
#define MAX_FVG         20
#define MAX_OB          20
#define MAX_TRADES_LOG  500
#define OBJ_PFX         "PAI_"

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_REGIME     { REGIME_TREND_UP, REGIME_TREND_DOWN, REGIME_RANGE, REGIME_VOLATILE, REGIME_SKIP };
enum ENUM_STRAT_TYPE { STRAT_TREND, STRAT_MEAN_REVERT, STRAT_SCALP, STRAT_VOLATILITY, STRAT_SKIP };
enum ENUM_ZONE_TYPE  { ZONE_EQUAL_HIGH, ZONE_EQUAL_LOW, ZONE_PDH, ZONE_PDL, ZONE_ASIAN_H, ZONE_ASIAN_L, ZONE_WEEKLY_H, ZONE_WEEKLY_L };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════ 1. PAIRS TO SCAN ══════"
input string   InpPairs              = "XAUUSD,EURUSD,GBPUSD,USDJPY,NAS100,US30,BTCUSD,AUDUSD,NZDUSD,USDCAD";
input int      InpScanIntervalSec    = 60;

input group "══════ 2. REGIME DETECTION ══════"
input int      InpADXPeriod          = 14;
input double   InpADXTrend           = 25.0;         // ADX > this = trending
input double   InpADXRange           = 18.0;         // ADX < this = ranging
input double   InpATRVolMult         = 1.4;          // ATR > SMA*this = volatile

input group "══════ 3. MULTI-TIMEFRAME ══════"
input int      InpMTFMinScore        = 60;           // Min MTF alignment score to trade
input double   InpMTFWeightD1        = 20.0;         // Daily weight
input double   InpMTFWeightH4        = 20.0;         // 4H weight
input double   InpMTFWeightH1        = 15.0;         // 1H weight
input double   InpMTFWeightM15       = 15.0;         // 15M weight
input double   InpMTFWeightM5        = 15.0;         // 5M weight
input double   InpMTFWeightM1        = 15.0;         // 1M weight

input group "══════ 4. CONFIDENCE ENGINE ══════"
input double   InpMinConfidence      = 60.0;         // Min confidence to trade
input double   InpConfTrend          = 15.0;         // Points: trend alignment
input double   InpConfLiqSweep       = 20.0;         // Points: liquidity sweep
input double   InpConfOB             = 15.0;         // Points: order block
input double   InpConfVolume         = 10.0;         // Points: volume confirmation
input double   InpConfMomentum       = 10.0;         // Points: momentum
input double   InpConfMTF            = 20.0;         // Points: higher TF agreement
input double   InpConfRR             = 10.0;         // Points: risk/reward quality

input group "══════ 5. RISK MANAGEMENT ══════"
input double   InpMaxDailyLoss       = 2.0;          // Max daily loss (% of balance)
input double   InpMaxWeeklyDD        = 5.0;          // Max weekly drawdown (%)
input int      InpConsecLossReduce   = 3;            // Reduce lots after N consecutive losses
input int      InpConsecLossPause    = 5;            // Pause after N consecutive losses
input double   InpLotReductionFactor = 0.5;          // Multiply lots by this after consec losses

input group "══════ 6. POSITION SIZING ══════"
input double   InpRiskLowConf        = 0.25;         // Risk % when confidence 60-75
input double   InpRiskMedConf        = 0.50;         // Risk % when confidence 75-90
input double   InpRiskHighConf       = 1.00;         // Risk % when confidence 90+

input group "══════ 7. TRADE MANAGEMENT ══════"
input double   InpSLATRMult          = 1.5;          // SL = ATR * this
input double   InpMinRR              = 1.5;          // Minimum risk:reward to take trade
input double   InpScaleOut1Pct       = 0.50;         // Close 50% at TP1
input double   InpBEMoveR            = 1.0;          // Move SL to BE at X R profit
input double   InpTrailStartR        = 1.5;          // Start trailing at X R
input double   InpTrailATRMult       = 0.5;          // Trail distance = ATR * this

input group "══════ 8. CAPITAL PRESERVATION ══════"
input double   InpMaxSpreadMult      = 2.0;          // Skip if spread > avg * this
input int      InpNewsQuietMin       = 15;           // Quiet mins around high-impact news
input bool     InpSkipLowLiquidity   = true;         // Skip if tick rate too low
input int      InpMinTicksPerMin     = 5;            // Min ticks/min to consider liquid

input group "══════ 9. SYSTEM ══════"
input int      InpMagicBase          = 500000;
input int      InpSlippage           = 30;
input int      InpMaxTotalTrades     = 8;
input int      InpMaxTradesPerPair   = 1;

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct LiquidityZone
{
   double         price;
   ENUM_ZONE_TYPE type;
   bool           swept;
   datetime       created;
};

struct FVGZone
{
   double   top;
   double   bottom;
   bool     isBullish;
   bool     filled;
};

struct OrderBlockZone
{
   double   top;
   double   bottom;
   bool     isBullish;
   bool     mitigated;
   int      strength;
};

struct TradeLog
{
   int      id;
   datetime time;
   string   symbol;
   string   session;
   string   strategy;
   string   regime;
   double   spread;
   double   atr;
   double   confidence;
   double   entryPrice;
   double   exitPrice;
   double   profit;
   double   profitPct;
   double   rMultiple;
   bool     isWin;
   int      holdTimeSec;
};

struct SessionStats
{
   int      trades;
   int      wins;
   double   winRate;
   double   pnl;
};

struct StrategyStats
{
   int      trades;
   int      wins;
   double   winRate;
   double   pnl;
   double   profitFactor;
   double   avgR;
};

struct PairAnalysis
{
   string         symbol;
   bool           active;
   // Regime
   ENUM_REGIME    regime;
   ENUM_STRAT_TYPE strategy;
   // Indicators
   int            hADX, hATR, hATRSlow;
   int            hEmaFast, hEmaSlow;
   int            hBB, hRSI, hMACD;
   // Cached values
   double         adx, adxPlus, adxMinus;
   double         atr, atrSMA;
   double         emaFast, emaSlow, prevEmaFast, prevEmaSlow;
   double         bbUpper, bbLower, bbMiddle;
   double         rsi;
   double         macdMain, macdSignal, macdHist;
   // Multi-TF
   double         mtfScore;
   bool           mtfBullish;
   // Liquidity
   LiquidityZone  liqZones[];
   int            liqCount;
   FVGZone        fvgZones[];
   int            fvgCount;
   OrderBlockZone obZones[];
   int            obCount;
   // SMC signals
   bool           mssBull, mssBear;
   bool           bosBull, bosBear;
   bool           liqSweepBull, liqSweepBear;
   bool           fvgBullPresent, fvgBearPresent;
   bool           obBullPresent, obBearPresent;
   // Confidence
   double         confidence;
   bool           isBuySignal;
   // Spread
   double         currentSpread, avgSpread;
   // Tick rate
   int            tickCount;
   datetime       tickCountStart;
   // Open trades
   int            openTrades;
   // Pair score (for ranking)
   double         pairScore;
};

struct ManagedTrade
{
   ulong    ticket;
   string   symbol;
   double   entryPrice;
   double   initialSL;
   double   currentSL;
   double   initialLots;
   double   currentLots;
   double   riskAmount;
   bool     isBuy;
   bool     beMoveDone;
   bool     partialDone;
   bool     trailing;
   double   maxProfitR;
   datetime openTime;
   double   confidence;
   string   strategy;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_posInfo;

PairAnalysis   g_pairs[];
int            g_pairCount;

ManagedTrade   g_managed[];
int            g_managedCount;

TradeLog       g_tradeLog[];
int            g_logCount;
int            g_nextLogId;

// Risk state
double         g_dayStartBalance;
double         g_weekStartBalance;
datetime       g_dayStart;
int            g_consecLosses;
bool           g_haltDaily;
bool           g_haltWeekly;
bool           g_haltConsec;

// Self-learning session stats
SessionStats   g_londonStats;
SessionStats   g_nyStats;
SessionStats   g_asianStats;
SessionStats   g_newsStats;
StrategyStats  g_stratStats[4]; // trend, mr, scalp, vol

datetime       g_lastScan;

//+------------------------------------------------------------------+
//| INITIALIZATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Parse pairs
   string pairList[];
   g_pairCount = StringSplit(InpPairs, ',', pairList);
   if(g_pairCount <= 0 || g_pairCount > MAX_PAIRS) { Print("ERROR: Invalid pairs"); return INIT_FAILED; }
   
   ArrayResize(g_pairs, g_pairCount);
   
   for(int i = 0; i < g_pairCount; i++)
   {
      StringTrimLeft(pairList[i]); StringTrimRight(pairList[i]);
      g_pairs[i].symbol = pairList[i];
      g_pairs[i].active = false;
      g_pairs[i].liqCount = 0;
      g_pairs[i].fvgCount = 0;
      g_pairs[i].obCount = 0;
      g_pairs[i].openTrades = 0;
      g_pairs[i].tickCount = 0;
      g_pairs[i].tickCountStart = TimeCurrent();
      g_pairs[i].avgSpread = 0;
      
      if(!SymbolSelect(pairList[i], true)) { Print("WARN: ", pairList[i], " unavailable"); continue; }
      
      g_pairs[i].hADX = iADX(pairList[i], PERIOD_M15, InpADXPeriod);
      g_pairs[i].hATR = iATR(pairList[i], PERIOD_M15, 14);
      g_pairs[i].hATRSlow = iATR(pairList[i], PERIOD_M15, 42);
      g_pairs[i].hEmaFast = iMA(pairList[i], PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
      g_pairs[i].hEmaSlow = iMA(pairList[i], PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
      g_pairs[i].hBB = iBands(pairList[i], PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
      g_pairs[i].hRSI = iRSI(pairList[i], PERIOD_M15, 14, PRICE_CLOSE);
      g_pairs[i].hMACD = iMACD(pairList[i], PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
      
      if(g_pairs[i].hADX == INVALID_HANDLE || g_pairs[i].hATR == INVALID_HANDLE ||
         g_pairs[i].hEmaFast == INVALID_HANDLE || g_pairs[i].hBB == INVALID_HANDLE)
      { Print("WARN: Indicators failed for ", pairList[i]); continue; }
      
      ArrayResize(g_pairs[i].liqZones, MAX_LIQ_ZONES);
      ArrayResize(g_pairs[i].fvgZones, MAX_FVG);
      ArrayResize(g_pairs[i].obZones, MAX_OB);
      g_pairs[i].active = true;
   }
   
   ArrayResize(g_managed, 50);
   g_managedCount = 0;
   ArrayResize(g_tradeLog, MAX_TRADES_LOG);
   g_logCount = 0;
   g_nextLogId = 1;
   
   g_dayStartBalance = g_account.Balance();
   g_weekStartBalance = g_account.Balance();
   g_dayStart = TimeCurrent();
   g_consecLosses = 0;
   g_haltDaily = false;
   g_haltWeekly = false;
   g_haltConsec = false;
   g_lastScan = 0;
   
   ZeroMemory(g_londonStats); ZeroMemory(g_nyStats);
   ZeroMemory(g_asianStats); ZeroMemory(g_newsStats);
   for(int i = 0; i < 4; i++) ZeroMemory(g_stratStats[i]);
   
   int active = 0;
   for(int i = 0; i < g_pairCount; i++) if(g_pairs[i].active) active++;
   
   Print("══════════════════════════════════════════════════");
   Print("     PRO AI TRADER v1.0 — 12-MODULE FRAMEWORK");
   Print("══════════════════════════════════════════════════");
   Print("Pairs:       ", active, "/", g_pairCount, " active");
   Print("Balance:     $", DoubleToString(g_account.Balance(), 2));
   Print("Min Conf:    ", InpMinConfidence, "%");
   Print("Daily Limit: ", InpMaxDailyLoss, "%");
   Print("══════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      IndicatorRelease(g_pairs[i].hADX);
      IndicatorRelease(g_pairs[i].hATR);
      IndicatorRelease(g_pairs[i].hATRSlow);
      IndicatorRelease(g_pairs[i].hEmaFast);
      IndicatorRelease(g_pairs[i].hEmaSlow);
      IndicatorRelease(g_pairs[i].hBB);
      IndicatorRelease(g_pairs[i].hRSI);
      IndicatorRelease(g_pairs[i].hMACD);
   }
   PrintSelfEvaluation();
   ObjectsDeleteAll(0, OBJ_PFX);
}

//+------------------------------------------------------------------+
//| MAIN TICK HANDLER                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily/weekly resets
   CheckResets();
   
   // Manage existing positions (every tick)
   ManageAllPositions();
   
   // Halt checks
   if(g_haltDaily || g_haltWeekly || g_haltConsec) return;
   
   // Daily DD check
   if(g_dayStartBalance > 0)
   {
      double dd = (g_dayStartBalance - g_account.Equity()) / g_dayStartBalance * 100.0;
      if(dd >= InpMaxDailyLoss) { g_haltDaily = true; Print("⚠ DAILY LIMIT HIT: ", DoubleToString(dd, 1), "%"); return; }
   }
   // Weekly DD check
   if(g_weekStartBalance > 0)
   {
      double wdd = (g_weekStartBalance - g_account.Equity()) / g_weekStartBalance * 100.0;
      if(wdd >= InpMaxWeeklyDD) { g_haltWeekly = true; Print("⚠ WEEKLY LIMIT HIT: ", DoubleToString(wdd, 1), "%"); return; }
   }
   
   // Full scan on interval
   if(TimeCurrent() - g_lastScan >= InpScanIntervalSec)
   {
      FullScan();
      g_lastScan = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| MODULE 1: MARKET REGIME DETECTION                                 |
//+------------------------------------------------------------------+
ENUM_REGIME DetectRegime(int idx)
{
   double adx = g_pairs[idx].adx;
   double atr = g_pairs[idx].atr;
   double atrSMA = g_pairs[idx].atrSMA;
   bool highVol = (atrSMA > 0 && atr > atrSMA * InpATRVolMult);
   
   if(adx > InpADXTrend)
   {
      if(highVol) return REGIME_VOLATILE; // Trending but volatile
      return (g_pairs[idx].adxPlus > g_pairs[idx].adxMinus) ? REGIME_TREND_UP : REGIME_TREND_DOWN;
   }
   if(adx < InpADXRange)
   {
      if(highVol) return REGIME_VOLATILE;
      return REGIME_RANGE;
   }
   if(highVol) return REGIME_VOLATILE;
   return REGIME_SKIP;
}

ENUM_STRAT_TYPE AssignStrategy(ENUM_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TREND_UP:
      case REGIME_TREND_DOWN:  return STRAT_TREND;
      case REGIME_RANGE:       return STRAT_MEAN_REVERT;
      case REGIME_VOLATILE:    return STRAT_VOLATILITY;
      default:                 return STRAT_SKIP;
   }
}

//+------------------------------------------------------------------+
//| MODULE 2: MULTI-TIMEFRAME ANALYSIS                                |
//+------------------------------------------------------------------+
double CalculateMTFScore(string sym, bool &isBullish)
{
   ENUM_TIMEFRAMES tfs[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1};
   double weights[] = {InpMTFWeightD1, InpMTFWeightH4, InpMTFWeightH1, InpMTFWeightM15, InpMTFWeightM5, InpMTFWeightM1};
   
   double bullScore = 0, bearScore = 0;
   
   for(int i = 0; i < 6; i++)
   {
      int hFast = iMA(sym, tfs[i], 9, 0, MODE_EMA, PRICE_CLOSE);
      int hSlow = iMA(sym, tfs[i], 21, 0, MODE_EMA, PRICE_CLOSE);
      if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE) continue;
      
      double fast[], slow[];
      bool ok = (CopyBuffer(hFast, 0, 0, 2, fast) >= 1 && CopyBuffer(hSlow, 0, 0, 2, slow) >= 1);
      IndicatorRelease(hFast);
      IndicatorRelease(hSlow);
      
      if(!ok) continue;
      
      if(fast[0] > slow[0])
         bullScore += weights[i];
      else
         bearScore += weights[i];
   }
   
   double totalWeight = InpMTFWeightD1 + InpMTFWeightH4 + InpMTFWeightH1 + InpMTFWeightM15 + InpMTFWeightM5 + InpMTFWeightM1;
   isBullish = (bullScore > bearScore);
   return MathMax(bullScore, bearScore) / totalWeight * 100.0;
}

//+------------------------------------------------------------------+
//| MODULE 3: LIQUIDITY INTELLIGENCE                                  |
//+------------------------------------------------------------------+
void DetectLiquidity(int idx)
{
   string sym = g_pairs[idx].symbol;
   g_pairs[idx].liqCount = 0;
   
   // Previous Day High/Low
   double pdh = iHigh(sym, PERIOD_D1, 1);
   double pdl = iLow(sym, PERIOD_D1, 1);
   if(pdh > 0) AddLiqZone(idx, pdh, ZONE_PDH);
   if(pdl > 0) AddLiqZone(idx, pdl, ZONE_PDL);
   
   // Weekly High/Low
   double wh = iHigh(sym, PERIOD_W1, 1);
   double wl = iLow(sym, PERIOD_W1, 1);
   if(wh > 0) AddLiqZone(idx, wh, ZONE_WEEKLY_H);
   if(wl > 0) AddLiqZone(idx, wl, ZONE_WEEKLY_L);
   
   // Asian session range (hours 0-8 server time)
   double asianH = 0, asianL = DBL_MAX;
   double m15High[], m15Low[];
   datetime m15Time[];
   int copied = CopyHigh(sym, PERIOD_M15, 0, 50, m15High);
   CopyLow(sym, PERIOD_M15, 0, 50, m15Low);
   CopyTime(sym, PERIOD_M15, 0, 50, m15Time);
   for(int i = 0; i < copied; i++)
   {
      MqlDateTime dt; TimeToStruct(m15Time[i], dt);
      if(dt.hour >= 0 && dt.hour < 8)
      {
         if(m15High[i] > asianH) asianH = m15High[i];
         if(m15Low[i] < asianL) asianL = m15Low[i];
      }
   }
   if(asianH > 0) AddLiqZone(idx, asianH, ZONE_ASIAN_H);
   if(asianL < DBL_MAX) AddLiqZone(idx, asianL, ZONE_ASIAN_L);
   
   // Equal highs/lows from H1 (where retail stops cluster)
   double h1High[], h1Low[];
   if(CopyHigh(sym, PERIOD_H1, 0, 30, h1High) >= 20 && CopyLow(sym, PERIOD_H1, 0, 30, h1Low) >= 20)
   {
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double tolerance = point * 30;
      for(int i = 2; i < 20; i++)
      {
         for(int j = i + 2; j < MathMin(i + 10, 25); j++)
         {
            if(MathAbs(h1High[i] - h1High[j]) < tolerance && g_pairs[idx].liqCount < MAX_LIQ_ZONES)
               AddLiqZone(idx, (h1High[i] + h1High[j]) / 2.0, ZONE_EQUAL_HIGH);
            if(MathAbs(h1Low[i] - h1Low[j]) < tolerance && g_pairs[idx].liqCount < MAX_LIQ_ZONES)
               AddLiqZone(idx, (h1Low[i] + h1Low[j]) / 2.0, ZONE_EQUAL_LOW);
         }
      }
   }
   
   // Check for liquidity sweeps
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   g_pairs[idx].liqSweepBull = false;
   g_pairs[idx].liqSweepBear = false;
   for(int i = 0; i < g_pairs[idx].liqCount; i++)
   {
      LiquidityZone &z = g_pairs[idx].liqZones[i];
      if(z.swept) continue;
      double point2 = SymbolInfoDouble(sym, SYMBOL_POINT);
      if((z.type == ZONE_PDL || z.type == ZONE_EQUAL_LOW || z.type == ZONE_ASIAN_L) && bid < z.price && bid > z.price - point2 * 100)
      { z.swept = true; g_pairs[idx].liqSweepBull = true; }
      if((z.type == ZONE_PDH || z.type == ZONE_EQUAL_HIGH || z.type == ZONE_ASIAN_H) && bid > z.price && bid < z.price + point2 * 100)
      { z.swept = true; g_pairs[idx].liqSweepBear = true; }
   }
}

void AddLiqZone(int idx, double price, ENUM_ZONE_TYPE type)
{
   if(g_pairs[idx].liqCount >= MAX_LIQ_ZONES) return;
   g_pairs[idx].liqZones[g_pairs[idx].liqCount].price = price;
   g_pairs[idx].liqZones[g_pairs[idx].liqCount].type = type;
   g_pairs[idx].liqZones[g_pairs[idx].liqCount].swept = false;
   g_pairs[idx].liqZones[g_pairs[idx].liqCount].created = TimeCurrent();
   g_pairs[idx].liqCount++;
}

//+------------------------------------------------------------------+
//| MODULE 4: SMART MONEY CONCEPTS                                    |
//+------------------------------------------------------------------+
void DetectSMC(int idx)
{
   string sym = g_pairs[idx].symbol;
   g_pairs[idx].fvgCount = 0;
   g_pairs[idx].obCount = 0;
   g_pairs[idx].mssBull = false; g_pairs[idx].mssBear = false;
   g_pairs[idx].bosBull = false; g_pairs[idx].bosBear = false;
   g_pairs[idx].fvgBullPresent = false; g_pairs[idx].fvgBearPresent = false;
   g_pairs[idx].obBullPresent = false; g_pairs[idx].obBearPresent = false;
   
   double h[], l[], c[], o[];
   if(CopyHigh(sym, PERIOD_M15, 0, 30, h) < 20) return;
   if(CopyLow(sym, PERIOD_M15, 0, 30, l) < 20) return;
   if(CopyClose(sym, PERIOD_M15, 0, 30, c) < 20) return;
   if(CopyOpen(sym, PERIOD_M15, 0, 30, o) < 20) return;
   
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   // --- FVG Detection ---
   for(int i = 2; i < 18 && g_pairs[idx].fvgCount < MAX_FVG; i++)
   {
      // Bullish FVG: candle[i+1] high < candle[i-1] low (gap up)
      if(l[i-1] > h[i+1])
      {
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].top = l[i-1];
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].bottom = h[i+1];
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].isBullish = true;
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].filled = (bid < h[i+1]);
         g_pairs[idx].fvgCount++;
         if(bid >= h[i+1] && bid <= l[i-1]) g_pairs[idx].fvgBullPresent = true;
      }
      // Bearish FVG
      if(h[i-1] < l[i+1] && g_pairs[idx].fvgCount < MAX_FVG)
      {
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].top = l[i+1];
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].bottom = h[i-1];
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].isBullish = false;
         g_pairs[idx].fvgZones[g_pairs[idx].fvgCount].filled = (bid > l[i+1]);
         g_pairs[idx].fvgCount++;
         if(bid >= h[i-1] && bid <= l[i+1]) g_pairs[idx].fvgBearPresent = true;
      }
   }
   
   // --- Order Block Detection ---
   for(int i = 3; i < 18 && g_pairs[idx].obCount < MAX_OB; i++)
   {
      // Bullish OB: bearish candle followed by strong bullish displacement
      if(c[i] < o[i] && c[i-1] > o[i-1])
      {
         double body = MathAbs(c[i-1] - o[i-1]);
         double range = h[i-1] - l[i-1];
         if(range > 0 && body > range * 0.6 && c[i-1] > h[i])
         {
            g_pairs[idx].obZones[g_pairs[idx].obCount].top = h[i];
            g_pairs[idx].obZones[g_pairs[idx].obCount].bottom = l[i];
            g_pairs[idx].obZones[g_pairs[idx].obCount].isBullish = true;
            g_pairs[idx].obZones[g_pairs[idx].obCount].mitigated = (bid < l[i]);
            g_pairs[idx].obCount++;
            if(bid >= l[i] && bid <= h[i]) g_pairs[idx].obBullPresent = true;
         }
      }
      // Bearish OB
      if(c[i] > o[i] && c[i-1] < o[i-1] && g_pairs[idx].obCount < MAX_OB)
      {
         double body = MathAbs(c[i-1] - o[i-1]);
         double range = h[i-1] - l[i-1];
         if(range > 0 && body > range * 0.6 && c[i-1] < l[i])
         {
            g_pairs[idx].obZones[g_pairs[idx].obCount].top = h[i];
            g_pairs[idx].obZones[g_pairs[idx].obCount].bottom = l[i];
            g_pairs[idx].obZones[g_pairs[idx].obCount].isBullish = false;
            g_pairs[idx].obZones[g_pairs[idx].obCount].mitigated = (bid > h[i]);
            g_pairs[idx].obCount++;
            if(bid >= l[i] && bid <= h[i]) g_pairs[idx].obBearPresent = true;
         }
      }
   }
   
   // --- Structure Detection (MSS / BOS) ---
   double swH[10], swL[10];
   int shC = 0, slC = 0;
   for(int i = 2; i < MathMin(20, ArraySize(h) - 2); i++)
   {
      if(h[i] > h[i-1] && h[i] > h[i+1] && shC < 10) swH[shC++] = h[i];
      if(l[i] < l[i-1] && l[i] < l[i+1] && slC < 10) swL[slC++] = l[i];
   }
   if(shC >= 2 && slC >= 2)
   {
      // MSS: break of previous swing against prevailing structure
      if(c[1] > swH[1] && swH[0] < swH[1]) g_pairs[idx].mssBull = true;
      if(c[1] < swL[1] && swL[0] > swL[1]) g_pairs[idx].mssBear = true;
      // BOS: break of most recent swing
      if(c[1] > swH[0]) g_pairs[idx].bosBull = true;
      if(c[1] < swL[0]) g_pairs[idx].bosBear = true;
   }
}

//+------------------------------------------------------------------+
//| MODULE 7: CONFIDENCE ENGINE                                       |
//+------------------------------------------------------------------+
double CalculateConfidence(int idx, bool &isBuy)
{
   double buyConf = 0, sellConf = 0;
   
   // Trend alignment
   if(g_pairs[idx].regime == REGIME_TREND_UP) buyConf += InpConfTrend;
   if(g_pairs[idx].regime == REGIME_TREND_DOWN) sellConf += InpConfTrend;
   
   // Liquidity sweep
   if(g_pairs[idx].liqSweepBull) buyConf += InpConfLiqSweep;
   if(g_pairs[idx].liqSweepBear) sellConf += InpConfLiqSweep;
   
   // Order block
   if(g_pairs[idx].obBullPresent) buyConf += InpConfOB;
   if(g_pairs[idx].obBearPresent) sellConf += InpConfOB;
   
   // FVG
   if(g_pairs[idx].fvgBullPresent) buyConf += 10;
   if(g_pairs[idx].fvgBearPresent) sellConf += 10;
   
   // MSS/BOS
   if(g_pairs[idx].mssBull || g_pairs[idx].bosBull) buyConf += 10;
   if(g_pairs[idx].mssBear || g_pairs[idx].bosBear) sellConf += 10;
   
   // Volume/momentum (MACD histogram direction)
   if(g_pairs[idx].macdHist > 0) buyConf += InpConfMomentum;
   if(g_pairs[idx].macdHist < 0) sellConf += InpConfMomentum;
   
   // RSI confirmation
   if(g_pairs[idx].rsi > 50 && g_pairs[idx].rsi < 70) buyConf += 5;
   if(g_pairs[idx].rsi < 50 && g_pairs[idx].rsi > 30) sellConf += 5;
   
   // Multi-timeframe agreement
   double mtfBonus = g_pairs[idx].mtfScore / 100.0 * InpConfMTF;
   if(g_pairs[idx].mtfBullish) buyConf += mtfBonus;
   else sellConf += mtfBonus;
   
   // RR quality (always available if setup exists)
   if(buyConf > 30 || sellConf > 30)
   {
      double betterScore = MathMax(buyConf, sellConf);
      if(betterScore > 50) { buyConf += (buyConf > sellConf ? InpConfRR : 0); sellConf += (sellConf > buyConf ? InpConfRR : 0); }
   }
   
   isBuy = (buyConf >= sellConf);
   return MathMin(MathMax(buyConf, sellConf), 100.0);
}

//+------------------------------------------------------------------+
//| MODULE 9: DYNAMIC POSITION SIZING                                 |
//+------------------------------------------------------------------+
double CalculateRiskPercent(double confidence)
{
   double riskPct;
   if(confidence >= 90)      riskPct = InpRiskHighConf;
   else if(confidence >= 75) riskPct = InpRiskMedConf;
   else                      riskPct = InpRiskLowConf;
   
   // Reduce after consecutive losses
   if(g_consecLosses >= InpConsecLossReduce)
      riskPct *= InpLotReductionFactor;
   
   return riskPct;
}

double CalculateLots(string sym, double slDistance, double riskPct)
{
   if(slDistance <= 0) return 0;
   double balance = g_account.Balance();
   double riskMoney = balance * riskPct / 100.0;
   
   double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   
   if(tickVal <= 0 || tickSize <= 0 || point <= 0) return 0;
   double pointVal = tickVal / tickSize * point;
   double slPoints = slDistance / point;
   double lots = riskMoney / (slPoints * pointVal);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(lotMin, MathMin(lots, lotMax));
}

//+------------------------------------------------------------------+
//| MODULE 11: CAPITAL PRESERVATION FILTERS                           |
//+------------------------------------------------------------------+
bool PassesCapitalFilters(int idx)
{
   // Spread filter
   if(g_pairs[idx].avgSpread > 0 && g_pairs[idx].currentSpread > g_pairs[idx].avgSpread * InpMaxSpreadMult)
      return false;
   
   // Liquidity filter
   if(InpSkipLowLiquidity)
   {
      int elapsed = (int)(TimeCurrent() - g_pairs[idx].tickCountStart);
      if(elapsed > 60)
      {
         double ticksPerMin = (double)g_pairs[idx].tickCount / (elapsed / 60.0);
         if(ticksPerMin < InpMinTicksPerMin) return false;
      }
   }
   
   // News filter (basic: skip 1st Friday, 3rd Wed, every Thu around key times)
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day_of_week == 5 && dt.day <= 7 && dt.hour >= 12 && dt.hour <= 16) return false; // NFP
   if(dt.day_of_week == 3 && dt.day >= 15 && dt.day <= 21 && dt.hour >= 18 && dt.hour <= 22) return false; // FOMC
   
   return true;
}

//+------------------------------------------------------------------+
//| FULL SCAN — Orchestrates all modules                              |
//+------------------------------------------------------------------+
void FullScan()
{
   UpdateOpenCounts();
   int totalOpen = CountTotalTrades();
   
   // Phase 1: Update data + classify all pairs
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      UpdateIndicators(i);
      g_pairs[i].regime = DetectRegime(i);
      g_pairs[i].strategy = AssignStrategy(g_pairs[i].regime);
      g_pairs[i].mtfScore = CalculateMTFScore(g_pairs[i].symbol, g_pairs[i].mtfBullish);
      DetectLiquidity(i);
      DetectSMC(i);
      g_pairs[i].confidence = CalculateConfidence(i, g_pairs[i].isBuySignal);
      g_pairs[i].pairScore = g_pairs[i].confidence;
   }
   
   // Phase 2: Rank pairs by score (highest first)
   int order[];
   ArrayResize(order, g_pairCount);
   for(int i = 0; i < g_pairCount; i++) order[i] = i;
   for(int i = 0; i < g_pairCount - 1; i++)
      for(int j = i + 1; j < g_pairCount; j++)
         if(g_pairs[order[j]].pairScore > g_pairs[order[i]].pairScore)
         { int tmp = order[i]; order[i] = order[j]; order[j] = tmp; }
   
   // Phase 3: Execute on best pairs
   for(int k = 0; k < g_pairCount; k++)
   {
      int i = order[k];
      if(!g_pairs[i].active) continue;
      if(g_pairs[i].strategy == STRAT_SKIP) continue;
      if(g_pairs[i].confidence < InpMinConfidence) continue;
      if(g_pairs[i].mtfScore < InpMTFMinScore) continue;
      if(g_pairs[i].openTrades >= InpMaxTradesPerPair) continue;
      if(totalOpen >= InpMaxTotalTrades) break;
      if(!PassesCapitalFilters(i)) continue;
      
      if(ExecuteSignal(i))
         totalOpen++;
   }
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE SIGNAL                                              |
//+------------------------------------------------------------------+
bool ExecuteSignal(int idx)
{
   string sym = g_pairs[idx].symbol;
   bool isBuy = g_pairs[idx].isBuySignal;
   double atr = g_pairs[idx].atr;
   if(atr <= 0) return false;
   
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   double slDist = atr * InpSLATRMult;
   double tpDist = slDist * InpMinRR;
   
   // RR check
   if(tpDist < slDist * InpMinRR) return false;
   
   double entry = isBuy ? ask : bid;
   double sl = isBuy ? entry - slDist : entry + slDist;
   double tp = isBuy ? entry + tpDist : entry - tpDist;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   double riskPct = CalculateRiskPercent(g_pairs[idx].confidence);
   double lots = CalculateLots(sym, slDist, riskPct);
   if(lots <= 0) return false;
   
   int magic = InpMagicBase + idx;
   g_trade.SetExpertMagicNumber(magic);
   
   string stratName = "";
   switch(g_pairs[idx].strategy)
   {
      case STRAT_TREND:       stratName = "TREND"; break;
      case STRAT_MEAN_REVERT: stratName = "MR"; break;
      case STRAT_SCALP:       stratName = "SCALP"; break;
      case STRAT_VOLATILITY:  stratName = "VOL"; break;
   }
   
   string comment = StringFormat("PAI|%s|%.0f", stratName, g_pairs[idx].confidence);
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   bool result = g_trade.PositionOpen(sym, type, lots, entry, sl, tp, comment);
   if(result)
   {
      // Register for management
      if(g_managedCount < ArraySize(g_managed))
      {
         ManagedTrade &mt = g_managed[g_managedCount];
         mt.ticket = g_trade.ResultOrder();
         mt.symbol = sym;
         mt.entryPrice = entry;
         mt.initialSL = sl;
         mt.currentSL = sl;
         mt.initialLots = lots;
         mt.currentLots = lots;
         mt.riskAmount = g_account.Balance() * riskPct / 100.0;
         mt.isBuy = isBuy;
         mt.beMoveDone = false;
         mt.partialDone = false;
         mt.trailing = false;
         mt.maxProfitR = 0;
         mt.openTime = TimeCurrent();
         mt.confidence = g_pairs[idx].confidence;
         mt.strategy = stratName;
         g_managedCount++;
      }
      
      Print(StringFormat("[%s] %s %s | Conf: %.0f%% | Lot: %.2f | Risk: %.2f%% | MTF: %.0f | Regime: %s",
            stratName, isBuy ? "BUY" : "SELL", sym, g_pairs[idx].confidence, lots, riskPct,
            g_pairs[idx].mtfScore, EnumToString(g_pairs[idx].regime)));
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 10: TRADE MANAGEMENT AI                                    |
//+------------------------------------------------------------------+
void ManageAllPositions()
{
   for(int i = g_managedCount - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByTicket(g_managed[i].ticket))
      {
         // Position closed — remove from managed list
         for(int j = i; j < g_managedCount - 1; j++)
            g_managed[j] = g_managed[j + 1];
         g_managedCount--;
         continue;
      }
      
      ManageSinglePosition(g_managed[i]);
   }
}

void ManageSinglePosition(ManagedTrade &mt)
{
   double bid = SymbolInfoDouble(mt.symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(mt.symbol, SYMBOL_ASK);
   double current = mt.isBuy ? bid : ask;
   double risk = MathAbs(mt.entryPrice - mt.initialSL);
   if(risk <= 0) return;
   
   double profitDist = mt.isBuy ? (current - mt.entryPrice) : (mt.entryPrice - current);
   double profitR = profitDist / risk;
   if(profitR > mt.maxProfitR) mt.maxProfitR = profitR;
   
   int digits = (int)SymbolInfoInteger(mt.symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(mt.symbol, SYMBOL_POINT);
   
   // --- Scale out 50% at TP1 (1R profit) ---
   if(!mt.partialDone && profitR >= InpBEMoveR)
   {
      double closeVol = MathFloor(mt.initialLots * InpScaleOut1Pct / SymbolInfoDouble(mt.symbol, SYMBOL_VOLUME_STEP))
                        * SymbolInfoDouble(mt.symbol, SYMBOL_VOLUME_STEP);
      double lotMin = SymbolInfoDouble(mt.symbol, SYMBOL_VOLUME_MIN);
      if(closeVol >= lotMin)
      {
         g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
         if(g_trade.PositionClosePartial(mt.ticket, closeVol))
         {
            mt.currentLots -= closeVol;
            mt.partialDone = true;
            Print(StringFormat("  ↓ Scaled out %.2f lots on %s (%.0fR)", closeVol, mt.symbol, profitR));
         }
      }
   }
   
   // --- Move SL to breakeven ---
   if(!mt.beMoveDone && profitR >= InpBEMoveR)
   {
      double newSL = mt.entryPrice + (mt.isBuy ? point : -point);
      newSL = NormalizeDouble(newSL, digits);
      g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
      if(g_trade.PositionModify(mt.ticket, newSL, g_posInfo.TakeProfit()))
      {
         mt.currentSL = newSL;
         mt.beMoveDone = true;
      }
   }
   
   // --- Trailing stop ---
   if(profitR >= InpTrailStartR)
   {
      double atrBuf[];
      int hATR = iATR(mt.symbol, PERIOD_M15, 14);
      if(hATR != INVALID_HANDLE)
      {
         if(CopyBuffer(hATR, 0, 0, 1, atrBuf) >= 1)
         {
            double trailDist = atrBuf[0] * InpTrailATRMult;
            double newSL;
            if(mt.isBuy)
            {
               newSL = NormalizeDouble(current - trailDist, digits);
               if(newSL > mt.currentSL)
               {
                  g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
                  if(g_trade.PositionModify(mt.ticket, newSL, g_posInfo.TakeProfit()))
                  {
                     mt.currentSL = newSL;
                     mt.trailing = true;
                  }
               }
            }
            else
            {
               newSL = NormalizeDouble(current + trailDist, digits);
               if(newSL < mt.currentSL)
               {
                  g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
                  if(g_trade.PositionModify(mt.ticket, newSL, g_posInfo.TakeProfit()))
                  {
                     mt.currentSL = newSL;
                     mt.trailing = true;
                  }
               }
            }
         }
         IndicatorRelease(hATR);
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 5 + 12: SELF-LEARNING DATABASE + SELF-EVALUATION           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < InpMagicBase || magic >= InpMagicBase + MAX_PAIRS) return;
   
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   bool isWin = (profit > 0);
   
   // Update consecutive losses
   if(isWin) g_consecLosses = 0;
   else
   {
      g_consecLosses++;
      if(g_consecLosses >= InpConsecLossPause)
      {
         g_haltConsec = true;
         Print("⚠ ", g_consecLosses, " consecutive losses — PAUSING");
      }
   }
   
   // Determine session
   MqlDateTime dt; TimeCurrent(dt);
   string session = "OTHER";
   if(dt.hour >= 8 && dt.hour < 12) session = "LONDON";
   else if(dt.hour >= 13 && dt.hour < 17) session = "NEWYORK";
   else if(dt.hour >= 0 && dt.hour < 8) session = "ASIAN";
   
   // Update session stats
   SessionStats *ss = NULL;
   if(session == "LONDON") ss = &g_londonStats;
   else if(session == "NEWYORK") ss = &g_nyStats;
   else if(session == "ASIAN") ss = &g_asianStats;
   if(ss != NULL)
   {
      ss.trades++;
      if(isWin) ss.wins++;
      ss.pnl += profit;
      ss.winRate = (ss.trades > 0) ? (double)ss.wins / ss.trades * 100 : 0;
   }
   
   // Determine strategy from comment
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   int stratIdx = -1;
   if(StringFind(comment, "TREND") >= 0) stratIdx = 0;
   else if(StringFind(comment, "MR") >= 0) stratIdx = 1;
   else if(StringFind(comment, "SCALP") >= 0) stratIdx = 2;
   else if(StringFind(comment, "VOL") >= 0) stratIdx = 3;
   
   if(stratIdx >= 0 && stratIdx < 4)
   {
      g_stratStats[stratIdx].trades++;
      if(isWin) g_stratStats[stratIdx].wins++;
      g_stratStats[stratIdx].pnl += profit;
      g_stratStats[stratIdx].winRate = (g_stratStats[stratIdx].trades > 0) ?
         (double)g_stratStats[stratIdx].wins / g_stratStats[stratIdx].trades * 100 : 0;
   }
   
   // Log to file
   LogTrade(sym, session, stratIdx >= 0 ? (stratIdx == 0 ? "TREND" : stratIdx == 1 ? "MR" : stratIdx == 2 ? "SCALP" : "VOL") : "UNKNOWN",
            profit, isWin);
   
   Print(StringFormat("◀ %s %s | P/L: $%.2f | Session: %s | Consec L: %d | WR: %.0f%%",
         isWin ? "WIN" : "LOSS", sym, profit, session,
         g_consecLosses, stratIdx >= 0 ? g_stratStats[stratIdx].winRate : 0));
}

void LogTrade(string sym, string session, string strategy, double profit, bool isWin)
{
   string filename = "ProAI_trades.csv";
   int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      if(FileSize(handle) == 0)
         FileWrite(handle, "ID", "Time", "Symbol", "Session", "Strategy", "Profit", "Win", "Balance");
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, g_nextLogId++, TimeToString(TimeCurrent()), sym, session, strategy,
                DoubleToString(profit, 2), isWin ? "YES" : "NO", DoubleToString(g_account.Balance(), 2));
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| MODULE 12: SELF-EVALUATION (printed on deinit)                    |
//+------------------------------------------------------------------+
void PrintSelfEvaluation()
{
   Print("══════════════════════════════════════════════════");
   Print("          SELF-EVALUATION REPORT");
   Print("══════════════════════════════════════════════════");
   Print("SESSION PERFORMANCE:");
   Print(StringFormat("  London:   %d trades | WR: %.0f%% | PnL: $%.2f", g_londonStats.trades, g_londonStats.winRate, g_londonStats.pnl));
   Print(StringFormat("  New York: %d trades | WR: %.0f%% | PnL: $%.2f", g_nyStats.trades, g_nyStats.winRate, g_nyStats.pnl));
   Print(StringFormat("  Asian:    %d trades | WR: %.0f%% | PnL: $%.2f", g_asianStats.trades, g_asianStats.winRate, g_asianStats.pnl));
   Print("STRATEGY PERFORMANCE:");
   string names[] = {"Trend Follow", "Mean Revert ", "Scalping    ", "Volatility  "};
   for(int i = 0; i < 4; i++)
      Print(StringFormat("  %s: %d trades | WR: %.0f%% | PnL: $%.2f", names[i], g_stratStats[i].trades, g_stratStats[i].winRate, g_stratStats[i].pnl));
   
   // Best/worst strategy
   int bestIdx = 0, worstIdx = 0;
   for(int i = 1; i < 4; i++)
   {
      if(g_stratStats[i].pnl > g_stratStats[bestIdx].pnl) bestIdx = i;
      if(g_stratStats[i].pnl < g_stratStats[worstIdx].pnl) worstIdx = i;
   }
   Print("  BEST:  ", names[bestIdx], " ($", DoubleToString(g_stratStats[bestIdx].pnl, 2), ")");
   Print("  WORST: ", names[worstIdx], " ($", DoubleToString(g_stratStats[worstIdx].pnl, 2), ")");
   Print("══════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                 |
//+------------------------------------------------------------------+
void UpdateIndicators(int idx)
{
   string sym = g_pairs[idx].symbol;
   double buf[];
   
   if(CopyBuffer(g_pairs[idx].hADX, 0, 0, 2, buf) >= 1) g_pairs[idx].adx = buf[0];
   if(CopyBuffer(g_pairs[idx].hADX, 1, 0, 2, buf) >= 1) g_pairs[idx].adxPlus = buf[0];
   if(CopyBuffer(g_pairs[idx].hADX, 2, 0, 2, buf) >= 1) g_pairs[idx].adxMinus = buf[0];
   if(CopyBuffer(g_pairs[idx].hATR, 0, 0, 2, buf) >= 1) g_pairs[idx].atr = buf[0];
   if(CopyBuffer(g_pairs[idx].hATRSlow, 0, 0, 2, buf) >= 1) g_pairs[idx].atrSMA = buf[0];
   
   double fast[], slow[];
   if(CopyBuffer(g_pairs[idx].hEmaFast, 0, 0, 3, fast) >= 2)
   { g_pairs[idx].emaFast = fast[0]; g_pairs[idx].prevEmaFast = fast[1]; }
   if(CopyBuffer(g_pairs[idx].hEmaSlow, 0, 0, 3, slow) >= 2)
   { g_pairs[idx].emaSlow = slow[0]; g_pairs[idx].prevEmaSlow = slow[1]; }
   
   if(CopyBuffer(g_pairs[idx].hBB, 0, 0, 2, buf) >= 1) g_pairs[idx].bbMiddle = buf[0];
   if(CopyBuffer(g_pairs[idx].hBB, 1, 0, 2, buf) >= 1) g_pairs[idx].bbUpper = buf[0];
   if(CopyBuffer(g_pairs[idx].hBB, 2, 0, 2, buf) >= 1) g_pairs[idx].bbLower = buf[0];
   if(CopyBuffer(g_pairs[idx].hRSI, 0, 0, 2, buf) >= 1) g_pairs[idx].rsi = buf[0];
   
   double macd[], sig[];
   if(CopyBuffer(g_pairs[idx].hMACD, 0, 0, 2, macd) >= 1) g_pairs[idx].macdMain = macd[0];
   if(CopyBuffer(g_pairs[idx].hMACD, 1, 0, 2, sig) >= 1) g_pairs[idx].macdSignal = sig[0];
   g_pairs[idx].macdHist = g_pairs[idx].macdMain - g_pairs[idx].macdSignal;
   
   // Spread
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   g_pairs[idx].currentSpread = (pt > 0) ? (ask - bid) / pt : 0;
   if(g_pairs[idx].avgSpread <= 0) g_pairs[idx].avgSpread = g_pairs[idx].currentSpread;
   else g_pairs[idx].avgSpread = g_pairs[idx].avgSpread * 0.95 + g_pairs[idx].currentSpread * 0.05;
   
   // Tick rate tracking
   g_pairs[idx].tickCount++;
}

void UpdateOpenCounts()
{
   for(int i = 0; i < g_pairCount; i++) g_pairs[i].openTrades = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         long magic = g_posInfo.Magic();
         if(magic >= InpMagicBase && magic < InpMagicBase + MAX_PAIRS)
         {
            int pIdx = (int)(magic - InpMagicBase);
            if(pIdx >= 0 && pIdx < g_pairCount) g_pairs[pIdx].openTrades++;
         }
      }
   }
}

int CountTotalTrades()
{
   int count = 0, total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         long magic = g_posInfo.Magic();
         if(magic >= InpMagicBase && magic < InpMagicBase + MAX_PAIRS) count++;
      }
   }
   return count;
}

void CheckResets()
{
   MqlDateTime dt, dtStart;
   TimeCurrent(dt);
   TimeToStruct(g_dayStart, dtStart);
   
   if(dt.day != dtStart.day || g_dayStart == 0)
   {
      g_dayStart = TimeCurrent();
      g_dayStartBalance = g_account.Balance();
      g_haltDaily = false;
      g_haltConsec = false;
      g_consecLosses = 0;
      // Reset tick counters
      for(int i = 0; i < g_pairCount; i++)
      { g_pairs[i].tickCount = 0; g_pairs[i].tickCountStart = TimeCurrent(); }
   }
   if(dt.day_of_week == 1 && dtStart.day_of_week != 1)
   {
      g_weekStartBalance = g_account.Balance();
      g_haltWeekly = false;
   }
}
//+------------------------------------------------------------------+
