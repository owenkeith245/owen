//+------------------------------------------------------------------+
//|                                           RiskManager.mqh         |
//|                Intelligent Capital Allocation & Safety             |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include <Trade\AccountInfo.mqh>

#define MAX_OPEN_TRADES 10

struct RiskConfig
{
   double maxDailyRiskPercent;    // 2.0 default
   double maxWeeklyRiskPercent;   // 5.0 default
   double maxSingleTradeRisk;    // 0.5% per trade
   int    maxOpenTrades;          // 10
   double maxCorrelationExposure; // max exposure in one direction
   double maxSpreadMultiplier;    // reject if spread > avg * this
   double maxSlippage;            // max allowed slippage in points
   double emergencyDrawdown;      // auto-stop if hit (%)
   int    maxConsecutiveLosses;   // halt after N losses
};

struct RiskState
{
   double dailyRiskUsed;
   double dailyRiskBudget;
   double weeklyDrawdown;
   double weekStartBalance;
   double todayStartBalance;
   int    openTradeCount;
   int    todayTradeCount;
   int    todayWins;
   int    todayLosses;
   int    consecutiveLosses;
   double totalExposureLong;
   double totalExposureShort;
   bool   haltDaily;
   bool   haltWeekly;
   bool   haltEmergency;
   bool   haltConsecutive;
   datetime lastTradeDay;
};

struct TradeRiskAllocation
{
   double riskMoney;
   double lotSize;
   double stopLossPoints;
   bool   approved;
   string rejectReason;
};

class CRiskManager
{
private:
   RiskConfig  m_config;
   RiskState   m_state;
   CAccountInfo m_account;
   string      m_symbol;
   double      m_pointValue;
   double      m_lotStep;
   double      m_lotMin;
   double      m_lotMax;

public:
   void Init(string symbol)
   {
      m_symbol = symbol;
      
      // Default config
      m_config.maxDailyRiskPercent = 2.0;
      m_config.maxWeeklyRiskPercent = 5.0;
      m_config.maxSingleTradeRisk = 0.5;
      m_config.maxOpenTrades = MAX_OPEN_TRADES;
      m_config.maxCorrelationExposure = 3.0; // max 3% one direction
      m_config.maxSpreadMultiplier = 2.5;
      m_config.maxSlippage = 20.0;
      m_config.emergencyDrawdown = 5.0;
      m_config.maxConsecutiveLosses = 5;
      
      // Lot info
      m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_lotMin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_lotMax = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_pointValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE) / 
                     SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      
      // Initial state
      ZeroMemory(m_state);
      m_state.weekStartBalance = m_account.Balance();
      m_state.todayStartBalance = m_account.Balance();
      m_state.dailyRiskBudget = m_account.Balance() * m_config.maxDailyRiskPercent / 100.0;
   }
   
   void SetConfig(RiskConfig &config) { m_config = config; }
   RiskConfig GetConfig() { return m_config; }
   RiskState GetState() { return m_state; }
   
   void OnNewDay()
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      
      if(dt.day != TimeDay(m_state.lastTradeDay))
      {
         m_state.lastTradeDay = TimeCurrent();
         m_state.dailyRiskUsed = 0;
         m_state.todayStartBalance = m_account.Balance();
         m_state.dailyRiskBudget = m_account.Balance() * m_config.maxDailyRiskPercent / 100.0;
         m_state.todayTradeCount = 0;
         m_state.todayWins = 0;
         m_state.todayLosses = 0;
         m_state.haltDaily = false;
         m_state.consecutiveLosses = 0;
         m_state.haltConsecutive = false;
      }
      
      // Check Monday for weekly reset
      if(dt.day_of_week == 1 && m_state.weekStartBalance == 0)
         m_state.weekStartBalance = m_account.Balance();
      
      // Weekly drawdown check
      if(m_state.weekStartBalance > 0)
      {
         m_state.weeklyDrawdown = (m_state.weekStartBalance - m_account.Balance()) / m_state.weekStartBalance * 100;
         if(m_state.weeklyDrawdown > m_config.maxWeeklyRiskPercent)
            m_state.haltWeekly = true;
      }
      
      // Emergency check
      if(m_state.todayStartBalance > 0)
      {
         double dailyDD = (m_state.todayStartBalance - m_account.Balance()) / m_state.todayStartBalance * 100;
         if(dailyDD > m_config.emergencyDrawdown)
            m_state.haltEmergency = true;
      }
   }
   
   bool CanTrade()
   {
      if(m_state.haltDaily || m_state.haltWeekly || m_state.haltEmergency || m_state.haltConsecutive)
         return false;
      if(m_state.openTradeCount >= m_config.maxOpenTrades)
         return false;
      if(m_state.dailyRiskUsed >= m_state.dailyRiskBudget)
         return false;
      return true;
   }
   
   string GetHaltReason()
   {
      if(m_state.haltEmergency) return "EMERGENCY DRAWDOWN";
      if(m_state.haltWeekly) return "WEEKLY LIMIT";
      if(m_state.haltDaily) return "DAILY LIMIT";
      if(m_state.haltConsecutive) return "CONSECUTIVE LOSSES";
      if(m_state.openTradeCount >= m_config.maxOpenTrades) return "MAX TRADES";
      if(m_state.dailyRiskUsed >= m_state.dailyRiskBudget) return "RISK BUDGET";
      return "";
   }
   
   TradeRiskAllocation AllocateRisk(double stopLossPoints, double confidence)
   {
      TradeRiskAllocation alloc;
      ZeroMemory(alloc);
      alloc.stopLossPoints = stopLossPoints;
      
      if(!CanTrade())
      {
         alloc.approved = false;
         alloc.rejectReason = GetHaltReason();
         return alloc;
      }
      
      // Calculate available risk
      double availableRisk = m_state.dailyRiskBudget - m_state.dailyRiskUsed;
      double maxTradeRisk = m_account.Balance() * m_config.maxSingleTradeRisk / 100.0;
      
      // Scale risk by confidence (higher confidence = more risk allocated)
      double confidenceScale = MathMin(confidence / 100.0, 1.0);
      double riskMoney = MathMin(maxTradeRisk * confidenceScale, availableRisk);
      
      if(riskMoney <= 0)
      {
         alloc.approved = false;
         alloc.rejectReason = "NO RISK BUDGET";
         return alloc;
      }
      
      // Calculate lot size
      if(stopLossPoints <= 0 || m_pointValue <= 0)
      {
         alloc.approved = false;
         alloc.rejectReason = "INVALID SL";
         return alloc;
      }
      
      double lotSize = riskMoney / (stopLossPoints * m_pointValue);
      lotSize = NormalizeLot(lotSize);
      
      if(lotSize < m_lotMin)
      {
         alloc.approved = false;
         alloc.rejectReason = "LOT TOO SMALL";
         return alloc;
      }
      
      alloc.riskMoney = riskMoney;
      alloc.lotSize = lotSize;
      alloc.approved = true;
      return alloc;
   }
   
   bool CheckSpread(double currentSpread, double avgSpread)
   {
      if(avgSpread <= 0) return true;
      return (currentSpread / avgSpread) <= m_config.maxSpreadMultiplier;
   }
   
   void OnTradeOpened(double riskAmount)
   {
      m_state.dailyRiskUsed += riskAmount;
      m_state.openTradeCount++;
      m_state.todayTradeCount++;
   }
   
   void OnTradeClosed(double profit, double riskAmount)
   {
      m_state.openTradeCount--;
      
      if(profit > 0)
      {
         m_state.todayWins++;
         m_state.consecutiveLosses = 0;
      }
      else
      {
         m_state.todayLosses++;
         m_state.consecutiveLosses++;
         if(m_state.consecutiveLosses >= m_config.maxConsecutiveLosses)
            m_state.haltConsecutive = true;
      }
      
      // Check daily halt
      double dailyPnL = m_account.Balance() - m_state.todayStartBalance;
      if(dailyPnL < -(m_state.dailyRiskBudget))
         m_state.haltDaily = true;
   }
   
   void UpdateOpenTradeCount(int count) { m_state.openTradeCount = count; }
   
   double GetDailyPnLPercent()
   {
      if(m_state.todayStartBalance <= 0) return 0;
      return (m_account.Balance() - m_state.todayStartBalance) / m_state.todayStartBalance * 100;
   }
   
   double GetRiskUsedPercent()
   {
      if(m_state.dailyRiskBudget <= 0) return 0;
      return m_state.dailyRiskUsed / m_state.dailyRiskBudget * 100;
   }

private:
   double NormalizeLot(double lot)
   {
      lot = MathFloor(lot / m_lotStep) * m_lotStep;
      if(lot < m_lotMin) return m_lotMin;
      if(lot > m_lotMax) return m_lotMax;
      return lot;
   }
   
   int TimeDay(datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return dt.day;
   }
};

#endif
