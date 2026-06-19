//+------------------------------------------------------------------+
//|                                             QuantEnginePro.mq5    |
//|                       QUANT ENGINE PRO v1.0                       |
//|        Fully Automated Quantitative Trading with Knowledge Engine |
//+------------------------------------------------------------------+
#property copyright "Quant Engine Pro"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "====== GENERAL ======"
input int      InpMagic              = 850000;          // Magic Number
input int      InpScanInterval       = 60;              // Scan interval (seconds)
input string   InpPairs              = "XAUUSD,EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,NAS100,US30,BTCUSD,USDCHF";

input group "====== QUANT KNOWLEDGE ENGINE ======"
input int      InpKnowledgeWindow    = 200;             // Statistical sample window (bars)
input int      InpMinSampleSize      = 50;              // Min samples for valid statistics
input double   InpZScoreEntry        = 2.0;             // Z-Score threshold for entry
input double   InpZScoreExit         = 0.5;             // Z-Score threshold for exit
input bool     InpUseBayesian        = true;            // Enable Bayesian probability updates
input bool     InpUseKellyCriterion  = true;            // Use Kelly Criterion for sizing

input group "====== REGIME DETECTION ======"
input int      InpRegimeLookback     = 100;             // Regime detection window
input double   InpTrendHurst         = 0.60;            // Hurst > this = trending
input double   InpMRHurst            = 0.40;            // Hurst < this = mean reverting
input int      InpRegimeMinBars      = 20;              // Min bars to confirm regime

input group "====== STATISTICAL MODELS ======"
input double   InpMinEdge            = 0.05;            // Min edge (expected value) to trade
input double   InpMaxRuinProb        = 0.01;            // Max ruin probability (1%)
input int      InpMonteCarloSims     = 1000;            // Monte Carlo simulations
input double   InpAlphaDecayThresh   = 0.70;            // Alpha decay threshold (Sharpe ratio)

input group "====== POSITION SIZING ======"
input double   InpMaxKellyFraction   = 0.25;            // Max Kelly fraction (quarter-Kelly)
input double   InpBaseRiskPct        = 0.50;            // Base risk % fallback
input double   InpMinLot             = 0.01;            // Min lot
input double   InpMaxLot             = 5.00;            // Max lot
input int      InpMaxPositions       = 5;               // Max simultaneous positions
input double   InpMaxPortfolioRisk   = 3.0;             // Max total portfolio risk %

input group "====== TRADE MANAGEMENT ======"
input double   InpSLMultiplier       = 2.0;             // SL = StdDev * multiplier
input double   InpTPMultiplier       = 3.0;             // TP = StdDev * multiplier
input double   InpBEThreshold        = 1.0;             // Move BE at 1x StdDev profit
input double   InpPartialAt          = 1.5;             // Partial close at 1.5x StdDev
input double   InpPartialPct         = 0.50;            // Close 50% at partial
input double   InpTrailStdDev        = 1.0;             // Trail at 1x StdDev

input group "====== CAPITAL PROTECTION ======"
input double   InpDailyDDLimit       = 2.0;             // Daily DD limit %
input double   InpWeeklyDDLimit      = 5.0;             // Weekly DD limit %
input double   InpMaxDrawdown        = 10.0;            // Emergency stop DD %
input int      InpConsecLossHalt     = 4;               // Halt after N consecutive losses
input int      InpCooldownSec        = 180;             // Cooldown between trades (per pair)

input group "====== LEARNING ENGINE ======"
input bool     InpSelfLearn          = true;            // Enable self-learning
input int      InpMinTradesEval      = 15;              // Min trades before strategy eval
input double   InpDisableSharpe      = 0.0;             // Disable strategy if Sharpe below this

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_REGIME
{
   REGIME_TRENDING,        // Hurst > 0.6 - persistent moves
   REGIME_MEAN_REVERTING,  // Hurst < 0.4 - oscillating
   REGIME_RANDOM_WALK,     // Hurst ~ 0.5 - no edge
   REGIME_VOLATILE,        // Extreme vol expansion
   REGIME_UNKNOWN
};

enum ENUM_QUANT_STRATEGY
{
   QSTRAT_MOMENTUM,        // Trending regime: ride the trend
   QSTRAT_MEAN_REVERSION,  // MR regime: fade extremes
   QSTRAT_STAT_ARB,        // Pairs/cointegration
   QSTRAT_BREAKOUT,        // Volatility expansion
   QSTRAT_NO_TRADE         // No statistical edge
};

enum ENUM_SIGNAL
{
   SIG_BUY,
   SIG_SELL,
   SIG_NONE
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct QuantKnowledge
{
   // Price statistics
   double   mean;
   double   stdDev;
   double   skewness;
   double   kurtosis;
   double   zScore;
   
   // Return distribution
   double   returnMean;
   double   returnStdDev;
   double   returnSkew;
   
   // Regime metrics
   double   hurstExponent;
   double   adx;
   double   atr;
   double   atrMean;
   double   atrStdDev;
   double   volZScore;       // Volatility z-score
   
   // Autocorrelation
   double   autoCorr1;       // Lag-1 autocorrelation
   double   autoCorr5;       // Lag-5 autocorrelation
   
   // Bayesian
   double   priorWinRate;    // Historical win rate
   double   likelihood;      // Current signal likelihood
   double   posterior;       // Updated probability
   
   // Edge metrics
   double   expectedValue;   // EV per trade
   double   kellyFraction;   // Optimal bet size
   double   sharpeRatio;     // Risk-adjusted return
   double   ruinProb;        // Probability of ruin
};

struct PairData
{
   string            symbol;
   bool              enabled;
   QuantKnowledge    knowledge;
   ENUM_REGIME       regime;
   ENUM_QUANT_STRATEGY strategy;
   ENUM_SIGNAL       signal;
   double            confidence;
   double            optimalLot;
   double            entryPrice;
   double            slDistance;
   double            tpDistance;
   // Performance tracking
   datetime          lastTradeTime;
   int               totalTrades;
   int               wins;
   int               losses;
   double            pnl;
   double            winRate;
   double            avgWin;
   double            avgLoss;
   double            stratSharpe;
   bool              stratEnabled;
};

struct ManagedTrade
{
   ulong       ticket;
   string      symbol;
   double      entryPrice;
   double      initialSL;
   double      currentSL;
   double      initialLots;
   double      currentLots;
   bool        isBuy;
   bool        beMoveDone;
   bool        partialDone;
   bool        trailing;
   double      maxProfitPips;
   double      entryStdDev;
   datetime    openTime;
   string      stratName;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_position;

PairData       g_pairs[20];
int            g_pairCount = 0;

ManagedTrade   g_managed[20];
int            g_managedCount = 0;

// Performance
int            g_totalTrades = 0;
int            g_totalWins = 0;
int            g_totalLosses = 0;
double         g_totalPnL = 0;
double         g_dailyPnL = 0;
double         g_weeklyPnL = 0;
int            g_consecLosses = 0;
int            g_consecWins = 0;
double         g_dayStartBalance = 0;
double         g_weekStartBalance = 0;
double         g_peakEquity = 0;
datetime       g_lastDay = 0;
datetime       g_lastWeek = 0;
datetime       g_lastScan = 0;

// Halt
bool           g_halted = false;
bool           g_emergencyStop = false;
datetime       g_haltTime = 0;

// Knowledge engine globals
double         g_portfolioSharpe = 0;
double         g_portfolioEV = 0;
int            g_activeStrategies = 0;

// Log
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
      g_pairs[i].stratEnabled = true;
      g_pairs[i].signal = SIG_NONE;
      g_pairs[i].lastTradeTime = 0;
      g_pairs[i].totalTrades = 0;
      g_pairs[i].wins = 0;
      g_pairs[i].losses = 0;
      g_pairs[i].pnl = 0;
      g_pairs[i].winRate = 0;
      g_pairs[i].avgWin = 0;
      g_pairs[i].avgLoss = 0;
      g_pairs[i].stratSharpe = 0;
   }
   
   g_dayStartBalance = g_account.Balance();
   g_weekStartBalance = g_account.Balance();
   g_peakEquity = g_account.Equity();
   g_lastDay = iTime(Symbol(), PERIOD_D1, 0);
   g_lastWeek = iTime(Symbol(), PERIOD_W1, 0);
   
   // Open log
   g_logFile = FileOpen("QuantEngine_trades.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ, ',');
   if(g_logFile != INVALID_HANDLE)
   {
      FileSeek(g_logFile, 0, SEEK_END);
      if(FileTell(g_logFile) == 0)
         FileWrite(g_logFile, "Time", "Symbol", "Strategy", "Regime", "ZScore",
                   "Confidence", "Kelly", "Lot", "Profit", "Win", "Sharpe",
                   "Hurst", "EV", "Balance");
   }
   
   Print("============================================");
   Print("  QUANT ENGINE PRO v1.0");
   Print("  Quantitative Knowledge-Based Trading");
   Print("============================================");
   Print("  Pairs: ", g_pairCount);
   Print("  Knowledge Window: ", InpKnowledgeWindow, " bars");
   Print("  Z-Score Entry: ", DoubleToString(InpZScoreEntry, 2));
   Print("  Min Edge (EV): ", DoubleToString(InpMinEdge, 3));
   Print("  Kelly Fraction: ", DoubleToString(InpMaxKellyFraction, 2));
   Print("  Bayesian Updates: ", InpUseBayesian ? "ON" : "OFF");
   Print("  >>> KNOWLEDGE ENGINE ONLINE <<<");
   Print("============================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logFile != INVALID_HANDLE) FileClose(g_logFile);
   ObjectsDeleteAll(0, "QEP_");
   PrintReport();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDayWeekReset();
   
   double equity = g_account.Equity();
   if(equity > g_peakEquity) g_peakEquity = equity;
   
   // Emergency stop
   if(g_emergencyStop) { DrawDashboard(); return; }
   
   if(g_peakEquity > 0)
   {
      double dd = (g_peakEquity - equity) / g_peakEquity * 100;
      if(dd >= InpMaxDrawdown)
      {
         g_emergencyStop = true;
         CloseAllPositions();
         Print("!!! QUANT ENGINE: EMERGENCY STOP - DD=", DoubleToString(dd, 2), "% !!!");
         DrawDashboard();
         return;
      }
   }
   
   // Manage positions
   ManagePositions();
   DrawDashboard();
   
   // Halt check
   if(g_halted)
   {
      if(TimeCurrent() - g_haltTime > 3600) // 1 hour recovery
      {
         g_halted = false;
         g_consecLosses = 0;
         Print("QEP: Halt lifted - resuming");
      }
      return;
   }
   
   // Scan interval
   if(TimeCurrent() - g_lastScan < InpScanInterval) return;
   g_lastScan = TimeCurrent();
   
   // Position limit
   if(CountPositions() >= InpMaxPositions) return;
   
   // Daily DD check
   if(g_dayStartBalance > 0)
   {
      double ddPct = (g_dayStartBalance - equity) / g_dayStartBalance * 100;
      if(ddPct >= InpDailyDDLimit) return;
   }
   
   // ====================================================
   // QUANT KNOWLEDGE ENGINE - MAIN LOOP
   // ====================================================
   
   // Phase 1: Build knowledge for all pairs
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled || !g_pairs[i].stratEnabled) continue;
      BuildKnowledge(i);
   }
   
   // Phase 2: Classify regimes
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled || !g_pairs[i].stratEnabled) continue;
      ClassifyRegime(i);
   }
   
   // Phase 3: Select strategies and generate signals
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled || !g_pairs[i].stratEnabled) continue;
      SelectStrategy(i);
      GenerateSignal(i);
   }
   
   // Phase 4: Calculate edge and position size
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled || !g_pairs[i].stratEnabled) continue;
      if(g_pairs[i].signal == SIG_NONE) continue;
      CalcEdgeAndSize(i);
   }
   
   // Phase 5: Find best opportunity with positive edge
   int bestIdx = -1;
   double bestEV = 0;
   
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].enabled || !g_pairs[i].stratEnabled) continue;
      if(g_pairs[i].signal == SIG_NONE) continue;
      if(g_pairs[i].knowledge.expectedValue < InpMinEdge) continue;
      if(g_pairs[i].knowledge.ruinProb > InpMaxRuinProb) continue;
      if(TimeCurrent() - g_pairs[i].lastTradeTime < InpCooldownSec) continue;
      if(HasPosition(g_pairs[i].symbol)) continue;
      
      if(g_pairs[i].knowledge.expectedValue > bestEV)
      {
         bestEV = g_pairs[i].knowledge.expectedValue;
         bestIdx = i;
      }
   }
   
   // Phase 6: Execute
   if(bestIdx >= 0)
   {
      ExecuteTrade(bestIdx);
   }
   
   // Phase 7: Self-learning (auto-rotate)
   if(InpSelfLearn) AutoRotate();
}

//+------------------------------------------------------------------+
//| BUILD KNOWLEDGE - Statistical Analysis                            |
//+------------------------------------------------------------------+
void BuildKnowledge(int idx)
{
   string sym = g_pairs[idx].symbol;
   int window = InpKnowledgeWindow;
   
   // Get close prices
   double closes[];
   if(CopyClose(sym, PERIOD_M15, 0, window + 1, closes) < window + 1) return;
   
   // Calculate returns
   double returns[];
   ArrayResize(returns, window);
   for(int i = 0; i < window; i++)
      returns[i] = (closes[i+1] - closes[i]) / closes[i];
   
   // Price statistics
   g_pairs[idx].knowledge.mean = CalcMean(closes, window + 1);
   g_pairs[idx].knowledge.stdDev = CalcStdDev(closes, window + 1);
   
   double currentPrice = SymbolInfoDouble(sym, SYMBOL_BID);
   if(g_pairs[idx].knowledge.stdDev > 0)
      g_pairs[idx].knowledge.zScore = (currentPrice - g_pairs[idx].knowledge.mean) / g_pairs[idx].knowledge.stdDev;
   else
      g_pairs[idx].knowledge.zScore = 0;
   
   // Return distribution
   g_pairs[idx].knowledge.returnMean = CalcMean(returns, window);
   g_pairs[idx].knowledge.returnStdDev = CalcStdDev(returns, window);
   g_pairs[idx].knowledge.returnSkew = CalcSkewness(returns, window);
   
   // ATR stats
   int hATR = iATR(sym, PERIOD_M15, 14);
   double atrBuf[];
   if(CopyBuffer(hATR, 0, 0, 30, atrBuf) >= 30)
   {
      g_pairs[idx].knowledge.atr = atrBuf[0];
      g_pairs[idx].knowledge.atrMean = CalcMean(atrBuf, 30);
      g_pairs[idx].knowledge.atrStdDev = CalcStdDev(atrBuf, 30);
      if(g_pairs[idx].knowledge.atrStdDev > 0)
         g_pairs[idx].knowledge.volZScore = (atrBuf[0] - g_pairs[idx].knowledge.atrMean) / g_pairs[idx].knowledge.atrStdDev;
   }
   IndicatorRelease(hATR);
   
   // ADX
   int hADX = iADX(sym, PERIOD_M15, 14);
   double adxBuf[];
   if(CopyBuffer(hADX, 0, 0, 1, adxBuf) > 0)
      g_pairs[idx].knowledge.adx = adxBuf[0];
   IndicatorRelease(hADX);
   
   // Hurst Exponent (R/S method approximation)
   g_pairs[idx].knowledge.hurstExponent = CalcHurst(returns, window);
   
   // Autocorrelation
   g_pairs[idx].knowledge.autoCorr1 = CalcAutoCorrelation(returns, window, 1);
   g_pairs[idx].knowledge.autoCorr5 = CalcAutoCorrelation(returns, window, 5);
   
   // Skewness and Kurtosis of prices
   g_pairs[idx].knowledge.skewness = CalcSkewness(closes, window + 1);
   g_pairs[idx].knowledge.kurtosis = CalcKurtosis(closes, window + 1);
}

//+------------------------------------------------------------------+
//| CLASSIFY REGIME via Hurst + ADX + Vol                             |
//+------------------------------------------------------------------+
void ClassifyRegime(int idx)
{
   double hurst = g_pairs[idx].knowledge.hurstExponent;
   double adx = g_pairs[idx].knowledge.adx;
   double volZ = g_pairs[idx].knowledge.volZScore;
   
   // Extreme volatility
   if(volZ > 2.5)
   {
      g_pairs[idx].regime = REGIME_VOLATILE;
      return;
   }
   
   // Trending: Hurst > threshold AND ADX confirms
   if(hurst > InpTrendHurst && adx > 25)
   {
      g_pairs[idx].regime = REGIME_TRENDING;
      return;
   }
   
   // Mean reverting: Hurst < threshold AND low ADX
   if(hurst < InpMRHurst && adx < 20)
   {
      g_pairs[idx].regime = REGIME_MEAN_REVERTING;
      return;
   }
   
   // Strong autocorrelation confirms trend
   if(g_pairs[idx].knowledge.autoCorr1 > 0.3 && adx > 22)
   {
      g_pairs[idx].regime = REGIME_TRENDING;
      return;
   }
   
   // Negative autocorrelation confirms MR
   if(g_pairs[idx].knowledge.autoCorr1 < -0.2)
   {
      g_pairs[idx].regime = REGIME_MEAN_REVERTING;
      return;
   }
   
   g_pairs[idx].regime = REGIME_RANDOM_WALK;
}

//+------------------------------------------------------------------+
//| SELECT STRATEGY                                                   |
//+------------------------------------------------------------------+
void SelectStrategy(int idx)
{
   switch(g_pairs[idx].regime)
   {
      case REGIME_TRENDING:
         g_pairs[idx].strategy = QSTRAT_MOMENTUM;
         break;
      case REGIME_MEAN_REVERTING:
         g_pairs[idx].strategy = QSTRAT_MEAN_REVERSION;
         break;
      case REGIME_VOLATILE:
         g_pairs[idx].strategy = QSTRAT_BREAKOUT;
         break;
      case REGIME_RANDOM_WALK:
      default:
         g_pairs[idx].strategy = QSTRAT_NO_TRADE;
         break;
   }
}

//+------------------------------------------------------------------+
//| GENERATE SIGNAL                                                   |
//+------------------------------------------------------------------+
void GenerateSignal(int idx)
{
   g_pairs[idx].signal = SIG_NONE;
   
   double zScore = g_pairs[idx].knowledge.zScore;
   ENUM_QUANT_STRATEGY strat = g_pairs[idx].strategy;
   
   if(strat == QSTRAT_NO_TRADE) return;
   
   string sym = g_pairs[idx].symbol;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   // EMAs for trend direction
   int hE9 = iMA(sym, PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
   int hE21 = iMA(sym, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   double e9[], e21[];
   bool trendUp = false, trendDown = false;
   if(CopyBuffer(hE9, 0, 0, 1, e9) > 0 && CopyBuffer(hE21, 0, 0, 1, e21) > 0)
   {
      trendUp = (e9[0] > e21[0]);
      trendDown = (e9[0] < e21[0]);
   }
   IndicatorRelease(hE9);
   IndicatorRelease(hE21);
   
   // RSI for momentum
   int hRSI = iRSI(sym, PERIOD_M15, 14, PRICE_CLOSE);
   double rsiBuf[];
   double rsi = 50;
   if(CopyBuffer(hRSI, 0, 0, 1, rsiBuf) > 0) rsi = rsiBuf[0];
   IndicatorRelease(hRSI);
   
   switch(strat)
   {
      case QSTRAT_MOMENTUM:
         // Trade in direction of trend when z-score is moderate
         if(trendUp && zScore > -1.0 && zScore < 1.0 && rsi > 50)
            g_pairs[idx].signal = SIG_BUY;
         else if(trendDown && zScore > -1.0 && zScore < 1.0 && rsi < 50)
            g_pairs[idx].signal = SIG_SELL;
         break;
         
      case QSTRAT_MEAN_REVERSION:
         // Fade extremes when z-score exceeds threshold
         if(zScore < -InpZScoreEntry && rsi < 35)
            g_pairs[idx].signal = SIG_BUY;   // Price far below mean - buy
         else if(zScore > InpZScoreEntry && rsi > 65)
            g_pairs[idx].signal = SIG_SELL;  // Price far above mean - sell
         break;
         
      case QSTRAT_BREAKOUT:
         // Volatility breakout - trade in direction of the expansion
         if(g_pairs[idx].knowledge.volZScore > 1.5)
         {
            if(trendUp && zScore > 1.0)
               g_pairs[idx].signal = SIG_BUY;
            else if(trendDown && zScore < -1.0)
               g_pairs[idx].signal = SIG_SELL;
         }
         break;
         
      default:
         break;
   }
}

//+------------------------------------------------------------------+
//| CALCULATE EDGE AND POSITION SIZE                                  |
//+------------------------------------------------------------------+
void CalcEdgeAndSize(int idx)
{
   // Bayesian update
   if(InpUseBayesian)
   {
      double prior = g_pairs[idx].winRate;
      if(prior <= 0) prior = 0.50;  // Default prior
      
      // Likelihood based on z-score magnitude and regime alignment
      double zMag = MathAbs(g_pairs[idx].knowledge.zScore);
      double likelihood = 0.50;
      
      if(g_pairs[idx].strategy == QSTRAT_MEAN_REVERSION)
         likelihood = 0.50 + MathMin(zMag / 5.0, 0.30);  // Higher z = higher MR probability
      else if(g_pairs[idx].strategy == QSTRAT_MOMENTUM)
         likelihood = 0.50 + g_pairs[idx].knowledge.adx / 100.0 * 0.30;
      else if(g_pairs[idx].strategy == QSTRAT_BREAKOUT)
         likelihood = 0.50 + MathMin(g_pairs[idx].knowledge.volZScore / 5.0, 0.25);
      
      // Bayesian posterior: P(win|evidence) = P(evidence|win) * P(win) / P(evidence)
      double pEvidence = likelihood * prior + (1.0 - likelihood) * (1.0 - prior);
      if(pEvidence > 0)
         g_pairs[idx].knowledge.posterior = (likelihood * prior) / pEvidence;
      else
         g_pairs[idx].knowledge.posterior = prior;
      
      g_pairs[idx].knowledge.priorWinRate = prior;
      g_pairs[idx].knowledge.likelihood = likelihood;
      g_pairs[idx].confidence = g_pairs[idx].knowledge.posterior * 100;
   }
   else
   {
      g_pairs[idx].confidence = g_pairs[idx].winRate > 0 ? g_pairs[idx].winRate : 50;
   }
   
   // Expected Value calculation
   double winProb = g_pairs[idx].knowledge.posterior;
   if(!InpUseBayesian) winProb = g_pairs[idx].winRate / 100.0;
   if(winProb <= 0) winProb = 0.50;
   
   double avgW = g_pairs[idx].avgWin;
   double avgL = g_pairs[idx].avgLoss;
   if(avgW <= 0) avgW = g_pairs[idx].knowledge.stdDev * InpTPMultiplier;
   if(avgL <= 0) avgL = g_pairs[idx].knowledge.stdDev * InpSLMultiplier;
   
   // EV = (WinProb * AvgWin) - (LossProb * AvgLoss)
   g_pairs[idx].knowledge.expectedValue = (winProb * avgW) - ((1.0 - winProb) * avgL);
   
   // Kelly Criterion: f* = (bp - q) / b
   // where b = avgWin/avgLoss, p = winProb, q = 1-p
   double b = (avgL > 0) ? avgW / avgL : 1.0;
   double kellyFull = (b * winProb - (1.0 - winProb)) / b;
   g_pairs[idx].knowledge.kellyFraction = MathMax(0, kellyFull) * InpMaxKellyFraction;
   
   // Monte Carlo ruin probability (simplified)
   g_pairs[idx].knowledge.ruinProb = CalcRuinProbability(winProb, b);
   
   // Sharpe ratio (annualized approximation)
   if(g_pairs[idx].knowledge.returnStdDev > 0)
      g_pairs[idx].knowledge.sharpeRatio = (g_pairs[idx].knowledge.returnMean / g_pairs[idx].knowledge.returnStdDev) * MathSqrt(252 * 24);
   else
      g_pairs[idx].knowledge.sharpeRatio = 0;
   
   // Calculate lot size
   g_pairs[idx].slDistance = g_pairs[idx].knowledge.stdDev * InpSLMultiplier;
   g_pairs[idx].tpDistance = g_pairs[idx].knowledge.stdDev * InpTPMultiplier;
   g_pairs[idx].optimalLot = CalcLotSize(idx);
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE (Kelly or Risk-Based)                          |
//+------------------------------------------------------------------+
double CalcLotSize(int idx)
{
   double equity = g_account.Equity();
   double lot = InpMinLot;
   
   if(InpUseKellyCriterion && g_pairs[idx].knowledge.kellyFraction > 0)
   {
      // Kelly-based: risk Kelly fraction of equity
      double kellyRisk = g_pairs[idx].knowledge.kellyFraction;
      double riskAmount = equity * kellyRisk;
      
      double sl = g_pairs[idx].slDistance;
      string sym = g_pairs[idx].symbol;
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue > 0 && tickSize > 0 && sl > 0)
      {
         double slTicks = sl / tickSize;
         lot = riskAmount / (slTicks * tickValue);
      }
   }
   else
   {
      // Fallback: standard risk-based
      double riskAmount = equity * InpBaseRiskPct / 100.0;
      double sl = g_pairs[idx].slDistance;
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
//| EXECUTE TRADE                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int idx)
{
   string sym = g_pairs[idx].symbol;
   bool isBuy = (g_pairs[idx].signal == SIG_BUY);
   double lot = g_pairs[idx].optimalLot;
   if(lot <= 0) return;
   
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double sl = g_pairs[idx].slDistance;
   double tp = g_pairs[idx].tpDistance;
   
   double entry, slPrice, tpPrice;
   if(isBuy)
   {
      entry = ask;
      slPrice = entry - sl;
      tpPrice = entry + tp;
   }
   else
   {
      entry = bid;
      slPrice = entry + sl;
      tpPrice = entry - tp;
   }
   
   string stratName = GetStratName(g_pairs[idx].strategy);
   string comment = "QEP|" + stratName + "|Z" + DoubleToString(g_pairs[idx].knowledge.zScore, 1) +
                    "|H" + DoubleToString(g_pairs[idx].knowledge.hurstExponent, 2);
   
   bool result = false;
   if(isBuy)
      result = g_trade.Buy(lot, sym, entry, slPrice, tpPrice, comment);
   else
      result = g_trade.Sell(lot, sym, entry, slPrice, tpPrice, comment);
   
   if(result)
   {
      if(g_managedCount < 20)
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
         g_managed[g_managedCount].entryStdDev = g_pairs[idx].knowledge.stdDev;
         g_managed[g_managedCount].openTime = TimeCurrent();
         g_managed[g_managedCount].stratName = stratName;
         g_managedCount++;
      }
      
      g_pairs[idx].lastTradeTime = TimeCurrent();
      
      Print("QEP: ", (isBuy ? "BUY" : "SELL"), " ", sym,
            " Lot=", DoubleToString(lot, 2),
            " Z=", DoubleToString(g_pairs[idx].knowledge.zScore, 2),
            " Hurst=", DoubleToString(g_pairs[idx].knowledge.hurstExponent, 3),
            " EV=", DoubleToString(g_pairs[idx].knowledge.expectedValue, 4),
            " Kelly=", DoubleToString(g_pairs[idx].knowledge.kellyFraction * 100, 1), "%",
            " Regime=", EnumToString(g_pairs[idx].regime));
   }
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = g_managedCount - 1; i >= 0; i--)
   {
      ulong ticket = g_managed[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         RemoveManaged(i);
         continue;
      }
      
      string sym = g_managed[i].symbol;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double entry = g_managed[i].entryPrice;
      double stdDev = g_managed[i].entryStdDev;
      bool isBuy = g_managed[i].isBuy;
      
      // Profit in terms of stdDev
      double profitDist = 0;
      if(isBuy) profitDist = bid - entry;
      else profitDist = entry - ask;
      
      double profitStdDevs = (stdDev > 0) ? profitDist / stdDev : 0;
      
      if(profitStdDevs > g_managed[i].maxProfitPips)
         g_managed[i].maxProfitPips = profitStdDevs;
      
      // 1. BE move at 1x StdDev profit
      if(!g_managed[i].beMoveDone && profitStdDevs >= InpBEThreshold)
      {
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         double newSL = entry;
         if(isBuy) newSL = entry + point * 3;
         else newSL = entry - point * 3;
         
         if(g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
         {
            g_managed[i].beMoveDone = true;
            g_managed[i].currentSL = newSL;
         }
      }
      
      // 2. Partial close at 1.5x StdDev
      if(!g_managed[i].partialDone && profitStdDevs >= InpPartialAt)
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
         else g_managed[i].partialDone = true;
      }
      
      // 3. Trailing at 1x StdDev distance
      if(g_managed[i].beMoveDone && g_managed[i].partialDone)
      {
         g_managed[i].trailing = true;
         double trailDist = stdDev * InpTrailStdDev;
         
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
      
      // 4. Z-Score mean reversion exit
      if(g_managed[i].stratName == "MR")
      {
         // Exit when price returns near mean (z-score < exit threshold)
         for(int p = 0; p < g_pairCount; p++)
         {
            if(g_pairs[p].symbol == sym)
            {
               if(MathAbs(g_pairs[p].knowledge.zScore) < InpZScoreExit && profitStdDevs > 0)
               {
                  g_trade.PositionClose(ticket);
                  Print("QEP: Z-Score exit on ", sym, " - returned to mean");
               }
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION - LEARNING                                   |
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
   
   bool isWin = (profit > 0);
   
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
         g_pairs[i].totalTrades++;
         if(isWin)
         {
            g_pairs[i].wins++;
            g_pairs[i].avgWin = (g_pairs[i].avgWin * (g_pairs[i].wins - 1) + profit) / g_pairs[i].wins;
         }
         else
         {
            g_pairs[i].losses++;
            g_pairs[i].avgLoss = (g_pairs[i].avgLoss * (g_pairs[i].losses - 1) + MathAbs(profit)) / g_pairs[i].losses;
         }
         g_pairs[i].pnl += profit;
         int total = g_pairs[i].wins + g_pairs[i].losses;
         g_pairs[i].winRate = (total > 0) ? (double)g_pairs[i].wins / total * 100 : 0;
         
         // Update strategy Sharpe
         if(g_pairs[i].knowledge.returnStdDev > 0 && total > 5)
         {
            double meanReturn = g_pairs[i].pnl / total;
            g_pairs[i].stratSharpe = meanReturn / g_pairs[i].knowledge.returnStdDev;
         }
         break;
      }
   }
   
   // Consecutive loss halt
   if(g_consecLosses >= InpConsecLossHalt)
   {
      g_halted = true;
      g_haltTime = TimeCurrent();
      Print("QEP: ", InpConsecLossHalt, " consecutive losses - HALTING");
   }
   
   // Log
   if(g_logFile != INVALID_HANDLE)
   {
      string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
      FileWrite(g_logFile, TimeToString(TimeCurrent()), dealSym,
                comment, "", "",
                "", "", DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
                DoubleToString(profit, 2), isWin ? "WIN" : "LOSS",
                "", "", "",
                DoubleToString(g_account.Balance(), 2));
      FileFlush(g_logFile);
   }
}

//+------------------------------------------------------------------+
//| AUTO-ROTATE (Alpha Decay Detection)                               |
//+------------------------------------------------------------------+
void AutoRotate()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].totalTrades < InpMinTradesEval) continue;
      
      // Disable if Sharpe below threshold
      if(g_pairs[i].stratSharpe < InpDisableSharpe && g_pairs[i].pnl < 0)
      {
         g_pairs[i].stratEnabled = false;
         Print("QEP: Disabled ", g_pairs[i].symbol, " - alpha decay (Sharpe=",
               DoubleToString(g_pairs[i].stratSharpe, 2), ")");
      }
      else if(g_pairs[i].stratSharpe > InpDisableSharpe + 0.5 || g_pairs[i].pnl > 0)
      {
         g_pairs[i].stratEnabled = true;
      }
   }
}

//+------------------------------------------------------------------+
//| STATISTICAL HELPER FUNCTIONS                                       |
//+------------------------------------------------------------------+
double CalcMean(const double &arr[], int size)
{
   if(size <= 0) return 0;
   double sum = 0;
   for(int i = 0; i < size; i++) sum += arr[i];
   return sum / size;
}

double CalcStdDev(const double &arr[], int size)
{
   if(size <= 1) return 0;
   double mean = CalcMean(arr, size);
   double sumSq = 0;
   for(int i = 0; i < size; i++) sumSq += (arr[i] - mean) * (arr[i] - mean);
   return MathSqrt(sumSq / (size - 1));
}

double CalcSkewness(const double &arr[], int size)
{
   if(size <= 2) return 0;
   double mean = CalcMean(arr, size);
   double sd = CalcStdDev(arr, size);
   if(sd <= 0) return 0;
   
   double sum = 0;
   for(int i = 0; i < size; i++)
      sum += MathPow((arr[i] - mean) / sd, 3);
   return sum / size;
}

double CalcKurtosis(const double &arr[], int size)
{
   if(size <= 3) return 0;
   double mean = CalcMean(arr, size);
   double sd = CalcStdDev(arr, size);
   if(sd <= 0) return 0;
   
   double sum = 0;
   for(int i = 0; i < size; i++)
      sum += MathPow((arr[i] - mean) / sd, 4);
   return (sum / size) - 3.0;  // Excess kurtosis
}

double CalcAutoCorrelation(const double &arr[], int size, int lag)
{
   if(size <= lag + 1) return 0;
   double mean = CalcMean(arr, size);
   double var = 0, cov = 0;
   
   for(int i = 0; i < size; i++)
      var += (arr[i] - mean) * (arr[i] - mean);
   
   for(int i = lag; i < size; i++)
      cov += (arr[i] - mean) * (arr[i - lag] - mean);
   
   if(var <= 0) return 0;
   return cov / var;
}

//+------------------------------------------------------------------+
//| HURST EXPONENT (Rescaled Range method)                            |
//+------------------------------------------------------------------+
double CalcHurst(const double &returns[], int size)
{
   if(size < 20) return 0.5;
   
   // Simplified R/S method using two partition sizes
   double rs1 = CalcRS(returns, size, size / 2);
   double rs2 = CalcRS(returns, size, size / 4);
   
   if(rs1 <= 0 || rs2 <= 0) return 0.5;
   
   // Hurst = log(RS1/RS2) / log(n1/n2)
   double hurst = MathLog(rs1 / rs2) / MathLog(2.0);
   
   // Clamp to valid range
   return MathMax(0.01, MathMin(0.99, hurst));
}

double CalcRS(const double &arr[], int totalSize, int blockSize)
{
   if(blockSize <= 2) return 0;
   int blocks = totalSize / blockSize;
   if(blocks <= 0) return 0;
   
   double rsSum = 0;
   int validBlocks = 0;
   
   for(int b = 0; b < blocks; b++)
   {
      int start = b * blockSize;
      
      // Mean of block
      double mean = 0;
      for(int i = 0; i < blockSize && (start + i) < totalSize; i++)
         mean += arr[start + i];
      mean /= blockSize;
      
      // Cumulative deviations
      double maxCum = -999999, minCum = 999999;
      double cumDev = 0;
      double sumSq = 0;
      
      for(int i = 0; i < blockSize && (start + i) < totalSize; i++)
      {
         double dev = arr[start + i] - mean;
         cumDev += dev;
         sumSq += dev * dev;
         if(cumDev > maxCum) maxCum = cumDev;
         if(cumDev < minCum) minCum = cumDev;
      }
      
      double range = maxCum - minCum;
      double stdDev = MathSqrt(sumSq / blockSize);
      
      if(stdDev > 0)
      {
         rsSum += range / stdDev;
         validBlocks++;
      }
   }
   
   return (validBlocks > 0) ? rsSum / validBlocks : 0;
}

//+------------------------------------------------------------------+
//| RUIN PROBABILITY (simplified Gambler's Ruin)                      |
//+------------------------------------------------------------------+
double CalcRuinProbability(double winProb, double payoffRatio)
{
   if(winProb <= 0 || winProb >= 1) return 0.5;
   if(payoffRatio <= 0) return 1.0;
   
   // Simplified: P(ruin) = ((1-p)/p)^(bankroll/unit)
   // For fractional Kelly, ruin approaches 0
   // Approximate using edge
   double edge = winProb * payoffRatio - (1.0 - winProb);
   if(edge <= 0) return 0.50; // No edge = high ruin
   
   // P(ruin) ~ exp(-2 * edge * bankroll_units)
   double bankrollUnits = 100; // Assume 100 units
   double ruin = MathExp(-2.0 * edge * bankrollUnits);
   
   return MathMin(ruin, 1.0);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                  |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i) && g_position.Magic() == InpMagic)
         count++;
   }
   return count;
}

bool HasPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
         if(g_position.Symbol() == sym && g_position.Magic() == InpMagic) return true;
   }
   return false;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i) && g_position.Magic() == InpMagic)
         g_trade.PositionClose(g_position.Ticket());
   }
}

void RemoveManaged(int index)
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
      g_managed[i].entryStdDev = g_managed[i+1].entryStdDev;
      g_managed[i].openTime = g_managed[i+1].openTime;
      g_managed[i].stratName = g_managed[i+1].stratName;
   }
   g_managedCount--;
}

string GetStratName(ENUM_QUANT_STRATEGY strat)
{
   switch(strat)
   {
      case QSTRAT_MOMENTUM: return "MOM";
      case QSTRAT_MEAN_REVERSION: return "MR";
      case QSTRAT_STAT_ARB: return "ARB";
      case QSTRAT_BREAKOUT: return "BRK";
      default: return "NONE";
   }
}

void CheckDayWeekReset()
{
   datetime currentDay = iTime(Symbol(), PERIOD_D1, 0);
   datetime currentWeek = iTime(Symbol(), PERIOD_W1, 0);
   
   if(currentDay != g_lastDay)
   {
      g_lastDay = currentDay;
      g_dailyPnL = 0;
      g_dayStartBalance = g_account.Balance();
      Print("QEP: New trading day");
   }
   if(currentWeek != g_lastWeek)
   {
      g_lastWeek = currentWeek;
      g_weeklyPnL = 0;
      g_weekStartBalance = g_account.Balance();
      Print("QEP: New trading week");
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                         |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   string pfx = "QEP_";
   
   string status = "SCANNING";
   color sClr = clrLime;
   if(g_emergencyStop) { status = "EMERGENCY STOP"; sClr = clrRed; }
   else if(g_halted) { status = "HALTED"; sClr = clrRed; }
   else if(g_managedCount > 0) { status = "TRADING"; sClr = clrLime; }
   
   CreateLabel(pfx+"h", x, y, "=== QUANT ENGINE PRO v1.0 ===", clrGold, 11); y += 18;
   CreateLabel(pfx+"s", x, y, "Status: " + status, sClr, 10); y += 16;
   
   // Best opportunity
   string bestSym = "---";
   double bestEV = 0;
   double bestZ = 0;
   double bestH = 0;
   string bestReg = "---";
   
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].knowledge.expectedValue > bestEV)
      {
         bestEV = g_pairs[i].knowledge.expectedValue;
         bestSym = g_pairs[i].symbol;
         bestZ = g_pairs[i].knowledge.zScore;
         bestH = g_pairs[i].knowledge.hurstExponent;
         bestReg = EnumToString(g_pairs[i].regime);
      }
   }
   
   CreateLabel(pfx+"bp", x, y, "Best: " + bestSym, clrWhite, 9); y += 14;
   CreateLabel(pfx+"ev", x, y, "EV: " + DoubleToString(bestEV, 4), bestEV > InpMinEdge ? clrLime : clrRed, 9); y += 14;
   CreateLabel(pfx+"z", x, y, "Z-Score: " + DoubleToString(bestZ, 2), clrWhite, 9); y += 14;
   CreateLabel(pfx+"hu", x, y, "Hurst: " + DoubleToString(bestH, 3), clrWhite, 9); y += 14;
   CreateLabel(pfx+"rg", x, y, "Regime: " + bestReg, clrWhite, 9); y += 16;
   
   // Account
   double equity = g_account.Equity();
   double dd = (g_peakEquity > 0) ? (g_peakEquity - equity) / g_peakEquity * 100 : 0;
   CreateLabel(pfx+"eq", x, y, "Equity: $" + DoubleToString(equity, 2), clrWhite, 9); y += 14;
   CreateLabel(pfx+"dd", x, y, "DD: " + DoubleToString(dd, 2) + "%", dd < 2 ? clrLime : (dd < 5 ? clrOrange : clrRed), 9); y += 14;
   
   double wr = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   CreateLabel(pfx+"wr", x, y, "WR: " + DoubleToString(wr, 1) + "% (" + IntegerToString(g_totalTrades) + " trades)", 
               wr >= 55 ? clrLime : clrOrange, 9); y += 14;
   CreateLabel(pfx+"pn", x, y, "PnL: $" + DoubleToString(g_totalPnL, 2), g_totalPnL >= 0 ? clrLime : clrRed, 9); y += 14;
   
   // Active strategies count
   g_activeStrategies = 0;
   for(int i = 0; i < g_pairCount; i++)
      if(g_pairs[i].stratEnabled) g_activeStrategies++;
   CreateLabel(pfx+"as", x, y, "Active pairs: " + IntegerToString(g_activeStrategies) + "/" + IntegerToString(g_pairCount), clrWhite, 9);
   
   ChartRedraw(0);
}

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
   Print("  QUANT ENGINE PRO - FINAL REPORT");
   Print("============================================");
   double wr = (g_totalTrades > 0) ? (double)g_totalWins / g_totalTrades * 100 : 0;
   Print("Trades: ", g_totalTrades);
   Print("Win Rate: ", DoubleToString(wr, 1), "%");
   Print("PnL: $", DoubleToString(g_totalPnL, 2));
   Print("Peak Equity: $", DoubleToString(g_peakEquity, 2));
   Print("--------------------------------------------");
   Print("PAIR PERFORMANCE:");
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].totalTrades > 0)
         Print("  ", g_pairs[i].symbol, ": T=", g_pairs[i].totalTrades,
               " WR=", DoubleToString(g_pairs[i].winRate, 1), "%",
               " PnL=$", DoubleToString(g_pairs[i].pnl, 2),
               " Sharpe=", DoubleToString(g_pairs[i].stratSharpe, 2),
               (g_pairs[i].stratEnabled ? "" : " [OFF]"));
   }
   Print("============================================");
}
//+------------------------------------------------------------------+
