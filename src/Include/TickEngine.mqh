//+------------------------------------------------------------------+
//|                                              TickEngine.mqh       |
//|                         Tick Data Processing Engine               |
//+------------------------------------------------------------------+
#ifndef TICK_ENGINE_MQH
#define TICK_ENGINE_MQH

#define TICK_BUFFER_SIZE 500

struct TickData
{
   double   bid;
   double   ask;
   double   spread;
   double   bidVolume;
   double   askVolume;
   datetime time;
   long     timeMs;
   int      flags;
};

struct TickMetrics
{
   // Order flow
   double   buyPressure;        // ratio of upticks
   double   sellPressure;       // ratio of downticks
   double   netFlow;            // buy - sell pressure
   
   // Momentum
   double   tickSpeed;          // ticks per second
   double   priceVelocity;      // price change per second
   double   acceleration;       // change in velocity
   
   // Spread analysis
   double   currentSpread;
   double   avgSpread;
   double   spreadRatio;        // current / average
   bool     spreadNormal;
   
   // Liquidity
   double   bidDepth;           // sum of bid volumes
   double   askDepth;           // sum of ask volumes
   double   liquidityImbalance; // (bid - ask) / (bid + ask)
   
   // Price levels
   double   highSinceReset;
   double   lowSinceReset;
   double   vwap;               // volume-weighted average price
   
   // Volatility (tick-based)
   double   tickVolatility;     // std dev of tick-to-tick moves
   double   rangePercent;       // (high - low) / avgPrice * 100
};

class CTickEngine
{
private:
   TickData    m_buffer[];
   int         m_bufferPos;
   int         m_tickCount;
   int         m_totalTicks;
   
   // Running calculations
   double      m_upticks;
   double      m_downticks;
   double      m_lastBid;
   double      m_lastAsk;
   long        m_lastTickMs;
   double      m_priceSum;
   double      m_volumeSum;
   double      m_spreadSum;
   double      m_bidVolSum;
   double      m_askVolSum;
   double      m_priceChanges[];
   int         m_changePos;
   double      m_lastVelocity;
   
   datetime    m_resetTime;
   double      m_highPrice;
   double      m_lowPrice;

public:
   TickMetrics metrics;
   
   void Init()
   {
      ArrayResize(m_buffer, TICK_BUFFER_SIZE);
      ArrayResize(m_priceChanges, TICK_BUFFER_SIZE);
      ArrayInitialize(m_priceChanges, 0);
      m_bufferPos = 0;
      m_tickCount = 0;
      m_totalTicks = 0;
      m_upticks = 0;
      m_downticks = 0;
      m_lastBid = 0;
      m_lastAsk = 0;
      m_lastTickMs = 0;
      m_priceSum = 0;
      m_volumeSum = 0;
      m_spreadSum = 0;
      m_bidVolSum = 0;
      m_askVolSum = 0;
      m_changePos = 0;
      m_lastVelocity = 0;
      m_resetTime = TimeCurrent();
      m_highPrice = 0;
      m_lowPrice = DBL_MAX;
      ZeroMemory(metrics);
   }
   
   void ProcessTick(MqlTick &tick)
   {
      TickData td;
      td.bid = tick.bid;
      td.ask = tick.ask;
      td.spread = (tick.ask - tick.bid) / _Point;
      td.bidVolume = (double)tick.volume_real;
      td.askVolume = (double)tick.volume_real;
      td.time = tick.time;
      td.timeMs = tick.time_msc;
      td.flags = tick.flags;
      
      // Store in circular buffer
      m_buffer[m_bufferPos] = td;
      m_bufferPos = (m_bufferPos + 1) % TICK_BUFFER_SIZE;
      m_tickCount = MathMin(m_tickCount + 1, TICK_BUFFER_SIZE);
      m_totalTicks++;
      
      // Update order flow
      if(m_lastBid > 0)
      {
         double change = tick.bid - m_lastBid;
         if(change > 0) m_upticks++;
         else if(change < 0) m_downticks++;
         
         // Store price change
         m_priceChanges[m_changePos] = change;
         m_changePos = (m_changePos + 1) % TICK_BUFFER_SIZE;
      }
      
      // Update running sums
      m_spreadSum += td.spread;
      m_priceSum += tick.bid;
      m_bidVolSum += td.bidVolume;
      m_askVolSum += td.askVolume;
      
      // High/Low
      if(tick.bid > m_highPrice) m_highPrice = tick.bid;
      if(tick.bid < m_lowPrice) m_lowPrice = tick.bid;
      
      // Calculate metrics
      UpdateMetrics(td);
      
      m_lastBid = tick.bid;
      m_lastAsk = tick.ask;
      m_lastTickMs = tick.time_msc;
   }
   
   void Reset()
   {
      m_upticks = 0;
      m_downticks = 0;
      m_totalTicks = 0;
      m_priceSum = 0;
      m_volumeSum = 0;
      m_spreadSum = 0;
      m_bidVolSum = 0;
      m_askVolSum = 0;
      m_highPrice = 0;
      m_lowPrice = DBL_MAX;
      m_resetTime = TimeCurrent();
   }
   
   int GetTickCount() { return m_tickCount; }
   int GetTotalTicks() { return m_totalTicks; }

private:
   void UpdateMetrics(TickData &td)
   {
      double totalTicks = m_upticks + m_downticks;
      if(totalTicks > 0)
      {
         metrics.buyPressure = m_upticks / totalTicks;
         metrics.sellPressure = m_downticks / totalTicks;
         metrics.netFlow = metrics.buyPressure - metrics.sellPressure;
      }
      
      // Tick speed
      if(m_lastTickMs > 0 && td.timeMs > m_lastTickMs)
      {
         double elapsed = (td.timeMs - m_lastTickMs) / 1000.0;
         if(elapsed > 0)
            metrics.tickSpeed = 1.0 / elapsed;
      }
      
      // Price velocity
      long totalElapsed = (long)(TimeCurrent() - m_resetTime);
      if(totalElapsed > 0 && m_totalTicks > 1)
      {
         double totalMove = td.bid - m_buffer[0].bid;
         double newVelocity = totalMove / (double)totalElapsed;
         metrics.acceleration = newVelocity - m_lastVelocity;
         metrics.priceVelocity = newVelocity;
         m_lastVelocity = newVelocity;
      }
      
      // Spread
      metrics.currentSpread = td.spread;
      if(m_totalTicks > 0)
         metrics.avgSpread = m_spreadSum / m_totalTicks;
      if(metrics.avgSpread > 0)
         metrics.spreadRatio = metrics.currentSpread / metrics.avgSpread;
      metrics.spreadNormal = (metrics.spreadRatio < 2.0);
      
      // Liquidity
      metrics.bidDepth = m_bidVolSum;
      metrics.askDepth = m_askVolSum;
      double totalDepth = metrics.bidDepth + metrics.askDepth;
      if(totalDepth > 0)
         metrics.liquidityImbalance = (metrics.bidDepth - metrics.askDepth) / totalDepth;
      
      // Price levels
      metrics.highSinceReset = m_highPrice;
      metrics.lowSinceReset = m_lowPrice;
      if(m_totalTicks > 0)
         metrics.vwap = m_priceSum / m_totalTicks;
      
      // Volatility
      metrics.tickVolatility = CalculateTickVolatility();
      double avgPrice = (m_highPrice + m_lowPrice) / 2.0;
      if(avgPrice > 0)
         metrics.rangePercent = (m_highPrice - m_lowPrice) / avgPrice * 100.0;
   }
   
   double CalculateTickVolatility()
   {
      if(m_tickCount < 10) return 0;
      
      int count = MathMin(m_tickCount, 100);
      double sum = 0, sumSq = 0;
      for(int i = 0; i < count; i++)
      {
         sum += m_priceChanges[i];
         sumSq += m_priceChanges[i] * m_priceChanges[i];
      }
      double mean = sum / count;
      double variance = (sumSq / count) - (mean * mean);
      return MathSqrt(MathAbs(variance));
   }
};

#endif
