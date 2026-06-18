//+------------------------------------------------------------------+
//|                                            AIAnalysis.mqh         |
//|                     AI Market Analysis - Weighted Scoring         |
//+------------------------------------------------------------------+
#ifndef AI_ANALYSIS_MQH
#define AI_ANALYSIS_MQH

#include "TickEngine.mqh"

//+------------------------------------------------------------------+
//| Analysis module scores                                            |
//+------------------------------------------------------------------+
struct ModuleScores
{
   double trend;          // 0-100
   double liquidity;      // 0-100
   double momentum;       // 0-100
   double volume;         // 0-100
   double structure;      // 0-100
   double volatility;     // 0-100
   double spread;         // 0-100
};

struct AISignal
{
   double   buyScore;        // 0-100
   double   sellScore;       // 0-100
   double   confidence;      // 0-100
   string   direction;       // "BUY", "SELL", "NONE"
   int      quality;         // 0-5 stars
   ModuleScores modules;
   datetime signalTime;
};

//+------------------------------------------------------------------+
//| Weight configuration                                              |
//+------------------------------------------------------------------+
struct AnalysisWeights
{
   double trend;       // default 0.20
   double liquidity;   // default 0.20
   double momentum;    // default 0.15
   double volume;      // default 0.15
   double structure;   // default 0.15
   double volatility;  // default 0.10
   double spread;      // default 0.05
};

class CAIAnalysis
{
private:
   AnalysisWeights m_weights;
   int             m_emaPeriodFast;
   int             m_emaPeriodSlow;
   int             m_atrPeriod;
   int             m_rsiPeriod;
   double          m_minConfidence;
   
   // Indicator handles
   int             m_hEmaFast;
   int             m_hEmaSlow;
   int             m_hAtr;
   int             m_hRsi;
   int             m_hMacd;
   int             m_hAdx;
   
   string          m_symbol;
   ENUM_TIMEFRAMES m_tfScalp;  // M1 for structure context

public:
   AISignal signal;
   
   void Init(string symbol, double minConfidence = 85.0)
   {
      m_symbol = symbol;
      m_minConfidence = minConfidence;
      m_tfScalp = PERIOD_M1;
      m_emaPeriodFast = 9;
      m_emaPeriodSlow = 21;
      m_atrPeriod = 14;
      m_rsiPeriod = 7;
      
      // Default weights (sum = 1.0)
      m_weights.trend = 0.20;
      m_weights.liquidity = 0.20;
      m_weights.momentum = 0.15;
      m_weights.volume = 0.15;
      m_weights.structure = 0.15;
      m_weights.volatility = 0.10;
      m_weights.spread = 0.05;
      
      // Create indicator handles
      m_hEmaFast = iMA(m_symbol, m_tfScalp, m_emaPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(m_symbol, m_tfScalp, m_emaPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
      m_hAtr = iATR(m_symbol, m_tfScalp, m_atrPeriod);
      m_hRsi = iRSI(m_symbol, m_tfScalp, m_rsiPeriod, PRICE_CLOSE);
      m_hMacd = iMACD(m_symbol, m_tfScalp, 12, 26, 9, PRICE_CLOSE);
      m_hAdx = iADX(m_symbol, m_tfScalp, 14);
      
      ZeroMemory(signal);
   }
   
   void SetWeights(AnalysisWeights &weights) { m_weights = weights; }
   
   void Analyze(TickMetrics &tickMetrics)
   {
      // Get indicator values
      double emaFast[], emaSlow[], atr[], rsi[], macd[], macdSignal[], adx[];
      CopyBuffer(m_hEmaFast, 0, 0, 5, emaFast);
      CopyBuffer(m_hEmaSlow, 0, 0, 5, emaSlow);
      CopyBuffer(m_hAtr, 0, 0, 5, atr);
      CopyBuffer(m_hRsi, 0, 0, 5, rsi);
      CopyBuffer(m_hMacd, 0, 0, 5, macd);
      CopyBuffer(m_hMacd, 1, 0, 5, macdSignal);
      CopyBuffer(m_hAdx, 0, 0, 5, adx);
      
      if(ArraySize(emaFast) < 3) return;
      
      // Score each module
      signal.modules.trend = ScoreTrend(emaFast, emaSlow, adx);
      signal.modules.liquidity = ScoreLiquidity(tickMetrics);
      signal.modules.momentum = ScoreMomentum(rsi, macd, macdSignal, tickMetrics);
      signal.modules.volume = ScoreVolume(tickMetrics);
      signal.modules.structure = ScoreStructure(emaFast, emaSlow);
      signal.modules.volatility = ScoreVolatility(atr, tickMetrics);
      signal.modules.spread = ScoreSpread(tickMetrics);
      
      // Calculate weighted scores
      double buyRaw = CalculateDirectionalScore(true, tickMetrics, emaFast, emaSlow, rsi);
      double sellRaw = CalculateDirectionalScore(false, tickMetrics, emaFast, emaSlow, rsi);
      
      signal.buyScore = buyRaw;
      signal.sellScore = sellRaw;
      
      // Determine direction
      if(buyRaw > sellRaw && buyRaw >= m_minConfidence)
      {
         signal.direction = "BUY";
         signal.confidence = buyRaw;
      }
      else if(sellRaw > buyRaw && sellRaw >= m_minConfidence)
      {
         signal.direction = "SELL";
         signal.confidence = sellRaw;
      }
      else
      {
         signal.direction = "NONE";
         signal.confidence = MathMax(buyRaw, sellRaw);
      }
      
      // Quality rating (0-5 stars)
      signal.quality = (int)MathFloor(signal.confidence / 20.0);
      signal.signalTime = TimeCurrent();
   }
   
   bool IsSignalValid() { return signal.direction != "NONE" && signal.confidence >= m_minConfidence; }

private:
   double ScoreTrend(double &emaFast[], double &emaSlow[], double &adx[])
   {
      double score = 50.0; // neutral start
      
      // EMA alignment
      if(emaFast[0] > emaSlow[0])
         score += 20.0; // bullish trend
      else
         score -= 20.0;
      
      // EMA slope
      if(ArraySize(emaFast) >= 3)
      {
         double slope = emaFast[0] - emaFast[2];
         if(slope > 0) score += MathMin(slope * 1000, 15.0);
         else score -= MathMin(MathAbs(slope) * 1000, 15.0);
      }
      
      // ADX strength
      if(ArraySize(adx) > 0 && adx[0] > 25)
         score += MathMin((adx[0] - 25) * 0.5, 15.0);
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreLiquidity(TickMetrics &tm)
   {
      double score = 50.0;
      
      // Order flow imbalance
      score += tm.liquidityImbalance * 30.0;
      
      // Buy/sell pressure
      if(tm.buyPressure > 0.6)
         score += (tm.buyPressure - 0.5) * 40.0;
      else if(tm.sellPressure > 0.6)
         score -= (tm.sellPressure - 0.5) * 40.0;
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreMomentum(double &rsi[], double &macd[], double &macdSig[], TickMetrics &tm)
   {
      double score = 50.0;
      
      // RSI
      if(ArraySize(rsi) > 0)
      {
         if(rsi[0] > 50 && rsi[0] < 80)
            score += (rsi[0] - 50) * 0.5;
         else if(rsi[0] < 50 && rsi[0] > 20)
            score -= (50 - rsi[0]) * 0.5;
      }
      
      // MACD histogram
      if(ArraySize(macd) > 0 && ArraySize(macdSig) > 0)
      {
         double hist = macd[0] - macdSig[0];
         score += MathMin(MathMax(hist * 100, -20), 20);
      }
      
      // Tick velocity
      score += MathMin(tm.priceVelocity * 50, 15.0);
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreVolume(TickMetrics &tm)
   {
      double score = 50.0;
      
      // Tick speed (higher = more active)
      if(tm.tickSpeed > 5.0)
         score += MathMin((tm.tickSpeed - 5.0) * 3.0, 25.0);
      else if(tm.tickSpeed < 1.0)
         score -= 20.0;
      
      // Liquidity depth
      double totalDepth = tm.bidDepth + tm.askDepth;
      if(totalDepth > 0)
         score += MathMin(totalDepth * 0.001, 25.0);
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreStructure(double &emaFast[], double &emaSlow[])
   {
      double score = 50.0;
      
      // Higher highs / lower lows in EMA
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
      
      // EMA convergence/divergence
      if(ArraySize(emaFast) > 0 && ArraySize(emaSlow) > 0)
      {
         double gap = MathAbs(emaFast[0] - emaSlow[0]);
         score += MathMin(gap * 500, 25.0);
      }
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreVolatility(double &atr[], TickMetrics &tm)
   {
      double score = 50.0;
      
      // ATR in good range (not too high, not too low)
      if(ArraySize(atr) >= 3)
      {
         double avgAtr = (atr[0] + atr[1] + atr[2]) / 3.0;
         double ratio = (avgAtr > 0) ? atr[0] / avgAtr : 1.0;
         
         if(ratio >= 0.8 && ratio <= 1.5)
            score += 25.0; // healthy volatility
         else if(ratio > 2.0)
            score -= 25.0; // too volatile
         else if(ratio < 0.5)
            score -= 15.0; // too quiet
      }
      
      // Tick volatility
      if(tm.tickVolatility > 0 && tm.tickVolatility < 2.0)
         score += 15.0;
      else if(tm.tickVolatility > 5.0)
         score -= 15.0;
      
      return MathMax(0, MathMin(100, score));
   }
   
   double ScoreSpread(TickMetrics &tm)
   {
      double score = 100.0; // start at max, deduct for bad spread
      
      if(!tm.spreadNormal)
         score -= 50.0;
      
      if(tm.spreadRatio > 1.5)
         score -= (tm.spreadRatio - 1.0) * 20.0;
      else if(tm.spreadRatio < 1.2)
         score += 10.0;
      
      return MathMax(0, MathMin(100, score));
   }
   
   double CalculateDirectionalScore(bool isBuy, TickMetrics &tm, double &emaFast[], double &emaSlow[], double &rsi[])
   {
      double trendScore, liqScore, momScore;
      
      if(isBuy)
      {
         trendScore = (emaFast[0] > emaSlow[0]) ? signal.modules.trend : 100.0 - signal.modules.trend;
         liqScore = (tm.netFlow > 0) ? signal.modules.liquidity : 100.0 - signal.modules.liquidity;
         momScore = (ArraySize(rsi) > 0 && rsi[0] > 50) ? signal.modules.momentum : 100.0 - signal.modules.momentum;
      }
      else
      {
         trendScore = (emaFast[0] < emaSlow[0]) ? signal.modules.trend : 100.0 - signal.modules.trend;
         liqScore = (tm.netFlow < 0) ? signal.modules.liquidity : 100.0 - signal.modules.liquidity;
         momScore = (ArraySize(rsi) > 0 && rsi[0] < 50) ? signal.modules.momentum : 100.0 - signal.modules.momentum;
      }
      
      double weighted = trendScore * m_weights.trend
                      + liqScore * m_weights.liquidity
                      + momScore * m_weights.momentum
                      + signal.modules.volume * m_weights.volume
                      + signal.modules.structure * m_weights.structure
                      + signal.modules.volatility * m_weights.volatility
                      + signal.modules.spread * m_weights.spread;
      
      return MathMax(0, MathMin(100, weighted));
   }
};

#endif
