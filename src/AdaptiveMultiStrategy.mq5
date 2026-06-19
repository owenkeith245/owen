//+------------------------------------------------------------------+
//|                                    AdaptiveMultiStrategy.mq5      |
//|       Multi-Strategy Regime-Adaptive Algorithmic Framework         |
//|                         Version 1.00                              |
//+------------------------------------------------------------------+
//| Architecture:                                                     |
//|   [Data Pipeline] → scans multiple pairs, calculates features     |
//|   [Strategy Registry] → Trend, Mean Reversion, Scalping modules   |
//|   [Regime Classifier] → ADX+ATR identifies market state per pair  |
//|   [Meta-Allocator] → routes capital to best strategy/pair combo   |
//|   [Risk Manager] → correlation filter, spread filter, DD limits   |
//|                                                                   |
//| Install: Copy to MT5/MQL5/Experts/ → Compile → Attach to chart   |
//| The EA will scan all configured pairs from a single chart.        |
//+------------------------------------------------------------------+
#property copyright "Adaptive Multi-Strategy v1.0"
#property link      ""
#property version   "1.00"
#property strict
#property description "Multi-Strategy Regime-Adaptive Framework"
#property description "Scans multiple pairs, classifies regime, routes to best strategy"
#property description "Strategies: Trend Following | Mean Reversion | Micro-Scalping"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAX_PAIRS          20
#define MAX_STRATEGIES     3
#define CORR_LOOKBACK      50
#define CORR_THRESHOLD     0.70

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_REGIME
{
   REGIME_TREND_BULL,        // Strong trend up
   REGIME_TREND_BEAR,        // Strong trend down
   REGIME_RANGE,             // Low volatility ranging
   REGIME_VOLATILE_RANGE,    // High volatility but no trend
   REGIME_SIDELINES          // Unpredictable — don't trade
};

enum ENUM_STRATEGY
{
   STRAT_TREND_FOLLOW = 0,   // Module A: Breakout / Trend Following
   STRAT_MEAN_REVERT  = 1,   // Module B: Mean Reversion / Grid Range
   STRAT_MICRO_SCALP  = 2,   // Module C: Micro-Scalping (quiet sessions)
   STRAT_NONE         = 3    // No strategy — sidelined
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "══════════ PAIRS TO SCAN ══════════"
input string   InpPairs = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCHF,NZDUSD,USDCAD,EURJPY,GBPJPY,XAUUSD";
input ENUM_TIMEFRAMES InpAnalysisTF     = PERIOD_M15;   // Analysis timeframe
input ENUM_TIMEFRAMES InpScalpTF        = PERIOD_M1;    // Scalping timeframe
input int      InpScanIntervalSec       = 60;           // Re-scan interval (seconds)

input group "══════════ REGIME CLASSIFIER ══════════"
input int      InpADXPeriod             = 14;           // ADX period
input int      InpATRPeriod             = 14;           // ATR period
input double   InpADXTrendThresh        = 25.0;         // ADX above this = trending
input double   InpADXRangeThresh        = 20.0;         // ADX below this = ranging
input double   InpATRVolatileMult       = 1.3;          // ATR > SMA*this = high volatility
input double   InpATRQuietMult          = 0.7;          // ATR < SMA*this = low volatility

input group "══════════ STRATEGY A: TREND FOLLOWING ══════════"
input int      InpTrendFastMA           = 9;            // Fast EMA period
input int      InpTrendSlowMA           = 21;           // Slow EMA period
input double   InpTrendRR               = 2.0;          // Reward:Risk ratio
input double   InpTrendSLATR            = 1.5;          // SL = ATR * this

input group "══════════ STRATEGY B: MEAN REVERSION ══════════"
input int      InpBBPeriod              = 20;           // Bollinger Band period
input double   InpBBDeviation           = 2.0;          // BB standard deviation
input int      InpRSIPeriod             = 14;           // RSI period
input double   InpRSIOverbought         = 70.0;         // RSI overbought level
input double   InpRSIOversold           = 30.0;         // RSI oversold level
input double   InpMRSLATR               = 1.0;          // SL = ATR * this
input double   InpMRTPATR               = 1.5;          // TP = ATR * this

input group "══════════ STRATEGY C: MICRO-SCALPING ══════════"
input int      InpScalpRSI              = 7;            // RSI period for scalp
input double   InpScalpRSIBuy           = 35.0;         // RSI below = buy signal
input double   InpScalpRSISell          = 65.0;         // RSI above = sell signal
input double   InpScalpTPPoints         = 50;           // TP in points
input double   InpScalpSLPoints         = 30;           // SL in points

input group "══════════ RISK MANAGEMENT ══════════"
input double   InpMaxRiskPerTrade       = 1.0;          // Max risk per trade (% of balance)
input double   InpMaxTotalRisk          = 5.0;          // Max total open risk (% of balance)
input int      InpMaxTradesPerPair      = 1;            // Max trades per pair
input int      InpMaxTotalTrades        = 10;           // Max total trades across all pairs
input double   InpMaxDailyDD            = 3.0;          // Max daily drawdown (%)
input double   InpMaxSpreadMult         = 2.0;          // Max spread vs average multiplier
input bool     InpUseCorrelationFilter  = true;         // Enable correlation filter
input double   InpCorrelationMax        = 0.70;         // Max correlation to allow both trades

input group "══════════ SYSTEM ══════════"
input int      InpMagicBase             = 900000;       // Base magic number
input int      InpSlippage              = 30;           // Max slippage (points)

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct PairData
{
   string         symbol;
   bool           active;
   
   // Indicator handles
   int            hADX;
   int            hATR;
   int            hATRSlow;
   int            hFastMA;
   int            hSlowMA;
   int            hBB;
   int            hRSI;
   int            hScalpRSI;
   
   // Regime
   ENUM_REGIME    regime;
   ENUM_STRATEGY  assignedStrategy;
   double         adxValue;
   double         atrValue;
   double         atrSMA;
   double         adxPlus;
   double         adxMinus;
   
   // Strategy-specific cached values
   double         fastMA;
   double         slowMA;
   double         prevFastMA;
   double         prevSlowMA;
   double         bbUpper;
   double         bbLower;
   double         bbMiddle;
   double         rsiValue;
   double         scalpRSI;
   double         currentSpread;
   double         avgSpread;
   
   // Performance tracking
   int            recentWins;
   int            recentLosses;
   double         recentPnL;
   int            openTrades;
   
   // Correlation
   double         closeData[];
};

struct StrategyPerformance
{
   int            trades;
   int            wins;
   int            losses;
   double         totalPnL;
   double         winRate;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_posInfo;

PairData       g_pairs[];
int            g_pairCount;

StrategyPerformance g_stratPerf[MAX_STRATEGIES];

datetime       g_lastScanTime;
datetime       g_dayStart;
double         g_dayStartBalance;
bool           g_haltDaily;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Parse pairs
   string pairList[];
   g_pairCount = StringSplit(InpPairs, ',', pairList);
   if(g_pairCount <= 0 || g_pairCount > MAX_PAIRS)
   {
      Print("ERROR: Invalid pair list. Found ", g_pairCount, " pairs.");
      return INIT_FAILED;
   }
   
   ArrayResize(g_pairs, g_pairCount);
   
   // Initialize each pair
   for(int i = 0; i < g_pairCount; i++)
   {
      StringTrimLeft(pairList[i]);
      StringTrimRight(pairList[i]);
      g_pairs[i].symbol = pairList[i];
      g_pairs[i].active = false;
      g_pairs[i].regime = REGIME_SIDELINES;
      g_pairs[i].assignedStrategy = STRAT_NONE;
      g_pairs[i].recentWins = 0;
      g_pairs[i].recentLosses = 0;
      g_pairs[i].recentPnL = 0;
      g_pairs[i].openTrades = 0;
      
      // Check symbol exists in Market Watch
      if(!SymbolSelect(pairList[i], true))
      {
         Print("WARNING: Symbol ", pairList[i], " not available. Skipping.");
         continue;
      }
      
      // Create indicator handles
      g_pairs[i].hADX = iADX(pairList[i], InpAnalysisTF, InpADXPeriod);
      g_pairs[i].hATR = iATR(pairList[i], InpAnalysisTF, InpATRPeriod);
      g_pairs[i].hATRSlow = iATR(pairList[i], InpAnalysisTF, InpATRPeriod * 3);
      g_pairs[i].hFastMA = iMA(pairList[i], InpAnalysisTF, InpTrendFastMA, 0, MODE_EMA, PRICE_CLOSE);
      g_pairs[i].hSlowMA = iMA(pairList[i], InpAnalysisTF, InpTrendSlowMA, 0, MODE_EMA, PRICE_CLOSE);
      g_pairs[i].hBB = iBands(pairList[i], InpAnalysisTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      g_pairs[i].hRSI = iRSI(pairList[i], InpAnalysisTF, InpRSIPeriod, PRICE_CLOSE);
      g_pairs[i].hScalpRSI = iRSI(pairList[i], InpScalpTF, InpScalpRSI, PRICE_CLOSE);
      
      if(g_pairs[i].hADX == INVALID_HANDLE || g_pairs[i].hATR == INVALID_HANDLE ||
         g_pairs[i].hFastMA == INVALID_HANDLE || g_pairs[i].hSlowMA == INVALID_HANDLE ||
         g_pairs[i].hBB == INVALID_HANDLE || g_pairs[i].hRSI == INVALID_HANDLE)
      {
         Print("WARNING: Failed to create indicators for ", pairList[i]);
         continue;
      }
      
      g_pairs[i].active = true;
   }
   
   // Strategy performance init
   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      g_stratPerf[i].trades = 0;
      g_stratPerf[i].wins = 0;
      g_stratPerf[i].losses = 0;
      g_stratPerf[i].totalPnL = 0;
      g_stratPerf[i].winRate = 0;
   }
   
   g_lastScanTime = 0;
   g_dayStart = 0;
   g_dayStartBalance = g_account.Balance();
   g_haltDaily = false;
   
   int activePairs = 0;
   for(int i = 0; i < g_pairCount; i++)
      if(g_pairs[i].active) activePairs++;
   
   Print("══════════════════════════════════════════════════════");
   Print("   ADAPTIVE MULTI-STRATEGY FRAMEWORK v1.0");
   Print("══════════════════════════════════════════════════════");
   Print("Active Pairs:     ", activePairs, " / ", g_pairCount);
   Print("Analysis TF:      ", EnumToString(InpAnalysisTF));
   Print("Scan Interval:    ", InpScanIntervalSec, "s");
   Print("Max Risk/Trade:   ", InpMaxRiskPerTrade, "%");
   Print("Max Total Risk:   ", InpMaxTotalRisk, "%");
   Print("Max Daily DD:     ", InpMaxDailyDD, "%");
   Print("Correlation:      ", InpUseCorrelationFilter ? "ON" : "OFF");
   Print("══════════════════════════════════════════════════════");
   for(int i = 0; i < g_pairCount; i++)
      if(g_pairs[i].active) Print("  ✓ ", g_pairs[i].symbol);
   Print("══════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      IndicatorRelease(g_pairs[i].hADX);
      IndicatorRelease(g_pairs[i].hATR);
      IndicatorRelease(g_pairs[i].hATRSlow);
      IndicatorRelease(g_pairs[i].hFastMA);
      IndicatorRelease(g_pairs[i].hSlowMA);
      IndicatorRelease(g_pairs[i].hBB);
      IndicatorRelease(g_pairs[i].hRSI);
      if(g_pairs[i].hScalpRSI != INVALID_HANDLE)
         IndicatorRelease(g_pairs[i].hScalpRSI);
   }
   
   Print("═══ PERFORMANCE SUMMARY ═══");
   Print("Trend Following: ", g_stratPerf[0].wins, "W / ", g_stratPerf[0].losses, "L | PnL: $", DoubleToString(g_stratPerf[0].totalPnL, 2));
   Print("Mean Reversion:  ", g_stratPerf[1].wins, "W / ", g_stratPerf[1].losses, "L | PnL: $", DoubleToString(g_stratPerf[1].totalPnL, 2));
   Print("Micro-Scalping:  ", g_stratPerf[2].wins, "W / ", g_stratPerf[2].losses, "L | PnL: $", DoubleToString(g_stratPerf[2].totalPnL, 2));
}

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   //=== Daily reset ===
   CheckDayReset();
   if(g_haltDaily) return;
   
   //=== Daily drawdown check ===
   if(InpMaxDailyDD > 0 && g_dayStartBalance > 0)
   {
      double dd = (g_dayStartBalance - g_account.Equity()) / g_dayStartBalance * 100.0;
      if(dd >= InpMaxDailyDD)
      {
         if(!g_haltDaily)
         {
            Print("⚠ DAILY DD LIMIT: ", DoubleToString(dd, 1), "% - Halting all trading");
            g_haltDaily = true;
         }
         return;
      }
   }
   
   //=== Count open positions per pair ===
   UpdateOpenCounts();
   
   //=== Periodic full scan ===
   if(TimeCurrent() - g_lastScanTime >= InpScanIntervalSec)
   {
      FullScan();
      g_lastScanTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| FULL MARKET SCAN                                                  |
//| Updates indicators, classifies regimes, executes strategies       |
//+------------------------------------------------------------------+
void FullScan()
{
   // Phase 1: Update all indicator data
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      UpdatePairData(i);
   }
   
   // Phase 2: Classify regime for each pair
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      ClassifyRegime(i);
      AssignStrategy(i);
   }
   
   // Phase 3: Correlation filter
   if(InpUseCorrelationFilter)
      ApplyCorrelationFilter();
   
   // Phase 4: Execute strategy for each eligible pair
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active) continue;
      if(g_pairs[i].assignedStrategy == STRAT_NONE) continue;
      if(g_pairs[i].openTrades >= InpMaxTradesPerPair) continue;
      if(CountTotalTrades() >= InpMaxTotalTrades) break;
      if(!CheckSpread(i)) continue;
      if(!CheckTotalRisk()) continue;
      
      ExecuteStrategy(i);
   }
}

//+------------------------------------------------------------------+
//| UPDATE INDICATOR DATA FOR A PAIR                                  |
//+------------------------------------------------------------------+
void UpdatePairData(int idx)
{
   string sym = g_pairs[idx].symbol;
   
   // ADX
   double adx[], adxP[], adxM[];
   if(CopyBuffer(g_pairs[idx].hADX, 0, 0, 2, adx) >= 1)
      g_pairs[idx].adxValue = adx[0];
   if(CopyBuffer(g_pairs[idx].hADX, 1, 0, 2, adxP) >= 1)
      g_pairs[idx].adxPlus = adxP[0];
   if(CopyBuffer(g_pairs[idx].hADX, 2, 0, 2, adxM) >= 1)
      g_pairs[idx].adxMinus = adxM[0];
   
   // ATR
   double atr[];
   if(CopyBuffer(g_pairs[idx].hATR, 0, 0, 2, atr) >= 1)
      g_pairs[idx].atrValue = atr[0];
   
   // ATR SMA (slow ATR as baseline)
   double atrSlow[];
   if(CopyBuffer(g_pairs[idx].hATRSlow, 0, 0, 2, atrSlow) >= 1)
      g_pairs[idx].atrSMA = atrSlow[0];
   
   // Moving Averages
   double fast[], slow[];
   if(CopyBuffer(g_pairs[idx].hFastMA, 0, 0, 3, fast) >= 2)
   {
      g_pairs[idx].fastMA = fast[0];
      g_pairs[idx].prevFastMA = fast[1];
   }
   if(CopyBuffer(g_pairs[idx].hSlowMA, 0, 0, 3, slow) >= 2)
   {
      g_pairs[idx].slowMA = slow[0];
      g_pairs[idx].prevSlowMA = slow[1];
   }
   
   // Bollinger Bands
   double bbM[], bbU[], bbL[];
   if(CopyBuffer(g_pairs[idx].hBB, 0, 0, 2, bbM) >= 1)
      g_pairs[idx].bbMiddle = bbM[0];
   if(CopyBuffer(g_pairs[idx].hBB, 1, 0, 2, bbU) >= 1)
      g_pairs[idx].bbUpper = bbU[0];
   if(CopyBuffer(g_pairs[idx].hBB, 2, 0, 2, bbL) >= 1)
      g_pairs[idx].bbLower = bbL[0];
   
   // RSI
   double rsi[];
   if(CopyBuffer(g_pairs[idx].hRSI, 0, 0, 2, rsi) >= 1)
      g_pairs[idx].rsiValue = rsi[0];
   
   // Scalp RSI
   double srsi[];
   if(g_pairs[idx].hScalpRSI != INVALID_HANDLE && CopyBuffer(g_pairs[idx].hScalpRSI, 0, 0, 2, srsi) >= 1)
      g_pairs[idx].scalpRSI = srsi[0];
   
   // Spread
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   g_pairs[idx].currentSpread = (point > 0) ? (ask - bid) / point : 0;
   if(g_pairs[idx].avgSpread == 0)
      g_pairs[idx].avgSpread = g_pairs[idx].currentSpread;
   else
      g_pairs[idx].avgSpread = g_pairs[idx].avgSpread * 0.95 + g_pairs[idx].currentSpread * 0.05;
   
   // Close data for correlation
   double closes[];
   if(CopyClose(sym, InpAnalysisTF, 0, CORR_LOOKBACK, closes) >= CORR_LOOKBACK)
   {
      ArrayResize(g_pairs[idx].closeData, CORR_LOOKBACK);
      ArrayCopy(g_pairs[idx].closeData, closes);
   }
}

//+------------------------------------------------------------------+
//| REGIME CLASSIFIER                                                 |
//| Uses ADX (trend strength) + ATR (volatility) to classify          |
//+------------------------------------------------------------------+
void ClassifyRegime(int idx)
{
   double adx = g_pairs[idx].adxValue;
   double atr = g_pairs[idx].atrValue;
   double atrSMA = g_pairs[idx].atrSMA;
   
   bool strongTrend = (adx > InpADXTrendThresh);
   bool ranging = (adx < InpADXRangeThresh);
   bool highVol = (atrSMA > 0 && atr > atrSMA * InpATRVolatileMult);
   bool lowVol = (atrSMA > 0 && atr < atrSMA * InpATRQuietMult);
   
   if(strongTrend && !highVol)
   {
      // Clean trend — ideal for trend following
      if(g_pairs[idx].adxPlus > g_pairs[idx].adxMinus)
         g_pairs[idx].regime = REGIME_TREND_BULL;
      else
         g_pairs[idx].regime = REGIME_TREND_BEAR;
   }
   else if(ranging && lowVol)
   {
      // Quiet ranging — ideal for mean reversion or scalping
      g_pairs[idx].regime = REGIME_RANGE;
   }
   else if(highVol && !strongTrend)
   {
      // Volatile but directionless — dangerous for most strategies
      g_pairs[idx].regime = REGIME_VOLATILE_RANGE;
   }
   else
   {
      // Ambiguous — sideline this pair
      g_pairs[idx].regime = REGIME_SIDELINES;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY ASSIGNMENT                                               |
//| Maps regime → best strategy module                                |
//+------------------------------------------------------------------+
void AssignStrategy(int idx)
{
   switch(g_pairs[idx].regime)
   {
      case REGIME_TREND_BULL:
      case REGIME_TREND_BEAR:
         g_pairs[idx].assignedStrategy = STRAT_TREND_FOLLOW;
         break;
         
      case REGIME_RANGE:
      {
         // Quiet range: use mean reversion or scalping based on session
         MqlDateTime dt;
         TimeCurrent(dt);
         int hour = dt.hour;
         // Asian session (quiet hours) → micro-scalp; otherwise → mean reversion
         if(hour >= 0 && hour < 8)
            g_pairs[idx].assignedStrategy = STRAT_MICRO_SCALP;
         else
            g_pairs[idx].assignedStrategy = STRAT_MEAN_REVERT;
         break;
      }
      
      case REGIME_VOLATILE_RANGE:
         // Too choppy for most strategies — sideline unless mean reversion
         // has been performing well recently
         if(g_stratPerf[STRAT_MEAN_REVERT].winRate > 60)
            g_pairs[idx].assignedStrategy = STRAT_MEAN_REVERT;
         else
            g_pairs[idx].assignedStrategy = STRAT_NONE;
         break;
         
      default:
         g_pairs[idx].assignedStrategy = STRAT_NONE;
         break;
   }
}

//+------------------------------------------------------------------+
//| CORRELATION FILTER                                                |
//| If two correlated pairs want to trade same direction, only keep   |
//| the one with stronger setup                                       |
//+------------------------------------------------------------------+
void ApplyCorrelationFilter()
{
   for(int i = 0; i < g_pairCount; i++)
   {
      if(!g_pairs[i].active || g_pairs[i].assignedStrategy == STRAT_NONE) continue;
      
      for(int j = i + 1; j < g_pairCount; j++)
      {
         if(!g_pairs[j].active || g_pairs[j].assignedStrategy == STRAT_NONE) continue;
         
         // Only filter if both want same direction
         bool iBuy = (g_pairs[i].regime == REGIME_TREND_BULL) || 
                     (g_pairs[i].assignedStrategy == STRAT_MEAN_REVERT && g_pairs[i].rsiValue < 50);
         bool jBuy = (g_pairs[j].regime == REGIME_TREND_BULL) ||
                     (g_pairs[j].assignedStrategy == STRAT_MEAN_REVERT && g_pairs[j].rsiValue < 50);
         
         if(iBuy != jBuy) continue; // Different directions = OK
         
         // Calculate correlation
         double corr = CalculateCorrelation(i, j);
         
         if(MathAbs(corr) > InpCorrelationMax)
         {
            // Disable the weaker setup (lower ADX = weaker trend signal)
            if(g_pairs[i].adxValue >= g_pairs[j].adxValue)
            {
               g_pairs[j].assignedStrategy = STRAT_NONE;
               // Print("  Corr filter: Disabled ", g_pairs[j].symbol, " (r=", DoubleToString(corr, 2), " with ", g_pairs[i].symbol, ")");
            }
            else
            {
               g_pairs[i].assignedStrategy = STRAT_NONE;
               // Print("  Corr filter: Disabled ", g_pairs[i].symbol, " (r=", DoubleToString(corr, 2), " with ", g_pairs[j].symbol, ")");
               break;
            }
         }
      }
   }
}

double CalculateCorrelation(int i, int j)
{
   int sizeI = ArraySize(g_pairs[i].closeData);
   int sizeJ = ArraySize(g_pairs[j].closeData);
   int n = MathMin(sizeI, sizeJ);
   if(n < 20) return 0;
   
   // Calculate returns
   double retI[], retJ[];
   ArrayResize(retI, n - 1);
   ArrayResize(retJ, n - 1);
   
   for(int k = 1; k < n; k++)
   {
      retI[k-1] = (g_pairs[i].closeData[k] > 0) ? (g_pairs[i].closeData[k] - g_pairs[i].closeData[k-1]) / g_pairs[i].closeData[k-1] : 0;
      retJ[k-1] = (g_pairs[j].closeData[k] > 0) ? (g_pairs[j].closeData[k] - g_pairs[j].closeData[k-1]) / g_pairs[j].closeData[k-1] : 0;
   }
   
   int m = n - 1;
   double sumI = 0, sumJ = 0, sumII = 0, sumJJ = 0, sumIJ = 0;
   for(int k = 0; k < m; k++)
   {
      sumI += retI[k];
      sumJ += retJ[k];
      sumII += retI[k] * retI[k];
      sumJJ += retJ[k] * retJ[k];
      sumIJ += retI[k] * retJ[k];
   }
   
   double meanI = sumI / m;
   double meanJ = sumJ / m;
   double varI = sumII / m - meanI * meanI;
   double varJ = sumJJ / m - meanJ * meanJ;
   double covIJ = sumIJ / m - meanI * meanJ;
   
   double denom = MathSqrt(varI * varJ);
   if(denom <= 0) return 0;
   
   return covIJ / denom;
}

//+------------------------------------------------------------------+
//| EXECUTE STRATEGY FOR A PAIR                                       |
//+------------------------------------------------------------------+
void ExecuteStrategy(int idx)
{
   switch(g_pairs[idx].assignedStrategy)
   {
      case STRAT_TREND_FOLLOW:
         ExecuteTrendFollowing(idx);
         break;
      case STRAT_MEAN_REVERT:
         ExecuteMeanReversion(idx);
         break;
      case STRAT_MICRO_SCALP:
         ExecuteMicroScalp(idx);
         break;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY A: TREND FOLLOWING                                       |
//| Entry: EMA crossover in direction of ADX trend                    |
//| SL: ATR-based | TP: RR ratio                                     |
//+------------------------------------------------------------------+
void ExecuteTrendFollowing(int idx)
{
   string sym = g_pairs[idx].symbol;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   // Check for EMA crossover
   bool crossUp = (g_pairs[idx].prevFastMA <= g_pairs[idx].prevSlowMA && g_pairs[idx].fastMA > g_pairs[idx].slowMA);
   bool crossDown = (g_pairs[idx].prevFastMA >= g_pairs[idx].prevSlowMA && g_pairs[idx].fastMA < g_pairs[idx].slowMA);
   
   // Or: already crossed and price pulling back to MA zone
   bool trendUp = (g_pairs[idx].fastMA > g_pairs[idx].slowMA && g_pairs[idx].regime == REGIME_TREND_BULL);
   bool trendDown = (g_pairs[idx].fastMA < g_pairs[idx].slowMA && g_pairs[idx].regime == REGIME_TREND_BEAR);
   
   double atr = g_pairs[idx].atrValue;
   if(atr <= 0) return;
   
   double slDist = atr * InpTrendSLATR;
   double tpDist = slDist * InpTrendRR;
   
   int magic = InpMagicBase + idx * 10 + STRAT_TREND_FOLLOW;
   g_trade.SetExpertMagicNumber(magic);
   
   if(crossUp || (trendUp && g_pairs[idx].openTrades == 0))
   {
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = NormalizeDouble(ask + tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Buy(lots, sym, ask, sl, tp, "AMS_Trend_" + sym))
         {
            Print("[TREND] BUY ", sym, " | Lot: ", DoubleToString(lots, 2), " | Regime: TREND_BULL");
            g_pairs[idx].openTrades++;
         }
      }
   }
   else if(crossDown || (trendDown && g_pairs[idx].openTrades == 0))
   {
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = NormalizeDouble(bid - tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Sell(lots, sym, bid, sl, tp, "AMS_Trend_" + sym))
         {
            Print("[TREND] SELL ", sym, " | Lot: ", DoubleToString(lots, 2), " | Regime: TREND_BEAR");
            g_pairs[idx].openTrades++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY B: MEAN REVERSION                                        |
//| Entry: RSI extreme + price at Bollinger Band boundary             |
//| SL/TP: ATR-based                                                  |
//+------------------------------------------------------------------+
void ExecuteMeanReversion(int idx)
{
   string sym = g_pairs[idx].symbol;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double atr = g_pairs[idx].atrValue;
   if(atr <= 0) return;
   
   double slDist = atr * InpMRSLATR;
   double tpDist = atr * InpMRTPATR;
   
   int magic = InpMagicBase + idx * 10 + STRAT_MEAN_REVERT;
   g_trade.SetExpertMagicNumber(magic);
   
   // Buy signal: price near lower BB + RSI oversold
   if(bid <= g_pairs[idx].bbLower && g_pairs[idx].rsiValue <= InpRSIOversold)
   {
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = NormalizeDouble(ask + tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Buy(lots, sym, ask, sl, tp, "AMS_MR_" + sym))
         {
            Print("[MR] BUY ", sym, " | RSI: ", DoubleToString(g_pairs[idx].rsiValue, 1), " | BB Low touch");
            g_pairs[idx].openTrades++;
         }
      }
   }
   
   // Sell signal: price near upper BB + RSI overbought
   if(ask >= g_pairs[idx].bbUpper && g_pairs[idx].rsiValue >= InpRSIOverbought)
   {
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = NormalizeDouble(bid - tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Sell(lots, sym, bid, sl, tp, "AMS_MR_" + sym))
         {
            Print("[MR] SELL ", sym, " | RSI: ", DoubleToString(g_pairs[idx].rsiValue, 1), " | BB High touch");
            g_pairs[idx].openTrades++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| STRATEGY C: MICRO-SCALPING                                        |
//| Entry: Fast RSI on M1, small TP/SL                                |
//| Best during quiet sessions (Asian)                                 |
//+------------------------------------------------------------------+
void ExecuteMicroScalp(int idx)
{
   string sym = g_pairs[idx].symbol;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   
   int magic = InpMagicBase + idx * 10 + STRAT_MICRO_SCALP;
   g_trade.SetExpertMagicNumber(magic);
   
   double slDist = InpScalpSLPoints * point;
   double tpDist = InpScalpTPPoints * point;
   
   // Buy: fast RSI oversold
   if(g_pairs[idx].scalpRSI < InpScalpRSIBuy)
   {
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = NormalizeDouble(ask + tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Buy(lots, sym, ask, sl, tp, "AMS_Scalp_" + sym))
         {
            Print("[SCALP] BUY ", sym, " | RSI(", InpScalpRSI, "): ", DoubleToString(g_pairs[idx].scalpRSI, 1));
            g_pairs[idx].openTrades++;
         }
      }
   }
   
   // Sell: fast RSI overbought
   if(g_pairs[idx].scalpRSI > InpScalpRSISell)
   {
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = NormalizeDouble(bid - tpDist, digits);
      double lots = CalculateLots(sym, slDist);
      if(lots > 0)
      {
         if(g_trade.Sell(lots, sym, bid, sl, tp, "AMS_Scalp_" + sym))
         {
            Print("[SCALP] SELL ", sym, " | RSI(", InpScalpRSI, "): ", DoubleToString(g_pairs[idx].scalpRSI, 1));
            g_pairs[idx].openTrades++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| RISK-BASED LOT SIZING                                             |
//+------------------------------------------------------------------+
double CalculateLots(string sym, double slDistance)
{
   if(slDistance <= 0) return 0;
   
   double balance = g_account.Balance();
   double riskMoney = balance * InpMaxRiskPerTrade / 100.0;
   
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   if(tickValue <= 0 || tickSize <= 0) return 0;
   
   double pointValue = tickValue / tickSize;
   double lots = riskMoney / (slDistance * pointValue / SymbolInfoDouble(sym, SYMBOL_POINT));
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, lotMin);
   lots = MathMin(lots, lotMax);
   
   return lots;
}

//+------------------------------------------------------------------+
//| SPREAD CHECK                                                      |
//+------------------------------------------------------------------+
bool CheckSpread(int idx)
{
   if(g_pairs[idx].avgSpread <= 0) return true;
   return (g_pairs[idx].currentSpread / g_pairs[idx].avgSpread) <= InpMaxSpreadMult;
}

//+------------------------------------------------------------------+
//| TOTAL RISK CHECK                                                  |
//+------------------------------------------------------------------+
bool CheckTotalRisk()
{
   double totalRisk = 0;
   double balance = g_account.Balance();
   if(balance <= 0) return false;
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         // Check if it belongs to us (magic in our range)
         long magic = g_posInfo.Magic();
         if(magic >= InpMagicBase && magic < InpMagicBase + MAX_PAIRS * 10 + MAX_STRATEGIES)
         {
            double risk = MathAbs(g_posInfo.PriceOpen() - g_posInfo.StopLoss());
            if(risk > 0)
            {
               double tickValue = SymbolInfoDouble(g_posInfo.Symbol(), SYMBOL_TRADE_TICK_VALUE);
               double tickSize = SymbolInfoDouble(g_posInfo.Symbol(), SYMBOL_TRADE_TICK_SIZE);
               if(tickSize > 0)
                  totalRisk += risk / tickSize * tickValue * g_posInfo.Volume();
            }
         }
      }
   }
   
   double riskPct = totalRisk / balance * 100.0;
   return (riskPct < InpMaxTotalRisk);
}

//+------------------------------------------------------------------+
//| COUNT OPEN TRADES PER PAIR                                        |
//+------------------------------------------------------------------+
void UpdateOpenCounts()
{
   for(int i = 0; i < g_pairCount; i++)
      g_pairs[i].openTrades = 0;
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         long magic = g_posInfo.Magic();
         if(magic >= InpMagicBase && magic < InpMagicBase + MAX_PAIRS * 10 + MAX_STRATEGIES)
         {
            string sym = g_posInfo.Symbol();
            for(int j = 0; j < g_pairCount; j++)
            {
               if(g_pairs[j].symbol == sym)
               {
                  g_pairs[j].openTrades++;
                  break;
               }
            }
         }
      }
   }
}

int CountTotalTrades()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         long magic = g_posInfo.Magic();
         if(magic >= InpMagicBase && magic < InpMagicBase + MAX_PAIRS * 10 + MAX_STRATEGIES)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                       |
//+------------------------------------------------------------------+
void CheckDayReset()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   MqlDateTime dtStart;
   TimeToStruct(g_dayStart, dtStart);
   
   if(dt.day != dtStart.day || g_dayStart == 0)
   {
      g_dayStart = TimeCurrent();
      g_dayStartBalance = g_account.Balance();
      g_haltDaily = false;
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION - Track performance per strategy                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic < InpMagicBase || magic >= InpMagicBase + MAX_PAIRS * 10 + MAX_STRATEGIES) return;
   
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + 
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   
   // Determine which strategy
   int stratIdx = (int)(magic % 10);
   if(stratIdx >= 0 && stratIdx < MAX_STRATEGIES)
   {
      g_stratPerf[stratIdx].trades++;
      g_stratPerf[stratIdx].totalPnL += profit;
      if(profit > 0)
         g_stratPerf[stratIdx].wins++;
      else
         g_stratPerf[stratIdx].losses++;
      
      if(g_stratPerf[stratIdx].trades > 0)
         g_stratPerf[stratIdx].winRate = (double)g_stratPerf[stratIdx].wins / g_stratPerf[stratIdx].trades * 100.0;
   }
   
   // Determine which pair
   int pairIdx = (int)((magic - InpMagicBase) / 10);
   if(pairIdx >= 0 && pairIdx < g_pairCount)
   {
      g_pairs[pairIdx].recentPnL += profit;
      if(profit > 0)
         g_pairs[pairIdx].recentWins++;
      else
         g_pairs[pairIdx].recentLosses++;
   }
   
   string stratName = "UNKNOWN";
   if(stratIdx == 0) stratName = "TREND";
   else if(stratIdx == 1) stratName = "MR";
   else if(stratIdx == 2) stratName = "SCALP";
   
   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   Print(StringFormat("[%s] %s closed | P/L: $%.2f | Strat WR: %.0f%%", stratName, sym, profit, 
         (stratIdx >= 0 && stratIdx < MAX_STRATEGIES) ? g_stratPerf[stratIdx].winRate : 0));
}
//+------------------------------------------------------------------+
