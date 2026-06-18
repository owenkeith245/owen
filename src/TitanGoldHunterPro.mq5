//+------------------------------------------------------------------+
//|                                        TitanGoldHunterPro.mq5    |
//|                        Institutional XAUUSD Trading Bot          |
//|                             Version 1.00                         |
//+------------------------------------------------------------------+
#property copyright "Titan Gold Hunter Pro"
#property link      ""
#property version   "1.00"
#property description "Institutional Gold EA - Liquidity, MSS, BOS, FVG"
#property description "Trades London & NY sessions, score >= 80"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Indicators\Trend.mqh>
#include <Indicators\Oscilators.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_BIAS
{
   BIAS_BULLISH,
   BIAS_BEARISH,
   BIAS_NEUTRAL
};

enum ENUM_SESSION
{
   SESSION_NONE,
   SESSION_LONDON,
   SESSION_NEWYORK
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== RISK MANAGEMENT ==="
input double   InpRiskPercent        = 1.0;          // Risk % per trade
input double   InpMaxDailyRisk       = 3.0;          // Max daily risk %
input int      InpMaxDailyLosses     = 3;            // Max consecutive losses
input double   InpMaxWeeklyDD        = 5.0;          // Max weekly drawdown %
input double   InpRR_Ratio1          = 2.0;          // TP1 Risk:Reward
input double   InpTrailStartR        = 1.0;          // Move SL to BE after X R
input double   InpTrailStepR         = 2.0;          // Start trailing after X R

input group "=== SESSION TIMES (EAT/UTC+3) ==="
input int      InpLondonStart        = 9;            // London open (EAT hour)
input int      InpLondonEnd          = 12;           // London close
input int      InpNewYorkStart       = 15;           // NY open
input int      InpNewYorkEnd         = 18;           // NY close

input group "=== TECHNICAL PARAMETERS ==="
input int      InpMA_Period          = 50;           // EMA period for bias
input int      InpATR_Period         = 20;           // ATR period
input double   InpDisplacementFactor = 1.5;          // Min body/ATR ratio
input double   InpATR_Mult_SL        = 0.5;          // SL buffer ATR multiplier
input double   InpVolatilityMinFactor= 0.8;          // ATR vs avg ATR min ratio
input double   InpSpreadMaxMult      = 2.0;          // Max spread multiplier

input group "=== NEWS FILTER ==="
input bool     InpUseNewsFilter      = true;         // Block news events
input int      InpNewsQuietMinutes   = 15;           // Minutes before/after

input group "=== SCORING WEIGHTS ==="
input int      InpScoreLiquidity     = 20;
input int      InpScoreMSS           = 15;
input int      InpScoreBOS           = 20;
input int      InpScoreFVG           = 15;
input int      InpScoreDisplacement  = 15;
input int      InpScoreVolatility    = 5;
input int      InpScoreSession       = 5;
input int      InpScoreTrend         = 5;

input group "=== MINIMUM SCORES ==="
input int      InpMinScoreElite      = 90;
input int      InpMinScoreStrong     = 80;
input int      InpMinScoreModerate   = 70;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
CAccountInfo   m_account;
CSymbolInfo    m_symbol;

CiMA           m_emaH4, m_emaH1;        // EMA using CiMA with MODE_EMA
CiATR          m_atrH1, m_atrM15;

MqlDateTime    m_time;
datetime       m_lastBarH4, m_lastBarH1, m_lastBarM15;

// Trade tracking
int            m_todayLosses = 0;
double         m_weekStartBalance = 0;
datetime       m_lastTradeDay = 0;
bool           m_haltDaily = false;
bool           m_haltWeekly = false;

// Setup storage
struct SetupInfo
{
   ENUM_BIAS      biasH4, biasH1;
   ENUM_SESSION   session;
   bool           liqSweepBull, liqSweepBear;
   bool           mssBull, mssBear;
   bool           bosBull, bosBear;
   bool           fvgBull, fvgBear;
   bool           displacementBull, displacementBear;
   bool           volatilityActive;
   double         score;
   datetime       time;
};
SetupInfo       m_setup;

// Dashboard
string          m_dashTrend, m_dashSession, m_dashVol, m_dashScore, m_dashStatus;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!m_symbol.Name(_Symbol))
      return INIT_FAILED;
   m_symbol.Refresh();
   
   m_trade.SetExpertMagicNumber(202406);
   m_trade.SetDeviationInPoints(30);
   m_trade.SetTypeFillingBySymbol(_Symbol);
   
   // Indicators: EMA using CiMA with MODE_EMA
   m_emaH4.Create(_Symbol, PERIOD_H4, InpMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   m_emaH1.Create(_Symbol, PERIOD_H1, InpMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   m_atrH1.Create(_Symbol, PERIOD_H1, InpATR_Period);
   m_atrM15.Create(_Symbol, PERIOD_M15, InpATR_Period);
   
   // Weekly reference
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 1) // Monday
      m_weekStartBalance = m_account.Balance();
   else
   {
      datetime monday = GetMondayMidnight();
      if(TimeCurrent() > monday)
         m_weekStartBalance = m_account.Balance();
   }
   
   m_lastBarH4 = 0;
   m_lastBarH1 = 0;
   m_lastBarM15 = 0;
   
   Print("Titan Gold Hunter Pro initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization - no manual cleanup required              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // CiMA/CiATR objects automatically release handles upon destruction.
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check daily/weekly halts
   if(m_haltWeekly) return;
   CheckNewDay();
   if(m_haltDaily) return;
   
   // Update time
   TimeCurrent(m_time);
   
   // Wait for new bar on M15
   if(!IsNewBar(PERIOD_M15, m_lastBarM15))
      return;
   
   // Refresh indicators
   m_emaH4.Refresh(-1);
   m_emaH1.Refresh(-1);
   m_atrH1.Refresh(-1);
   m_atrM15.Refresh(-1);
   
   // 1. Session filter
   m_setup.session = GetCurrentSession();
   if(m_setup.session == SESSION_NONE)
   {
      UpdateDashboard("NEUTRAL","CLOSED","LOW","0","WAITING SESSION");
      return;
   }
   
   // 2. Market bias (H4 & H1)
   m_setup.biasH4 = GetBias(PERIOD_H4, m_emaH4);
   m_setup.biasH1 = GetBias(PERIOD_H1, m_emaH1);
   if(m_setup.biasH4 != m_setup.biasH1 || m_setup.biasH4 == BIAS_NEUTRAL)
   {
      UpdateDashboard(m_setup.biasH4==BIAS_BULLISH?"BULLISH":"BEARISH",
                     SessionToString(m_setup.session),"LOW","0","BIAS MISMATCH");
      return;
   }
   
   // 3. Volatility filter
   double atrH1 = m_atrH1.Main(1);
   double avgATR = GetAverageATR(20, PERIOD_H1);
   m_setup.volatilityActive = (atrH1 >= avgATR * InpVolatilityMinFactor);
   if(!m_setup.volatilityActive)
   {
      UpdateDashboard(BiasToString(m_setup.biasH4),SessionToString(m_setup.session),
                     "LOW","0","VOLATILITY DEAD");
      return;
   }
   
   // 4. News filter
   if(InpUseNewsFilter && IsNewsEvent())
   {
      UpdateDashboard(BiasToString(m_setup.biasH4),SessionToString(m_setup.session),
                     VolString(),"0","NEWS EVENT");
      return;
   }
   
   // 5-9. Signal detection
   DetectLiquiditySweeps();
   DetectMSS();
   DetectBOS();
   DetectDisplacement();
   DetectFVG();
   
   // 10. Score
   CalculateScore();
   
   // 11. Decision
   string signal = "NONE";
   if(m_setup.biasH4 == BIAS_BULLISH && m_setup.liqSweepBull && m_setup.mssBull 
      && m_setup.bosBull && m_setup.fvgBull && m_setup.volatilityActive 
      && m_setup.score >= InpMinScoreStrong)
   {
      signal = "BUY";
   }
   else if(m_setup.biasH4 == BIAS_BEARISH && m_setup.liqSweepBear && m_setup.mssBear 
            && m_setup.bosBear && m_setup.fvgBear && m_setup.volatilityActive 
            && m_setup.score >= InpMinScoreStrong)
   {
      signal = "SELL";
   }
   
   UpdateDashboard(BiasToString(m_setup.biasH4),SessionToString(m_setup.session),
                  VolString(),DoubleToString(m_setup.score,0),signal);
   
   if(signal != "NONE" && !IsPositionOpen())
   {
      if(m_setup.score >= InpMinScoreStrong)
         ExecuteTrade(signal == "BUY" ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   }
   
   // Manage open positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                  |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastBar)
{
   datetime time[];
   if(CopyTime(_Symbol, tf, 0, 1, time) != 1)
      return false;
   if(time[0] != lastBar)
   {
      lastBar = time[0];
      return true;
   }
   return false;
}

ENUM_SESSION GetCurrentSession()
{
   int hour = m_time.hour;
   if(hour >= InpLondonStart && hour < InpLondonEnd)
      return SESSION_LONDON;
   if(hour >= InpNewYorkStart && hour < InpNewYorkEnd)
      return SESSION_NEWYORK;
   return SESSION_NONE;
}

ENUM_BIAS GetBias(ENUM_TIMEFRAMES tf, CiMA &ema)
{
   ema.Refresh(-1);
   double emaVal = ema.Main(1);
   double priceClose = iClose(_Symbol, tf, 1);
   
   double high[], low[], close[];
   if(CopyHigh(_Symbol, tf, 0, 20, high) < 20) return BIAS_NEUTRAL;
   if(CopyLow(_Symbol, tf, 0, 20, low) < 20) return BIAS_NEUTRAL;
   if(CopyClose(_Symbol, tf, 0, 20, close) < 20) return BIAS_NEUTRAL;
   
   bool higherHigh = false, higherLow = false;
   bool lowerHigh = false, lowerLow = false;
   
   if(high[1] > high[2]) higherHigh = true;
   if(low[1] > low[2]) higherLow = true;
   if(high[1] < high[2]) lowerHigh = true;
   if(low[1] < low[2]) lowerLow = true;
   
   if(higherHigh && higherLow && priceClose > emaVal)
      return BIAS_BULLISH;
   if(lowerHigh && lowerLow && priceClose < emaVal)
      return BIAS_BEARISH;
   return BIAS_NEUTRAL;
}

double GetAverageATR(int lookback, ENUM_TIMEFRAMES tf)
{
   CiATR atr;
   if(!atr.Create(_Symbol, tf, InpATR_Period))
      return 0;
   atr.Refresh(-1);
   double sum = 0;
   for(int i=1; i<=lookback; i++)
      sum += atr.Main(i);
   return sum / lookback;
}

void DetectLiquiditySweeps()
{
   double prevDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   double prevDayLow = iLow(_Symbol, PERIOD_D1, 1);
   double currHigh = iHigh(_Symbol, PERIOD_M15, 1);
   double currLow = iLow(_Symbol, PERIOD_M15, 1);
   
   m_setup.liqSweepBull = false;
   m_setup.liqSweepBear = false;
   
   if(currHigh > prevDayHigh && iClose(_Symbol, PERIOD_M15, 1) < prevDayHigh)
      m_setup.liqSweepBear = true;
   
   if(currLow < prevDayLow && iClose(_Symbol, PERIOD_M15, 1) > prevDayLow)
      m_setup.liqSweepBull = true;
}

void DetectMSS()
{
   m_setup.mssBull = false;
   m_setup.mssBear = false;
   
   double high[], low[];
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 5, high) < 5) return;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 5, low) < 5) return;
   
   if(m_setup.biasH1 == BIAS_BULLISH && iClose(_Symbol, PERIOD_H1, 1) > high[2])
      m_setup.mssBull = true;
   
   if(m_setup.biasH1 == BIAS_BEARISH && iClose(_Symbol, PERIOD_H1, 1) < low[2])
      m_setup.mssBear = true;
}

void DetectBOS()
{
   m_setup.bosBull = false;
   m_setup.bosBear = false;
   
   double high[], low[], close[];
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 20, high) < 20) return;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 20, low) < 20) return;
   if(CopyClose(_Symbol, PERIOD_H1, 0, 20, close) < 20) return;
   
   double swingHigh = high[1], swingLow = low[1];
   for(int i=2; i<10; i++)
   {
      if(high[i] > swingHigh) swingHigh = high[i];
      if(low[i] < swingLow) swingLow = low[i];
   }
   
   if(m_setup.biasH1 == BIAS_BULLISH && close[1] > swingHigh)
      m_setup.bosBull = true;
   if(m_setup.biasH1 == BIAS_BEARISH && close[1] < swingLow)
      m_setup.bosBear = true;
}

void DetectDisplacement()
{
   m_setup.displacementBull = false;
   m_setup.displacementBear = false;
   
   double open = iOpen(_Symbol, PERIOD_M15, 1);
   double close = iClose(_Symbol, PERIOD_M15, 1);
   double high = iHigh(_Symbol, PERIOD_M15, 1);
   double low = iLow(_Symbol, PERIOD_M15, 1);
   double body = MathAbs(close - open);
   double atr = m_atrM15.Main(1);
   if(atr <= 0) return;
   
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   if(body > InpDisplacementFactor * atr && upperWick < body*0.3 && lowerWick < body*0.3)
   {
      if(close > open)
         m_setup.displacementBull = true;
      else
         m_setup.displacementBear = true;
   }
}

void DetectFVG()
{
   m_setup.fvgBull = false;
   m_setup.fvgBear = false;
   
   double high1 = iHigh(_Symbol, PERIOD_M15, 2);
   double low1 = iLow(_Symbol, PERIOD_M15, 2);
   double high2 = iHigh(_Symbol, PERIOD_M15, 3);
   double low2 = iLow(_Symbol, PERIOD_M15, 3);
   double close2 = iClose(_Symbol, PERIOD_M15, 3);
   
   if(low1 > high2 && close2 > iOpen(_Symbol, PERIOD_M15, 3))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(currentPrice <= high2 && currentPrice >= low1 - 10*_Point)
         m_setup.fvgBull = true;
   }
   if(high1 < low2 && close2 < iOpen(_Symbol, PERIOD_M15, 3))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(currentPrice >= low2 && currentPrice <= high1 + 10*_Point)
         m_setup.fvgBear = true;
   }
}

void CalculateScore()
{
   int score = 0;
   if((m_setup.biasH4 == BIAS_BULLISH && m_setup.liqSweepBull) ||
      (m_setup.biasH4 == BIAS_BEARISH && m_setup.liqSweepBear))
      score += InpScoreLiquidity;
   if(m_setup.mssBull || m_setup.mssBear) score += InpScoreMSS;
   if(m_setup.bosBull || m_setup.bosBear) score += InpScoreBOS;
   if(m_setup.fvgBull || m_setup.fvgBear) score += InpScoreFVG;
   if(m_setup.displacementBull || m_setup.displacementBear) score += InpScoreDisplacement;
   if(m_setup.volatilityActive) score += InpScoreVolatility;
   if(m_setup.session != SESSION_NONE) score += InpScoreSession;
   if(m_setup.biasH4 == m_setup.biasH1) score += InpScoreTrend;
   
   m_setup.score = score;
}

void ExecuteTrade(ENUM_ORDER_TYPE type)
{
   double riskPercent = InpRiskPercent / 100.0;
   double balance = m_account.Balance();
   double riskMoney = balance * riskPercent;
   
   double atr = m_atrH1.Main(1);
   double slBuffer = InpATR_Mult_SL * atr;
   
   double entry, sl, tp1;
   double spread = (m_symbol.Ask() - m_symbol.Bid()) / _Point;
   double avgSpread = GetAverageSpread();
   if(spread > avgSpread * InpSpreadMaxMult) return;
   
   if(type == ORDER_TYPE_BUY)
   {
      entry = m_symbol.Ask();
      double liqLow = iLow(_Symbol, PERIOD_D1, 1);
      sl = liqLow - slBuffer;
      tp1 = entry + (entry - sl) * InpRR_Ratio1;
   }
   else
   {
      entry = m_symbol.Bid();
      double liqHigh = iHigh(_Symbol, PERIOD_D1, 1);
      sl = liqHigh + slBuffer;
      tp1 = entry - (sl - entry) * InpRR_Ratio1;
   }
   
   double pointValue = m_symbol.TickValue() / m_symbol.TickSize();
   double lotSize = riskMoney / (MathAbs(entry - sl) * pointValue);
   lotSize = NormalizeLot(lotSize);
   
   if(lotSize < m_symbol.LotsMin()) return;
   
   m_trade.PositionOpen(_Symbol, type, lotSize, entry, sl, tp1, "TitanGold");
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i>=0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() != _Symbol) continue;
         double entry = m_position.PriceOpen();
         double sl = m_position.StopLoss();
         double currentPrice = m_position.PositionType() == POSITION_TYPE_BUY ? 
                               m_symbol.Bid() : m_symbol.Ask();
         double atr = m_atrH1.Main(1);
         
         double risk = MathAbs(entry - sl);
         if(risk <= 0) continue;
         double profitR = (m_position.PositionType() == POSITION_TYPE_BUY ? 
                           currentPrice - entry : entry - currentPrice) / risk;
         
         if(profitR >= InpTrailStartR && (m_position.PositionType() == POSITION_TYPE_BUY ? 
            sl < entry : sl > entry))
         {
            m_trade.PositionModify(m_position.Ticket(), entry, m_position.TakeProfit());
            Print("SL moved to BE");
         }
         
         if(profitR >= InpTrailStepR)
         {
            double trailDist = 0.5 * atr;
            if(m_position.PositionType() == POSITION_TYPE_BUY)
            {
               double newSL = currentPrice - trailDist;
               if(newSL > sl)
                  m_trade.PositionModify(m_position.Ticket(), newSL, m_position.TakeProfit());
            }
            else
            {
               double newSL = currentPrice + trailDist;
               if(newSL < sl)
                  m_trade.PositionModify(m_position.Ticket(), newSL, m_position.TakeProfit());
            }
         }
      }
   }
}

bool IsPositionOpen()
{
   for(int i=0; i<PositionsTotal(); i++)
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol)
         return true;
   return false;
}

double NormalizeLot(double lot)
{
   double step = m_symbol.LotsStep();
   double minLot = m_symbol.LotsMin();
   double maxLot = m_symbol.LotsMax();
   lot = MathFloor(lot / step) * step;
   if(lot < minLot) return minLot;
   if(lot > maxLot) return maxLot;
   return lot;
}

double GetAverageSpread()
{
   return 30.0; // average for Gold
}

bool IsNewsEvent()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   // Block NFP (first Friday 15:30 EAT)
   if(dt.day_of_week == 5 && dt.day <= 7 && dt.hour == 15 && dt.min >= 30-InpNewsQuietMinutes && dt.min <= 30+InpNewsQuietMinutes)
      return true;
   return false;
}

void CheckNewDay()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day != m_lastTradeDay)
   {
      m_lastTradeDay = dt.day;
      m_todayLosses = 0;
      m_haltDaily = false;
   }
   if(dt.day_of_week == 1 && m_weekStartBalance == 0)
      m_weekStartBalance = m_account.Balance();
   if(m_weekStartBalance > 0)
   {
      double dd = (m_weekStartBalance - m_account.Balance()) / m_weekStartBalance * 100;
      if(dd > InpMaxWeeklyDD)
         m_haltWeekly = true;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            if(profit < 0)
               m_todayLosses++;
            if(m_todayLosses >= InpMaxDailyLosses)
               m_haltDaily = true;
         }
      }
   }
}

datetime GetMondayMidnight()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int daysSinceMonday = (dt.day_of_week == 0) ? 6 : dt.day_of_week - 1;
   datetime monday = TimeCurrent() - daysSinceMonday * 86400 - dt.hour*3600 - dt.min*60 - dt.sec;
   return monday;
}

string BiasToString(ENUM_BIAS bias)
{
   switch(bias)
   {
      case BIAS_BULLISH: return "BULLISH";
      case BIAS_BEARISH: return "BEARISH";
      default: return "NEUTRAL";
   }
}

string SessionToString(ENUM_SESSION sess)
{
   switch(sess)
   {
      case SESSION_LONDON: return "LONDON";
      case SESSION_NEWYORK: return "NEW YORK";
      default: return "CLOSED";
   }
}

string VolString()
{
   return m_setup.volatilityActive ? "HIGH" : "LOW";
}

void UpdateDashboard(string trend, string session, string vol, string score, string status)
{
   m_dashTrend = trend;
   m_dashSession = session;
   m_dashVol = vol;
   m_dashScore = score;
   m_dashStatus = status;
   
   Comment("TREND: ",m_dashTrend," | SESSION: ",m_dashSession,
           " | VOLATILITY: ",m_dashVol," | SCORE: ",m_dashScore,
           " | STATUS: ",m_dashStatus);
}
//+------------------------------------------------------------------+
