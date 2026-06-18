//+------------------------------------------------------------------+
//|                                            NewsFilter.mqh         |
//|                     High-Impact News Event Filter                  |
//+------------------------------------------------------------------+
#ifndef NEWS_FILTER_MQH
#define NEWS_FILTER_MQH

struct NewsEvent
{
   datetime time;
   string   title;
   int      impact;       // 1=low, 2=medium, 3=high
   string   currency;
   bool     active;
};

class CNewsFilter
{
private:
   int      m_quietMinutes;       // minutes to block before/after
   bool     m_enabled;
   bool     m_isNewsTime;
   datetime m_nextEvent;
   string   m_nextEventTitle;
   
   // Known recurring high-impact events (EAT/UTC+3)
   // NFP: 1st Friday, 15:30 EAT
   // FOMC: varies (usually Wed 21:00 EAT)
   // CPI: ~2nd/3rd Tue/Wed 15:30 EAT

public:
   void Init(int quietMinutes = 15, bool enabled = true)
   {
      m_quietMinutes = quietMinutes;
      m_enabled = enabled;
      m_isNewsTime = false;
      m_nextEvent = 0;
      m_nextEventTitle = "";
   }
   
   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() { return m_enabled; }
   
   bool IsNewsTime()
   {
      if(!m_enabled) return false;
      
      MqlDateTime dt;
      TimeCurrent(dt);
      
      m_isNewsTime = false;
      
      // Check NFP (1st Friday of month, 15:30 EAT)
      if(IsNFPWindow(dt))
      {
         m_isNewsTime = true;
         m_nextEventTitle = "NFP";
         return true;
      }
      
      // Check FOMC (approximate - 3rd Wed, 21:00 EAT)
      if(IsFOMCWindow(dt))
      {
         m_isNewsTime = true;
         m_nextEventTitle = "FOMC";
         return true;
      }
      
      // Check CPI (approximate - mid-month, 15:30 EAT)
      if(IsCPIWindow(dt))
      {
         m_isNewsTime = true;
         m_nextEventTitle = "CPI";
         return true;
      }
      
      // Check weekly jobless claims (every Thursday 15:30 EAT)
      if(IsJoblessClaimsWindow(dt))
      {
         m_isNewsTime = true;
         m_nextEventTitle = "CLAIMS";
         return true;
      }
      
      return false;
   }
   
   string GetNextEventTitle() { return m_nextEventTitle; }
   int GetQuietMinutes() { return m_quietMinutes; }
   
   bool IsHighImpactDay()
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      
      // NFP day
      if(dt.day_of_week == 5 && dt.day <= 7) return true;
      // FOMC day (approximate)
      if(dt.day_of_week == 3 && dt.day >= 15 && dt.day <= 21) return true;
      
      return false;
   }

private:
   bool IsNFPWindow(MqlDateTime &dt)
   {
      // 1st Friday of month
      if(dt.day_of_week != 5 || dt.day > 7) return false;
      return IsWithinWindow(dt, 15, 30);
   }
   
   bool IsFOMCWindow(MqlDateTime &dt)
   {
      // 3rd Wednesday (day 15-21)
      if(dt.day_of_week != 3 || dt.day < 15 || dt.day > 21) return false;
      return IsWithinWindow(dt, 21, 0);
   }
   
   bool IsCPIWindow(MqlDateTime &dt)
   {
      // Mid-month (10-14), Tuesday or Wednesday
      if((dt.day_of_week != 2 && dt.day_of_week != 3) || dt.day < 10 || dt.day > 14) return false;
      return IsWithinWindow(dt, 15, 30);
   }
   
   bool IsJoblessClaimsWindow(MqlDateTime &dt)
   {
      // Every Thursday
      if(dt.day_of_week != 4) return false;
      return IsWithinWindow(dt, 15, 30);
   }
   
   bool IsWithinWindow(MqlDateTime &dt, int eventHour, int eventMin)
   {
      int currentMin = dt.hour * 60 + dt.min;
      int eventMinTotal = eventHour * 60 + eventMin;
      
      return (currentMin >= eventMinTotal - m_quietMinutes && 
              currentMin <= eventMinTotal + m_quietMinutes);
   }
};

#endif
