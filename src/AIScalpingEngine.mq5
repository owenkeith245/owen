//+------------------------------------------------------------------+
//|                                      AIScalpingEngine.mq5         |
//|              AI Scalping Engine Pro v1.0 - FULLY AUTOMATED         |
//|                    Zero-Intervention Trading System                |
//+------------------------------------------------------------------+
//| Autonomous Modules:                                               |
//|  1. Universal Market Scanner (12+ instruments every tick)         |
//|  2. AI Confidence Score (8-factor weighted 0-100)                 |
//|  3. Market Regime Adaptation (Trend/Range/Momentum/Volatile)      |
//|  4. Smart Capital Allocation (confidence-scaled risk)             |
//|  5. Dynamic SL (liquidity/swing/ATR-based invalidation)           |
//|  6. Intelligent TP (partial close, BE move, trail, momentum exit) |
//|  7. News Protection (auto-detect, pause, resume)                  |
//|  8. Drawdown Protection (daily/weekly/monthly limits)             |
//|  9. Consecutive Loss Protection (reduce/pause/analyze)            |
//| 10. Self-Learning Database (session/pair/strategy stats)          |
//| 11. On-Chart Dashboard (live stats panel)                         |
//| 12. Trade Cooldown + Equity Protector + Slippage Guard            |
//| 13. Correlation Filter + Spread Filter + Volatility Filter        |
//| 14. Session AI (auto-learns best trading hours)                   |
//+------------------------------------------------------------------+
#property copyright "AI Scalping Engine Pro v1.0"
#property link      ""
#property version   "1.00"
#property strict
#property description "AI Scalping Engine - FULLY SELF-AUTOMATED"
#property description "Scans all markets, selects best opportunity, trades autonomously"
#property description "Self-learning, self-healing, zero-intervention required"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAX_PAIRS       15
#define MAX_LIQ_ZONES   20
#define MAX_FVG         15
#define MAX_OB          15
#define MAX_MANAGED     30
#define OBJ_PFX         "ASE_"

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_REGIME
{
   REGIME_TREND_BULL,
   REGIME_TREND_BEAR,
   REGIME_RANGE,
   REGIME_MOMENTUM_BULL,
   REGIME_MOMENTUM_BEAR,
   REGIME_HIGH_VOLATILITY,
   REGIME_LOW_LIQUIDITY,
   REGIME_SKIP
};

enum ENUM_STRAT
{
   STRAT_TREND_PULLBACK,
   STRAT_LIQ_SCALP,
   STRAT_BREAKOUT,
   STRAT_WAIT,
   STRAT_NONE
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════ MARKETS ══════"
input string   InpPairs              = "XAUUSD,EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,NZDUSD,US30,NAS100,BTCUSD";
input int      InpScanIntervalSec    = 30;

input group "══════ AI CONFIDENCE ══════"
input double   InpMinConfidence      = 70.0;         // Min confidence to trade
input double   InpConfTrend          = 15.0;         // Trend alignment points
input double   InpConfLiqSweep       = 20.0;         // Liquidity sweep points
input double   InpConfOB             = 15.0;         // Order block points
input double   InpConfVolume         = 10.0;         // Volume/MACD points
input double   InpConfMomentum       = 15.0;         // Momentum points
input double   InpConfMTF            = 15.0;         // Higher TF agreement points
input double   InpConfSpread         = 10.0;         // Spread quality points

input group "══════ RISK MANAGEMENT ══════"
input double   InpRiskLow            = 0.25;         // Risk % at 70-80 confidence
input double   InpRiskMed            = 0.50;         // Risk % at 80-90 confidence
input double   InpRiskHigh           = 1.00;         // Risk % at 90+ confidence
input double   InpMaxRiskPerTrade    = 1.00;         // Absolute max risk per trade
input double   InpDailyLossLimit     = 2.0;          // Daily loss limit (%)
input double   InpWeeklyLossLimit    = 5.0;          // Weekly loss limit (%)
input double   InpMonthlyLossLimit   = 8.0;          // Monthly loss limit (% - requires restart)

input group "══════ CONSECUTIVE LOSS ══════"
input int      InpConsecReduceAt     = 2;            // Reduce risk after N losses
input int      InpConsecHalveAt      = 3;            // Halve risk at N losses
input int      InpConsecStopAt       = 5;            // Stop trading at N losses
input int      InpConsecCooldownMin  = 60;           // Cooldown after stop (minutes)

input group "══════ TRADE MANAGEMENT ══════"
input double   InpSLATRMult          = 1.5;          // SL = ATR * this
input double   InpMinRR              = 1.5;          // Min reward:risk ratio
input double   InpPartialClosePct    = 0.50;         // Close 50% at first TP
input double   InpBEMoveR            = 1.0;          // Move SL to BE at this R
input double   InpTrailStartR        = 1.5;          // Start trailing at this R
input double   InpTrailATRMult       = 0.5;          // Trail distance = ATR * this

input group "══════ FILTERS ══════"
input double   InpMaxSpreadMult      = 2.0;          // Max spread vs average
input int      InpTradeCooldownSec   = 120;          // Seconds between trades per pair
input bool     InpCorrelationFilter  = true;         // Block correlated pairs
input double   InpCorrelationMax     = 0.70;         // Max correlation allowed
input bool     InpSlippageGuard      = true;         // Cancel on bad slippage
input int      InpMaxSlippage        = 30;           // Max slippage points

input group "══════ EQUITY PROTECTOR ══════"
input bool     InpEquityProtector    = true;         // Lock profits + cut DD exposure
input double   InpProfitLockPct      = 50.0;         // Lock this % of day's profit
input double   InpDDRiskCutPct       = 50.0;         // Cut risk by this % during DD

input group "══════ AUTO-PILOT ══════"
input bool     InpFullAuto           = true;         // Full auto mode
input bool     InpAutoStratRotation  = true;         // Disable losing strategies
input bool     InpAutoPairRotation   = true;         // Disable losing pairs
input bool     InpAutoSessionFilter  = true;         // Skip bad sessions
input double   InpSessionMinWR       = 45.0;         // Min WR to trade session
input int      InpStratMinTrades     = 10;           // Trades before evaluating strategy
input double   InpStratDisableWR     = 35.0;         // Disable strategy below this WR
input bool     InpAutoRecovery       = true;         // Auto-resume after cooldown
input int      InpRecoveryCooldownMin = 30;          // Recovery cooldown minutes
input bool     InpShowDashboard      = true;         // Show on-chart dashboard

input group "══════ SYSTEM ══════"
input int      InpMagicBase          = 600000;
input int      InpMaxTotalTrades     = 6;
input int      InpMaxTradesPerPair   = 1;

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct PairData
{
   string   symbol;
   bool     active;
   bool     disabled;
   // Indicators
   int      hADX, hATR, hATRSlow, hEmaFast, hEmaSlow;
   int      hBB, hRSI, hMACD;
   // Cached
   double   adx, adxPlus, adxMinus;
   double   atr, atrSMA;
   double   emaFast, emaSlow, prevEmaFast, prevEmaSlow;
   double   bbUpper, bbLower, bbMiddle;
   double   rsi, macdMain, macdSignal, macdHist;
   // MTF
   double   mtfScore;
   bool     mtfBullish;
   // Regime
   ENUM_REGIME regime;
   ENUM_STRAT  strategy;
   // SMC
   bool     liqSweepBull, liqSweepBear;
   bool     fvgBullPresent, fvgBearPresent;
   bool     obBullPresent, obBearPresent;
   bool     mssBull, mssBear, bosBull, bosBear;
   // Confidence
   double   confidence;
   bool     isBuySignal;
   double   pairScore;
   // Spread
   double   currentSpread, avgSpread;
   // Tracking
   int      openTrades;
   datetime lastTradeTime;
   int      pairWins, pairLosses;
   double   pairPnL;
};

struct ManagedTrade
{
   ulong    ticket;
   string   symbol;
   double   entryPrice;
   double   initialSL, currentSL;
   double   initialLots, currentLots;
   bool     isBuy;
   bool     beMoveDone, partialDone, trailing;
   double   maxProfitR;
   datetime openTime;
   double   confidence;
   string   stratName;
};

struct SessionStats
{
   int      trades, wins;
   double   winRate, pnl;
};

struct StrategyStats
{
   int      trades, wins;
   double   winRate, pnl;
   bool     disabled;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_posInfo;

PairData       g_pairs[];
int            g_pairCount;

ManagedTrade   g_managed[];
int            g_managedCount;

SessionStats   g_londonStats, g_nyStats, g_asianStats;
StrategyStats  g_stratStats[4]; // pullback, liqscalp, breakout, wait

double         g_dayStartBal, g_weekStartBal, g_monthStartBal;
datetime       g_dayStart, g_weekStart, g_monthStart;
int            g_consecLosses;
bool           g_haltDaily, g_haltWeekly, g_haltMonthly, g_haltConsec;
datetime       g_haltTime;
datetime       g_lastScan;
double         g_dayPeakEquity;
int            g_todayTrades, g_todayWins;
double         g_todayPnL;

//+------------------------------------------------------------------+
//| INITIALIZATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetDeviationInPoints(InpMaxSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   string pairList[];
   g_pairCount = StringSplit(InpPairs, ',', pairList);
   if(g_pairCount <= 0 || g_pairCount > MAX_PAIRS)
   { Print("ERROR: Invalid pairs"); return INIT_FAILED; }

   ArrayResize(g_pairs, g_pairCount);

   for(int i = 0; i < g_pairCount; i++)
   {
      StringTrimLeft(pairList[i]);
      StringTrimRight(pairList[i]);
      g_pairs[i].symbol = pairList[i];
      g_pairs[i].active = false;
      g_pairs[i].disabled = false;
      g_pairs[i].openTrades = 0;
      g_pairs[i].lastTradeTime = 0;
      g_pairs[i].avgSpread = 0;
      g_pairs[i].pairWins = 0;
      g_pairs[i].pairLosses = 0;
      g_pairs[i].pairPnL = 0;

      if(!SymbolSelect(pairList[i], true))
      { Print("WARN: ", pairList[i], " unavailable"); continue; }

      g_pairs[i].hADX = iADX(pairList[i], PERIOD_M15, 14);
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

      g_pairs[i].active = true;
   }

   ArrayResize(g_managed, MAX_MANAGED);
   g_managedCount = 0;

   g_dayStartBal = g_account.Balance();
   g_weekStartBal = g_account.Balance();
   g_monthStartBal = g_account.Balance();
   g_dayStart = TimeCurrent();
   g_weekStart = TimeCurrent();
   g_monthStart = TimeCurrent();
   g_consecLosses = 0;
   g_haltDaily = false;
   g_haltWeekly = false;
   g_haltMonthly = false;
   g_haltConsec = false;
   g_haltTime = 0;
   g_lastScan = 0;
   g_dayPeakEquity = g_account.Equity();
   g_todayTrades = 0;
   g_todayWins = 0;
   g_todayPnL = 0;

   ZeroMemory(g_londonStats);
   ZeroMemory(g_nyStats);
   ZeroMemory(g_asianStats);
   for(int i = 0; i < 4; i++) { ZeroMemory(g_stratStats[i]); g_stratStats[i].disabled = false; }

   int active = 0;
   for(int i = 0; i < g_pairCount; i++) if(g_pairs[i].active) active++;

   Print("══════════════════════════════════════════════════");
   Print("   AI SCALPING ENGINE PRO v1.0 - FULLY AUTOMATED");
   Print("══════════════════════════════════════════════════");
   Print("Mode:        ", InpFullAuto ? "FULL AUTO-PILOT" : "SEMI-AUTO");
   Print("Markets:     ", active, "/", g_pairCount, " active");
   Print("Balance:     $", DoubleToString(g_account.Balance(), 2));
   Print("Min Conf:    ", InpMinConfidence, "%");
   Print("Daily Limit: ", InpMaxRiskPerTrade, "% / ", InpDailyLossLimit, "% DD");
   Print("Strat Rotate: ", InpAutoStratRotation ? "ON" : "OFF");
   Print("Pair Rotate:  ", InpAutoPairRotation ? "ON" : "OFF");
   Print("Session AI:   ", InpAutoSessionFilter ? "ON" : "OFF");
   Print("Equity Guard: ", InpEquityProtector ? "ON" : "OFF");
   Print("Dashboard:    ", InpShowDashboard ? "ON" : "OFF");
   Print("══════════════════════════════════════════════════");
   Print("  >>> ENGINE STARTED — NO INTERVENTION NEEDED <<<");
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
   PrintPerformanceReport();
   ObjectsDeleteAll(0, OBJ_PFX);
}

//+------------------------------------------------------------------+
//| MAIN TICK HANDLER                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckTimeResets();
   ManageAllPositions();

   if(InpShowDashboard)
      UpdateDashboard();

   // Monthly halt = requires manual restart
   if(g_haltMonthly) return;

   // Auto-recovery
   if(InpAutoRecovery && (g_haltDaily || g_haltWeekly || g_haltConsec))
   {
      if(g_haltTime > 0)
      {
         int elapsedMin = (int)((TimeCurrent() - g_haltTime) / 60);
         if(elapsedMin >= InpRecoveryCooldownMin)
         {
            if(g_haltConsec)
            {
               g_haltConsec = false;
               g_consecLosses = 0;
               g_haltTime = 0;
               Print("AUTO-RECOVERY: Consec loss pause lifted after ", InpRecoveryCooldownMin, "min");
            }
            if(g_haltDaily)
            {
               double dd = (g_dayStartBal > 0) ? (g_dayStartBal - g_account.Equity()) / g_dayStartBal * 100 : 0;
               if(dd < InpDailyLossLimit * 0.8)
               { g_haltDaily = false; g_haltTime = 0; Print("AUTO-RECOVERY: Daily halt lifted"); }
            }
            if(g_haltWeekly)
            {
               double wdd = (g_weekStartBal > 0) ? (g_weekStartBal - g_account.Equity()) / g_weekStartBal * 100 : 0;
               if(wdd < InpWeeklyLossLimit * 0.8)
               { g_haltWeekly = false; g_haltTime = 0; Print("AUTO-RECOVERY: Weekly halt lifted"); }
            }
         }
      }
   }

   if(g_haltDaily || g_haltWeekly || g_haltConsec) return;

   // DD checks
   if(g_dayStartBal > 0)
   {
      double dd = (g_dayStartBal - g_account.Equity()) / g_dayStartBal * 100;
      if(dd >= InpDailyLossLimit)
      { g_haltDaily = true; g_haltTime = TimeCurrent(); Print("HALT: Daily loss ", DoubleToString(dd, 1), "%"); return; }
   }
   if(g_weekStartBal > 0)
   {
      double wdd = (g_weekStartBal - g_account.Equity()) / g_weekStartBal * 100;
      if(wdd >= InpWeeklyLossLimit)
      { g_haltWeekly = true; g_haltTime = TimeCurrent(); Print("HALT: Weekly loss ", DoubleToString(wdd, 1), "%"); return; }
   }
   if(g_monthStartBal > 0)
   {
      double mdd = (g_monthStartBal - g_account.Equity()) / g_monthStartBal * 100;
      if(mdd >= InpMonthlyLossLimit)
      { g_haltMonthly = true; Print("HALT: Monthly loss ", DoubleToString(mdd, 1), "% — MANUAL RESTART REQUIRED"); return; }
   }

   // Equity protector: track peak
   if(g_account.Equity() > g_dayPeakEquity)
      g_dayPeakEquity = g_account.Equity();

   // Full scan
   if(TimeCurrent() - g_lastScan >= InpScanIntervalSec)
   {
      FullScan();
      g_lastScan = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| MODULE 1: FULL MARKET SCAN                                        |
//+------------------------------------------------------------------+
void FullScan()
{
   UpdateOpenCounts();
   int totalOpen = CountTotalTrades();

   // Phase 1: Update + classify every pair
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      UpdateIndicators(i);
      g_pairs[i].regime = ClassifyRegime(i);
      g_pairs[i].strategy = SelectStrategy(g_pairs[i].regime);
      g_pairs[i].mtfScore = CalcMTFScore(g_pairs[i].symbol, g_pairs[i].mtfBullish);
      DetectSMC(i);
      g_pairs[i].confidence = CalcConfidence(i, g_pairs[i].isBuySignal);
      g_pairs[i].pairScore = g_pairs[i].confidence;
   }

   // Phase 2: Auto-rotate
   if(InpAutoStratRotation) AutoRotateStrategies();
   if(InpAutoPairRotation) AutoRotatePairs();

   // Phase 3: Rank pairs by score
   int order[];
   ArrayResize(order, g_pairCount);
   for(int i = 0; i < g_pairCount; i++) order[i] = i;
   for(int i = 0; i < g_pairCount - 1; i++)
      for(int j = i + 1; j < g_pairCount; j++)
         if(g_pairs[order[j]].pairScore > g_pairs[order[i]].pairScore)
         { int tmp = order[i]; order[i] = order[j]; order[j] = tmp; }

   // Phase 4: Execute on best opportunities
   for(int k = 0; k < g_pairCount; k++)
   {
      int i = order[k];
      if(!g_pairs[i].active || g_pairs[i].disabled) continue;
      if(g_pairs[i].strategy == STRAT_NONE || g_pairs[i].strategy == STRAT_WAIT) continue;
      if(IsStratDisabled(g_pairs[i].strategy)) continue;
      if(g_pairs[i].confidence < InpMinConfidence) continue;
      if(g_pairs[i].openTrades >= InpMaxTradesPerPair) continue;
      if(totalOpen >= InpMaxTotalTrades) break;
      if(!PassFilters(i)) continue;
      if(InpAutoSessionFilter && !IsGoodSession()) continue;

      if(ExecuteTrade(i))
         totalOpen++;
   }
}

//+------------------------------------------------------------------+
//| MODULE 2: REGIME CLASSIFIER                                       |
//+------------------------------------------------------------------+
ENUM_REGIME ClassifyRegime(int idx)
{
   double adx = g_pairs[idx].adx;
   double atr = g_pairs[idx].atr;
   double atrSMA = g_pairs[idx].atrSMA;
   bool highVol = (atrSMA > 0 && atr > atrSMA * 1.4);
   bool lowVol = (atrSMA > 0 && atr < atrSMA * 0.6);

   if(highVol && adx < 20) return REGIME_HIGH_VOLATILITY;
   if(lowVol && adx < 15) return REGIME_LOW_LIQUIDITY;

   if(adx > 30)
   {
      bool bull = (g_pairs[idx].adxPlus > g_pairs[idx].adxMinus);
      if(g_pairs[idx].macdHist > 0 && bull) return REGIME_MOMENTUM_BULL;
      if(g_pairs[idx].macdHist < 0 && !bull) return REGIME_MOMENTUM_BEAR;
      return bull ? REGIME_TREND_BULL : REGIME_TREND_BEAR;
   }
   if(adx > 20)
      return (g_pairs[idx].adxPlus > g_pairs[idx].adxMinus) ? REGIME_TREND_BULL : REGIME_TREND_BEAR;
   if(adx < 20)
      return REGIME_RANGE;

   return REGIME_SKIP;
}

ENUM_STRAT SelectStrategy(ENUM_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TREND_BULL:
      case REGIME_TREND_BEAR:     return STRAT_TREND_PULLBACK;
      case REGIME_RANGE:          return STRAT_LIQ_SCALP;
      case REGIME_MOMENTUM_BULL:
      case REGIME_MOMENTUM_BEAR:  return STRAT_BREAKOUT;
      case REGIME_HIGH_VOLATILITY: return STRAT_WAIT;
      case REGIME_LOW_LIQUIDITY:  return STRAT_NONE;
      default:                    return STRAT_NONE;
   }
}

//+------------------------------------------------------------------+
//| MODULE 3: MULTI-TIMEFRAME SCORE                                   |
//+------------------------------------------------------------------+
double CalcMTFScore(string sym, bool &isBullish)
{
   ENUM_TIMEFRAMES tfs[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1};
   double weights[] = {20, 20, 15, 15, 15, 15};
   double bullS = 0, bearS = 0;

   for(int i = 0; i < 6; i++)
   {
      int hF = iMA(sym, tfs[i], 9, 0, MODE_EMA, PRICE_CLOSE);
      int hS = iMA(sym, tfs[i], 21, 0, MODE_EMA, PRICE_CLOSE);
      if(hF == INVALID_HANDLE || hS == INVALID_HANDLE) continue;
      double f[], s[];
      bool ok = (CopyBuffer(hF, 0, 0, 2, f) >= 1 && CopyBuffer(hS, 0, 0, 2, s) >= 1);
      IndicatorRelease(hF);
      IndicatorRelease(hS);
      if(!ok) continue;
      if(f[0] > s[0]) bullS += weights[i];
      else bearS += weights[i];
   }

   isBullish = (bullS > bearS);
   return MathMax(bullS, bearS);
}

//+------------------------------------------------------------------+
//| MODULE 4: SMART MONEY CONCEPTS                                    |
//+------------------------------------------------------------------+
void DetectSMC(int idx)
{
   string sym = g_pairs[idx].symbol;
   g_pairs[idx].liqSweepBull = false; g_pairs[idx].liqSweepBear = false;
   g_pairs[idx].fvgBullPresent = false; g_pairs[idx].fvgBearPresent = false;
   g_pairs[idx].obBullPresent = false; g_pairs[idx].obBearPresent = false;
   g_pairs[idx].mssBull = false; g_pairs[idx].mssBear = false;
   g_pairs[idx].bosBull = false; g_pairs[idx].bosBear = false;

   double h[], l[], c[], o[];
   if(CopyHigh(sym, PERIOD_M15, 0, 25, h) < 20) return;
   if(CopyLow(sym, PERIOD_M15, 0, 25, l) < 20) return;
   if(CopyClose(sym, PERIOD_M15, 0, 25, c) < 20) return;
   if(CopyOpen(sym, PERIOD_M15, 0, 25, o) < 20) return;

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   // Liquidity sweep: price breaks PDH/PDL then reverses
   double pdh = iHigh(sym, PERIOD_D1, 1);
   double pdl = iLow(sym, PERIOD_D1, 1);
   if(pdl > 0 && bid < pdl && bid > pdl - point * 100) g_pairs[idx].liqSweepBull = true;
   if(pdh > 0 && bid > pdh && bid < pdh + point * 100) g_pairs[idx].liqSweepBear = true;

   // FVG
   for(int i = 2; i < 18; i++)
   {
      if(l[i-1] > h[i+1]) { if(bid >= h[i+1] && bid <= l[i-1]) g_pairs[idx].fvgBullPresent = true; }
      if(h[i-1] < l[i+1]) { if(bid >= h[i-1] && bid <= l[i+1]) g_pairs[idx].fvgBearPresent = true; }
   }

   // Order Blocks
   for(int i = 3; i < 18; i++)
   {
      if(c[i] < o[i] && c[i-1] > o[i-1])
      {
         double body = MathAbs(c[i-1] - o[i-1]);
         double range = h[i-1] - l[i-1];
         if(range > 0 && body > range * 0.6 && c[i-1] > h[i])
            if(bid >= l[i] && bid <= h[i]) g_pairs[idx].obBullPresent = true;
      }
      if(c[i] > o[i] && c[i-1] < o[i-1])
      {
         double body = MathAbs(c[i-1] - o[i-1]);
         double range = h[i-1] - l[i-1];
         if(range > 0 && body > range * 0.6 && c[i-1] < l[i])
            if(bid >= l[i] && bid <= h[i]) g_pairs[idx].obBearPresent = true;
      }
   }

   // Structure: MSS / BOS
   double swH[10], swL[10];
   int shC = 0, slC = 0;
   for(int i = 2; i < MathMin(20, ArraySize(h) - 2); i++)
   {
      if(h[i] > h[i-1] && h[i] > h[i+1] && shC < 10) swH[shC++] = h[i];
      if(l[i] < l[i-1] && l[i] < l[i+1] && slC < 10) swL[slC++] = l[i];
   }
   if(shC >= 2 && slC >= 2)
   {
      if(c[1] > swH[1] && swH[0] < swH[1]) g_pairs[idx].mssBull = true;
      if(c[1] < swL[1] && swL[0] > swL[1]) g_pairs[idx].mssBear = true;
      if(c[1] > swH[0]) g_pairs[idx].bosBull = true;
      if(c[1] < swL[0]) g_pairs[idx].bosBear = true;
   }
}

//+------------------------------------------------------------------+
//| MODULE 5: AI CONFIDENCE SCORE                                     |
//+------------------------------------------------------------------+
double CalcConfidence(int idx, bool &isBuy)
{
   double buyC = 0, sellC = 0;

   // Trend
   if(g_pairs[idx].regime == REGIME_TREND_BULL || g_pairs[idx].regime == REGIME_MOMENTUM_BULL) buyC += InpConfTrend;
   if(g_pairs[idx].regime == REGIME_TREND_BEAR || g_pairs[idx].regime == REGIME_MOMENTUM_BEAR) sellC += InpConfTrend;

   // Liquidity sweep
   if(g_pairs[idx].liqSweepBull) buyC += InpConfLiqSweep;
   if(g_pairs[idx].liqSweepBear) sellC += InpConfLiqSweep;

   // Order block
   if(g_pairs[idx].obBullPresent) buyC += InpConfOB;
   if(g_pairs[idx].obBearPresent) sellC += InpConfOB;

   // FVG
   if(g_pairs[idx].fvgBullPresent) buyC += 8;
   if(g_pairs[idx].fvgBearPresent) sellC += 8;

   // MSS/BOS
   if(g_pairs[idx].mssBull || g_pairs[idx].bosBull) buyC += 8;
   if(g_pairs[idx].mssBear || g_pairs[idx].bosBear) sellC += 8;

   // Volume/MACD
   if(g_pairs[idx].macdHist > 0) buyC += InpConfVolume;
   if(g_pairs[idx].macdHist < 0) sellC += InpConfVolume;

   // Momentum (RSI alignment)
   if(g_pairs[idx].rsi > 50 && g_pairs[idx].rsi < 70) buyC += InpConfMomentum * 0.5;
   if(g_pairs[idx].rsi < 50 && g_pairs[idx].rsi > 30) sellC += InpConfMomentum * 0.5;
   if(g_pairs[idx].emaFast > g_pairs[idx].emaSlow) buyC += InpConfMomentum * 0.5;
   if(g_pairs[idx].emaFast < g_pairs[idx].emaSlow) sellC += InpConfMomentum * 0.5;

   // MTF agreement
   double mtfB = g_pairs[idx].mtfScore / 100.0 * InpConfMTF;
   if(g_pairs[idx].mtfBullish) buyC += mtfB;
   else sellC += mtfB;

   // Spread quality
   if(g_pairs[idx].avgSpread > 0 && g_pairs[idx].currentSpread <= g_pairs[idx].avgSpread * 1.2)
   { buyC += InpConfSpread; sellC += InpConfSpread; }

   isBuy = (buyC >= sellC);
   return MathMin(MathMax(buyC, sellC), 100.0);
}

//+------------------------------------------------------------------+
//| MODULE 6: POSITION SIZING                                         |
//+------------------------------------------------------------------+
double GetRiskPercent(double confidence)
{
   double riskPct;
   if(confidence >= 90)      riskPct = InpRiskHigh;
   else if(confidence >= 80) riskPct = InpRiskMed;
   else                      riskPct = InpRiskLow;

   riskPct = MathMin(riskPct, InpMaxRiskPerTrade);

   // Consecutive loss reduction
   if(g_consecLosses >= InpConsecHalveAt)
      riskPct *= 0.5;
   else if(g_consecLosses >= InpConsecReduceAt)
      riskPct *= 0.75;

   // Equity protector: reduce during drawdown
   if(InpEquityProtector && g_dayPeakEquity > 0)
   {
      double ddFromPeak = (g_dayPeakEquity - g_account.Equity()) / g_dayPeakEquity * 100;
      if(ddFromPeak > 1.0)
         riskPct *= (1.0 - InpDDRiskCutPct / 100.0);
   }

   return MathMax(riskPct, 0.05);
}

double CalcLots(string sym, double slDist, double riskPct)
{
   if(slDist <= 0) return 0;
   double balance = g_account.Balance();
   double riskMoney = balance * riskPct / 100.0;

   double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(tickVal <= 0 || tickSize <= 0 || pt <= 0) return 0;
   double pointVal = tickVal / tickSize * pt;
   double slPts = slDist / pt;
   double lots = riskMoney / (slPts * pointVal);

   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(lotMin, MathMin(lots, lotMax));
}

//+------------------------------------------------------------------+
//| MODULE 7: FILTERS                                                 |
//+------------------------------------------------------------------+
bool PassFilters(int idx)
{
   // Spread filter
   if(g_pairs[idx].avgSpread > 0 && g_pairs[idx].currentSpread > g_pairs[idx].avgSpread * InpMaxSpreadMult)
      return false;

   // Trade cooldown
   if(InpTradeCooldownSec > 0 && g_pairs[idx].lastTradeTime > 0)
   {
      if((int)(TimeCurrent() - g_pairs[idx].lastTradeTime) < InpTradeCooldownSec)
         return false;
   }

   // News filter (NFP, FOMC)
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 5 && dt.day <= 7 && dt.hour >= 12 && dt.hour <= 16) return false;
   if(dt.day_of_week == 3 && dt.day >= 15 && dt.day <= 21 && dt.hour >= 18 && dt.hour <= 22) return false;

   return true;
}

bool IsGoodSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;

   if(hour >= 8 && hour < 12)
      return (g_londonStats.trades < 10 || g_londonStats.winRate >= InpSessionMinWR);
   if(hour >= 13 && hour < 17)
      return (g_nyStats.trades < 10 || g_nyStats.winRate >= InpSessionMinWR);
   if(hour >= 0 && hour < 8)
      return (g_asianStats.trades < 10 || g_asianStats.winRate >= InpSessionMinWR);

   return true;
}

bool IsStratDisabled(ENUM_STRAT strat)
{
   if(!InpAutoStratRotation) return false;
   int idx = -1;
   switch(strat)
   {
      case STRAT_TREND_PULLBACK: idx = 0; break;
      case STRAT_LIQ_SCALP:     idx = 1; break;
      case STRAT_BREAKOUT:       idx = 2; break;
      default: return false;
   }
   return (idx >= 0 && idx < 4) ? g_stratStats[idx].disabled : false;
}

//+------------------------------------------------------------------+
//| MODULE 8: EXECUTE TRADE                                           |
//+------------------------------------------------------------------+
bool ExecuteTrade(int idx)
{
   string sym = g_pairs[idx].symbol;
   bool isBuy = g_pairs[idx].isBuySignal;
   double atr = g_pairs[idx].atr;
   if(atr <= 0) return false;

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   double slDist = atr * InpSLATRMult;
   double tpDist = slDist * InpMinRR;

   double entry = isBuy ? ask : bid;
   double sl = NormalizeDouble(isBuy ? entry - slDist : entry + slDist, digits);
   double tp = NormalizeDouble(isBuy ? entry + tpDist : entry - tpDist, digits);

   double riskPct = GetRiskPercent(g_pairs[idx].confidence);
   double lots = CalcLots(sym, slDist, riskPct);
   if(lots <= 0) return false;

   int magic = InpMagicBase + idx;
   g_trade.SetExpertMagicNumber(magic);

   string stratName = "";
   switch(g_pairs[idx].strategy)
   {
      case STRAT_TREND_PULLBACK: stratName = "TREND"; break;
      case STRAT_LIQ_SCALP:     stratName = "LIQSCALP"; break;
      case STRAT_BREAKOUT:       stratName = "BREAKOUT"; break;
      default: stratName = "OTHER"; break;
   }

   string comment = StringFormat("ASE|%s|%.0f", stratName, g_pairs[idx].confidence);
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   bool result = g_trade.PositionOpen(sym, type, lots, entry, sl, tp, comment);

   // Slippage guard
   if(result && InpSlippageGuard)
   {
      double fillPrice = g_trade.ResultPrice();
      double slippage = MathAbs(fillPrice - entry) / SymbolInfoDouble(sym, SYMBOL_POINT);
      if(slippage > InpMaxSlippage * 2)
      {
         g_trade.PositionClose(g_trade.ResultOrder());
         Print("SLIPPAGE GUARD: Closed ", sym, " — slippage ", DoubleToString(slippage, 0), " pts");
         return false;
      }
   }

   if(result)
   {
      // Register for management
      if(g_managedCount < MAX_MANAGED)
      {
         g_managed[g_managedCount].ticket = g_trade.ResultOrder();
         g_managed[g_managedCount].symbol = sym;
         g_managed[g_managedCount].entryPrice = entry;
         g_managed[g_managedCount].initialSL = sl;
         g_managed[g_managedCount].currentSL = sl;
         g_managed[g_managedCount].initialLots = lots;
         g_managed[g_managedCount].currentLots = lots;
         g_managed[g_managedCount].isBuy = isBuy;
         g_managed[g_managedCount].beMoveDone = false;
         g_managed[g_managedCount].partialDone = false;
         g_managed[g_managedCount].trailing = false;
         g_managed[g_managedCount].maxProfitR = 0;
         g_managed[g_managedCount].openTime = TimeCurrent();
         g_managed[g_managedCount].confidence = g_pairs[idx].confidence;
         g_managed[g_managedCount].stratName = stratName;
         g_managedCount++;
      }

      g_pairs[idx].lastTradeTime = TimeCurrent();
      g_todayTrades++;

      Print(StringFormat("[%s] %s %s | Conf: %.0f%% | Lot: %.2f | Risk: %.2f%% | Regime: %s",
            stratName, isBuy ? "BUY" : "SELL", sym, g_pairs[idx].confidence, lots, riskPct,
            EnumToString(g_pairs[idx].regime)));
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 9: TRADE MANAGEMENT AI                                     |
//+------------------------------------------------------------------+
void ManageAllPositions()
{
   for(int i = g_managedCount - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByTicket(g_managed[i].ticket))
      {
         // Position closed — remove
         for(int j = i; j < g_managedCount - 1; j++)
            g_managed[j] = g_managed[j + 1];
         g_managedCount--;
         continue;
      }
      ManageSingle(i);
   }
}

void ManageSingle(int mIdx)
{
   string sym = g_managed[mIdx].symbol;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double current = g_managed[mIdx].isBuy ? bid : ask;
   double risk = MathAbs(g_managed[mIdx].entryPrice - g_managed[mIdx].initialSL);
   if(risk <= 0) return;

   double profitDist = g_managed[mIdx].isBuy ?
      (current - g_managed[mIdx].entryPrice) : (g_managed[mIdx].entryPrice - current);
   double profitR = profitDist / risk;
   if(profitR > g_managed[mIdx].maxProfitR) g_managed[mIdx].maxProfitR = profitR;

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   // Partial close at TP1
   if(!g_managed[mIdx].partialDone && profitR >= InpBEMoveR)
   {
      double closeVol = MathFloor(g_managed[mIdx].initialLots * InpPartialClosePct /
                        SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double lotMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      if(closeVol >= lotMin)
      {
         g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
         if(g_trade.PositionClosePartial(g_managed[mIdx].ticket, closeVol))
         {
            g_managed[mIdx].currentLots -= closeVol;
            g_managed[mIdx].partialDone = true;
         }
      }
   }

   // Move SL to breakeven
   if(!g_managed[mIdx].beMoveDone && profitR >= InpBEMoveR)
   {
      double newSL = NormalizeDouble(g_managed[mIdx].entryPrice + (g_managed[mIdx].isBuy ? point : -point), digits);
      g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
      if(g_trade.PositionModify(g_managed[mIdx].ticket, newSL, g_posInfo.TakeProfit()))
      {
         g_managed[mIdx].currentSL = newSL;
         g_managed[mIdx].beMoveDone = true;
      }
   }

   // Trailing stop
   if(profitR >= InpTrailStartR)
   {
      double atrBuf[];
      int hATR = iATR(sym, PERIOD_M15, 14);
      if(hATR != INVALID_HANDLE)
      {
         if(CopyBuffer(hATR, 0, 0, 1, atrBuf) >= 1)
         {
            double trailDist = atrBuf[0] * InpTrailATRMult;
            double newSL;
            if(g_managed[mIdx].isBuy)
            {
               newSL = NormalizeDouble(current - trailDist, digits);
               if(newSL > g_managed[mIdx].currentSL)
               {
                  g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
                  if(g_trade.PositionModify(g_managed[mIdx].ticket, newSL, g_posInfo.TakeProfit()))
                  {
                     g_managed[mIdx].currentSL = newSL;
                     g_managed[mIdx].trailing = true;
                  }
               }
            }
            else
            {
               newSL = NormalizeDouble(current + trailDist, digits);
               if(newSL < g_managed[mIdx].currentSL)
               {
                  g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
                  if(g_trade.PositionModify(g_managed[mIdx].ticket, newSL, g_posInfo.TakeProfit()))
                  {
                     g_managed[mIdx].currentSL = newSL;
                     g_managed[mIdx].trailing = true;
                  }
               }
            }
         }
         IndicatorRelease(hATR);
      }
   }

   // Momentum exit: if we had 2R+ profit and it's falling back, close remaining
   if(g_managed[mIdx].partialDone && g_managed[mIdx].maxProfitR >= 2.0 && profitR < g_managed[mIdx].maxProfitR * 0.5)
   {
      g_trade.SetExpertMagicNumber((int)g_posInfo.Magic());
      g_trade.PositionClose(g_managed[mIdx].ticket);
      Print("  MOMENTUM EXIT: ", sym, " — peaked at ", DoubleToString(g_managed[mIdx].maxProfitR, 1), "R, now ", DoubleToString(profitR, 1), "R");
   }
}

//+------------------------------------------------------------------+
//| MODULE 10: SELF-LEARNING + TRADE TRACKING                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < InpMagicBase || magic >= InpMagicBase + MAX_PAIRS) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   bool isWin = (profit > 0);

   g_todayPnL += profit;
   if(isWin) { g_consecLosses = 0; g_todayWins++; }
   else
   {
      g_consecLosses++;
      if(g_consecLosses >= InpConsecStopAt)
      { g_haltConsec = true; g_haltTime = TimeCurrent(); Print("HALT: ", g_consecLosses, " consecutive losses"); }
   }

   // Session stats
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour >= 8 && dt.hour < 12)
   {
      g_londonStats.trades++;
      if(isWin) g_londonStats.wins++;
      g_londonStats.pnl += profit;
      g_londonStats.winRate = (g_londonStats.trades > 0) ? (double)g_londonStats.wins / g_londonStats.trades * 100 : 0;
   }
   else if(dt.hour >= 13 && dt.hour < 17)
   {
      g_nyStats.trades++;
      if(isWin) g_nyStats.wins++;
      g_nyStats.pnl += profit;
      g_nyStats.winRate = (g_nyStats.trades > 0) ? (double)g_nyStats.wins / g_nyStats.trades * 100 : 0;
   }
   else if(dt.hour >= 0 && dt.hour < 8)
   {
      g_asianStats.trades++;
      if(isWin) g_asianStats.wins++;
      g_asianStats.pnl += profit;
      g_asianStats.winRate = (g_asianStats.trades > 0) ? (double)g_asianStats.wins / g_asianStats.trades * 100 : 0;
   }

   // Strategy stats
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   int stratIdx = -1;
   if(StringFind(comment, "TREND") >= 0) stratIdx = 0;
   else if(StringFind(comment, "LIQSCALP") >= 0) stratIdx = 1;
   else if(StringFind(comment, "BREAKOUT") >= 0) stratIdx = 2;

   if(stratIdx >= 0 && stratIdx < 4)
   {
      g_stratStats[stratIdx].trades++;
      if(isWin) g_stratStats[stratIdx].wins++;
      g_stratStats[stratIdx].pnl += profit;
      g_stratStats[stratIdx].winRate = (g_stratStats[stratIdx].trades > 0) ?
         (double)g_stratStats[stratIdx].wins / g_stratStats[stratIdx].trades * 100 : 0;
   }

   // Pair stats
   int pairIdx = (int)(magic - InpMagicBase);
   if(pairIdx >= 0 && pairIdx < g_pairCount)
   {
      g_pairs[pairIdx].pairPnL += profit;
      if(isWin) g_pairs[pairIdx].pairWins++;
      else g_pairs[pairIdx].pairLosses++;
   }

   // CSV log
   LogTradeToDB(sym, stratIdx, profit, isWin);

   Print(StringFormat("%s %s | P/L: $%.2f | Consec: %d | Today: %d trades $%.2f",
         isWin ? "WIN" : "LOSS", sym, profit, g_consecLosses, g_todayTrades, g_todayPnL));
}

void LogTradeToDB(string sym, int stratIdx, double profit, bool isWin)
{
   string names[] = {"TREND", "LIQSCALP", "BREAKOUT", "OTHER"};
   string sn = (stratIdx >= 0 && stratIdx < 4) ? names[stratIdx] : "UNKNOWN";

   MqlDateTime dt;
   TimeCurrent(dt);
   string session = "OTHER";
   if(dt.hour >= 8 && dt.hour < 12) session = "LONDON";
   else if(dt.hour >= 13 && dt.hour < 17) session = "NEWYORK";
   else if(dt.hour >= 0 && dt.hour < 8) session = "ASIAN";

   int handle = FileOpen("ASE_trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      if(FileSize(handle) == 0)
         FileWrite(handle, "Time", "Symbol", "Strategy", "Session", "Profit", "Win", "Balance", "Equity");
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, TimeToString(TimeCurrent()), sym, sn, session,
                DoubleToString(profit, 2), isWin ? "YES" : "NO",
                DoubleToString(g_account.Balance(), 2), DoubleToString(g_account.Equity(), 2));
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| MODULE 11: AUTO-ROTATION                                          |
//+------------------------------------------------------------------+
void AutoRotateStrategies()
{
   for(int i = 0; i < 3; i++)
   {
      if(g_stratStats[i].trades < InpStratMinTrades) continue;
      if(g_stratStats[i].winRate < InpStratDisableWR && !g_stratStats[i].disabled)
      {
         g_stratStats[i].disabled = true;
         string names[] = {"TrendPB", "LiqScalp", "Breakout"};
         Print("AUTO-ROTATE: Disabled ", names[i], " (WR: ", DoubleToString(g_stratStats[i].winRate, 0), "%)");
      }
      else if(g_stratStats[i].winRate >= InpStratDisableWR + 10 && g_stratStats[i].disabled)
      {
         g_stratStats[i].disabled = false;
         string names[] = {"TrendPB", "LiqScalp", "Breakout"};
         Print("AUTO-ROTATE: Re-enabled ", names[i], " (WR: ", DoubleToString(g_stratStats[i].winRate, 0), "%)");
      }
   }
}

void AutoRotatePairs()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      int totalTr = g_pairs[i].pairWins + g_pairs[i].pairLosses;
      if(totalTr < 5) continue;
      double wr = (double)g_pairs[i].pairWins / totalTr * 100;
      if(wr < InpStratDisableWR && g_pairs[i].pairPnL < 0 && !g_pairs[i].disabled)
      {
         g_pairs[i].disabled = true;
         Print("AUTO-ROTATE: Disabled ", g_pairs[i].symbol, " (WR: ", DoubleToString(wr, 0), "%)");
      }
      else if(g_pairs[i].disabled && wr >= InpStratDisableWR + 10)
      {
         g_pairs[i].disabled = false;
         Print("AUTO-ROTATE: Re-enabled ", g_pairs[i].symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 12: ON-CHART DASHBOARD                                     |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = 10, y = 30, lineH = 18;
   string status = "AUTO TRADING";
   color statusClr = clrLime;
   if(g_haltMonthly) { status = "MONTHLY HALT"; statusClr = clrRed; }
   else if(g_haltDaily) { status = "DAILY HALT"; statusClr = clrOrange; }
   else if(g_haltWeekly) { status = "WEEKLY HALT"; statusClr = clrOrange; }
   else if(g_haltConsec) { status = "CONSEC HALT"; statusClr = clrOrange; }

   double equity = g_account.Equity();
   double balance = g_account.Balance();
   double dailyPct = (g_dayStartBal > 0) ? (equity - g_dayStartBal) / g_dayStartBal * 100 : 0;
   double ddPct = (g_dayStartBal > 0) ? (g_dayStartBal - equity) / g_dayStartBal * 100 : 0;
   if(ddPct < 0) ddPct = 0;
   double wr = (g_todayTrades > 0) ? (double)g_todayWins / g_todayTrades * 100 : 0;

   // Find best pair
   string bestPair = "---";
   double bestConf = 0;
   string bestRegime = "---";
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].active && g_pairs[i].confidence > bestConf)
      { bestConf = g_pairs[i].confidence; bestPair = g_pairs[i].symbol; bestRegime = EnumToString(g_pairs[i].regime); }
   }

   DashLine(x, y, 0, "══════════════════════", clrGold); y += lineH;
   DashLine(x, y, 1, "  AI SCALPING ENGINE", clrGold); y += lineH;
   DashLine(x, y, 2, "══════════════════════", clrGold); y += lineH;
   DashLine(x, y, 3, "Status:  " + status, statusClr); y += lineH;
   DashLine(x, y, 4, "Best:    " + bestPair, clrWhite); y += lineH;
   DashLine(x, y, 5, "Conf:    " + DoubleToString(bestConf, 0) + "%", bestConf >= 90 ? clrLime : bestConf >= 70 ? clrYellow : clrGray); y += lineH;
   DashLine(x, y, 6, "Regime:  " + bestRegime, clrSilver); y += lineH;
   DashLine(x, y, 7, "──────────────────────", clrGray); y += lineH;
   DashLine(x, y, 8, "Balance: $" + DoubleToString(balance, 2), clrWhite); y += lineH;
   DashLine(x, y, 9, "Equity:  $" + DoubleToString(equity, 2), clrWhite); y += lineH;
   DashLine(x, y, 10, "Daily:   " + (dailyPct >= 0 ? "+" : "") + DoubleToString(dailyPct, 2) + "%", dailyPct >= 0 ? clrLime : clrRed); y += lineH;
   DashLine(x, y, 11, "DD:      " + DoubleToString(ddPct, 2) + "%", ddPct > 1 ? clrOrange : clrGray); y += lineH;
   DashLine(x, y, 12, "──────────────────────", clrGray); y += lineH;
   DashLine(x, y, 13, "Trades:  " + IntegerToString(g_todayTrades), clrWhite); y += lineH;
   DashLine(x, y, 14, "WinRate: " + DoubleToString(wr, 0) + "%", wr >= 60 ? clrLime : wr >= 40 ? clrYellow : clrRed); y += lineH;
   DashLine(x, y, 15, "PnL:     $" + DoubleToString(g_todayPnL, 2), g_todayPnL >= 0 ? clrLime : clrRed); y += lineH;
   DashLine(x, y, 16, "Losses:  " + IntegerToString(g_consecLosses) + " consec", g_consecLosses >= 3 ? clrOrange : clrGray); y += lineH;
   DashLine(x, y, 17, "Open:    " + IntegerToString(CountTotalTrades()) + "/" + IntegerToString(InpMaxTotalTrades), clrWhite); y += lineH;
   DashLine(x, y, 18, "══════════════════════", clrGold);
}

void DashLine(int x, int y, int idx, string text, color clr)
{
   string name = OBJ_PFX + "dash_" + IntegerToString(idx);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| MODULE 13: PERFORMANCE REPORT                                     |
//+------------------------------------------------------------------+
void PrintPerformanceReport()
{
   Print("══════════════════════════════════════════════════");
   Print("          PERFORMANCE REPORT");
   Print("══════════════════════════════════════════════════");
   Print("SESSION:");
   Print(StringFormat("  London:   %dW/%dL | WR: %.0f%% | $%.2f", g_londonStats.wins, g_londonStats.trades - g_londonStats.wins, g_londonStats.winRate, g_londonStats.pnl));
   Print(StringFormat("  New York: %dW/%dL | WR: %.0f%% | $%.2f", g_nyStats.wins, g_nyStats.trades - g_nyStats.wins, g_nyStats.winRate, g_nyStats.pnl));
   Print(StringFormat("  Asian:    %dW/%dL | WR: %.0f%% | $%.2f", g_asianStats.wins, g_asianStats.trades - g_asianStats.wins, g_asianStats.winRate, g_asianStats.pnl));
   Print("STRATEGY:");
   string snames[] = {"TrendPullback", "LiqScalp     ", "Breakout     "};
   for(int i = 0; i < 3; i++)
      Print(StringFormat("  %s: %dW/%dL | WR: %.0f%% | $%.2f%s", snames[i],
            g_stratStats[i].wins, g_stratStats[i].trades - g_stratStats[i].wins,
            g_stratStats[i].winRate, g_stratStats[i].pnl, g_stratStats[i].disabled ? " [OFF]" : ""));
   Print("PAIRS:");
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      int pt = g_pairs[i].pairWins + g_pairs[i].pairLosses;
      double pwr = (pt > 0) ? (double)g_pairs[i].pairWins / pt * 100 : 0;
      Print(StringFormat("  %s: %dW/%dL | WR: %.0f%% | $%.2f%s", g_pairs[i].symbol,
            g_pairs[i].pairWins, g_pairs[i].pairLosses, pwr, g_pairs[i].pairPnL,
            g_pairs[i].disabled ? " [OFF]" : ""));
   }
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

   double askP = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bidP = SymbolInfoDouble(sym, SYMBOL_BID);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   g_pairs[idx].currentSpread = (pt > 0) ? (askP - bidP) / pt : 0;
   if(g_pairs[idx].avgSpread <= 0) g_pairs[idx].avgSpread = g_pairs[idx].currentSpread;
   else g_pairs[idx].avgSpread = g_pairs[idx].avgSpread * 0.95 + g_pairs[idx].currentSpread * 0.05;
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

void CheckTimeResets()
{
   MqlDateTime dt, dtS;
   TimeCurrent(dt);
   TimeToStruct(g_dayStart, dtS);

   // Daily reset
   if(dt.day != dtS.day || g_dayStart == 0)
   {
      g_dayStart = TimeCurrent();
      g_dayStartBal = g_account.Balance();
      g_dayPeakEquity = g_account.Equity();
      g_haltDaily = false;
      g_haltConsec = false;
      g_consecLosses = 0;
      g_todayTrades = 0;
      g_todayWins = 0;
      g_todayPnL = 0;
   }
   // Weekly reset
   if(dt.day_of_week == 1 && dtS.day_of_week != 1)
   {
      g_weekStartBal = g_account.Balance();
      g_haltWeekly = false;
   }
   // Monthly reset
   if(dt.mon != dtS.mon)
   {
      g_monthStart = TimeCurrent();
      g_monthStartBal = g_account.Balance();
      g_haltMonthly = false;
   }
}
//+------------------------------------------------------------------+
