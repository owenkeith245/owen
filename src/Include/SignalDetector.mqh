//+------------------------------------------------------------------+
//|                                         SignalDetector.mqh        |
//|            Liquidity, FVG, Order Blocks, MSS Detection            |
//+------------------------------------------------------------------+
#ifndef SIGNAL_DETECTOR_MQH
#define SIGNAL_DETECTOR_MQH

#define MAX_ZONES 20

//+------------------------------------------------------------------+
//| Zone structures                                                   |
//+------------------------------------------------------------------+
struct LiquidityZone
{
   double   price;
   bool     isHigh;     // true = resistance, false = support
   int      touches;    // how many times tested
   bool     swept;      // has been taken out
   datetime created;
   datetime lastTest;
};

struct FairValueGap
{
   double   top;        // upper boundary
   double   bottom;     // lower boundary
   bool     isBullish;
   bool     filled;     // price has returned to fill it
   double   midpoint;
   datetime created;
};

struct OrderBlock
{
   double   top;
   double   bottom;
   bool     isBullish;
   bool     mitigated;  // price has revisited
   int      strength;   // based on displacement after
   datetime created;
};

struct StructurePoint
{
   double   price;
   bool     isHigh;
   datetime time;
   int      barIndex;
};

struct SignalState
{
   // Liquidity
   bool     liquiditySweepBull;
   bool     liquiditySweepBear;
   double   nearestLiqHigh;
   double   nearestLiqLow;
   
   // FVG
   bool     fvgBullPresent;
   bool     fvgBearPresent;
   double   fvgBullEntry;
   double   fvgBearEntry;
   
   // Order Blocks
   bool     obBullPresent;
   bool     obBearPresent;
   double   obBullTop;
   double   obBullBottom;
   double   obBearTop;
   double   obBearBottom;
   
   // Market Structure
   bool     mssBull;    // market structure shift bullish
   bool     mssBear;
   bool     bosBull;    // break of structure bullish
   bool     bosBear;
   
   // Combined
   double   structureScore;  // 0-100
};

class CSignalDetector
{
private:
   string          m_symbol;
   LiquidityZone   m_liqZones[];
   FairValueGap    m_fvgZones[];
   OrderBlock      m_obZones[];
   StructurePoint  m_swings[];
   int             m_liqCount;
   int             m_fvgCount;
   int             m_obCount;
   int             m_swingCount;

public:
   SignalState state;
   
   void Init(string symbol)
   {
      m_symbol = symbol;
      ArrayResize(m_liqZones, MAX_ZONES);
      ArrayResize(m_fvgZones, MAX_ZONES);
      ArrayResize(m_obZones, MAX_ZONES);
      ArrayResize(m_swings, MAX_ZONES * 2);
      m_liqCount = 0;
      m_fvgCount = 0;
      m_obCount = 0;
      m_swingCount = 0;
      ZeroMemory(state);
   }
   
   void Update(double currentBid, double currentAsk)
   {
      ZeroMemory(state);
      
      // Get price data for multiple timeframes
      double h1High[], h1Low[], h1Close[], h1Open[];
      double m15High[], m15Low[], m15Close[], m15Open[];
      double m5High[], m5Low[], m5Close[], m5Open[];
      
      CopyHigh(m_symbol, PERIOD_H1, 0, 30, h1High);
      CopyLow(m_symbol, PERIOD_H1, 0, 30, h1Low);
      CopyClose(m_symbol, PERIOD_H1, 0, 30, h1Close);
      CopyOpen(m_symbol, PERIOD_H1, 0, 30, h1Open);
      
      CopyHigh(m_symbol, PERIOD_M15, 0, 30, m15High);
      CopyLow(m_symbol, PERIOD_M15, 0, 30, m15Low);
      CopyClose(m_symbol, PERIOD_M15, 0, 30, m15Close);
      CopyOpen(m_symbol, PERIOD_M15, 0, 30, m15Open);
      
      CopyHigh(m_symbol, PERIOD_M5, 0, 30, m5High);
      CopyLow(m_symbol, PERIOD_M5, 0, 30, m5Low);
      CopyClose(m_symbol, PERIOD_M5, 0, 30, m5Close);
      CopyOpen(m_symbol, PERIOD_M5, 0, 30, m5Open);
      
      if(ArraySize(h1High) < 20 || ArraySize(m15High) < 20 || ArraySize(m5High) < 20)
         return;
      
      // Detect all signals
      DetectLiquidityZones(h1High, h1Low, currentBid);
      DetectLiquiditySweeps(m15High, m15Low, m15Close, currentBid);
      DetectFVG(m5High, m5Low, m5Close, m5Open, currentBid, currentAsk);
      DetectOrderBlocks(m15High, m15Low, m15Close, m15Open, currentBid);
      DetectStructure(h1High, h1Low, h1Close, currentBid);
      
      // Calculate combined structure score
      CalculateStructureScore();
   }
   
   // Accessors for chart drawing
   int GetLiquidityZoneCount() { return m_liqCount; }
   int GetFVGCount() { return m_fvgCount; }
   int GetOrderBlockCount() { return m_obCount; }
   
   LiquidityZone GetLiquidityZone(int i) { return m_liqZones[i]; }
   FairValueGap GetFVG(int i) { return m_fvgZones[i]; }
   OrderBlock GetOrderBlock(int i) { return m_obZones[i]; }

private:
   void DetectLiquidityZones(double &highs[], double &lows[], double currentPrice)
   {
      m_liqCount = 0;
      int size = ArraySize(highs);
      
      // Find swing highs and lows as liquidity pools
      for(int i = 2; i < size - 2 && m_liqCount < MAX_ZONES; i++)
      {
         // Swing high
         if(highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
            highs[i] > highs[i+1] && highs[i] > highs[i+2])
         {
            m_liqZones[m_liqCount].price = highs[i];
            m_liqZones[m_liqCount].isHigh = true;
            m_liqZones[m_liqCount].swept = (currentPrice > highs[i]);
            m_liqZones[m_liqCount].touches = CountTouches(highs, lows, highs[i], true);
            m_liqCount++;
         }
         
         // Swing low
         if(lows[i] < lows[i-1] && lows[i] < lows[i-2] &&
            lows[i] < lows[i+1] && lows[i] < lows[i+2])
         {
            if(m_liqCount < MAX_ZONES)
            {
               m_liqZones[m_liqCount].price = lows[i];
               m_liqZones[m_liqCount].isHigh = false;
               m_liqZones[m_liqCount].swept = (currentPrice < lows[i]);
               m_liqZones[m_liqCount].touches = CountTouches(highs, lows, lows[i], false);
               m_liqCount++;
            }
         }
      }
      
      // Find nearest levels
      state.nearestLiqHigh = DBL_MAX;
      state.nearestLiqLow = 0;
      for(int i = 0; i < m_liqCount; i++)
      {
         if(m_liqZones[i].isHigh && !m_liqZones[i].swept && m_liqZones[i].price < state.nearestLiqHigh && m_liqZones[i].price > currentPrice)
            state.nearestLiqHigh = m_liqZones[i].price;
         if(!m_liqZones[i].isHigh && !m_liqZones[i].swept && m_liqZones[i].price > state.nearestLiqLow && m_liqZones[i].price < currentPrice)
            state.nearestLiqLow = m_liqZones[i].price;
      }
   }
   
   void DetectLiquiditySweeps(double &highs[], double &lows[], double &closes[], double currentPrice)
   {
      // Check if recent price action swept a key level
      if(ArraySize(highs) < 5) return;
      
      // Previous day high/low
      double prevDayHigh = iHigh(m_symbol, PERIOD_D1, 1);
      double prevDayLow = iLow(m_symbol, PERIOD_D1, 1);
      
      // Bullish sweep: price went below prev low then closed above
      if(lows[1] < prevDayLow && closes[1] > prevDayLow)
         state.liquiditySweepBull = true;
      
      // Bearish sweep: price went above prev high then closed below
      if(highs[1] > prevDayHigh && closes[1] < prevDayHigh)
         state.liquiditySweepBear = true;
   }
   
   void DetectFVG(double &highs[], double &lows[], double &closes[], double &opens[], double bid, double ask)
   {
      m_fvgCount = 0;
      int size = ArraySize(highs);
      
      for(int i = 2; i < size - 1 && m_fvgCount < MAX_ZONES; i++)
      {
         // Bullish FVG: gap between candle i+1 high and candle i-1 low
         if(lows[i-1] > highs[i+1])
         {
            FairValueGap fvg;
            fvg.top = lows[i-1];
            fvg.bottom = highs[i+1];
            fvg.isBullish = true;
            fvg.midpoint = (fvg.top + fvg.bottom) / 2.0;
            fvg.filled = (bid <= fvg.midpoint);
            m_fvgZones[m_fvgCount] = fvg;
            m_fvgCount++;
            
            // Signal if price is in the FVG
            if(bid >= fvg.bottom && bid <= fvg.top)
            {
               state.fvgBullPresent = true;
               state.fvgBullEntry = fvg.midpoint;
            }
         }
         
         // Bearish FVG: gap between candle i+1 low and candle i-1 high
         if(highs[i-1] < lows[i+1])
         {
            if(m_fvgCount < MAX_ZONES)
            {
               FairValueGap fvg;
               fvg.top = lows[i+1];
               fvg.bottom = highs[i-1];
               fvg.isBullish = false;
               fvg.midpoint = (fvg.top + fvg.bottom) / 2.0;
               fvg.filled = (ask >= fvg.midpoint);
               m_fvgZones[m_fvgCount] = fvg;
               m_fvgCount++;
               
               if(ask >= fvg.bottom && ask <= fvg.top)
               {
                  state.fvgBearPresent = true;
                  state.fvgBearEntry = fvg.midpoint;
               }
            }
         }
      }
   }
   
   void DetectOrderBlocks(double &highs[], double &lows[], double &closes[], double &opens[], double currentPrice)
   {
      m_obCount = 0;
      int size = ArraySize(highs);
      
      for(int i = 3; i < size - 1 && m_obCount < MAX_ZONES; i++)
      {
         // Bullish OB: last down candle before an impulsive up move
         if(closes[i] < opens[i]) // bearish candle
         {
            // Check if followed by strong bullish displacement
            double nextBody = MathAbs(closes[i-1] - opens[i-1]);
            double nextRange = highs[i-1] - lows[i-1];
            if(closes[i-1] > opens[i-1] && nextBody > nextRange * 0.6)
            {
               // Strong bullish follow-through
               if(closes[i-1] > highs[i]) // displacement above OB
               {
                  OrderBlock ob;
                  ob.top = highs[i];
                  ob.bottom = lows[i];
                  ob.isBullish = true;
                  ob.mitigated = (currentPrice < ob.bottom);
                  ob.strength = (int)(nextBody / (highs[i] - lows[i]) * 5);
                  m_obZones[m_obCount] = ob;
                  m_obCount++;
                  
                  if(currentPrice >= ob.bottom && currentPrice <= ob.top)
                  {
                     state.obBullPresent = true;
                     state.obBullTop = ob.top;
                     state.obBullBottom = ob.bottom;
                  }
               }
            }
         }
         
         // Bearish OB: last up candle before impulsive down move
         if(closes[i] > opens[i] && m_obCount < MAX_ZONES) // bullish candle
         {
            double nextBody = MathAbs(closes[i-1] - opens[i-1]);
            double nextRange = highs[i-1] - lows[i-1];
            if(closes[i-1] < opens[i-1] && nextBody > nextRange * 0.6)
            {
               if(closes[i-1] < lows[i]) // displacement below OB
               {
                  OrderBlock ob;
                  ob.top = highs[i];
                  ob.bottom = lows[i];
                  ob.isBullish = false;
                  ob.mitigated = (currentPrice > ob.top);
                  ob.strength = (int)(nextBody / (highs[i] - lows[i]) * 5);
                  m_obZones[m_obCount] = ob;
                  m_obCount++;
                  
                  if(currentPrice >= ob.bottom && currentPrice <= ob.top)
                  {
                     state.obBearPresent = true;
                     state.obBearTop = ob.top;
                     state.obBearBottom = ob.bottom;
                  }
               }
            }
         }
      }
   }
   
   void DetectStructure(double &highs[], double &lows[], double &closes[], double currentPrice)
   {
      int size = ArraySize(highs);
      if(size < 20) return;
      
      // Find swing highs and lows for structure
      double swingHighs[10], swingLows[10];
      int shCount = 0, slCount = 0;
      
      for(int i = 2; i < MathMin(size - 2, 15); i++)
      {
         if(highs[i] > highs[i-1] && highs[i] > highs[i+1] && shCount < 10)
            swingHighs[shCount++] = highs[i];
         if(lows[i] < lows[i-1] && lows[i] < lows[i+1] && slCount < 10)
            swingLows[slCount++] = lows[i];
      }
      
      // MSS: close breaks a recent swing
      if(shCount >= 2 && slCount >= 2)
      {
         // Bullish MSS: price breaks above a lower high
         if(closes[1] > swingHighs[1] && swingHighs[0] < swingHighs[1])
            state.mssBull = true;
         
         // Bearish MSS: price breaks below a higher low
         if(closes[1] < swingLows[1] && swingLows[0] > swingLows[1])
            state.mssBear = true;
         
         // BOS: price breaks the most recent swing
         if(closes[1] > swingHighs[0])
            state.bosBull = true;
         if(closes[1] < swingLows[0])
            state.bosBear = true;
      }
   }
   
   void CalculateStructureScore()
   {
      double score = 0;
      
      if(state.liquiditySweepBull || state.liquiditySweepBear) score += 25;
      if(state.fvgBullPresent || state.fvgBearPresent) score += 20;
      if(state.obBullPresent || state.obBearPresent) score += 20;
      if(state.mssBull || state.mssBear) score += 20;
      if(state.bosBull || state.bosBear) score += 15;
      
      state.structureScore = MathMin(score, 100);
   }
   
   int CountTouches(double &highs[], double &lows[], double level, bool isHigh)
   {
      int count = 0;
      double tolerance = _Point * 20;
      int size = isHigh ? ArraySize(highs) : ArraySize(lows);
      
      for(int i = 0; i < size; i++)
      {
         double price = isHigh ? highs[i] : lows[i];
         if(MathAbs(price - level) < tolerance)
            count++;
      }
      return count;
   }
};

#endif
