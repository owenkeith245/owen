//+------------------------------------------------------------------+
//|                                           TradeLogger.mqh         |
//|                   Trade History & Performance Analytics            |
//+------------------------------------------------------------------+
#ifndef TRADE_LOGGER_MQH
#define TRADE_LOGGER_MQH

#define MAX_LOG_ENTRIES 1000

struct TradeRecord
{
   int      id;
   datetime openTime;
   datetime closeTime;
   string   direction;     // "BUY" or "SELL"
   double   entryPrice;
   double   exitPrice;
   double   stopLoss;
   double   takeProfit;
   double   lots;
   double   profit;
   double   profitPercent;
   double   rMultiple;     // profit in R units
   double   confidence;    // AI confidence at entry
   string   session;       // London, NY, etc
   string   reason;        // Primary signal reason
   int      durationSec;   // trade duration
   double   spreadAtEntry;
   double   maxDrawdown;   // max adverse excursion
   double   maxProfit;     // max favorable excursion
   bool     isWin;
};

struct PerformanceStats
{
   int      totalTrades;
   int      wins;
   int      losses;
   double   winRate;
   double   avgWin;
   double   avgLoss;
   double   profitFactor;
   double   avgRMultiple;
   double   maxConsecutiveWins;
   double   maxConsecutiveLosses;
   double   avgDurationSec;
   double   totalProfit;
   double   maxDrawdown;
   double   sharpeRatio;
   
   // Per-session stats
   double   londonWinRate;
   double   nyWinRate;
   int      londonTrades;
   int      nyTrades;
   
   // Per-confidence stats
   double   highConfWinRate;   // conf >= 90
   double   medConfWinRate;    // conf 80-90
   int      highConfTrades;
   int      medConfTrades;
};

class CTradeLogger
{
private:
   TradeRecord     m_records[];
   int             m_recordCount;
   int             m_nextId;
   string          m_logFile;
   PerformanceStats m_stats;
   bool            m_fileLogging;

public:
   void Init(string symbol, bool fileLogging = true)
   {
      ArrayResize(m_records, MAX_LOG_ENTRIES);
      m_recordCount = 0;
      m_nextId = 1;
      m_logFile = "GoldAI_" + symbol + "_trades.csv";
      m_fileLogging = fileLogging;
      ZeroMemory(m_stats);
      
      if(m_fileLogging)
         WriteHeader();
   }
   
   void LogTrade(TradeRecord &record)
   {
      record.id = m_nextId++;
      record.isWin = (record.profit > 0);
      
      // Calculate R-multiple
      double risk = MathAbs(record.entryPrice - record.stopLoss);
      if(risk > 0)
         record.rMultiple = (record.exitPrice - record.entryPrice) / risk * (record.direction == "BUY" ? 1 : -1);
      
      // Duration
      record.durationSec = (int)(record.closeTime - record.openTime);
      
      // Store
      if(m_recordCount < MAX_LOG_ENTRIES)
      {
         m_records[m_recordCount] = record;
         m_recordCount++;
      }
      
      // Write to file
      if(m_fileLogging)
         WriteRecord(record);
      
      // Update stats
      UpdateStats();
   }
   
   PerformanceStats GetStats() { return m_stats; }
   int GetTradeCount() { return m_recordCount; }
   
   TradeRecord GetLastTrade()
   {
      if(m_recordCount > 0)
         return m_records[m_recordCount - 1];
      TradeRecord empty;
      ZeroMemory(empty);
      return empty;
   }
   
   double GetWinRate() { return m_stats.winRate; }
   double GetProfitFactor() { return m_stats.profitFactor; }
   
   // Adaptive confidence threshold based on performance
   double GetAdaptiveThreshold()
   {
      if(m_recordCount < 20) return 85.0; // default
      
      // If high-conf trades do well, keep threshold
      if(m_stats.highConfWinRate > 70) return 85.0;
      // If medium-conf also does well, lower threshold
      if(m_stats.medConfWinRate > 65) return 80.0;
      // Otherwise raise threshold
      return 90.0;
   }

private:
   void UpdateStats()
   {
      if(m_recordCount == 0) return;
      
      m_stats.totalTrades = m_recordCount;
      m_stats.wins = 0;
      m_stats.losses = 0;
      m_stats.totalProfit = 0;
      double totalWin = 0, totalLoss = 0;
      double totalR = 0, totalDuration = 0;
      int consWins = 0, consLosses = 0, maxConsW = 0, maxConsL = 0;
      int londonW = 0, londonL = 0, nyW = 0, nyL = 0;
      int highConfW = 0, highConfL = 0, medConfW = 0, medConfL = 0;
      
      double equity = 0, peak = 0, maxDD = 0;
      double returns[];
      ArrayResize(returns, m_recordCount);
      
      for(int i = 0; i < m_recordCount; i++)
      {
         TradeRecord &r = m_records[i];
         m_stats.totalProfit += r.profit;
         totalR += r.rMultiple;
         totalDuration += r.durationSec;
         returns[i] = r.profitPercent;
         
         equity += r.profit;
         if(equity > peak) peak = equity;
         double dd = peak - equity;
         if(dd > maxDD) maxDD = dd;
         
         if(r.isWin)
         {
            m_stats.wins++;
            totalWin += r.profit;
            consWins++;
            consLosses = 0;
            if(consWins > maxConsW) maxConsW = consWins;
         }
         else
         {
            m_stats.losses++;
            totalLoss += MathAbs(r.profit);
            consLosses++;
            consWins = 0;
            if(consLosses > maxConsL) maxConsL = consLosses;
         }
         
         // Session stats
         if(r.session == "London")
         {
            if(r.isWin) londonW++; else londonL++;
         }
         else if(r.session == "NewYork")
         {
            if(r.isWin) nyW++; else nyL++;
         }
         
         // Confidence stats
         if(r.confidence >= 90)
         {
            if(r.isWin) highConfW++; else highConfL++;
         }
         else if(r.confidence >= 80)
         {
            if(r.isWin) medConfW++; else medConfL++;
         }
      }
      
      m_stats.winRate = (m_recordCount > 0) ? (double)m_stats.wins / m_recordCount * 100 : 0;
      m_stats.avgWin = (m_stats.wins > 0) ? totalWin / m_stats.wins : 0;
      m_stats.avgLoss = (m_stats.losses > 0) ? totalLoss / m_stats.losses : 0;
      m_stats.profitFactor = (totalLoss > 0) ? totalWin / totalLoss : 999;
      m_stats.avgRMultiple = (m_recordCount > 0) ? totalR / m_recordCount : 0;
      m_stats.maxConsecutiveWins = maxConsW;
      m_stats.maxConsecutiveLosses = maxConsL;
      m_stats.avgDurationSec = (m_recordCount > 0) ? totalDuration / m_recordCount : 0;
      m_stats.maxDrawdown = maxDD;
      
      m_stats.londonTrades = londonW + londonL;
      m_stats.nyTrades = nyW + nyL;
      m_stats.londonWinRate = (m_stats.londonTrades > 0) ? (double)londonW / m_stats.londonTrades * 100 : 0;
      m_stats.nyWinRate = (m_stats.nyTrades > 0) ? (double)nyW / m_stats.nyTrades * 100 : 0;
      
      m_stats.highConfTrades = highConfW + highConfL;
      m_stats.medConfTrades = medConfW + medConfL;
      m_stats.highConfWinRate = (m_stats.highConfTrades > 0) ? (double)highConfW / m_stats.highConfTrades * 100 : 0;
      m_stats.medConfWinRate = (m_stats.medConfTrades > 0) ? (double)medConfW / m_stats.medConfTrades * 100 : 0;
      
      // Sharpe ratio
      m_stats.sharpeRatio = CalculateSharpe(returns, m_recordCount);
   }
   
   double CalculateSharpe(double &returns[], int count)
   {
      if(count < 2) return 0;
      double sum = 0, sumSq = 0;
      for(int i = 0; i < count; i++)
      {
         sum += returns[i];
         sumSq += returns[i] * returns[i];
      }
      double mean = sum / count;
      double variance = (sumSq / count) - (mean * mean);
      double stddev = MathSqrt(MathAbs(variance));
      if(stddev == 0) return 0;
      return mean / stddev * MathSqrt(252); // annualized
   }
   
   void WriteHeader()
   {
      int handle = FileOpen(m_logFile, FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
      if(handle != INVALID_HANDLE)
      {
         FileWrite(handle, "ID", "OpenTime", "CloseTime", "Direction", "Entry", "Exit",
                   "SL", "TP", "Lots", "Profit", "ProfitPct", "RMultiple",
                   "Confidence", "Session", "Reason", "Duration", "Spread");
         FileClose(handle);
      }
   }
   
   void WriteRecord(TradeRecord &r)
   {
      int handle = FileOpen(m_logFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ",");
      if(handle != INVALID_HANDLE)
      {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, r.id, TimeToString(r.openTime), TimeToString(r.closeTime),
                   r.direction, r.entryPrice, r.exitPrice, r.stopLoss, r.takeProfit,
                   r.lots, r.profit, r.profitPercent, r.rMultiple,
                   r.confidence, r.session, r.reason, r.durationSec, r.spreadAtEntry);
         FileClose(handle);
      }
   }
};

#endif
