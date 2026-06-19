//+------------------------------------------------------------------+
//|                                           AIQuantScalperX.mq5     |
//|                              AI QUANT SCALPER X v1.0              |
//|                    Multi-Layer Consensus Decision Engine          |
//+------------------------------------------------------------------+
#property copyright "AI Quant Scalper X"
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
input int      InpMagic              = 800000;          // Magic Number
input int      InpScanInterval       = 30;              // Scan interval (seconds)
input bool     InpFullAuto           = true;            // Full autonomous mode

input group "══════ MARKETS ══════"
input string   InpPairs              = "XAUUSD,EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,USDCHF,NAS100,US30,BTCUSD";

input group "══════ PORTFOLIO RISK MANAGEMENT ══════"
input double   InpMaxPortfolioRisk   = 3.0;            // Max total portfolio risk (%)
input double   InpMaxPerInstrument   = 1.0;            // Max risk per instrument (%)
input double   InpMaxCorrelation     = 0.70;           // Max correlation allowed
input int      InpMaxOpenPositions   = 5;              // Max simultaneous positions

input group "══════ POSITION SIZING ══════"
input bool     InpUseTierLots        = true;            // Use equity-tier lot sizing
input double   InpBaseRiskPct        = 0.50;            // Base risk % of equity
input double   InpMinLot             = 0.01;            // Minimum lot size
input double   InpMaxLot             = 5.00;            // Maximum lot size

input group "══════ ADAPTIVE RISK ENGINE ══════"
input double   InpRiskBoostPct       = 0.75;            // Risk after win streak
input double   InpRiskReducePct      = 0.25;            // Risk after loss streak
input int      InpWinStreakBoost     = 5;               // Win streak to boost
input int      InpLossStreakReduce   = 3;               // Loss streak to reduce

input group "══════ PROBABILITY ENGINE ══════"
input double   InpMinConfidence      = 60.0;            // Min confidence to trade
input double   InpConfSmall          = 74.0;            // Below = small position
input double   InpConfNormal         = 89.0;            // Below = normal position
input double   InpConfHigh           = 90.0;            // Above = high-confidence

input group "══════ CAPITAL PROTECTION ══════"
input double   InpDailyDDLimit       = 2.0;             // Daily drawdown limit (%)
input double   InpWeeklyDDLimit      = 5.0;             // Weekly drawdown limit (%)
input int      InpMaxDailyTrades     = 15;              // Max trades per day
input int      InpConsecStopAt       = 5;               // Stop after N consec losses
input double   InpEmergencyDD        = 10.0;            // Emergency stop drawdown (%)

input group "══════ TRADE MANAGEMENT ══════"
input double   InpSLATRMult          = 1.5;             // SL = ATR * multiplier
input double   InpMinRR              = 2.0;             // Minimum Reward:Risk
input double   InpBEPips             = 5.0;             // Move BE after X pips
input double   InpPartialPips        = 10.0;            // Partial close after X pips
input double   InpPartialPct         = 0.50;            // Close this % at partial
input double   InpTrailATR           = 1.0;             // Trail ATR multiplier
input double   InpMomentumExitPct    = 0.50;            // Exit if profit drops this % from peak
input double   InpCooldownSec        = 120;             // Seconds between trades per pair

input group "══════ LEARNING ENGINE ══════"
input bool     InpAutoStratRotation  = true;            // Auto-disable bad strategies
input double   InpStratDisableWR     = 35.0;            // Disable below this WR
input bool     InpAutoSessionFilter  = true;            // Skip bad sessions
input double   InpSessionMinWR       = 45.0;            // Min session WR
input bool     InpAutoPairRotation   = true;            // Disable losing pairs
input int      InpMinTradesEval      = 10;              // Min trades before evaluation

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_REGIME
{
   REGIME_TREND_BULL,
   REGIME_TREND_BEAR,
   REGIME_RANGE,
   REGIME_BREAKOUT_BULL,
   REGIME_BREAKOUT_BEAR,
   REGIME_CHAOTIC,
   REGIME_LOW_LIQUIDITY,
   REGIME_UNKNOWN
};

enum ENUM_STRATEGY
{
   STRAT_PULLBACK,
   STRAT_MOMENTUM,
   STRAT_MEAN_REVERSION,
   STRAT_BREAKOUT,
   STRAT_LIQ_SCALP,
   STRAT_NO_TRADE
};

enum ENUM_SIGNAL
{
   SIGNAL_BUY,
   SIGNAL_SELL,
   SIGNAL_NONE
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct PairData
{
   string      symbol;
   bool        enabled;
   double      score;
   ENUM_REGIME regime;
   ENUM_STRATEGY strategy;
   ENUM_SIGNAL signal;
   // Indicators
   double      adx, plusDI, minusDI;
   double      atr, atrSMA;
   double      ema9, ema21, ema50, ema200;
   double      rsi14, rsi7;
   double      bbUpper, bbLower, bbMid;
   double      macdMain, macdSignal, macdHist;
   double      bid, ask, spread;
   double      avgSpread;
   double      pdh, pdl;       // Previous day high/low
   double      aSessionH, aSessionL; // Asian session range
   // Scoring
   double      confidence;
   double      trendScore;
   double      mtfScore;
   double      liqScore;
   double      obScore;
   double      volScore;
   double      momentumScore;
   double      volatilityScore;
   double      spreadScore;
   // Performance
   datetime    lastTradeTime;
   int         wins, losses;
   double      pnl;
   double      winRate;
   double      currentRiskAlloc; // Current risk allocated
};

struct ManagedTrade
{
   ulong       ticket;
   string      symbol;
   double      entryPrice;
   double      initialSL, currentSL;
   double      initialTP;
   double      initialLots, currentLots;
   bool        isBuy;
   bool        beMoveDone, partialDone, trailing;
   double      maxProfitPips;
   double      entryMomentum;
   double      entryVolume;
   datetime    openTime;
   double      confidence;
   string      stratName;
   string      regime;
};

struct SessionStats
{
   int         trades;
   int         wins;
   double      pnl;
   double      winRate;
};

struct StrategyStats
{
   int         trades;
   int         wins;
   double      pnl;
   double      winRate;
   bool        enabled;
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

// Performance
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
double         g_peakEquity = 0;
datetime       g_lastDay = 0;
datetime       g_lastWeek = 0;
datetime       g_lastScan = 0;

// Halt flags
bool           g_dailyHalt = false;
bool           g_weeklyHalt = false;
bool           g_consecHalt = false;
bool           g_emergencyStop = false;
datetime       g_haltTime = 0;

// Portfolio tracking
double         g_totalRiskUsed = 0;

// Session stats
SessionStats   g_londonStats;
SessionStats   g_nyStats;
SessionStats   g_asianStats;
SessionStats   g_overlapStats;

// Strategy stats
StrategyStats  g_pullbackStats;
StrategyStats  g_momentumStats;
StrategyStats  g_mrStats;
StrategyStats  g_breakoutStats;
StrategyStats  g_liqStats;

// Log file
int            g_logFile = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Parse pairs
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
      g_pairs[i].currentRiskAlloc = 0;
      g_pairs[i].signal = SIGNAL_NONE;
   }
   
   // Init session stats
   ZeroMemory(g_londonStats);
   ZeroMemory(g_nyStats);
   ZeroMemory(g_asianStats);
   ZeroMemory(g_overlapStats);
   
   // Init strategy stats
   ZeroMemory(g_pullbackStats);  g_pullbackStats.enabled = true;
   ZeroMemory(g_momentumStats);  g_momentumStats.enabled = true;
   ZeroMemory(g_mrStats);        g_mrStats.enabled = true;
   ZeroMemory(g_breakoutStats);  g_breakoutStats.enabled = true;
   ZeroMemory(g_liqStats);       g_liqStats.enabled = true;
   
   // Account tracking
   g_dayStartBalance = g_account.Balance();
   g_weekStartBalance = g_account.Balance();
   g_dayHighEquity = g_account.Equity();
   g_peakEquity = g_account.Equity();
   g_lastDay = iTime(Symbol(), PERIOD_D1, 0);
   g_lastWeek = iTime(Symbol(), PERIOD_W1, 0);
   
   // Open log
   g_logFile = FileOpen("AQX_trades.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ, ',');
   if(g_logFile != INVALID_HANDLE)
   {
      FileSeek(g_logFile, 0, SEEK_END);
      if(FileTell(g_logFile) == 0)
         FileWrite(g_logFile, "Time", "Symbol", "Strategy", "Regime", "Session",
                   "Confidence", "Lot", "Profit", "Win", "Balance", "Equity",
                   "DailyPnL", "Drawdown");
   }
   
   Print("════════════════════════════════════════════");
   Print("  AI QUANT SCALPER X v1.0");
   Print("  Multi-Layer Consensus Decision Engine");
   Print("════════════════════════════════════════════");
   Print("  Mode: ", InpFullAuto ? "FULLY AUTONOMOUS" : "SEMI-AUTO");
   Print("  Pairs: ", g_pairCount);
   Print("  Portfolio Risk Cap: ", DoubleToString(InpMaxPortfolioRisk, 1), "%");
   Print("  Per-Instrument Cap: ", DoubleToString(InpMaxPerInstrument, 1), "%");
   Print("  Min Confidence: ", DoubleToString(InpMinConfidence, 0), "%");
   Print("  >>> ALL SYSTEMS ONLINE — SCANNING <<<");
   Print("════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logFile != INVALID_HANDLE) FileClose(g_logFile);
   ObjectsDeleteAll(0, "AQX_");
   PrintPerformanceReport();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Day/week reset
   CheckDayWeekReset();
   
   // Update equity tracking
   double equity = g_account.Equity();
   if(equity > g_dayHighEquity) g_dayHighEquity = equity;
   if(equity > g_peakEquity) g_peakEquity = equity;
   
   // Emergency stop check
   if(g_emergencyStop)
   {
      DrawDashboard();
      return;
   }
   
   // Check emergency drawdown
   if(g_peakEquity > 0)
   {
      double totalDD = (g_peakEquity - equity) / g_peakEquity * 100;
      if(totalDD >= InpEmergencyDD)
      {
         g_emergencyStop = true;
         CloseAllPositions();
         Print("▓▓▓ AI QUANT SCALPER X: EMERGENCY STOP — DD=", DoubleToString(totalDD, 2), "% ▓▓▓");
         DrawDashboard();
         return;
      }
   }
   
   // Halt checks
   if(g_dailyHalt || g_weeklyHalt || g_consecHalt)
   {
      // Auto-recovery after 30 minutes
      if(TimeCurrent() - g_haltTime > 1800)
      {
         if(g_consecHalt)
         {
            g_consecHalt = false;
            g_consecLosses = 0;
            Print("AQX: Consecutive loss halt lifted — cooldown complete");
         }
         if(g_dailyHalt)
         {
            double ddPct = (g_dayStartBalance > 0) ? 
                           (g_dayStartBalance - equity) / g_dayStartBalance * 100 : 0;
            if(ddPct < InpDailyDDLimit * 0.6)
            {
               g_dailyHalt = false;
               Print("AQX: Daily halt lifted — partial recovery");
            }
         }
      }
      ManageOpenTrades();
      DrawDashboard();
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
   
   // Daily limit
   if(g_dailyTrades >= InpMaxDailyTrades)
   {
      DrawDashboard();
      return;
   }
   
   // Portfolio risk check
   UpdatePortfolioRisk();
   if(g_totalRiskUsed >= InpMaxPortfolioRisk)
   {
      DrawDashboard();
      return;
   }
   
   // Max positions check
   int openCount = CountOpenPositions();
   if(openCount >= InpMaxOpenPositions)
   {
      DrawDashboard();
      return;
   }
   
   // ═══════════════════════════════════════
   // MULTI-LAYER DECISION ENGINE
   // ═══════════════════════════════════════
   
   // Layer 1: Scan all markets
   ScanMarkets();
   
   // Layer 2: Auto-rotation
   if(InpAutoStratRotation) AutoRotateStrategies();
   if(InpAutoPairRotation) AutoRotatePairs();
   
   // Layer 3: Find consensus opportunities
   int bestIdx = -1;
   double bestScore = 0;
   
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled) continue;
      if(g_pairs[i].confidence < InpMinConfidence) continue;
      if(g_pairs[i].strategy == STRAT_NO_TRADE) continue;
      if(g_pairs[i].signal == SIGNAL_NONE) continue;
      
      // Cooldown
      if(TimeCurrent() - g_pairs[i].lastTradeTime < (int)InpCooldownSec) continue;
      
      // Session filter
      if(InpAutoSessionFilter && !IsGoodSession()) continue;
      
      // Already positioned
      if(HasPosition(g_pairs[i].symbol)) continue;
      
      // Risk allocation check
      if(g_pairs[i].currentRiskAlloc + GetTradeRisk(i) > InpMaxPerInstrument) continue;
      
      // Portfolio capacity
      if(g_totalRiskUsed + GetTradeRisk(i) > InpMaxPortfolioRisk) continue;
      
      // Correlation check
      if(IsCorrelatedWithOpen(i)) continue;
      
      if(g_pairs[i].confidence > bestScore)
      {
         bestScore = g_pairs[i].confidence;
         bestIdx = i;
      }
   }
   
   // Layer 4: Execute if consensus
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
      
      g_pairs[i].bid = SymbolInfoDouble(sym, SYMBOL_BID);
      g_pairs[i].ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      g_pairs[i].spread = (g_pairs[i].ask - g_pairs[i].bid) / SymbolInfoDouble(sym, SYMBOL_POINT);
      
      // Calculate all indicators
      CalcIndicators(i);
      
      // Classify regime
      ClassifyRegime(i);
      
      // Select strategy
      SelectStrategy(i);
      
      // Generate signal (requires consensus)
      GenerateSignal(i);
      
      // Calculate 8-factor probability score
      CalcProbabilityScore(i);
   }
}

//+------------------------------------------------------------------+
//| CALCULATE INDICATORS                                              |
//+------------------------------------------------------------------+
void CalcIndicators(int idx)
{
   string sym = g_pairs[idx].symbol;
   
   // EMAs on M15
   int hE9 = iMA(sym, PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
   int hE21 = iMA(sym, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   int hE50 = iMA(sym, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   int hE200 = iMA(sym, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   double buf[];
   if(CopyBuffer(hE9, 0, 0, 1, buf) > 0) g_pairs[idx].ema9 = buf[0];
   if(CopyBuffer(hE21, 0, 0, 1, buf) > 0) g_pairs[idx].ema21 = buf[0];
   if(CopyBuffer(hE50, 0, 0, 1, buf) > 0) g_pairs[idx].ema50 = buf[0];
   if(CopyBuffer(hE200, 0, 0, 1, buf) > 0) g_pairs[idx].ema200 = buf[0];
   
   // ADX with +DI and -DI
   int hADX = iADX(sym, PERIOD_M15, 14);
   if(CopyBuffer(hADX, 0, 0, 1, buf) > 0) g_pairs[idx].adx = buf[0];
   if(CopyBuffer(hADX, 1, 0, 1, buf) > 0) g_pairs[idx].plusDI = buf[0];
   if(CopyBuffer(hADX, 2, 0, 1, buf) > 0) g_pairs[idx].minusDI = buf[0];
   
   // ATR
   int hATR = iATR(sym, PERIOD_M15, 14);
   double atrBuf[];
   if(CopyBuffer(hATR, 0, 0, 5, atrBuf) > 0)
   {
      g_pairs[idx].atr = atrBuf[0];
      g_pairs[idx].atrSMA = (atrBuf[0] + atrBuf[1] + atrBuf[2] + atrBuf[3] + atrBuf[4]) / 5.0;
   }
   
   // RSI
   int hRSI14 = iRSI(sym, PERIOD_M15, 14, PRICE_CLOSE);
   int hRSI7 = iRSI(sym, PERIOD_M5, 7, PRICE_CLOSE);
   if(CopyBuffer(hRSI14, 0, 0, 1, buf) > 0) g_pairs[idx].rsi14 = buf[0];
   if(CopyBuffer(hRSI7, 0, 0, 1, buf) > 0) g_pairs[idx].rsi7 = buf[0];
   
   // Bollinger Bands
   int hBB = iBands(sym, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
   if(CopyBuffer(hBB, 0, 0, 1, buf) > 0) g_pairs[idx].bbMid = buf[0];
   if(CopyBuffer(hBB, 1, 0, 1, buf) > 0) g_pairs[idx].bbUpper = buf[0];
   if(CopyBuffer(hBB, 2, 0, 1, buf) > 0) g_pairs[idx].bbLower = buf[0];
   
   // MACD
   int hMACD = iMACD(sym, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   if(CopyBuffer(hMACD, 0, 0, 1, buf) > 0) g_pairs[idx].macdMain = buf[0];
   if(CopyBuffer(hMACD, 1, 0, 1, buf) > 0) g_pairs[idx].macdSignal = buf[0];
   g_pairs[idx].macdHist = g_pairs[idx].macdMain - g_pairs[idx].macdSignal;
   
   // Previous day high/low
   double dH[], dL[];
   if(CopyHigh(sym, PERIOD_D1, 1, 1, dH) > 0) g_pairs[idx].pdh = dH[0];
   if(CopyLow(sym, PERIOD_D1, 1, 1, dL) > 0) g_pairs[idx].pdl = dL[0];
   
   // Asian session high/low (approximate: use H4 bar 1-2 during 0-7 UTC)
   double h4H[], h4L[];
   if(CopyHigh(sym, PERIOD_H4, 1, 2, h4H) > 0)
      g_pairs[idx].aSessionH = MathMax(h4H[0], h4H[1]);
   if(CopyLow(sym, PERIOD_H4, 1, 2, h4L) > 0)
      g_pairs[idx].aSessionL = MathMin(h4L[0], h4L[1]);
   
   // Average spread approximation
   if(g_pairs[idx].atr > 0)
      g_pairs[idx].avgSpread = g_pairs[idx].atr / SymbolInfoDouble(sym, SYMBOL_POINT) * 0.008;
   else
      g_pairs[idx].avgSpread = g_pairs[idx].spread;
   
   // Release
   IndicatorRelease(hE9); IndicatorRelease(hE21);
   IndicatorRelease(hE50); IndicatorRelease(hE200);
   IndicatorRelease(hADX); IndicatorRelease(hATR);
   IndicatorRelease(hRSI14); IndicatorRelease(hRSI7);
   IndicatorRelease(hBB); IndicatorRelease(hMACD);
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
   double plusDI = g_pairs[idx].plusDI;
   double minusDI = g_pairs[idx].minusDI;
   
   // Chaotic: very high volatility + low ADX (random moves)
   if(atr > atrSMA * 2.5 && adx < 20)
   {
      g_pairs[idx].regime = REGIME_CHAOTIC;
      return;
   }
   
   // Low liquidity
   if(atr < atrSMA * 0.3)
   {
      g_pairs[idx].regime = REGIME_LOW_LIQUIDITY;
      return;
   }
   
   // Breakout: high vol + strong ADX
   if(atr > atrSMA * 1.5 && adx > 30)
   {
      if(plusDI > minusDI)
         g_pairs[idx].regime = REGIME_BREAKOUT_BULL;
      else
         g_pairs[idx].regime = REGIME_BREAKOUT_BEAR;
      return;
   }
   
   // Strong trend
   if(adx > 25)
   {
      if(ema9 > ema21 && ema21 > ema50 && plusDI > minusDI)
         g_pairs[idx].regime = REGIME_TREND_BULL;
      else if(ema9 < ema21 && ema21 < ema50 && minusDI > plusDI)
         g_pairs[idx].regime = REGIME_TREND_BEAR;
      else if(plusDI > minusDI)
         g_pairs[idx].regime = REGIME_TREND_BULL;
      else
         g_pairs[idx].regime = REGIME_TREND_BEAR;
      return;
   }
   
   // Range
   if(adx < 22 && atr <= atrSMA * 1.3)
   {
      g_pairs[idx].regime = REGIME_RANGE;
      return;
   }
   
   g_pairs[idx].regime = REGIME_UNKNOWN;
}

//+------------------------------------------------------------------+
//| SELECT STRATEGY                                                   |
//+------------------------------------------------------------------+
void SelectStrategy(int idx)
{
   ENUM_REGIME regime = g_pairs[idx].regime;
   
   switch(regime)
   {
      case REGIME_TREND_BULL:
      case REGIME_TREND_BEAR:
         if(g_pullbackStats.enabled)
            g_pairs[idx].strategy = STRAT_PULLBACK;
         else if(g_momentumStats.enabled)
            g_pairs[idx].strategy = STRAT_MOMENTUM;
         else
            g_pairs[idx].strategy = STRAT_NO_TRADE;
         break;
         
      case REGIME_RANGE:
         if(g_mrStats.enabled)
            g_pairs[idx].strategy = STRAT_MEAN_REVERSION;
         else if(g_liqStats.enabled)
            g_pairs[idx].strategy = STRAT_LIQ_SCALP;
         else
            g_pairs[idx].strategy = STRAT_NO_TRADE;
         break;
         
      case REGIME_BREAKOUT_BULL:
      case REGIME_BREAKOUT_BEAR:
         if(g_breakoutStats.enabled)
            g_pairs[idx].strategy = STRAT_BREAKOUT;
         else
            g_pairs[idx].strategy = STRAT_NO_TRADE;
         break;
         
      case REGIME_CHAOTIC:
      case REGIME_LOW_LIQUIDITY:
      default:
         g_pairs[idx].strategy = STRAT_NO_TRADE;
         break;
   }
}

//+------------------------------------------------------------------+
//| GENERATE SIGNAL — REQUIRES MULTI-MODULE CONSENSUS                 |
//+------------------------------------------------------------------+
void GenerateSignal(int idx)
{
   g_pairs[idx].signal = SIGNAL_NONE;
   
   ENUM_STRATEGY strat = g_pairs[idx].strategy;
   if(strat == STRAT_NO_TRADE) return;
   
   double bid = g_pairs[idx].bid;
   bool structureBuy = false;
   bool structureSell = false;
   
   // ──── Module 1: Market Structure ────
   bool trendAligned = false;
   
   if(strat == STRAT_PULLBACK || strat == STRAT_MOMENTUM)
   {
      if(g_pairs[idx].regime == REGIME_TREND_BULL)
      {
         // Pullback condition: price near EMA21
         double dist = MathAbs(bid - g_pairs[idx].ema21);
         if(dist < g_pairs[idx].atr * 0.8)
         {
            structureBuy = true;
            trendAligned = true;
         }
      }
      else if(g_pairs[idx].regime == REGIME_TREND_BEAR)
      {
         double dist = MathAbs(bid - g_pairs[idx].ema21);
         if(dist < g_pairs[idx].atr * 0.8)
         {
            structureSell = true;
            trendAligned = true;
         }
      }
   }
   else if(strat == STRAT_MEAN_REVERSION || strat == STRAT_LIQ_SCALP)
   {
      // Near BB bands or PDH/PDL
      if(bid <= g_pairs[idx].bbLower + g_pairs[idx].atr * 0.2)
      {
         structureBuy = true;
         trendAligned = true;
      }
      else if(bid >= g_pairs[idx].bbUpper - g_pairs[idx].atr * 0.2)
      {
         structureSell = true;
         trendAligned = true;
      }
   }
   else if(strat == STRAT_BREAKOUT)
   {
      if(g_pairs[idx].regime == REGIME_BREAKOUT_BULL && bid > g_pairs[idx].pdh)
      {
         structureBuy = true;
         trendAligned = true;
      }
      else if(g_pairs[idx].regime == REGIME_BREAKOUT_BEAR && bid < g_pairs[idx].pdl)
      {
         structureSell = true;
         trendAligned = true;
      }
   }
   
   if(!structureBuy && !structureSell) return;
   
   // ──── Module 2: Momentum Confirmation ────
   bool momentumAgrees = false;
   
   if(structureBuy)
   {
      if(g_pairs[idx].macdHist > 0 || g_pairs[idx].rsi14 > 40)
         momentumAgrees = true;
   }
   else
   {
      if(g_pairs[idx].macdHist < 0 || g_pairs[idx].rsi14 < 60)
         momentumAgrees = true;
   }
   
   if(!momentumAgrees) return;
   
   // ──── Module 3: Volatility Check ────
   bool volOK = (g_pairs[idx].atr > g_pairs[idx].atrSMA * 0.5 && 
                 g_pairs[idx].atr < g_pairs[idx].atrSMA * 2.5);
   if(!volOK) return;
   
   // ──── Module 4: Spread Quality ────
   bool spreadOK = true;
   if(g_pairs[idx].avgSpread > 0)
   {
      double ratio = g_pairs[idx].spread / MathMax(g_pairs[idx].avgSpread, 1.0);
      if(ratio > 2.0) spreadOK = false;
   }
   if(!spreadOK) return;
   
   // ──── Module 5: Higher TF Alignment ────
   bool htfAligned = false;
   if(structureBuy && bid > g_pairs[idx].ema200)
      htfAligned = true;
   else if(structureSell && bid < g_pairs[idx].ema200)
      htfAligned = true;
   else if(strat == STRAT_MEAN_REVERSION)
      htfAligned = true;  // MR doesn't need HTF alignment
   
   // HTF is a strong filter but not absolute blocker for high-conf setups
   // We'll factor it into scoring instead
   
   // ──── ALL MODULES AGREE → Generate Signal ────
   if(structureBuy)
      g_pairs[idx].signal = SIGNAL_BUY;
   else if(structureSell)
      g_pairs[idx].signal = SIGNAL_SELL;
}

//+------------------------------------------------------------------+
//| CALCULATE 8-FACTOR PROBABILITY SCORE                              |
//+------------------------------------------------------------------+
void CalcProbabilityScore(int idx)
{
   if(g_pairs[idx].signal == SIGNAL_NONE)
   {
      g_pairs[idx].confidence = 0;
      return;
   }
   
   double score = 0;
   bool isBuy = (g_pairs[idx].signal == SIGNAL_BUY);
   double bid = g_pairs[idx].bid;
   string sym = g_pairs[idx].symbol;
   
   // Factor 1: Trend Alignment (0-15)
   if(isBuy)
   {
      if(g_pairs[idx].ema9 > g_pairs[idx].ema21 && g_pairs[idx].ema21 > g_pairs[idx].ema50)
         g_pairs[idx].trendScore = 15;
      else if(g_pairs[idx].ema9 > g_pairs[idx].ema21)
         g_pairs[idx].trendScore = 8;
      else
         g_pairs[idx].trendScore = 3;
   }
   else
   {
      if(g_pairs[idx].ema9 < g_pairs[idx].ema21 && g_pairs[idx].ema21 < g_pairs[idx].ema50)
         g_pairs[idx].trendScore = 15;
      else if(g_pairs[idx].ema9 < g_pairs[idx].ema21)
         g_pairs[idx].trendScore = 8;
      else
         g_pairs[idx].trendScore = 3;
   }
   score += g_pairs[idx].trendScore;
   
   // Factor 2: Multi-Timeframe Agreement (0-15)
   double mtf = 0;
   if(isBuy && bid > g_pairs[idx].ema200) mtf += 8;
   else if(!isBuy && bid < g_pairs[idx].ema200) mtf += 8;
   
   // H1 EMA check via ema50 on M15 ≈ H1 context
   if(isBuy && bid > g_pairs[idx].ema50) mtf += 7;
   else if(!isBuy && bid < g_pairs[idx].ema50) mtf += 7;
   g_pairs[idx].mtfScore = mtf;
   score += mtf;
   
   // Factor 3: Liquidity Sweep (0-20)
   double liqScore = 0;
   if(g_pairs[idx].pdh > 0 && g_pairs[idx].pdl > 0)
   {
      double atr = g_pairs[idx].atr;
      // Swept PDL and bouncing (bullish)
      if(isBuy && bid < g_pairs[idx].pdl + atr * 0.3 && g_pairs[idx].rsi14 < 35)
         liqScore = 20;
      // Swept PDH and rejecting (bearish)
      else if(!isBuy && bid > g_pairs[idx].pdh - atr * 0.3 && g_pairs[idx].rsi14 > 65)
         liqScore = 20;
      // Near Asian session liquidity
      else if(isBuy && bid < g_pairs[idx].aSessionL + atr * 0.2)
         liqScore = 14;
      else if(!isBuy && bid > g_pairs[idx].aSessionH - atr * 0.2)
         liqScore = 14;
      // Near PDH/PDL
      else if(MathAbs(bid - g_pairs[idx].pdh) < atr * 0.5 || 
              MathAbs(bid - g_pairs[idx].pdl) < atr * 0.5)
         liqScore = 8;
   }
   g_pairs[idx].liqScore = liqScore;
   score += liqScore;
   
   // Factor 4: Order Block / Support-Resistance (0-10)
   double obScore = 0;
   double bbRange = g_pairs[idx].bbUpper - g_pairs[idx].bbLower;
   if(bbRange > 0)
   {
      double pos = (bid - g_pairs[idx].bbLower) / bbRange;
      if(isBuy && pos < 0.20) obScore = 10;
      else if(!isBuy && pos > 0.80) obScore = 10;
      else if(isBuy && pos < 0.35) obScore = 6;
      else if(!isBuy && pos > 0.65) obScore = 6;
      else obScore = 2;
   }
   g_pairs[idx].obScore = obScore;
   score += obScore;
   
   // Factor 5: Volume / MACD (0-10)
   double volScore = 0;
   if(isBuy && g_pairs[idx].macdHist > 0) volScore = 10;
   else if(!isBuy && g_pairs[idx].macdHist < 0) volScore = 10;
   else if(MathAbs(g_pairs[idx].macdHist) < MathAbs(g_pairs[idx].macdMain) * 0.3) volScore = 4;
   else volScore = 2;
   g_pairs[idx].volScore = volScore;
   score += volScore;
   
   // Factor 6: Momentum (0-10)
   double momScore = 0;
   if(isBuy)
   {
      if(g_pairs[idx].rsi14 > 50 && g_pairs[idx].rsi14 < 70) momScore = 10;
      else if(g_pairs[idx].rsi14 > 40) momScore = 6;
      else momScore = 2;
   }
   else
   {
      if(g_pairs[idx].rsi14 < 50 && g_pairs[idx].rsi14 > 30) momScore = 10;
      else if(g_pairs[idx].rsi14 < 60) momScore = 6;
      else momScore = 2;
   }
   g_pairs[idx].momentumScore = momScore;
   score += momScore;
   
   // Factor 7: Volatility Quality (0-10)
   double vqScore = 0;
   if(g_pairs[idx].atrSMA > 0)
   {
      double atrRatio = g_pairs[idx].atr / g_pairs[idx].atrSMA;
      if(atrRatio >= 0.8 && atrRatio <= 1.5) vqScore = 10;
      else if(atrRatio >= 0.6 && atrRatio <= 2.0) vqScore = 6;
      else vqScore = 2;
   }
   g_pairs[idx].volatilityScore = vqScore;
   score += vqScore;
   
   // Factor 8: Spread & Execution Quality (0-10)
   double spScore = 0;
   if(g_pairs[idx].avgSpread > 0)
   {
      double ratio = g_pairs[idx].spread / MathMax(g_pairs[idx].avgSpread, 1.0);
      if(ratio < 0.8) spScore = 10;
      else if(ratio < 1.2) spScore = 8;
      else if(ratio < 1.5) spScore = 5;
      else spScore = 1;
   }
   else
      spScore = 5;
   g_pairs[idx].spreadScore = spScore;
   score += spScore;
   
   g_pairs[idx].confidence = MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
//+------------------------------------------------------------------+
double CalcLotSize(int idx)
{
   double equity = g_account.Equity();
   double riskPct = GetAdaptiveRisk();
   double confidence = g_pairs[idx].confidence;
   
   // Scale risk by confidence band
   if(confidence < InpConfSmall) riskPct *= 0.50;       // Small position
   else if(confidence < InpConfNormal) riskPct *= 0.75; // Normal
   else riskPct *= 1.0;                                 // High confidence
   
   double lot = InpMinLot;
   
   if(InpUseTierLots && equity < 5000)
   {
      // Tier-based for small accounts
      if(equity < 50) lot = 0.01;
      else if(equity < 100) lot = 0.02;
      else if(equity < 250) lot = 0.05;
      else if(equity < 500) lot = 0.10;
      else if(equity < 1000) lot = 0.20;
      else if(equity < 2500) lot = 0.30;
      else lot = 0.40;
      
      // Scale by confidence
      if(confidence < InpConfSmall) lot *= 0.5;
      else if(confidence >= InpConfHigh) lot *= 1.25;
   }
   else
   {
      // Risk-based calculation
      double riskAmount = equity * riskPct / 100.0;
      double sl = g_pairs[idx].atr * InpSLATRMult;
      
      string sym = g_pairs[idx].symbol;
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue > 0 && tickSize > 0 && sl > 0)
      {
         double slTicks = sl / tickSize;
         lot = riskAmount / (slTicks * tickValue);
      }
   }
   
   // Normalize
   string sym = g_pairs[idx].symbol;
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, InpMaxLot));
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| ADAPTIVE RISK                                                     |
//+------------------------------------------------------------------+
double GetAdaptiveRisk()
{
   double risk = InpBaseRiskPct;
   
   // Win streak boost
   if(g_consecWins >= InpWinStreakBoost)
      risk = InpRiskBoostPct;
   
   // Loss streak reduce
   if(g_consecLosses >= InpLossStreakReduce)
      risk = InpRiskReducePct;
   
   // Drawdown reducer
   double equity = g_account.Equity();
   if(g_dayHighEquity > 0)
   {
      double dd = (g_dayHighEquity - equity) / g_dayHighEquity * 100;
      if(dd > 1.0) risk *= 0.75;
      if(dd > 1.5) risk *= 0.50;
   }
   
   return MathMax(risk, 0.10);
}

//+------------------------------------------------------------------+
//| GET TRADE RISK                                                    |
//+------------------------------------------------------------------+
double GetTradeRisk(int idx)
{
   double riskPct = GetAdaptiveRisk();
   double confidence = g_pairs[idx].confidence;
   
   if(confidence < InpConfSmall) riskPct *= 0.50;
   else if(confidence < InpConfNormal) riskPct *= 0.75;
   
   return riskPct;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int idx)
{
   string sym = g_pairs[idx].symbol;
   bool isBuy = (g_pairs[idx].signal == SIGNAL_BUY);
   
   double lot = CalcLotSize(idx);
   if(lot <= 0) return;
   
   // SL/TP
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
   
   // Final spread check
   if(g_pairs[idx].avgSpread > 0 && g_pairs[idx].spread > g_pairs[idx].avgSpread * 3.0)
   {
      Print("AQX: Spread filter blocked trade on ", sym);
      return;
   }
   
   string stratName = GetStratName(g_pairs[idx].strategy);
   string comment = "AQX|" + stratName + "|" + DoubleToString(g_pairs[idx].confidence, 0);
   
   bool result = false;
   if(isBuy)
      result = g_trade.Buy(lot, sym, entry, slPrice, tpPrice, comment);
   else
      result = g_trade.Sell(lot, sym, entry, slPrice, tpPrice, comment);
   
   if(result)
   {
      // Register in managed trades
      if(g_managedCount < 50)
      {
         g_managed[g_managedCount].ticket = g_trade.ResultOrder();
         g_managed[g_managedCount].symbol = sym;
         g_managed[g_managedCount].entryPrice = entry;
         g_managed[g_managedCount].initialSL = slPrice;
         g_managed[g_managedCount].currentSL = slPrice;
         g_managed[g_managedCount].initialTP = tpPrice;
         g_managed[g_managedCount].initialLots = lot;
         g_managed[g_managedCount].currentLots = lot;
         g_managed[g_managedCount].isBuy = isBuy;
         g_managed[g_managedCount].beMoveDone = false;
         g_managed[g_managedCount].partialDone = false;
         g_managed[g_managedCount].trailing = false;
         g_managed[g_managedCount].maxProfitPips = 0;
         g_managed[g_managedCount].entryMomentum = g_pairs[idx].macdHist;
         g_managed[g_managedCount].entryVolume = g_pairs[idx].atr;
         g_managed[g_managedCount].openTime = TimeCurrent();
         g_managed[g_managedCount].confidence = g_pairs[idx].confidence;
         g_managed[g_managedCount].stratName = stratName;
         g_managed[g_managedCount].regime = EnumToString(g_pairs[idx].regime);
         g_managedCount++;
      }
      
      g_pairs[idx].lastTradeTime = TimeCurrent();
      g_pairs[idx].currentRiskAlloc += GetTradeRisk(idx);
      g_dailyTrades++;
      
      Print("AQX: ", (isBuy ? "BUY" : "SELL"), " ", sym,
            " Lot=", DoubleToString(lot, 2),
            " Conf=", DoubleToString(g_pairs[idx].confidence, 0), "%",
            " Strat=", stratName,
            " Regime=", EnumToString(g_pairs[idx].regime));
   }
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES — DYNAMIC MANAGEMENT                          |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = g_managedCount - 1; i >= 0; i--)
   {
      ulong ticket = g_managed[i].ticket;
      
      if(!PositionSelectByTicket(ticket))
      {
         RemoveManagedTrade(i);
         continue;
      }
      
      string sym = g_managed[i].symbol;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double entry = g_managed[i].entryPrice;
      bool isBuy = g_managed[i].isBuy;
      
      // Profit in pips
      double profitPips = 0;
      if(isBuy)
         profitPips = (bid - entry) / point;
      else
         profitPips = (entry - ask) / point;
      
      if(profitPips > g_managed[i].maxProfitPips)
         g_managed[i].maxProfitPips = profitPips;
      
      double bePoints = InpBEPips / point * 10;
      double partialPoints = InpPartialPips / point * 10;
      
      // ──── Dynamic Management ────
      
      // 1. Move to breakeven
      if(!g_managed[i].beMoveDone && profitPips >= bePoints)
      {
         double newSL = entry;
         if(isBuy) newSL = entry + point * 3;
         else newSL = entry - point * 3;
         
         if(g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
         {
            g_managed[i].beMoveDone = true;
            g_managed[i].currentSL = newSL;
         }
      }
      
      // 2. Partial close
      if(!g_managed[i].partialDone && profitPips >= partialPoints)
      {
         double closeVol = NormalizeDouble(g_managed[i].currentLots * InpPartialPct, 2);
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
            g_managed[i].partialDone = true;
      }
      
      // 3. ATR trailing stop
      if(g_managed[i].beMoveDone && g_managed[i].partialDone)
      {
         g_managed[i].trailing = true;
         
         int hATR = iATR(sym, PERIOD_M15, 14);
         double atrBuf[];
         if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0)
         {
            double trailDist = atrBuf[0] * InpTrailATR;
            
            if(isBuy)
            {
               double newSL = bid - trailDist;
               if(newSL > g_managed[i].currentSL)
               {
                  g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  g_managed[i].currentSL = newSL;
               }
            }
            else
            {
               double newSL = ask + trailDist;
               if(newSL < g_managed[i].currentSL)
               {
                  g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  g_managed[i].currentSL = newSL;
               }
            }
         }
         IndicatorRelease(hATR);
      }
      
      // 4. Momentum deterioration exit
      if(g_managed[i].maxProfitPips > partialPoints && g_managed[i].trailing)
      {
         if(profitPips < g_managed[i].maxProfitPips * InpMomentumExitPct)
         {
            g_trade.PositionClose(ticket);
            Print("AQX: Momentum exit on ", sym, " — profit faded from peak");
         }
      }
      
      // 5. Time-based exit: close if no progress after 2 hours
      if(TimeCurrent() - g_managed[i].openTime > 7200)
      {
         if(profitPips < bePoints * 0.5 && !g_managed[i].beMoveDone)
         {
            g_trade.PositionClose(ticket);
            Print("AQX: Time exit on ", sym, " — no progress in 2h");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION — SELF-LEARNING                                 |
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
   string dealSym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
   
   bool isWin = (profit > 0);
   
   // Update totals
   g_totalTrades++;
   g_totalPnL += profit;
   g_dailyPnL += profit;
   g_weeklyPnL += profit;
   
   if(isWin) { g_totalWins++; g_consecWins++; g_consecLosses = 0; }
   else      { g_totalLosses++; g_consecLosses++; g_consecWins = 0; }
   
   // Update pair stats
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].symbol == dealSym)
      {
         if(isWin) g_pairs[i].wins++;
         else g_pairs[i].losses++;
         g_pairs[i].pnl += profit;
         int t = g_pairs[i].wins + g_pairs[i].losses;
         g_pairs[i].winRate = (t > 0) ? (double)g_pairs[i].wins / t * 100 : 0;
         // Release risk allocation on close
         g_pairs[i].currentRiskAlloc = MathMax(0, g_pairs[i].currentRiskAlloc - InpBaseRiskPct);
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
   else if(session == "NEWYORK")
   {
      g_nyStats.trades++;
      if(isWin) g_nyStats.wins++;
      g_nyStats.pnl += profit;
      g_nyStats.winRate = (g_nyStats.trades > 0) ? (double)g_nyStats.wins / g_nyStats.trades * 100 : 0;
   }
   else if(session == "OVERLAP")
   {
      g_overlapStats.trades++;
      if(isWin) g_overlapStats.wins++;
      g_overlapStats.pnl += profit;
      g_overlapStats.winRate = (g_overlapStats.trades > 0) ? (double)g_overlapStats.wins / g_overlapStats.trades * 100 : 0;
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
   if(stratName == "PULLBACK")
   {
      g_pullbackStats.trades++;
      if(isWin) g_pullbackStats.wins++;
      g_pullbackStats.pnl += profit;
      g_pullbackStats.winRate = (g_pullbackStats.trades > 0) ? (double)g_pullbackStats.wins / g_pullbackStats.trades * 100 : 0;
   }
   else if(stratName == "MOMENTUM")
   {
      g_momentumStats.trades++;
      if(isWin) g_momentumStats.wins++;
      g_momentumStats.pnl += profit;
      g_momentumStats.winRate = (g_momentumStats.trades > 0) ? (double)g_momentumStats.wins / g_momentumStats.trades * 100 : 0;
   }
   else if(stratName == "MR")
   {
      g_mrStats.trades++;
      if(isWin) g_mrStats.wins++;
      g_mrStats.pnl += profit;
      g_mrStats.winRate = (g_mrStats.trades > 0) ? (double)g_mrStats.wins / g_mrStats.trades * 100 : 0;
   }
   else if(stratName == "BREAKOUT")
   {
      g_breakoutStats.trades++;
      if(isWin) g_breakoutStats.wins++;
      g_breakoutStats.pnl += profit;
      g_breakoutStats.winRate = (g_breakoutStats.trades > 0) ? (double)g_breakoutStats.wins / g_breakoutStats.trades * 100 : 0;
   }
   else if(stratName == "LIQSCALP")
   {
      g_liqStats.trades++;
      if(isWin) g_liqStats.wins++;
      g_liqStats.pnl += profit;
      g_liqStats.winRate = (g_liqStats.trades > 0) ? (double)g_liqStats.wins / g_liqStats.trades * 100 : 0;
   }
   
   // Halt checks
   if(g_consecLosses >= InpConsecStopAt)
   {
      g_consecHalt = true;
      g_haltTime = TimeCurrent();
      Print("AQX: ", InpConsecStopAt, " consecutive losses — PAUSING");
   }
   
   if(g_dayStartBalance > 0)
   {
      double ddPct = -g_dailyPnL / g_dayStartBalance * 100;
      if(ddPct >= InpDailyDDLimit)
      {
         g_dailyHalt = true;
         g_haltTime = TimeCurrent();
         Print("AQX: Daily DD limit hit (", DoubleToString(ddPct, 2), "%) — HALTING");
      }
   }
   
   if(g_weekStartBalance > 0)
   {
      double wddPct = -g_weeklyPnL / g_weekStartBalance * 100;
      if(wddPct >= InpWeeklyDDLimit)
      {
         g_weeklyHalt = true;
         g_haltTime = TimeCurrent();
         Print("AQX: Weekly DD limit hit — HALTING");
      }
   }
   
   // Log to CSV
   if(g_logFile != INVALID_HANDLE)
   {
      double equity = g_account.Equity();
      double dd = (g_peakEquity > 0) ? (g_peakEquity - equity) / g_peakEquity * 100 : 0;
      FileWrite(g_logFile, TimeToString(TimeCurrent()), dealSym, stratName, "", session,
                "", DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
                DoubleToString(profit, 2), isWin ? "WIN" : "LOSS",
                DoubleToString(g_account.Balance(), 2), DoubleToString(equity, 2),
                DoubleToString(g_dailyPnL, 2), DoubleToString(dd, 2));
      FileFlush(g_logFile);
   }
}

//+------------------------------------------------------------------+
//| AUTO-ROTATE STRATEGIES                                            |
//+------------------------------------------------------------------+
void AutoRotateStrategies()
{
   if(g_pullbackStats.trades >= InpMinTradesEval)
   {
      if(g_pullbackStats.winRate < InpStratDisableWR) g_pullbackStats.enabled = false;
      else if(g_pullbackStats.winRate >= 45.0) g_pullbackStats.enabled = true;
   }
   if(g_momentumStats.trades >= InpMinTradesEval)
   {
      if(g_momentumStats.winRate < InpStratDisableWR) g_momentumStats.enabled = false;
      else if(g_momentumStats.winRate >= 45.0) g_momentumStats.enabled = true;
   }
   if(g_mrStats.trades >= InpMinTradesEval)
   {
      if(g_mrStats.winRate < InpStratDisableWR) g_mrStats.enabled = false;
      else if(g_mrStats.winRate >= 45.0) g_mrStats.enabled = true;
   }
   if(g_breakoutStats.trades >= InpMinTradesEval)
   {
      if(g_breakoutStats.winRate < InpStratDisableWR) g_breakoutStats.enabled = false;
      else if(g_breakoutStats.winRate >= 45.0) g_breakoutStats.enabled = true;
   }
   if(g_liqStats.trades >= InpMinTradesEval)
   {
      if(g_liqStats.winRate < InpStratDisableWR) g_liqStats.enabled = false;
      else if(g_liqStats.winRate >= 45.0) g_liqStats.enabled = true;
   }
}

//+------------------------------------------------------------------+
//| AUTO-ROTATE PAIRS                                                 |
//+------------------------------------------------------------------+
void AutoRotatePairs()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      int total = g_pairs[i].wins + g_pairs[i].losses;
      if(total < InpMinTradesEval) continue;
      
      if(g_pairs[i].pnl < 0 && g_pairs[i].winRate < InpStratDisableWR)
         g_pairs[i].enabled = false;
      else if(g_pairs[i].pnl >= 0 || g_pairs[i].winRate >= 45.0)
         g_pairs[i].enabled = true;
   }
}

//+------------------------------------------------------------------+
//| UPDATE PORTFOLIO RISK                                             |
//+------------------------------------------------------------------+
void UpdatePortfolioRisk()
{
   g_totalRiskUsed = 0;
   for(int i = 0; i < g_pairCount; i++)
      g_totalRiskUsed += g_pairs[i].currentRiskAlloc;
}

//+------------------------------------------------------------------+
//| IS CORRELATED WITH OPEN POSITIONS                                 |
//+------------------------------------------------------------------+
bool IsCorrelatedWithOpen(int idx)
{
   string sym = g_pairs[idx].symbol;
   
   // Simple correlation check based on currency exposure
   // USD pairs: if already long USD via EURUSD short, don't short GBPUSD
   string base = StringSubstr(sym, 0, 3);
   string quote = StringSubstr(sym, 3, 3);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_position.SelectByIndex(i)) continue;
      if(g_position.Magic() != InpMagic) continue;
      
      string posSym = g_position.Symbol();
      if(posSym == sym) continue;
      
      string posBase = StringSubstr(posSym, 0, 3);
      string posQuote = StringSubstr(posSym, 3, 3);
      
      // Same base or quote = correlated
      if(base == posBase || base == posQuote || quote == posBase || quote == posQuote)
      {
         // Count how many correlated positions we already have
         int corrCount = 0;
         for(int j = PositionsTotal() - 1; j >= 0; j--)
         {
            if(!g_position.SelectByIndex(j)) continue;
            if(g_position.Magic() != InpMagic) continue;
            string pSym = g_position.Symbol();
            string pB = StringSubstr(pSym, 0, 3);
            string pQ = StringSubstr(pSym, 3, 3);
            if(base == pB || base == pQ || quote == pB || quote == pQ)
               corrCount++;
         }
         
         if(corrCount >= 2) return true;  // Too correlated
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| COUNT OPEN POSITIONS                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i) && g_position.Magic() == InpMagic)
         count++;
   }
   return count;
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
      if(g_position.SelectByIndex(i) && g_position.Magic() == InpMagic)
         g_trade.PositionClose(g_position.Ticket());
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
      g_managed[i].initialTP = g_managed[i+1].initialTP;
      g_managed[i].initialLots = g_managed[i+1].initialLots;
      g_managed[i].currentLots = g_managed[i+1].currentLots;
      g_managed[i].isBuy = g_managed[i+1].isBuy;
      g_managed[i].beMoveDone = g_managed[i+1].beMoveDone;
      g_managed[i].partialDone = g_managed[i+1].partialDone;
      g_managed[i].trailing = g_managed[i+1].trailing;
      g_managed[i].maxProfitPips = g_managed[i+1].maxProfitPips;
      g_managed[i].entryMomentum = g_managed[i+1].entryMomentum;
      g_managed[i].entryVolume = g_managed[i+1].entryVolume;
      g_managed[i].openTime = g_managed[i+1].openTime;
      g_managed[i].confidence = g_managed[i+1].confidence;
      g_managed[i].stratName = g_managed[i+1].stratName;
      g_managed[i].regime = g_managed[i+1].regime;
   }
   g_managedCount--;
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
      
      // Reset per-instrument risk allocation
      for(int i = 0; i < g_pairCount; i++)
         g_pairs[i].currentRiskAlloc = 0;
      
      Print("AQX: New trading day — all daily counters reset");
   }
   
   if(currentWeek != g_lastWeek)
   {
      g_lastWeek = currentWeek;
      g_weeklyPnL = 0;
      g_weeklyHalt = false;
      g_weekStartBalance = g_account.Balance();
      Print("AQX: New trading week — weekly counters reset");
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
//| IS GOOD SESSION                                                   |
//+------------------------------------------------------------------+
bool IsGoodSession()
{
   string session = GetCurrentSession();
   
   if(session == "LONDON" && g_londonStats.trades >= InpMinTradesEval && g_londonStats.winRate < InpSessionMinWR)
      return false;
   if(session == "NEWYORK" && g_nyStats.trades >= InpMinTradesEval && g_nyStats.winRate < InpSessionMinWR)
      return false;
   if(session == "OVERLAP" && g_overlapStats.trades >= InpMinTradesEval && g_overlapStats.winRate < InpSessionMinWR)
      return false;
   if(session == "ASIAN" && g_asianStats.trades >= InpMinTradesEval && g_asianStats.winRate < InpSessionMinWR)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| GET STRATEGY NAME                                                 |
//+------------------------------------------------------------------+
string GetStratName(ENUM_STRATEGY strat)
{
   switch(strat)
   {
      case STRAT_PULLBACK: return "PULLBACK";
      case STRAT_MOMENTUM: return "MOMENTUM";
      case STRAT_MEAN_REVERSION: return "MR";
      case STRAT_BREAKOUT: return "BREAKOUT";
      case STRAT_LIQ_SCALP: return "LIQSCALP";
      default: return "NONE";
   }
}

//+------------------------------------------------------------------+
//| EXTRACT STRATEGY FROM COMMENT                                     |
//+------------------------------------------------------------------+
string ExtractStrategy(string comment)
{
   if(StringFind(comment, "PULLBACK") >= 0) return "PULLBACK";
   if(StringFind(comment, "MOMENTUM") >= 0) return "MOMENTUM";
   if(StringFind(comment, "MR") >= 0) return "MR";
   if(StringFind(comment, "BREAKOUT") >= 0) return "BREAKOUT";
   if(StringFind(comment, "LIQSCALP") >= 0) return "LIQSCALP";
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| DRAW DASHBOARD                                                    |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   color clrTitle = clrGold;
   color clrText = clrWhite;
   color clrGood = clrLime;
   color clrBad = clrRed;
   color clrWarn = clrOrange;
   string pfx = "AQX_";
   
   // Status
   string status = "SCANNING";
   color sClr = clrGood;
   if(g_emergencyStop) { status = "EMERGENCY STOP"; sClr = clrBad; }
   else if(g_dailyHalt) { status = "DAILY HALT"; sClr = clrBad; }
   else if(g_weeklyHalt) { status = "WEEKLY HALT"; sClr = clrBad; }
   else if(g_consecHalt) { status = "CONSEC HALT"; sClr = clrWarn; }
   else if(CountOpenPositions() > 0) { status = "TRADING"; sClr = clrGood; }
   
   CreateLabel(pfx+"t0", x, y, "═══ AI QUANT SCALPER X v1.0 ═══", clrTitle, 11); y += 20;
   CreateLabel(pfx+"t1", x, y, "Multi-Layer Consensus Engine", clrText, 9); y += 16;
   CreateLabel(pfx+"st", x, y, "Status: " + status, sClr, 10); y += 18;
   
   // Best opportunity
   string bestPair = "---";
   double bestConf = 0;
   string bestRegime = "---";
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].confidence > bestConf)
      {
         bestConf = g_pairs[i].confidence;
         bestPair = g_pairs[i].symbol;
         bestRegime = EnumToString(g_pairs[i].regime);
      }
   }
   
   CreateLabel(pfx+"bp", x, y, "Top: " + bestPair + " (" + DoubleToString(bestConf, 0) + "%)", 
               bestConf >= 75 ? clrGood : clrWarn, 10); y += 16;
   CreateLabel(pfx+"rg", x, y, "Regime: " + bestRegime, clrText, 9); y += 18;
   
   // Account
   double bal = g_account.Balance();
   double eq = g_account.Equity();
   double dailyPct = (g_dayStartBalance > 0) ? (eq - g_dayStartBalance) / g_dayStartBalance * 100 : 0;
   double totalDD = (g_peakEquity > 0) ? (g_peakEquity - eq) / g_peakEquity * 100 : 0;
   
   CreateLabel(pfx+"bl", x, y, "Balance: $" + DoubleToString(bal, 2), clrText, 10); y += 16;
   CreateLabel(pfx+"eq", x, y, "Equity:  $" + DoubleToString(eq, 2), clrText, 10); y += 16;
   CreateLabel(pfx+"dy", x, y, "Daily: " + (dailyPct >= 0 ? "+" : "") + DoubleToString(dailyPct, 2) + "%",
               dailyPct >= 0 ? clrGood : clrBad, 10); y += 16;
   CreateLabel(pfx+"dd", x, y, "DD: " + DoubleToString(totalDD, 2) + "%",
               totalDD < 2 ? clrGood : (totalDD < 5 ? clrWarn : clrBad), 10); y += 18;
   
   // Portfolio risk
   CreateLabel(pfx+"pr", x, y, "Portfolio Risk: " + DoubleToString(g_totalRiskUsed, 2) + "% / " + DoubleToString(InpMaxPortfolioRisk, 1) + "%",
               g_totalRiskUsed < InpMaxPortfolioRisk * 0.8 ? clrGood : clrWarn, 10); y += 16;
   CreateLabel(pfx+"op", x, y, "Positions: " + IntegerToString(CountOpenPositions()) + " / " + IntegerToString(InpMaxOpenPositions), clrText, 10); y += 18;
   
   // Stats
   double winRate = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   CreateLabel(pfx+"tr", x, y, "Trades: " + IntegerToString(g_totalTrades), clrText, 10); y += 16;
   CreateLabel(pfx+"wr", x, y, "WR: " + DoubleToString(winRate, 1) + "%",
               winRate >= 65 ? clrGood : (winRate >= 50 ? clrWarn : clrBad), 10); y += 16;
   CreateLabel(pfx+"pn", x, y, "PnL: $" + DoubleToString(g_totalPnL, 2),
               g_totalPnL >= 0 ? clrGood : clrBad, 10); y += 16;
   
   // Streak
   string streakStr = "W:" + IntegerToString(g_consecWins) + " L:" + IntegerToString(g_consecLosses);
   CreateLabel(pfx+"sk", x, y, streakStr, g_consecLosses >= 3 ? clrBad : clrText, 10); y += 16;
   
   // Adaptive risk display
   double risk = GetAdaptiveRisk();
   string riskMode = "NORMAL";
   if(g_consecWins >= InpWinStreakBoost) riskMode = "BOOSTED";
   else if(g_consecLosses >= InpLossStreakReduce) riskMode = "REDUCED";
   CreateLabel(pfx+"ri", x, y, "Risk: " + DoubleToString(risk, 2) + "% [" + riskMode + "]", clrText, 9);
   
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
void PrintPerformanceReport()
{
   Print("════════════════════════════════════════════════");
   Print("  AI QUANT SCALPER X — FINAL PERFORMANCE REPORT");
   Print("════════════════════════════════════════════════");
   double wr = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   double pf = 0;
   if(g_totalLosses > 0 && g_totalPnL != 0)
   {
      double grossWin = 0, grossLoss = 0;
      // Approximate from win rate and total
      grossWin = (g_totalWins > 0) ? g_totalPnL * (wr / 100.0) * 2 : 0;
      grossLoss = MathAbs(g_totalPnL - grossWin);
      if(grossLoss > 0) pf = grossWin / grossLoss;
   }
   
   Print("Trades: ", g_totalTrades, " | Wins: ", g_totalWins, " | Losses: ", g_totalLosses);
   Print("Win Rate: ", DoubleToString(wr, 1), "%");
   Print("Total PnL: $", DoubleToString(g_totalPnL, 2));
   Print("Profit Factor: ~", DoubleToString(pf, 2));
   Print("Peak Equity: $", DoubleToString(g_peakEquity, 2));
   Print("────────────────────────────────────────────────");
   Print("SESSION STATS:");
   Print("  London:  T=", g_londonStats.trades, " WR=", DoubleToString(g_londonStats.winRate, 1), "% PnL=$", DoubleToString(g_londonStats.pnl, 2));
   Print("  Overlap: T=", g_overlapStats.trades, " WR=", DoubleToString(g_overlapStats.winRate, 1), "% PnL=$", DoubleToString(g_overlapStats.pnl, 2));
   Print("  NY:      T=", g_nyStats.trades, " WR=", DoubleToString(g_nyStats.winRate, 1), "% PnL=$", DoubleToString(g_nyStats.pnl, 2));
   Print("  Asian:   T=", g_asianStats.trades, " WR=", DoubleToString(g_asianStats.winRate, 1), "% PnL=$", DoubleToString(g_asianStats.pnl, 2));
   Print("────────────────────────────────────────────────");
   Print("STRATEGY STATS:");
   Print("  Pullback:  T=", g_pullbackStats.trades, " WR=", DoubleToString(g_pullbackStats.winRate, 1), "% ", (g_pullbackStats.enabled ? "[ON]" : "[OFF]"));
   Print("  Momentum:  T=", g_momentumStats.trades, " WR=", DoubleToString(g_momentumStats.winRate, 1), "% ", (g_momentumStats.enabled ? "[ON]" : "[OFF]"));
   Print("  MeanRev:   T=", g_mrStats.trades, " WR=", DoubleToString(g_mrStats.winRate, 1), "% ", (g_mrStats.enabled ? "[ON]" : "[OFF]"));
   Print("  Breakout:  T=", g_breakoutStats.trades, " WR=", DoubleToString(g_breakoutStats.winRate, 1), "% ", (g_breakoutStats.enabled ? "[ON]" : "[OFF]"));
   Print("  LiqScalp:  T=", g_liqStats.trades, " WR=", DoubleToString(g_liqStats.winRate, 1), "% ", (g_liqStats.enabled ? "[ON]" : "[OFF]"));
   Print("────────────────────────────────────────────────");
   Print("PAIR STATS:");
   for(int i = 0; i < g_pairCount; i++)
   {
      int t = g_pairs[i].wins + g_pairs[i].losses;
      if(t > 0)
         Print("  ", g_pairs[i].symbol, ": T=", t, " WR=", DoubleToString(g_pairs[i].winRate, 1), 
               "% PnL=$", DoubleToString(g_pairs[i].pnl, 2), (g_pairs[i].enabled ? "" : " [OFF]"));
   }
   Print("════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
