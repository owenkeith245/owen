//+------------------------------------------------------------------+
//|                                              AIScalperPro.mq5     |
//|                                  AI SCALPER PRO v1.0              |
//|                        Fully Autonomous Adaptive Trading System   |
//+------------------------------------------------------------------+
#property copyright "AI Scalper Pro"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════ GENERAL ══════"
input int      InpMagic              = 700000;          // Magic Number
input int      InpScanInterval       = 30;              // Scan interval (seconds)
input bool     InpFullAuto           = true;            // Full autonomous mode

input group "══════ MARKETS ══════"
input string   InpPairs              = "XAUUSD,EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,USDCHF,NAS100,US30,BTCUSD";

input group "══════ ACCOUNT CONTROL MANAGER ══════"
input bool     InpUseTierLots        = true;            // Use equity-tier lot sizing
input double   InpBaseRiskPct        = 0.50;            // Base risk % of equity
input double   InpMinLot             = 0.01;            // Minimum lot size
input double   InpMaxLot             = 5.00;            // Maximum lot size

input group "══════ ADAPTIVE RISK ENGINE ══════"
input double   InpRiskBoostPct       = 0.75;            // Risk after 5+ win streak
input double   InpRiskReducePct      = 0.25;            // Risk after 3 consecutive losses
input int      InpWinStreakThreshold  = 5;              // Win streak to boost risk
input int      InpLossStreakReduce    = 3;              // Loss streak to reduce risk

input group "══════ AI CONFIDENCE MODEL ══════"
input double   InpMinConfidence      = 60.0;            // Minimum confidence to trade
input double   InpConfSmall          = 68.0;            // Below this = small lot
input double   InpConfNormal         = 82.0;            // Below this = normal lot
input double   InpConfMax            = 95.0;            // Above this = max allowed

input group "══════ CAPITAL PROTECTION ══════"
input double   InpDailyLossLimit     = 2.0;             // Daily loss limit (%)
input double   InpWeeklyLossLimit    = 5.0;             // Weekly loss limit (%)
input int      InpMaxDailyTrades     = 20;              // Max trades per day
input int      InpConsecStopAt       = 5;               // Stop trading at N consec losses
input double   InpMaxDDPercent       = 15.0;            // Max total drawdown (%)

input group "══════ TRADE MANAGEMENT ══════"
input double   InpSLATRMult          = 1.5;             // SL = ATR * multiplier
input double   InpMinRR              = 1.5;             // Minimum Reward:Risk
input double   InpBEMovePips         = 5.0;             // Move to BE after X pips profit
input double   InpPartialClosePips   = 10.0;            // Close 50% after X pips
input double   InpPartialClosePct    = 0.50;            // Partial close percentage
input double   InpTrailATRMult       = 1.0;             // Trailing stop ATR multiplier
input double   InpTradeCooldownSec   = 90;              // Seconds between trades per pair

input group "══════ AUTO-LEARNING ══════"
input bool     InpAutoStratRotation  = true;            // Disable losing strategies
input double   InpStratDisableWR     = 35.0;            // Disable below this WR
input bool     InpAutoSessionFilter  = true;            // Skip bad sessions
input double   InpSessionMinWR       = 45.0;            // Min WR to trade session
input bool     InpAutoPairRotation   = true;            // Disable losing pairs
input int      InpPairMinTrades      = 5;               // Min trades before pair eval

//+------------------------------------------------------------------+
//| ENUMS                                                             |
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
   REGIME_UNKNOWN
};

enum ENUM_STRATEGY
{
   STRAT_TREND_PULLBACK,
   STRAT_LIQ_SCALP,
   STRAT_BREAKOUT,
   STRAT_MEAN_REVERSION,
   STRAT_WAIT
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct PairData
{
   string   symbol;
   bool     enabled;
   double   score;
   ENUM_REGIME regime;
   ENUM_STRATEGY strategy;
   double   adx, atr, atrSMA;
   double   ema9, ema21, ema50;
   double   rsi14, rsi7;
   double   bbUpper, bbLower, bbMid;
   double   macdMain, macdSignal;
   double   bid, ask, spread;
   double   avgSpread;
   double   pdh, pdl;  // Previous day high/low
   double   confidence;
   datetime lastTradeTime;
   int      wins, losses;
   double   pnl;
   double   winRate;
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
   bool     isBuy;
   bool     beMoveDone;
   bool     partialDone;
   bool     trailing;
   double   maxProfitPips;
   datetime openTime;
   double   confidence;
   string   stratName;
};

struct SessionStats
{
   int      trades;
   int      wins;
   double   pnl;
   double   winRate;
};

struct StrategyStats
{
   int      trades;
   int      wins;
   double   pnl;
   double   winRate;
   bool     enabled;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_position;

PairData       g_pairs[20];
int            g_pairCount = 0;

ManagedTrade   g_managed[50];
int            g_managedCount = 0;

// Performance tracking
int            g_totalTrades = 0;
int            g_totalWins = 0;
int            g_totalLosses = 0;
double         g_totalPnL = 0;
int            g_consecWins = 0;
int            g_consecLosses = 0;
int            g_dailyTrades = 0;
double         g_dailyPnL = 0;
double         g_weeklyPnL = 0;
double         g_dayStartBalance = 0;
double         g_weekStartBalance = 0;
double         g_dayHighEquity = 0;
datetime       g_lastDay = 0;
datetime       g_lastWeek = 0;
datetime       g_lastScan = 0;
bool           g_dailyHalt = false;
bool           g_weeklyHalt = false;
bool           g_consecHalt = false;
datetime       g_haltTime = 0;

// Session stats
SessionStats   g_londonStats;
SessionStats   g_nyStats;
SessionStats   g_asianStats;

// Strategy stats
StrategyStats  g_trendStats;
StrategyStats  g_mrStats;
StrategyStats  g_scalperStats;
StrategyStats  g_breakoutStats;

// File handle for learning
int            g_logFile = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize pairs
   string pairs[];
   int count = StringSplit(InpPairs, ',', pairs);
   g_pairCount = MathMin(count, 20);
   
   for(int i = 0; i < g_pairCount; i++)
   {
      StringTrimLeft(pairs[i]);
      StringTrimRight(pairs[i]);
      g_pairs[i].symbol = pairs[i];
      g_pairs[i].enabled = true;
      g_pairs[i].score = 0;
      g_pairs[i].confidence = 0;
      g_pairs[i].lastTradeTime = 0;
      g_pairs[i].wins = 0;
      g_pairs[i].losses = 0;
      g_pairs[i].pnl = 0;
      g_pairs[i].winRate = 0;
   }
   
   // Initialize session stats
   ZeroMemory(g_londonStats);
   ZeroMemory(g_nyStats);
   ZeroMemory(g_asianStats);
   
   // Initialize strategy stats
   ZeroMemory(g_trendStats);
   g_trendStats.enabled = true;
   ZeroMemory(g_mrStats);
   g_mrStats.enabled = true;
   ZeroMemory(g_scalperStats);
   g_scalperStats.enabled = true;
   ZeroMemory(g_breakoutStats);
   g_breakoutStats.enabled = true;
   
   // Set day/week start
   g_dayStartBalance = g_account.Balance();
   g_weekStartBalance = g_account.Balance();
   g_dayHighEquity = g_account.Equity();
   g_lastDay = iTime(Symbol(), PERIOD_D1, 0);
   g_lastWeek = iTime(Symbol(), PERIOD_W1, 0);
   
   // Open trade log
   g_logFile = FileOpen("ASP_trades.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ, ',');
   if(g_logFile != INVALID_HANDLE)
   {
      FileSeek(g_logFile, 0, SEEK_END);
      if(FileTell(g_logFile) == 0)
         FileWrite(g_logFile, "Time", "Symbol", "Strategy", "Session", "Confidence", "Lot", "Profit", "Win", "Balance", "Equity", "Regime");
   }
   
   Print("═══════════════════════════════════════");
   Print("  AI SCALPER PRO v1.0 — FULLY AUTONOMOUS");
   Print("  Mode: ", InpFullAuto ? "FULL AUTO-PILOT" : "SEMI-AUTO");
   Print("  Pairs: ", g_pairCount);
   Print("  Base Risk: ", DoubleToString(InpBaseRiskPct, 2), "%");
   Print("  >>> BOT IS NOW RUNNING — NO INTERVENTION NEEDED");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logFile != INVALID_HANDLE)
      FileClose(g_logFile);
   
   ObjectsDeleteAll(0, "ASP_");
   
   PrintPerformanceReport();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new day/week
   CheckDayWeekReset();
   
   // Update equity high
   double equity = g_account.Equity();
   if(equity > g_dayHighEquity)
      g_dayHighEquity = equity;
   
   // Check halts
   if(g_dailyHalt || g_weeklyHalt || g_consecHalt)
   {
      // Auto-recovery after 30 minutes
      if(TimeCurrent() - g_haltTime > 1800)
      {
         if(g_dailyHalt)
         {
            double ddPct = (g_dayStartBalance - equity) / g_dayStartBalance * 100;
            if(ddPct < InpDailyLossLimit * 0.7)
            {
               g_dailyHalt = false;
               Print("AI SCALPER PRO: Daily halt lifted — recovery detected");
            }
         }
         if(g_consecHalt)
         {
            g_consecHalt = false;
            g_consecLosses = 0;
            Print("AI SCALPER PRO: Consecutive loss halt lifted — cooldown complete");
         }
      }
      
      ManageOpenTrades();
      DrawDashboard();
      return;
   }
   
   // Check max drawdown
   double totalDD = (g_dayStartBalance - equity) / g_dayStartBalance * 100;
   if(totalDD > InpMaxDDPercent)
   {
      Print("AI SCALPER PRO: MAX DRAWDOWN HIT — EMERGENCY STOP");
      CloseAllPositions();
      ExpertRemove();
      return;
   }
   
   // Manage existing trades
   ManageOpenTrades();
   
   // Scan interval
   if(TimeCurrent() - g_lastScan < InpScanInterval)
   {
      DrawDashboard();
      return;
   }
   g_lastScan = TimeCurrent();
   
   // Daily trade limit check
   if(g_dailyTrades >= InpMaxDailyTrades)
   {
      DrawDashboard();
      return;
   }
   
   // Scan and score all pairs
   ScanMarkets();
   
   // Auto-rotation
   if(InpAutoStratRotation) AutoRotateStrategies();
   if(InpAutoPairRotation) AutoRotatePairs();
   
   // Find best opportunity
   int bestIdx = -1;
   double bestScore = 0;
   
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled) continue;
      if(g_pairs[i].confidence < InpMinConfidence) continue;
      if(g_pairs[i].strategy == STRAT_WAIT) continue;
      
      // Cooldown check
      if(TimeCurrent() - g_pairs[i].lastTradeTime < (int)InpTradeCooldownSec) continue;
      
      // Session filter
      if(InpAutoSessionFilter && !IsGoodSession()) continue;
      
      // Already have position on this pair?
      if(HasPosition(g_pairs[i].symbol)) continue;
      
      if(g_pairs[i].confidence > bestScore)
      {
         bestScore = g_pairs[i].confidence;
         bestIdx = i;
      }
   }
   
   // Execute best trade
   if(bestIdx >= 0)
   {
      ExecuteTrade(bestIdx);
   }
   
   DrawDashboard();
}

//+------------------------------------------------------------------+
//| SCAN ALL MARKETS                                                  |
//+------------------------------------------------------------------+
void ScanMarkets()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      string sym = g_pairs[i].symbol;
      
      if(!SymbolSelect(sym, true)) continue;
      if(SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
      
      // Get price data
      g_pairs[i].bid = SymbolInfoDouble(sym, SYMBOL_BID);
      g_pairs[i].ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      g_pairs[i].spread = (g_pairs[i].ask - g_pairs[i].bid) / SymbolInfoDouble(sym, SYMBOL_POINT);
      
      // Calculate indicators
      CalcIndicators(i);
      
      // Classify regime
      ClassifyRegime(i);
      
      // Select strategy
      SelectStrategy(i);
      
      // Calculate confidence score
      CalcConfidence(i);
   }
}

//+------------------------------------------------------------------+
//| CALCULATE INDICATORS                                              |
//+------------------------------------------------------------------+
void CalcIndicators(int idx)
{
   string sym = g_pairs[idx].symbol;
   
   // EMA 9, 21, 50 on M15
   int hEMA9 = iMA(sym, PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
   int hEMA21 = iMA(sym, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   int hEMA50 = iMA(sym, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   double ema9[], ema21[], ema50[];
   if(CopyBuffer(hEMA9, 0, 0, 1, ema9) > 0) g_pairs[idx].ema9 = ema9[0];
   if(CopyBuffer(hEMA21, 0, 0, 1, ema21) > 0) g_pairs[idx].ema21 = ema21[0];
   if(CopyBuffer(hEMA50, 0, 0, 1, ema50) > 0) g_pairs[idx].ema50 = ema50[0];
   
   // ADX
   int hADX = iADX(sym, PERIOD_M15, 14);
   double adxVal[];
   if(CopyBuffer(hADX, 0, 0, 1, adxVal) > 0) g_pairs[idx].adx = adxVal[0];
   
   // ATR
   int hATR = iATR(sym, PERIOD_M15, 14);
   double atrVal[];
   if(CopyBuffer(hATR, 0, 0, 3, atrVal) > 0)
   {
      g_pairs[idx].atr = atrVal[0];
      g_pairs[idx].atrSMA = (atrVal[0] + atrVal[1] + atrVal[2]) / 3.0;
   }
   
   // RSI 14 and RSI 7
   int hRSI14 = iRSI(sym, PERIOD_M15, 14, PRICE_CLOSE);
   int hRSI7 = iRSI(sym, PERIOD_M5, 7, PRICE_CLOSE);
   double rsi14[], rsi7[];
   if(CopyBuffer(hRSI14, 0, 0, 1, rsi14) > 0) g_pairs[idx].rsi14 = rsi14[0];
   if(CopyBuffer(hRSI7, 0, 0, 1, rsi7) > 0) g_pairs[idx].rsi7 = rsi7[0];
   
   // Bollinger Bands
   int hBB = iBands(sym, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
   double bbU[], bbL[], bbM[];
   if(CopyBuffer(hBB, 1, 0, 1, bbU) > 0) g_pairs[idx].bbUpper = bbU[0];
   if(CopyBuffer(hBB, 2, 0, 1, bbL) > 0) g_pairs[idx].bbLower = bbL[0];
   if(CopyBuffer(hBB, 0, 0, 1, bbM) > 0) g_pairs[idx].bbMid = bbM[0];
   
   // MACD
   int hMACD = iMACD(sym, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   double macdM[], macdS[];
   if(CopyBuffer(hMACD, 0, 0, 1, macdM) > 0) g_pairs[idx].macdMain = macdM[0];
   if(CopyBuffer(hMACD, 1, 0, 1, macdS) > 0) g_pairs[idx].macdSignal = macdS[0];
   
   // Previous day high/low
   double dailyHigh[], dailyLow[];
   if(CopyHigh(sym, PERIOD_D1, 1, 1, dailyHigh) > 0) g_pairs[idx].pdh = dailyHigh[0];
   if(CopyLow(sym, PERIOD_D1, 1, 1, dailyLow) > 0) g_pairs[idx].pdl = dailyLow[0];
   
   // Average spread (approximation)
   g_pairs[idx].avgSpread = g_pairs[idx].atr / SymbolInfoDouble(sym, SYMBOL_POINT) * 0.01;
   
   // Release handles
   IndicatorRelease(hEMA9);
   IndicatorRelease(hEMA21);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
   IndicatorRelease(hRSI14);
   IndicatorRelease(hRSI7);
   IndicatorRelease(hBB);
   IndicatorRelease(hMACD);
}

//+------------------------------------------------------------------+
//| CLASSIFY MARKET REGIME                                            |
//+------------------------------------------------------------------+
void ClassifyRegime(int idx)
{
   double adx = g_pairs[idx].adx;
   double atr = g_pairs[idx].atr;
   double atrSMA = g_pairs[idx].atrSMA;
   double ema9 = g_pairs[idx].ema9;
   double ema21 = g_pairs[idx].ema21;
   double ema50 = g_pairs[idx].ema50;
   double macdMain = g_pairs[idx].macdMain;
   
   // High volatility regime
   if(atr > atrSMA * 2.0)
   {
      g_pairs[idx].regime = REGIME_HIGH_VOLATILITY;
      return;
   }
   
   // Low liquidity
   if(atr < atrSMA * 0.3)
   {
      g_pairs[idx].regime = REGIME_LOW_LIQUIDITY;
      return;
   }
   
   // Strong trend
   if(adx > 25)
   {
      if(ema9 > ema21 && ema21 > ema50 && macdMain > 0)
         g_pairs[idx].regime = REGIME_TREND_BULL;
      else if(ema9 < ema21 && ema21 < ema50 && macdMain < 0)
         g_pairs[idx].regime = REGIME_TREND_BEAR;
      else if(macdMain > 0)
         g_pairs[idx].regime = REGIME_MOMENTUM_BULL;
      else
         g_pairs[idx].regime = REGIME_MOMENTUM_BEAR;
      return;
   }
   
   // Range
   if(adx < 20 && atr < atrSMA * 1.2)
   {
      g_pairs[idx].regime = REGIME_RANGE;
      return;
   }
   
   g_pairs[idx].regime = REGIME_UNKNOWN;
}

//+------------------------------------------------------------------+
//| SELECT STRATEGY BASED ON REGIME                                   |
//+------------------------------------------------------------------+
void SelectStrategy(int idx)
{
   ENUM_REGIME regime = g_pairs[idx].regime;
   
   switch(regime)
   {
      case REGIME_TREND_BULL:
      case REGIME_TREND_BEAR:
         g_pairs[idx].strategy = g_trendStats.enabled ? STRAT_TREND_PULLBACK : STRAT_WAIT;
         break;
      case REGIME_RANGE:
         g_pairs[idx].strategy = g_mrStats.enabled ? STRAT_MEAN_REVERSION : STRAT_WAIT;
         break;
      case REGIME_MOMENTUM_BULL:
      case REGIME_MOMENTUM_BEAR:
         g_pairs[idx].strategy = g_breakoutStats.enabled ? STRAT_BREAKOUT : STRAT_WAIT;
         break;
      case REGIME_HIGH_VOLATILITY:
         g_pairs[idx].strategy = STRAT_WAIT;
         break;
      case REGIME_LOW_LIQUIDITY:
         g_pairs[idx].strategy = STRAT_WAIT;
         break;
      default:
         g_pairs[idx].strategy = STRAT_WAIT;
         break;
   }
}

//+------------------------------------------------------------------+
//| CALCULATE AI CONFIDENCE SCORE                                     |
//+------------------------------------------------------------------+
void CalcConfidence(int idx)
{
   double score = 0;
   string sym = g_pairs[idx].symbol;
   double bid = g_pairs[idx].bid;
   ENUM_STRATEGY strat = g_pairs[idx].strategy;
   
   if(strat == STRAT_WAIT)
   {
      g_pairs[idx].confidence = 0;
      return;
   }
   
   // Factor 1: Trend Alignment (0-15)
   if(g_pairs[idx].ema9 > g_pairs[idx].ema21 && g_pairs[idx].ema21 > g_pairs[idx].ema50)
      score += 15;
   else if(g_pairs[idx].ema9 < g_pairs[idx].ema21 && g_pairs[idx].ema21 < g_pairs[idx].ema50)
      score += 15;
   else if(g_pairs[idx].ema9 > g_pairs[idx].ema21 || g_pairs[idx].ema9 < g_pairs[idx].ema21)
      score += 7;
   
   // Factor 2: Liquidity Sweep Check (0-20)
   double pdh = g_pairs[idx].pdh;
   double pdl = g_pairs[idx].pdl;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   
   if(pdh > 0 && pdl > 0)
   {
      // Swept PDH and reversed (bearish sweep)
      if(bid > pdh && g_pairs[idx].rsi14 > 70) score += 20;
      // Swept PDL and reversed (bullish sweep)
      else if(bid < pdl && g_pairs[idx].rsi14 < 30) score += 20;
      // Near liquidity zone
      else if(MathAbs(bid - pdh) < g_pairs[idx].atr * 0.5 || MathAbs(bid - pdl) < g_pairs[idx].atr * 0.5)
         score += 10;
   }
   
   // Factor 3: Volume/MACD Confirmation (0-15)
   if((g_pairs[idx].macdMain > g_pairs[idx].macdSignal && g_pairs[idx].regime == REGIME_TREND_BULL) ||
      (g_pairs[idx].macdMain < g_pairs[idx].macdSignal && g_pairs[idx].regime == REGIME_TREND_BEAR))
      score += 15;
   else if(MathAbs(g_pairs[idx].macdMain) > MathAbs(g_pairs[idx].macdSignal))
      score += 8;
   
   // Factor 4: Momentum/RSI (0-15)
   if(strat == STRAT_MEAN_REVERSION)
   {
      if(g_pairs[idx].rsi14 < 30 || g_pairs[idx].rsi14 > 70) score += 15;
      else if(g_pairs[idx].rsi14 < 35 || g_pairs[idx].rsi14 > 65) score += 8;
   }
   else
   {
      if(g_pairs[idx].rsi14 > 50 && g_pairs[idx].regime == REGIME_TREND_BULL) score += 15;
      else if(g_pairs[idx].rsi14 < 50 && g_pairs[idx].regime == REGIME_TREND_BEAR) score += 15;
      else score += 5;
   }
   
   // Factor 5: Order Block (0-15)
   // Simplified: price near BB boundary in ranging market
   if(strat == STRAT_MEAN_REVERSION)
   {
      double bbRange = g_pairs[idx].bbUpper - g_pairs[idx].bbLower;
      if(bbRange > 0)
      {
         double pos = (bid - g_pairs[idx].bbLower) / bbRange;
         if(pos < 0.15 || pos > 0.85) score += 15;
         else if(pos < 0.25 || pos > 0.75) score += 8;
      }
   }
   else
   {
      // For trend: price pulling back to EMA21
      double distToEMA = MathAbs(bid - g_pairs[idx].ema21);
      double atr = g_pairs[idx].atr;
      if(atr > 0 && distToEMA < atr * 0.5) score += 15;
      else if(atr > 0 && distToEMA < atr) score += 8;
   }
   
   // Factor 6: Session Quality (0-10)
   string session = GetCurrentSession();
   if(session == "LONDON" || session == "NEWYORK") score += 10;
   else if(session == "OVERLAP") score += 10;
   else score += 3;
   
   // Factor 7: Spread Quality (0-10)
   double spreadPts = g_pairs[idx].spread;
   double avgSpread = g_pairs[idx].avgSpread;
   if(avgSpread > 0)
   {
      double spreadRatio = spreadPts / MathMax(avgSpread, 1.0);
      if(spreadRatio < 1.0) score += 10;
      else if(spreadRatio < 1.5) score += 7;
      else if(spreadRatio < 2.0) score += 3;
      else score = 0;  // Spread too wide, kill score
   }
   else
      score += 5;
   
   g_pairs[idx].confidence = MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| DYNAMIC ACCOUNT CONTROL MANAGER - LOT CALCULATION                 |
//+------------------------------------------------------------------+
double CalcLotSize(int idx)
{
   double equity = g_account.Equity();
   double baseLot = InpMinLot;
   
   // Equity-tier based lot sizing
   if(InpUseTierLots)
   {
      if(equity < 50) baseLot = 0.01;
      else if(equity < 100) baseLot = 0.02;
      else if(equity < 250) baseLot = 0.03;
      else if(equity < 500) baseLot = 0.05;
      else if(equity < 1000) baseLot = 0.10;
      else if(equity < 2500) baseLot = 0.20;
      else if(equity < 5000) baseLot = 0.30;
      else
      {
         // Percentage-based for larger accounts
         double riskPct = GetAdaptiveRisk();
         double conf = g_pairs[idx].confidence;
         
         // Scale by confidence
         if(conf < InpConfSmall) riskPct *= 0.5;
         else if(conf < InpConfNormal) riskPct *= 0.75;
         else if(conf >= InpConfMax) riskPct *= 1.0;
         
         double riskAmount = equity * riskPct / 100.0;
         double sl = g_pairs[idx].atr * InpSLATRMult;
         
         string sym = g_pairs[idx].symbol;
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         
         if(tickValue > 0 && tickSize > 0 && sl > 0)
         {
            double slTicks = sl / tickSize;
            baseLot = riskAmount / (slTicks * tickValue);
         }
      }
   }
   else
   {
      // Pure percentage-based
      double riskPct = GetAdaptiveRisk();
      double conf = g_pairs[idx].confidence;
      
      if(conf < InpConfSmall) riskPct *= 0.5;
      else if(conf < InpConfNormal) riskPct *= 0.75;
      
      double riskAmount = equity * riskPct / 100.0;
      double sl = g_pairs[idx].atr * InpSLATRMult;
      
      string sym = g_pairs[idx].symbol;
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue > 0 && tickSize > 0 && sl > 0)
      {
         double slTicks = sl / tickSize;
         baseLot = riskAmount / (slTicks * tickValue);
      }
   }
   
   // Apply confidence scaling for tier accounts
   if(InpUseTierLots && equity < 5000)
   {
      double conf = g_pairs[idx].confidence;
      if(conf < InpConfSmall) baseLot *= 0.5;
      else if(conf >= InpConfMax) baseLot *= 1.5;
   }
   
   // Clamp to limits
   string sym = g_pairs[idx].symbol;
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   
   baseLot = MathMax(baseLot, minLot);
   baseLot = MathMin(baseLot, MathMin(maxLot, InpMaxLot));
   baseLot = MathFloor(baseLot / stepLot) * stepLot;
   
   return baseLot;
}

//+------------------------------------------------------------------+
//| ADAPTIVE RISK ENGINE                                              |
//+------------------------------------------------------------------+
double GetAdaptiveRisk()
{
   double risk = InpBaseRiskPct;
   
   // Win streak boost
   if(g_consecWins >= InpWinStreakThreshold)
      risk = InpRiskBoostPct;
   
   // Loss streak reduce
   if(g_consecLosses >= InpLossStreakReduce)
      risk = InpRiskReducePct;
   
   // Equity drawdown reduce
   double equity = g_account.Equity();
   double ddFromPeak = 0;
   if(g_dayHighEquity > 0)
      ddFromPeak = (g_dayHighEquity - equity) / g_dayHighEquity * 100;
   
   if(ddFromPeak > 1.0) risk *= 0.75;
   if(ddFromPeak > 1.5) risk *= 0.50;
   
   return MathMax(risk, 0.10);
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int idx)
{
   string sym = g_pairs[idx].symbol;
   ENUM_STRATEGY strat = g_pairs[idx].strategy;
   ENUM_REGIME regime = g_pairs[idx].regime;
   
   bool isBuy = false;
   
   // Determine direction based on strategy
   switch(strat)
   {
      case STRAT_TREND_PULLBACK:
         isBuy = (regime == REGIME_TREND_BULL);
         break;
      case STRAT_MEAN_REVERSION:
         isBuy = (g_pairs[idx].rsi14 < 35 && g_pairs[idx].bid < g_pairs[idx].bbLower + g_pairs[idx].atr * 0.2);
         if(!isBuy)
            isBuy = !(g_pairs[idx].rsi14 > 65 && g_pairs[idx].bid > g_pairs[idx].bbUpper - g_pairs[idx].atr * 0.2);
         break;
      case STRAT_BREAKOUT:
         isBuy = (regime == REGIME_MOMENTUM_BULL);
         break;
      default:
         return;
   }
   
   // Calculate lot size
   double lot = CalcLotSize(idx);
   if(lot <= 0) return;
   
   // Calculate SL and TP
   double atr = g_pairs[idx].atr;
   double sl = atr * InpSLATRMult;
   double tp = sl * InpMinRR;
   
   double entry, slPrice, tpPrice;
   
   if(isBuy)
   {
      entry = g_pairs[idx].ask;
      slPrice = entry - sl;
      tpPrice = entry + tp;
   }
   else
   {
      entry = g_pairs[idx].bid;
      slPrice = entry + sl;
      tpPrice = entry - tp;
   }
   
   // Slippage protection - check spread
   double spreadPts = g_pairs[idx].spread;
   if(g_pairs[idx].avgSpread > 0 && spreadPts > g_pairs[idx].avgSpread * 3.0)
   {
      Print("AI SCALPER PRO: Spread too wide on ", sym, " — skipping");
      return;
   }
   
   // Execute
   bool result = false;
   if(isBuy)
      result = g_trade.Buy(lot, sym, entry, slPrice, tpPrice, "ASP|" + GetStratName(strat));
   else
      result = g_trade.Sell(lot, sym, entry, slPrice, tpPrice, "ASP|" + GetStratName(strat));
   
   if(result)
   {
      // Register managed trade
      if(g_managedCount < 50)
      {
         g_managed[g_managedCount].ticket = g_trade.ResultOrder();
         g_managed[g_managedCount].symbol = sym;
         g_managed[g_managedCount].entryPrice = entry;
         g_managed[g_managedCount].initialSL = slPrice;
         g_managed[g_managedCount].currentSL = slPrice;
         g_managed[g_managedCount].initialLots = lot;
         g_managed[g_managedCount].currentLots = lot;
         g_managed[g_managedCount].isBuy = isBuy;
         g_managed[g_managedCount].beMoveDone = false;
         g_managed[g_managedCount].partialDone = false;
         g_managed[g_managedCount].trailing = false;
         g_managed[g_managedCount].maxProfitPips = 0;
         g_managed[g_managedCount].openTime = TimeCurrent();
         g_managed[g_managedCount].confidence = g_pairs[idx].confidence;
         g_managed[g_managedCount].stratName = GetStratName(strat);
         g_managedCount++;
      }
      
      g_pairs[idx].lastTradeTime = TimeCurrent();
      g_dailyTrades++;
      
      Print("AI SCALPER PRO: ", (isBuy ? "BUY" : "SELL"), " ", sym,
            " Lot=", DoubleToString(lot, 2),
            " Conf=", DoubleToString(g_pairs[idx].confidence, 0), "%",
            " Strat=", GetStratName(strat));
   }
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES                                                |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = g_managedCount - 1; i >= 0; i--)
   {
      ulong ticket = g_managed[i].ticket;
      
      // Check if position still exists
      if(!PositionSelectByTicket(ticket))
      {
         // Position closed — remove from managed
         RemoveManagedTrade(i);
         continue;
      }
      
      string sym = g_managed[i].symbol;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double entry = g_managed[i].entryPrice;
      bool isBuy = g_managed[i].isBuy;
      
      // Calculate profit in pips
      double profitPips = 0;
      if(isBuy)
         profitPips = (bid - entry) / point;
      else
         profitPips = (entry - ask) / point;
      
      // Track max profit
      if(profitPips > g_managed[i].maxProfitPips)
         g_managed[i].maxProfitPips = profitPips;
      
      // Convert thresholds to points
      double bePoints = InpBEMovePips / point * 10;  // pips to points
      double partialPoints = InpPartialClosePips / point * 10;
      
      // 1. Move to breakeven
      if(!g_managed[i].beMoveDone && profitPips >= bePoints)
      {
         double newSL = entry;
         if(isBuy)
            newSL = entry + point * 2;
         else
            newSL = entry - point * 2;
         
         if(g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
         {
            g_managed[i].beMoveDone = true;
            g_managed[i].currentSL = newSL;
         }
      }
      
      // 2. Partial close at target
      if(!g_managed[i].partialDone && profitPips >= partialPoints)
      {
         double closeVol = NormalizeDouble(g_managed[i].currentLots * InpPartialClosePct, 2);
         double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         
         if(closeVol >= minVol)
         {
            if(g_trade.PositionClosePartial(ticket, closeVol))
            {
               g_managed[i].partialDone = true;
               g_managed[i].currentLots -= closeVol;
            }
         }
         else
         {
            g_managed[i].partialDone = true;
         }
      }
      
      // 3. Trailing stop
      if(g_managed[i].beMoveDone && g_managed[i].partialDone)
      {
         g_managed[i].trailing = true;
         
         // ATR-based trailing
         int hATR = iATR(sym, PERIOD_M15, 14);
         double atrBuf[];
         if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0)
         {
            double trailDist = atrBuf[0] * InpTrailATRMult;
            double newSL = 0;
            
            if(isBuy)
            {
               newSL = bid - trailDist;
               if(newSL > g_managed[i].currentSL)
                  g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
            else
            {
               newSL = ask + trailDist;
               if(newSL < g_managed[i].currentSL || g_managed[i].currentSL == 0)
                  g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
            
            if(newSL != 0)
               g_managed[i].currentSL = newSL;
         }
         IndicatorRelease(hATR);
      }
      
      // 4. Momentum exit — if profit drops 50% from peak
      if(g_managed[i].maxProfitPips > partialPoints && profitPips < g_managed[i].maxProfitPips * 0.5)
      {
         if(g_managed[i].trailing)
         {
            g_trade.PositionClose(ticket);
            Print("AI SCALPER PRO: Momentum exit on ", sym);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER - SELF LEARNING                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   
   if(HistoryDealSelect(dealTicket))
   {
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(dealMagic != InpMagic) return;
      
      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) return;
      
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) + 
                      HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                      HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      string dealSym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
      
      bool isWin = (profit > 0);
      
      // Update totals
      g_totalTrades++;
      g_totalPnL += profit;
      g_dailyPnL += profit;
      g_weeklyPnL += profit;
      
      if(isWin)
      {
         g_totalWins++;
         g_consecWins++;
         g_consecLosses = 0;
      }
      else
      {
         g_totalLosses++;
         g_consecLosses++;
         g_consecWins = 0;
      }
      
      // Update pair stats
      for(int i = 0; i < g_pairCount; i++)
      {
         if(g_pairs[i].symbol == dealSym)
         {
            if(isWin) g_pairs[i].wins++;
            else g_pairs[i].losses++;
            g_pairs[i].pnl += profit;
            int totalPairTrades = g_pairs[i].wins + g_pairs[i].losses;
            g_pairs[i].winRate = (totalPairTrades > 0) ? (double)g_pairs[i].wins / totalPairTrades * 100 : 0;
            break;
         }
      }
      
      // Update session stats
      string session = GetCurrentSession();
      if(session == "LONDON")
      {
         g_londonStats.trades++;
         if(isWin) g_londonStats.wins++;
         g_londonStats.pnl += profit;
         g_londonStats.winRate = (g_londonStats.trades > 0) ? (double)g_londonStats.wins / g_londonStats.trades * 100 : 0;
      }
      else if(session == "NEWYORK" || session == "OVERLAP")
      {
         g_nyStats.trades++;
         if(isWin) g_nyStats.wins++;
         g_nyStats.pnl += profit;
         g_nyStats.winRate = (g_nyStats.trades > 0) ? (double)g_nyStats.wins / g_nyStats.trades * 100 : 0;
      }
      else if(session == "ASIAN")
      {
         g_asianStats.trades++;
         if(isWin) g_asianStats.wins++;
         g_asianStats.pnl += profit;
         g_asianStats.winRate = (g_asianStats.trades > 0) ? (double)g_asianStats.wins / g_asianStats.trades * 100 : 0;
      }
      
      // Update strategy stats
      string stratName = ExtractStrategy(comment);
      if(stratName == "TREND")
      {
         g_trendStats.trades++;
         if(isWin) g_trendStats.wins++;
         g_trendStats.pnl += profit;
         g_trendStats.winRate = (g_trendStats.trades > 0) ? (double)g_trendStats.wins / g_trendStats.trades * 100 : 0;
      }
      else if(stratName == "MR")
      {
         g_mrStats.trades++;
         if(isWin) g_mrStats.wins++;
         g_mrStats.pnl += profit;
         g_mrStats.winRate = (g_mrStats.trades > 0) ? (double)g_mrStats.wins / g_mrStats.trades * 100 : 0;
      }
      else if(stratName == "SCALP")
      {
         g_scalperStats.trades++;
         if(isWin) g_scalperStats.wins++;
         g_scalperStats.pnl += profit;
         g_scalperStats.winRate = (g_scalperStats.trades > 0) ? (double)g_scalperStats.wins / g_scalperStats.trades * 100 : 0;
      }
      else if(stratName == "BREAKOUT")
      {
         g_breakoutStats.trades++;
         if(isWin) g_breakoutStats.wins++;
         g_breakoutStats.pnl += profit;
         g_breakoutStats.winRate = (g_breakoutStats.trades > 0) ? (double)g_breakoutStats.wins / g_breakoutStats.trades * 100 : 0;
      }
      
      // Check consecutive loss halt
      if(g_consecLosses >= InpConsecStopAt)
      {
         g_consecHalt = true;
         g_haltTime = TimeCurrent();
         Print("AI SCALPER PRO: ", InpConsecStopAt, " consecutive losses — PAUSING");
      }
      
      // Check daily loss limit
      double dailyLossPct = 0;
      if(g_dayStartBalance > 0)
         dailyLossPct = -g_dailyPnL / g_dayStartBalance * 100;
      if(dailyLossPct >= InpDailyLossLimit)
      {
         g_dailyHalt = true;
         g_haltTime = TimeCurrent();
         Print("AI SCALPER PRO: Daily loss limit hit (", DoubleToString(dailyLossPct, 2), "%) — HALTING");
      }
      
      // Check weekly loss limit
      double weeklyLossPct = 0;
      if(g_weekStartBalance > 0)
         weeklyLossPct = -g_weeklyPnL / g_weekStartBalance * 100;
      if(weeklyLossPct >= InpWeeklyLossLimit)
      {
         g_weeklyHalt = true;
         g_haltTime = TimeCurrent();
         Print("AI SCALPER PRO: Weekly loss limit hit — HALTING");
      }
      
      // Log to CSV
      if(g_logFile != INVALID_HANDLE)
      {
         string regimeStr = EnumToString(g_pairs[0].regime);
         FileWrite(g_logFile, TimeToString(TimeCurrent()), dealSym, stratName, session,
                   DoubleToString(0, 0), DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
                   DoubleToString(profit, 2), isWin ? "WIN" : "LOSS",
                   DoubleToString(g_account.Balance(), 2), DoubleToString(g_account.Equity(), 2),
                   regimeStr);
         FileFlush(g_logFile);
      }
   }
}

//+------------------------------------------------------------------+
//| AUTO-ROTATE STRATEGIES                                            |
//+------------------------------------------------------------------+
void AutoRotateStrategies()
{
   // Disable poor-performing strategies
   if(g_trendStats.trades >= 10 && g_trendStats.winRate < InpStratDisableWR)
      g_trendStats.enabled = false;
   else if(g_trendStats.trades >= 10 && g_trendStats.winRate >= 45.0)
      g_trendStats.enabled = true;
   
   if(g_mrStats.trades >= 10 && g_mrStats.winRate < InpStratDisableWR)
      g_mrStats.enabled = false;
   else if(g_mrStats.trades >= 10 && g_mrStats.winRate >= 45.0)
      g_mrStats.enabled = true;
   
   if(g_scalperStats.trades >= 10 && g_scalperStats.winRate < InpStratDisableWR)
      g_scalperStats.enabled = false;
   else if(g_scalperStats.trades >= 10 && g_scalperStats.winRate >= 45.0)
      g_scalperStats.enabled = true;
   
   if(g_breakoutStats.trades >= 10 && g_breakoutStats.winRate < InpStratDisableWR)
      g_breakoutStats.enabled = false;
   else if(g_breakoutStats.trades >= 10 && g_breakoutStats.winRate >= 45.0)
      g_breakoutStats.enabled = true;
}

//+------------------------------------------------------------------+
//| AUTO-ROTATE PAIRS                                                 |
//+------------------------------------------------------------------+
void AutoRotatePairs()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      int totalTrades = g_pairs[i].wins + g_pairs[i].losses;
      if(totalTrades < InpPairMinTrades) continue;
      
      if(g_pairs[i].pnl < 0 && g_pairs[i].winRate < InpStratDisableWR)
         g_pairs[i].enabled = false;
      else if(g_pairs[i].pnl >= 0 || g_pairs[i].winRate >= 45.0)
         g_pairs[i].enabled = true;
   }
}

//+------------------------------------------------------------------+
//| CHECK DAY/WEEK RESET                                              |
//+------------------------------------------------------------------+
void CheckDayWeekReset()
{
   datetime currentDay = iTime(Symbol(), PERIOD_D1, 0);
   datetime currentWeek = iTime(Symbol(), PERIOD_W1, 0);
   
   if(currentDay != g_lastDay)
   {
      g_lastDay = currentDay;
      g_dailyPnL = 0;
      g_dailyTrades = 0;
      g_dailyHalt = false;
      g_dayStartBalance = g_account.Balance();
      g_dayHighEquity = g_account.Equity();
      Print("AI SCALPER PRO: New trading day — counters reset");
   }
   
   if(currentWeek != g_lastWeek)
   {
      g_lastWeek = currentWeek;
      g_weeklyPnL = 0;
      g_weeklyHalt = false;
      g_weekStartBalance = g_account.Balance();
      Print("AI SCALPER PRO: New trading week — weekly counters reset");
   }
}

//+------------------------------------------------------------------+
//| GET CURRENT SESSION                                               |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(hour >= 0 && hour < 7) return "ASIAN";
   if(hour >= 7 && hour < 12) return "LONDON";
   if(hour >= 12 && hour < 16) return "OVERLAP";
   if(hour >= 16 && hour < 21) return "NEWYORK";
   return "ASIAN";
}

//+------------------------------------------------------------------+
//| IS GOOD SESSION (for auto-session filter)                         |
//+------------------------------------------------------------------+
bool IsGoodSession()
{
   if(!InpAutoSessionFilter) return true;
   
   string session = GetCurrentSession();
   
   if(session == "LONDON" && g_londonStats.trades >= 10 && g_londonStats.winRate < InpSessionMinWR)
      return false;
   if((session == "NEWYORK" || session == "OVERLAP") && g_nyStats.trades >= 10 && g_nyStats.winRate < InpSessionMinWR)
      return false;
   if(session == "ASIAN" && g_asianStats.trades >= 10 && g_asianStats.winRate < InpSessionMinWR)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| HAS POSITION ON SYMBOL                                            |
//+------------------------------------------------------------------+
bool HasPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Symbol() == sym && g_position.Magic() == InpMagic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Magic() == InpMagic)
            g_trade.PositionClose(g_position.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| REMOVE MANAGED TRADE                                              |
//+------------------------------------------------------------------+
void RemoveManagedTrade(int index)
{
   for(int i = index; i < g_managedCount - 1; i++)
   {
      g_managed[i].ticket = g_managed[i+1].ticket;
      g_managed[i].symbol = g_managed[i+1].symbol;
      g_managed[i].entryPrice = g_managed[i+1].entryPrice;
      g_managed[i].initialSL = g_managed[i+1].initialSL;
      g_managed[i].currentSL = g_managed[i+1].currentSL;
      g_managed[i].initialLots = g_managed[i+1].initialLots;
      g_managed[i].currentLots = g_managed[i+1].currentLots;
      g_managed[i].isBuy = g_managed[i+1].isBuy;
      g_managed[i].beMoveDone = g_managed[i+1].beMoveDone;
      g_managed[i].partialDone = g_managed[i+1].partialDone;
      g_managed[i].trailing = g_managed[i+1].trailing;
      g_managed[i].maxProfitPips = g_managed[i+1].maxProfitPips;
      g_managed[i].openTime = g_managed[i+1].openTime;
      g_managed[i].confidence = g_managed[i+1].confidence;
      g_managed[i].stratName = g_managed[i+1].stratName;
   }
   g_managedCount--;
}

//+------------------------------------------------------------------+
//| GET STRATEGY NAME                                                 |
//+------------------------------------------------------------------+
string GetStratName(ENUM_STRATEGY strat)
{
   switch(strat)
   {
      case STRAT_TREND_PULLBACK: return "TREND";
      case STRAT_MEAN_REVERSION: return "MR";
      case STRAT_BREAKOUT: return "BREAKOUT";
      case STRAT_LIQ_SCALP: return "SCALP";
      default: return "WAIT";
   }
}

//+------------------------------------------------------------------+
//| EXTRACT STRATEGY FROM COMMENT                                     |
//+------------------------------------------------------------------+
string ExtractStrategy(string comment)
{
   if(StringFind(comment, "TREND") >= 0) return "TREND";
   if(StringFind(comment, "MR") >= 0) return "MR";
   if(StringFind(comment, "SCALP") >= 0) return "SCALP";
   if(StringFind(comment, "BREAKOUT") >= 0) return "BREAKOUT";
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| DRAW ON-CHART DASHBOARD                                           |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   color clrTitle = clrGold;
   color clrText = clrWhite;
   color clrGood = clrLime;
   color clrBad = clrRed;
   color clrWarn = clrOrange;
   
   string prefix = "ASP_";
   
   // Status
   string status = "AUTO TRADING";
   color statusClr = clrGood;
   if(g_dailyHalt) { status = "DAILY HALT"; statusClr = clrBad; }
   else if(g_weeklyHalt) { status = "WEEKLY HALT"; statusClr = clrBad; }
   else if(g_consecHalt) { status = "CONSEC HALT"; statusClr = clrWarn; }
   
   CreateLabel(prefix+"title", x, y, "══ AI SCALPER PRO v1.0 ══", clrTitle, 11); y += 20;
   CreateLabel(prefix+"status", x, y, "Status: " + status, statusClr, 10); y += 16;
   
   // Find best pair
   string bestPair = "---";
   double bestConf = 0;
   ENUM_REGIME bestRegime = REGIME_UNKNOWN;
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].confidence > bestConf)
      {
         bestConf = g_pairs[i].confidence;
         bestPair = g_pairs[i].symbol;
         bestRegime = g_pairs[i].regime;
      }
   }
   
   CreateLabel(prefix+"pair", x, y, "Best: " + bestPair, clrText, 10); y += 16;
   CreateLabel(prefix+"conf", x, y, "Conf: " + DoubleToString(bestConf, 0) + "%", 
               bestConf >= 80 ? clrGood : (bestConf >= 60 ? clrWarn : clrBad), 10); y += 16;
   CreateLabel(prefix+"regime", x, y, "Regime: " + EnumToString(bestRegime), clrText, 10); y += 20;
   
   // Account info
   double balance = g_account.Balance();
   double equity = g_account.Equity();
   double dailyPct = (g_dayStartBalance > 0) ? (equity - g_dayStartBalance) / g_dayStartBalance * 100 : 0;
   
   CreateLabel(prefix+"bal", x, y, "Balance: $" + DoubleToString(balance, 2), clrText, 10); y += 16;
   CreateLabel(prefix+"eq", x, y, "Equity: $" + DoubleToString(equity, 2), clrText, 10); y += 16;
   CreateLabel(prefix+"daily", x, y, "Daily: " + (dailyPct >= 0 ? "+" : "") + DoubleToString(dailyPct, 2) + "%",
               dailyPct >= 0 ? clrGood : clrBad, 10); y += 16;
   
   // Current lot tier
   double tierLot = GetCurrentTierLot(equity);
   CreateLabel(prefix+"lot", x, y, "Tier Lot: " + DoubleToString(tierLot, 2), clrText, 10); y += 16;
   
   // Risk mode
   double currentRisk = GetAdaptiveRisk();
   string riskLabel = "Risk: " + DoubleToString(currentRisk, 2) + "%";
   if(g_consecWins >= InpWinStreakThreshold) riskLabel += " (BOOSTED)";
   else if(g_consecLosses >= InpLossStreakReduce) riskLabel += " (REDUCED)";
   CreateLabel(prefix+"risk", x, y, riskLabel, clrText, 10); y += 20;
   
   // Stats
   double winRate = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   CreateLabel(prefix+"trades", x, y, "Trades: " + IntegerToString(g_totalTrades), clrText, 10); y += 16;
   CreateLabel(prefix+"wr", x, y, "WinRate: " + DoubleToString(winRate, 1) + "%",
               winRate >= 60 ? clrGood : (winRate >= 45 ? clrWarn : clrBad), 10); y += 16;
   CreateLabel(prefix+"pnl", x, y, "PnL: $" + DoubleToString(g_totalPnL, 2),
               g_totalPnL >= 0 ? clrGood : clrBad, 10); y += 16;
   CreateLabel(prefix+"streak", x, y, "W:" + IntegerToString(g_consecWins) + " L:" + IntegerToString(g_consecLosses), clrText, 10); y += 16;
   
   // Open positions
   int openCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i) && g_position.Magic() == InpMagic)
         openCount++;
   }
   CreateLabel(prefix+"open", x, y, "Open: " + IntegerToString(openCount), clrText, 10);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| CREATE LABEL HELPER                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| GET CURRENT TIER LOT (for display)                                |
//+------------------------------------------------------------------+
double GetCurrentTierLot(double equity)
{
   if(equity < 50) return 0.01;
   if(equity < 100) return 0.02;
   if(equity < 250) return 0.03;
   if(equity < 500) return 0.05;
   if(equity < 1000) return 0.10;
   if(equity < 2500) return 0.20;
   if(equity < 5000) return 0.30;
   return 0.50;
}

//+------------------------------------------------------------------+
//| PRINT PERFORMANCE REPORT                                          |
//+------------------------------------------------------------------+
void PrintPerformanceReport()
{
   Print("═══════════════════════════════════════════");
   Print("  AI SCALPER PRO — PERFORMANCE REPORT");
   Print("═══════════════════════════════════════════");
   Print("Total Trades: ", g_totalTrades);
   double winRate = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   Print("Win Rate: ", DoubleToString(winRate, 1), "%");
   Print("Total PnL: $", DoubleToString(g_totalPnL, 2));
   Print("───────────────────────────────────────────");
   Print("SESSION PERFORMANCE:");
   Print("  London:  Trades=", g_londonStats.trades, " WR=", DoubleToString(g_londonStats.winRate, 1), "% PnL=$", DoubleToString(g_londonStats.pnl, 2));
   Print("  NY:      Trades=", g_nyStats.trades, " WR=", DoubleToString(g_nyStats.winRate, 1), "% PnL=$", DoubleToString(g_nyStats.pnl, 2));
   Print("  Asian:   Trades=", g_asianStats.trades, " WR=", DoubleToString(g_asianStats.winRate, 1), "% PnL=$", DoubleToString(g_asianStats.pnl, 2));
   Print("───────────────────────────────────────────");
   Print("STRATEGY PERFORMANCE:");
   Print("  Trend:    Trades=", g_trendStats.trades, " WR=", DoubleToString(g_trendStats.winRate, 1), "% PnL=$", DoubleToString(g_trendStats.pnl, 2), (g_trendStats.enabled ? " [ON]" : " [OFF]"));
   Print("  MeanRev:  Trades=", g_mrStats.trades, " WR=", DoubleToString(g_mrStats.winRate, 1), "% PnL=$", DoubleToString(g_mrStats.pnl, 2), (g_mrStats.enabled ? " [ON]" : " [OFF]"));
   Print("  Scalper:  Trades=", g_scalperStats.trades, " WR=", DoubleToString(g_scalperStats.winRate, 1), "% PnL=$", DoubleToString(g_scalperStats.pnl, 2), (g_scalperStats.enabled ? " [ON]" : " [OFF]"));
   Print("  Breakout: Trades=", g_breakoutStats.trades, " WR=", DoubleToString(g_breakoutStats.winRate, 1), "% PnL=$", DoubleToString(g_breakoutStats.pnl, 2), (g_breakoutStats.enabled ? " [ON]" : " [OFF]"));
   Print("───────────────────────────────────────────");
   Print("PAIR PERFORMANCE:");
   for(int i = 0; i < g_pairCount; i++)
   {
      int totalTrades = g_pairs[i].wins + g_pairs[i].losses;
      if(totalTrades > 0)
         Print("  ", g_pairs[i].symbol, ": Trades=", totalTrades, " WR=", DoubleToString(g_pairs[i].winRate, 1), "% PnL=$", DoubleToString(g_pairs[i].pnl, 2), (g_pairs[i].enabled ? "" : " [DISABLED]"));
   }
   Print("═══════════════════════════════════════════");
}
//+------------------------------------------------------------------+
