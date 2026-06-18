//+------------------------------------------------------------------+
//|                                          GoldAIScalper.mq5        |
//|               Commercial-Grade AI Scalping Bot for XAUUSD         |
//|                             Version 2.00                          |
//+------------------------------------------------------------------+
#property copyright "Gold AI Scalper"
#property link      ""
#property version   "2.00"
#property description "Tick-Based AI Scalping System for XAUUSD"
#property description "Multi-Module Architecture: Tick Engine + AI Analysis + Risk + Positions"
#property description "Operates on every tick with weighted confluence scoring"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "Include/TickEngine.mqh"
#include "Include/AIAnalysis.mqh"
#include "Include/RiskManager.mqh"
#include "Include/PositionManager.mqh"
#include "Include/SignalDetector.mqh"
#include "Include/NewsFilter.mqh"
#include "Include/ChartVisualizer.mqh"
#include "Include/TradeLogger.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== AI CONFIGURATION ==="
input double   InpMinConfidence      = 85.0;         // Minimum confidence to trade (%)
input double   InpWeightTrend        = 0.20;         // Trend weight
input double   InpWeightLiquidity    = 0.20;         // Liquidity weight
input double   InpWeightMomentum     = 0.15;         // Momentum weight
input double   InpWeightVolume       = 0.15;         // Volume weight
input double   InpWeightStructure    = 0.15;         // Structure weight
input double   InpWeightVolatility   = 0.10;         // Volatility weight
input double   InpWeightSpread       = 0.05;         // Spread weight

input group "=== RISK MANAGEMENT ==="
input double   InpMaxDailyRisk       = 2.0;          // Max daily risk (%)
input double   InpMaxTradeRisk       = 0.5;          // Max risk per trade (%)
input int      InpMaxOpenTrades      = 5;            // Max simultaneous trades
input double   InpMaxWeeklyDD        = 5.0;          // Max weekly drawdown (%)
input double   InpEmergencyDD        = 5.0;          // Emergency stop drawdown (%)
input int      InpMaxConsecLosses    = 5;            // Halt after N consecutive losses
input double   InpMaxSpreadMult      = 2.5;          // Max spread multiplier

input group "=== TRADE MANAGEMENT ==="
input double   InpRR1                = 2.0;          // TP1 Risk:Reward
input double   InpRR2                = 3.0;          // TP2 Risk:Reward
input double   InpRR3                = 5.0;          // TP3 Risk:Reward
input double   InpBreakEvenR         = 1.0;          // Move to BE at X R profit
input double   InpTrailStartR        = 2.0;          // Start trailing at X R
input double   InpPartialClose1      = 0.40;         // Close % at TP1
input double   InpPartialClose2      = 0.30;         // Close % at TP2
input double   InpTrailATRMult       = 0.5;          // Trail distance = ATR * this

input group "=== SESSION FILTER ==="
input int      InpLondonStart        = 9;            // London open (EAT hour)
input int      InpLondonEnd          = 12;           // London close
input int      InpNewYorkStart       = 15;           // NY open
input int      InpNewYorkEnd         = 18;           // NY close
input bool     InpTradeAsianSession  = false;        // Trade Asian session?

input group "=== NEWS FILTER ==="
input bool     InpUseNewsFilter      = true;         // Enable news filter
input int      InpNewsQuietMin       = 15;           // Quiet period (minutes)

input group "=== DISPLAY ==="
input bool     InpShowDashboard      = true;         // Show live dashboard
input bool     InpDrawZones          = true;         // Draw liquidity/FVG/OB zones
input bool     InpLogTrades          = true;         // Log trades to file

//+------------------------------------------------------------------+
//| GLOBAL MODULES                                                    |
//+------------------------------------------------------------------+
CTickEngine       g_tickEngine;
CAIAnalysis       g_aiAnalysis;
CRiskManager      g_riskManager;
CPositionManager  g_posManager;
CSignalDetector   g_signalDetector;
CNewsFilter       g_newsFilter;
CChartVisualizer  g_visualizer;
CTradeLogger      g_logger;

CAccountInfo      g_account;
CSymbolInfo       g_symbol;

// Timing
datetime          g_lastStructureUpdate = 0;
int               g_ticksSinceSignal = 0;
int               g_magic = 202500;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(!g_symbol.Name(_Symbol))
      return INIT_FAILED;
   g_symbol.Refresh();
   
   // Initialize all modules
   g_tickEngine.Init();
   g_aiAnalysis.Init(_Symbol, InpMinConfidence);
   g_riskManager.Init(_Symbol);
   g_posManager.Init(_Symbol, g_magic);
   g_signalDetector.Init(_Symbol);
   g_newsFilter.Init(InpNewsQuietMin, InpUseNewsFilter);
   g_visualizer.Init();
   g_logger.Init(_Symbol, InpLogTrades);
   
   // Configure weights
   AnalysisWeights weights;
   weights.trend = InpWeightTrend;
   weights.liquidity = InpWeightLiquidity;
   weights.momentum = InpWeightMomentum;
   weights.volume = InpWeightVolume;
   weights.structure = InpWeightStructure;
   weights.volatility = InpWeightVolatility;
   weights.spread = InpWeightSpread;
   g_aiAnalysis.SetWeights(weights);
   
   // Configure risk
   RiskConfig riskCfg;
   riskCfg.maxDailyRiskPercent = InpMaxDailyRisk;
   riskCfg.maxWeeklyRiskPercent = InpMaxWeeklyDD;
   riskCfg.maxSingleTradeRisk = InpMaxTradeRisk;
   riskCfg.maxOpenTrades = InpMaxOpenTrades;
   riskCfg.maxCorrelationExposure = 3.0;
   riskCfg.maxSpreadMultiplier = InpMaxSpreadMult;
   riskCfg.maxSlippage = 20.0;
   riskCfg.emergencyDrawdown = InpEmergencyDD;
   riskCfg.maxConsecutiveLosses = InpMaxConsecLosses;
   g_riskManager.SetConfig(riskCfg);
   
   // Configure position management
   g_posManager.SetManagementParams(InpBreakEvenR, InpTrailStartR, InpPartialClose1, InpPartialClose2, InpTrailATRMult);
   
   Print("Gold AI Scalper v2.0 initialized on ", _Symbol);
   Print("Min Confidence: ", InpMinConfidence, "% | Max Daily Risk: ", InpMaxDailyRisk, "%");
   Print("Max Trades: ", InpMaxOpenTrades, " | TP Ratios: ", InpRR1, "/", InpRR2, "/", InpRR3);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_visualizer.Cleanup();
   Print("Gold AI Scalper stopped. Total trades logged: ", g_logger.GetTradeCount());
}

//+------------------------------------------------------------------+
//| Expert tick function - CORE LOOP                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   // === 1. PROCESS TICK ===
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   g_tickEngine.ProcessTick(tick);
   g_symbol.Refresh();
   
   // === 2. RISK CHECKS ===
   g_riskManager.OnNewDay();
   g_riskManager.UpdateOpenTradeCount(g_posManager.GetOpenCount());
   
   if(!g_riskManager.CanTrade())
   {
      // Still manage existing positions
      ManageOpenPositions(tick);
      UpdateDisplay();
      return;
   }
   
   // === 3. SESSION FILTER ===
   if(!IsActiveSession())
   {
      ManageOpenPositions(tick);
      UpdateDisplay();
      return;
   }
   
   // === 4. NEWS FILTER ===
   if(g_newsFilter.IsNewsTime())
   {
      ManageOpenPositions(tick);
      UpdateDisplay();
      return;
   }
   
   // === 5. SPREAD FILTER ===
   if(!g_riskManager.CheckSpread(g_tickEngine.metrics.currentSpread, g_tickEngine.metrics.avgSpread))
   {
      ManageOpenPositions(tick);
      UpdateDisplay();
      return;
   }
   
   // === 6. STRUCTURE UPDATE (every 5 seconds) ===
   if(TimeCurrent() - g_lastStructureUpdate >= 5)
   {
      g_signalDetector.Update(tick.bid, tick.ask);
      g_lastStructureUpdate = TimeCurrent();
   }
   
   // === 7. AI ANALYSIS ===
   g_aiAnalysis.Analyze(g_tickEngine.metrics);
   
   // === 8. TRADE DECISION ===
   if(g_aiAnalysis.IsSignalValid() && g_ticksSinceSignal > 50)
   {
      ExecuteSignal(tick);
      g_ticksSinceSignal = 0;
   }
   else
   {
      g_ticksSinceSignal++;
   }
   
   // === 9. MANAGE POSITIONS ===
   ManageOpenPositions(tick);
   
   // === 10. UPDATE DISPLAY ===
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Execute a trade based on AI signal                                |
//+------------------------------------------------------------------+
void ExecuteSignal(MqlTick &tick)
{
   bool isBuy = (g_aiAnalysis.signal.direction == "BUY");
   
   // Calculate stop loss using ATR + structure
   double atr[];
   CopyBuffer(iATR(_Symbol, PERIOD_M1, 14), 0, 0, 1, atr);
   if(ArraySize(atr) == 0) return;
   
   double slDistance = atr[0] * 1.5; // 1.5 ATR for scalping
   
   // Use structure levels for better SL placement
   if(isBuy && g_signalDetector.state.nearestLiqLow > 0)
   {
      double structSL = tick.bid - g_signalDetector.state.nearestLiqLow;
      if(structSL > 0 && structSL < slDistance * 2)
         slDistance = structSL + atr[0] * 0.2; // below structure + buffer
   }
   else if(!isBuy && g_signalDetector.state.nearestLiqHigh < DBL_MAX)
   {
      double structSL = g_signalDetector.state.nearestLiqHigh - tick.ask;
      if(structSL > 0 && structSL < slDistance * 2)
         slDistance = structSL + atr[0] * 0.2;
   }
   
   double slPoints = slDistance / _Point;
   
   // Request risk allocation
   TradeRiskAllocation alloc = g_riskManager.AllocateRisk(slPoints, g_aiAnalysis.signal.confidence);
   if(!alloc.approved)
   {
      Print("Trade rejected: ", alloc.rejectReason);
      return;
   }
   
   // Build trade setup
   TradeSetup setup;
   setup.isBuy = isBuy;
   setup.entryPrice = isBuy ? tick.ask : tick.bid;
   setup.stopLoss = isBuy ? setup.entryPrice - slDistance : setup.entryPrice + slDistance;
   setup.lotSize = alloc.lotSize;
   setup.riskAmount = alloc.riskMoney;
   setup.confidence = g_aiAnalysis.signal.confidence;
   setup.atr = atr[0];
   setup.rrRatio1 = InpRR1;
   setup.rrRatio2 = InpRR2;
   setup.rrRatio3 = InpRR3;
   
   // Execute
   if(g_posManager.OpenTrade(setup))
   {
      g_riskManager.OnTradeOpened(alloc.riskMoney);
      
      if(InpDrawZones)
      {
         double tp1 = isBuy ? setup.entryPrice + slDistance * InpRR1 : setup.entryPrice - slDistance * InpRR1;
         g_visualizer.DrawEntry(setup.entryPrice, setup.stopLoss, tp1, isBuy);
      }
      
      Print(StringFormat("TRADE: %s | Conf: %.0f%% | Lots: %.2f | Risk: $%.2f | SL: %.2f pts",
            setup.isBuy ? "BUY" : "SELL", setup.confidence, setup.lotSize, setup.riskAmount, slPoints));
   }
}

//+------------------------------------------------------------------+
//| Manage all open positions                                         |
//+------------------------------------------------------------------+
void ManageOpenPositions(MqlTick &tick)
{
   double atr[];
   CopyBuffer(iATR(_Symbol, PERIOD_M1, 14), 0, 0, 1, atr);
   double currentATR = (ArraySize(atr) > 0) ? atr[0] : 0;
   
   g_posManager.ManageAll(tick.bid, tick.ask, currentATR);
}

//+------------------------------------------------------------------+
//| Check if we're in an active trading session                       |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(hour >= InpLondonStart && hour < InpLondonEnd) return true;
   if(hour >= InpNewYorkStart && hour < InpNewYorkEnd) return true;
   if(InpTradeAsianSession && hour >= 2 && hour < 9) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Update dashboard and chart drawings                               |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   if(!InpShowDashboard) return;
   
   RiskState riskState = g_riskManager.GetState();
   PerformanceStats stats = g_logger.GetStats();
   
   g_visualizer.DrawDashboard(
      g_aiAnalysis.signal,
      riskState,
      g_tickEngine.metrics,
      g_account.Balance(),
      g_account.Equity(),
      stats.winRate,
      g_posManager.GetOpenCount()
   );
   
   if(InpDrawZones)
   {
      g_visualizer.DrawLiquidityZones(g_signalDetector);
      g_visualizer.DrawFVGZones(g_signalDetector);
      g_visualizer.DrawOrderBlocks(g_signalDetector);
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler - log closed trades                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            
            // Log to trade logger
            TradeRecord record;
            ZeroMemory(record);
            record.closeTime = TimeCurrent();
            record.profit = profit;
            record.lots = volume;
            record.profitPercent = (g_account.Balance() > 0) ? profit / g_account.Balance() * 100 : 0;
            record.direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "SELL" : "BUY";
            record.exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            record.session = GetCurrentSessionName();
            record.confidence = g_aiAnalysis.signal.confidence;
            
            g_logger.LogTrade(record);
            g_riskManager.OnTradeClosed(profit, 0);
            g_visualizer.ClearEntry();
            
            Print(StringFormat("CLOSED: %s | Profit: $%.2f (%.2f%%) | Win Rate: %.0f%%",
                  record.direction, profit, record.profitPercent, g_logger.GetWinRate()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Get current session name                                  |
//+------------------------------------------------------------------+
string GetCurrentSessionName()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour >= InpLondonStart && dt.hour < InpLondonEnd) return "London";
   if(dt.hour >= InpNewYorkStart && dt.hour < InpNewYorkEnd) return "NewYork";
   return "Other";
}
//+------------------------------------------------------------------+
