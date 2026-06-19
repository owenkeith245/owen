//+------------------------------------------------------------------+
//|                                              StraddleAIPro.mq5    |
//|                        STRADDLE AI PRO v1.0                       |
//|              Fully Automated News Straddle Trading System          |
//+------------------------------------------------------------------+
#property copyright "Straddle AI Pro"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "====== GENERAL ======"
input int      InpMagic              = 900000;          // Magic Number
input bool     InpFullAuto           = true;            // Fully autonomous mode
input string   InpSymbol             = "";              // Symbol (empty = current chart)

input group "====== NEWS SCHEDULE ======"
input bool     InpUseBuiltInNews     = true;            // Use built-in news times
input string   InpCustomTimes        = "";              // Custom straddle times (HH:MM,HH:MM,...)
input int      InpPlaceBeforeSec     = 30;              // Place orders X seconds before event
input int      InpCancelAfterSec     = 120;             // Cancel unfilled orders after X seconds
input bool     InpMondayEnabled      = true;            // Trade on Monday
input bool     InpTuesdayEnabled     = true;            // Trade on Tuesday
input bool     InpWednesdayEnabled   = true;            // Trade on Wednesday
input bool     InpThursdayEnabled    = true;            // Trade on Thursday
input bool     InpFridayEnabled      = true;            // Trade on Friday

input group "====== STRADDLE SETTINGS ======"
input double   InpDistanceATRMult    = 1.0;             // Distance = ATR * multiplier
input int      InpMinDistancePoints  = 50;              // Min distance in points
input int      InpMaxDistancePoints  = 500;             // Max distance in points
input double   InpSLATRMult          = 2.0;             // Stop Loss = ATR * multiplier
input double   InpTPATRMult          = 3.0;             // Take Profit = ATR * multiplier
input double   InpMinRR              = 1.5;             // Minimum Reward:Risk ratio

input group "====== POSITION SIZING ======"
input bool     InpUseTierLots        = true;            // Use equity-tier lots
input double   InpRiskPct            = 0.50;            // Risk % per straddle
input double   InpMinLot             = 0.01;            // Minimum lot
input double   InpMaxLot             = 5.00;            // Maximum lot

input group "====== TRADE MANAGEMENT ======"
input double   InpBEPips             = 3.0;             // Move to BE after X pips
input double   InpPartialPips        = 8.0;             // Partial close after X pips
input double   InpPartialPct         = 0.50;            // Close this % at partial
input double   InpTrailATRMult       = 0.5;             // Trail stop ATR multiplier
input bool     InpAutoCancel         = true;            // Auto-cancel other side on fill
input int      InpMaxHoldMinutes     = 30;              // Max hold time (minutes)

input group "====== SAFETY FILTERS ======"
input double   InpMaxSpreadPoints    = 50;              // Max spread to place straddle
input double   InpDailyDDLimit       = 2.0;             // Daily drawdown limit (%)
input int      InpMaxStraddlesDay    = 5;               // Max straddles per day
input int      InpMaxConsecLosses    = 3;               // Pause after X consecutive losses
input double   InpMinATR             = 0;               // Min ATR to trade (0=auto)

input group "====== LEARNING ENGINE ======"
input bool     InpAutoLearn          = true;            // Enable self-learning
input int      InpMinEventsEval      = 5;               // Min events before evaluation
input double   InpDisableWR          = 30.0;            // Disable event type below this WR

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_EVENT_TYPE
{
   EVENT_NFP,
   EVENT_FOMC,
   EVENT_CPI,
   EVENT_ECB,
   EVENT_BOE,
   EVENT_GDP,
   EVENT_RETAIL,
   EVENT_PMI,
   EVENT_CUSTOM,
   EVENT_BREAKOUT,
   EVENT_COUNT
};

enum ENUM_STRADDLE_STATE
{
   STATE_WAITING,           // Waiting for next event
   STATE_PENDING,           // Orders placed, waiting for trigger
   STATE_TRIGGERED_BUY,     // Buy side triggered
   STATE_TRIGGERED_SELL,    // Sell side triggered
   STATE_MANAGING,          // Managing active position
   STATE_HALTED             // Halted (DD or consec losses)
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct NewsEvent
{
   int         dayOfWeek;   // 0=Sun, 1=Mon...5=Fri
   int         hour;
   int         minute;
   ENUM_EVENT_TYPE type;
   string      name;
   bool        enabled;
};

struct StraddleOrder
{
   ulong       buyTicket;
   ulong       sellTicket;
   datetime    placedTime;
   datetime    eventTime;
   double      buyPrice;
   double      sellPrice;
   double      lotSize;
   ENUM_EVENT_TYPE eventType;
   bool        active;
};

struct ManagedPosition
{
   ulong       ticket;
   bool        isBuy;
   double      entryPrice;
   double      initialSL;
   double      currentSL;
   double      initialLots;
   double      currentLots;
   bool        beMoveDone;
   bool        partialDone;
   bool        trailing;
   double      maxProfitPips;
   datetime    openTime;
   ENUM_EVENT_TYPE eventType;
};

struct EventStats
{
   int         trades;
   int         wins;
   double      pnl;
   double      winRate;
   bool        enabled;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CAccountInfo   g_account;
CPositionInfo  g_position;
COrderInfo     g_order;

string         g_symbol;
ENUM_STRADDLE_STATE g_state = STATE_WAITING;

NewsEvent      g_events[100];
int            g_eventCount = 0;

StraddleOrder  g_currentStraddle;

ManagedPosition g_managed[10];
int            g_managedCount = 0;

// Performance
int            g_totalStraddles = 0;
int            g_totalWins = 0;
int            g_totalLosses = 0;
double         g_totalPnL = 0;
int            g_dailyStraddles = 0;
double         g_dailyPnL = 0;
int            g_consecLosses = 0;
int            g_consecWins = 0;
double         g_dayStartBalance = 0;
datetime       g_lastDay = 0;
bool           g_halted = false;
datetime       g_haltTime = 0;

// Event stats
EventStats     g_eventStats[10]; // One per EVENT_TYPE

// Log
int            g_logFile = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = (InpSymbol == "") ? Symbol() : InpSymbol;
   
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize event stats
   for(int i = 0; i < 10; i++)
   {
      g_eventStats[i].trades = 0;
      g_eventStats[i].wins = 0;
      g_eventStats[i].pnl = 0;
      g_eventStats[i].winRate = 0;
      g_eventStats[i].enabled = true;
   }
   
   // Build news schedule
   BuildNewsSchedule();
   
   // Parse custom times
   if(InpCustomTimes != "")
      ParseCustomTimes();
   
   // Account tracking
   g_dayStartBalance = g_account.Balance();
   g_lastDay = iTime(g_symbol, PERIOD_D1, 0);
   
   // Init straddle state
   g_currentStraddle.active = false;
   
   // Open log
   g_logFile = FileOpen("StraddleAI_trades.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ, ',');
   if(g_logFile != INVALID_HANDLE)
   {
      FileSeek(g_logFile, 0, SEEK_END);
      if(FileTell(g_logFile) == 0)
         FileWrite(g_logFile, "Time", "Symbol", "EventType", "Direction", "Lot",
                   "Entry", "Exit", "Profit", "Win", "Balance", "DailyPnL");
   }
   
   Print("============================================");
   Print("  STRADDLE AI PRO v1.0");
   Print("  Fully Automated News Straddle System");
   Print("============================================");
   Print("  Mode: ", InpFullAuto ? "FULL AUTO" : "SEMI-AUTO");
   Print("  Symbol: ", g_symbol);
   Print("  Events loaded: ", g_eventCount);
   Print("  Risk per straddle: ", DoubleToString(InpRiskPct, 2), "%");
   Print("  Place before event: ", InpPlaceBeforeSec, "s");
   Print("  >>> SCANNING FOR NEWS EVENTS <<<");
   Print("============================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logFile != INVALID_HANDLE) FileClose(g_logFile);
   ObjectsDeleteAll(0, "SAP_");
   PrintReport();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Day reset
   CheckDayReset();
   
   // Manage active positions
   ManagePositions();
   
   // Draw dashboard
   DrawDashboard();
   
   // Check halt
   if(g_halted)
   {
      // Auto-recover after 60 minutes
      if(TimeCurrent() - g_haltTime > 3600)
      {
         g_halted = false;
         g_consecLosses = 0;
         g_state = STATE_WAITING;
         Print("SAP: Halt lifted - resuming operations");
      }
      return;
   }
   
   // Daily limits
   if(g_dailyStraddles >= InpMaxStraddlesDay)
      return;
   
   // Daily DD check
   double equity = g_account.Equity();
   if(g_dayStartBalance > 0)
   {
      double ddPct = (g_dayStartBalance - equity) / g_dayStartBalance * 100;
      if(ddPct >= InpDailyDDLimit)
      {
         g_halted = true;
         g_haltTime = TimeCurrent();
         g_state = STATE_HALTED;
         Print("SAP: Daily DD limit hit (", DoubleToString(ddPct, 2), "%) - HALTING");
         return;
      }
   }
   
   // State machine
   switch(g_state)
   {
      case STATE_WAITING:
         CheckForUpcomingEvent();
         CheckBreakoutStraddle();
         break;
         
      case STATE_PENDING:
         MonitorPendingOrders();
         break;
         
      case STATE_TRIGGERED_BUY:
      case STATE_TRIGGERED_SELL:
      case STATE_MANAGING:
         // Handled in ManagePositions()
         break;
         
      case STATE_HALTED:
         break;
   }
}

//+------------------------------------------------------------------+
//| BUILD NEWS SCHEDULE                                               |
//+------------------------------------------------------------------+
void BuildNewsSchedule()
{
   g_eventCount = 0;
   
   if(!InpUseBuiltInNews) return;
   
   // NFP - First Friday of month, 13:30 UTC
   AddEvent(5, 13, 30, EVENT_NFP, "NFP");
   
   // FOMC - Wednesday (varies), 19:00 UTC
   AddEvent(3, 19, 0, EVENT_FOMC, "FOMC");
   
   // CPI - Usually Tuesday/Wednesday, 13:30 UTC
   AddEvent(2, 13, 30, EVENT_CPI, "CPI_TUE");
   AddEvent(3, 13, 30, EVENT_CPI, "CPI_WED");
   
   // ECB - Thursday, 13:15 UTC
   AddEvent(4, 13, 15, EVENT_ECB, "ECB");
   
   // BOE - Thursday, 12:00 UTC
   AddEvent(4, 12, 0, EVENT_BOE, "BOE");
   
   // GDP - Various days, 13:30 UTC
   AddEvent(3, 13, 30, EVENT_GDP, "GDP_WED");
   AddEvent(4, 13, 30, EVENT_GDP, "GDP_THU");
   
   // Retail Sales - Tuesday/Thursday 13:30
   AddEvent(2, 13, 30, EVENT_RETAIL, "RETAIL");
   
   // PMI - Monday/Wednesday 14:45
   AddEvent(1, 14, 45, EVENT_PMI, "PMI_MON");
   AddEvent(3, 14, 45, EVENT_PMI, "PMI_WED");
   
   // Common high-impact times (daily recurring)
   AddEvent(1, 8, 30, EVENT_CUSTOM, "LONDON_830");
   AddEvent(2, 8, 30, EVENT_CUSTOM, "LONDON_830");
   AddEvent(3, 8, 30, EVENT_CUSTOM, "LONDON_830");
   AddEvent(4, 8, 30, EVENT_CUSTOM, "LONDON_830");
   AddEvent(5, 8, 30, EVENT_CUSTOM, "LONDON_830");
   
   // NY Open volatility
   AddEvent(1, 13, 30, EVENT_CUSTOM, "NY_1330");
   AddEvent(2, 13, 30, EVENT_CUSTOM, "NY_1330");
   AddEvent(3, 13, 30, EVENT_CUSTOM, "NY_1330");
   AddEvent(4, 13, 30, EVENT_CUSTOM, "NY_1330");
   AddEvent(5, 13, 30, EVENT_CUSTOM, "NY_1330");
}

//+------------------------------------------------------------------+
//| ADD EVENT                                                         |
//+------------------------------------------------------------------+
void AddEvent(int dow, int hour, int minute, ENUM_EVENT_TYPE type, string name)
{
   if(g_eventCount >= 100) return;
   
   g_events[g_eventCount].dayOfWeek = dow;
   g_events[g_eventCount].hour = hour;
   g_events[g_eventCount].minute = minute;
   g_events[g_eventCount].type = type;
   g_events[g_eventCount].name = name;
   g_events[g_eventCount].enabled = true;
   g_eventCount++;
}

//+------------------------------------------------------------------+
//| PARSE CUSTOM TIMES                                                |
//+------------------------------------------------------------------+
void ParseCustomTimes()
{
   string parts[];
   int count = StringSplit(InpCustomTimes, ',', parts);
   
   for(int i = 0; i < count && g_eventCount < 100; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      
      string timeParts[];
      if(StringSplit(parts[i], ':', timeParts) == 2)
      {
         int hour = (int)StringToInteger(timeParts[0]);
         int minute = (int)StringToInteger(timeParts[1]);
         
         // Add for all enabled days
         for(int d = 1; d <= 5; d++)
         {
            if(d == 1 && !InpMondayEnabled) continue;
            if(d == 2 && !InpTuesdayEnabled) continue;
            if(d == 3 && !InpWednesdayEnabled) continue;
            if(d == 4 && !InpThursdayEnabled) continue;
            if(d == 5 && !InpFridayEnabled) continue;
            
            AddEvent(d, hour, minute, EVENT_CUSTOM, "CUSTOM_" + parts[i]);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK FOR UPCOMING EVENT                                          |
//+------------------------------------------------------------------+
void CheckForUpcomingEvent()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Check day enabled
   if(dt.day_of_week == 1 && !InpMondayEnabled) return;
   if(dt.day_of_week == 2 && !InpTuesdayEnabled) return;
   if(dt.day_of_week == 3 && !InpWednesdayEnabled) return;
   if(dt.day_of_week == 4 && !InpThursdayEnabled) return;
   if(dt.day_of_week == 5 && !InpFridayEnabled) return;
   
   for(int i = 0; i < g_eventCount; i++)
   {
      if(!g_events[i].enabled) continue;
      if(g_events[i].dayOfWeek != dt.day_of_week) continue;
      
      // Check if event type is still enabled (learning)
      int typeIdx = (int)g_events[i].type;
      if(typeIdx < 10 && !g_eventStats[typeIdx].enabled) continue;
      
      // Calculate seconds until event
      int eventSeconds = g_events[i].hour * 3600 + g_events[i].minute * 60;
      int currentSeconds = dt.hour * 3600 + dt.min * 60 + dt.sec;
      int secsUntil = eventSeconds - currentSeconds;
      
      // Place straddle X seconds before
      if(secsUntil > 0 && secsUntil <= InpPlaceBeforeSec)
      {
         PlaceStraddle(g_events[i].type, g_events[i].name);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK BREAKOUT STRADDLE (non-news based)                         |
//+------------------------------------------------------------------+
void CheckBreakoutStraddle()
{
   // Breakout straddle: when ATR suddenly expands + price consolidating
   int hATR = iATR(g_symbol, PERIOD_M5, 14);
   double atrBuf[];
   if(CopyBuffer(hATR, 0, 0, 5, atrBuf) < 5) { IndicatorRelease(hATR); return; }
   IndicatorRelease(hATR);
   
   double currentATR = atrBuf[0];
   double avgATR = (atrBuf[1] + atrBuf[2] + atrBuf[3] + atrBuf[4]) / 4.0;
   
   // If ATR is very low (consolidation) and it's during active hours
   MqlDateTime dt;
   TimeCurrent(dt);
   bool activeHours = (dt.hour >= 7 && dt.hour <= 20);
   
   if(activeHours && currentATR < avgATR * 0.5 && avgATR > 0)
   {
      // Check if we haven't placed a breakout straddle recently
      static datetime lastBreakout = 0;
      if(TimeCurrent() - lastBreakout < 3600) return; // 1 hour cooldown
      
      // Tight consolidation detected - place breakout straddle
      int typeIdx = (int)EVENT_BREAKOUT;
      if(typeIdx < 10 && !g_eventStats[typeIdx].enabled) return;
      
      PlaceStraddle(EVENT_BREAKOUT, "BREAKOUT");
      lastBreakout = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| PLACE STRADDLE                                                    |
//+------------------------------------------------------------------+
void PlaceStraddle(ENUM_EVENT_TYPE eventType, string eventName)
{
   // Already have active straddle
   if(g_currentStraddle.active) return;
   
   // Spread check
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;
   
   if(spread > InpMaxSpreadPoints)
   {
      Print("SAP: Spread too wide (", DoubleToString(spread, 0), " > ", DoubleToString(InpMaxSpreadPoints, 0), ") - skipping");
      return;
   }
   
   // Get ATR for distance calculation
   int hATR = iATR(g_symbol, PERIOD_M5, 14);
   double atrBuf[];
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) < 1) { IndicatorRelease(hATR); return; }
   IndicatorRelease(hATR);
   double atr = atrBuf[0];
   
   // Min ATR check
   if(InpMinATR > 0 && atr < InpMinATR)
   {
      Print("SAP: ATR too low (", DoubleToString(atr, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)), ") - skipping");
      return;
   }
   
   // Calculate distance
   double distance = atr * InpDistanceATRMult;
   double minDist = InpMinDistancePoints * point;
   double maxDist = InpMaxDistancePoints * point;
   distance = MathMax(distance, minDist);
   distance = MathMin(distance, maxDist);
   
   // SL and TP
   double sl = atr * InpSLATRMult;
   double tp = atr * InpTPATRMult;
   
   // RR check
   if(sl > 0 && tp / sl < InpMinRR)
      tp = sl * InpMinRR;
   
   // Calculate lot size
   double lot = CalcLotSize(sl);
   if(lot <= 0) return;
   
   // Buy Stop price
   double buyPrice = ask + distance;
   double buySL = buyPrice - sl;
   double buyTP = buyPrice + tp;
   
   // Sell Stop price
   double sellPrice = bid - distance;
   double sellSL = sellPrice + sl;
   double sellTP = sellPrice - tp;
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   buyPrice = NormalizeDouble(buyPrice, digits);
   buySL = NormalizeDouble(buySL, digits);
   buyTP = NormalizeDouble(buyTP, digits);
   sellPrice = NormalizeDouble(sellPrice, digits);
   sellSL = NormalizeDouble(sellSL, digits);
   sellTP = NormalizeDouble(sellTP, digits);
   
   string comment = "SAP|" + eventName;
   
   // Place Buy Stop
   bool buyPlaced = g_trade.BuyStop(lot, buyPrice, g_symbol, buySL, buyTP, 
                                     ORDER_TIME_GTC, 0, comment);
   ulong buyTicket = 0;
   if(buyPlaced) buyTicket = g_trade.ResultOrder();
   
   // Place Sell Stop
   bool sellPlaced = g_trade.SellStop(lot, sellPrice, g_symbol, sellSL, sellTP,
                                       ORDER_TIME_GTC, 0, comment);
   ulong sellTicket = 0;
   if(sellPlaced) sellTicket = g_trade.ResultOrder();
   
   if(buyPlaced || sellPlaced)
   {
      g_currentStraddle.buyTicket = buyTicket;
      g_currentStraddle.sellTicket = sellTicket;
      g_currentStraddle.placedTime = TimeCurrent();
      g_currentStraddle.eventTime = TimeCurrent() + InpPlaceBeforeSec;
      g_currentStraddle.buyPrice = buyPrice;
      g_currentStraddle.sellPrice = sellPrice;
      g_currentStraddle.lotSize = lot;
      g_currentStraddle.eventType = eventType;
      g_currentStraddle.active = true;
      
      g_state = STATE_PENDING;
      g_dailyStraddles++;
      g_totalStraddles++;
      
      Print("SAP: STRADDLE PLACED for ", eventName);
      Print("  Buy Stop: ", DoubleToString(buyPrice, digits), " SL=", DoubleToString(buySL, digits), " TP=", DoubleToString(buyTP, digits));
      Print("  Sell Stop: ", DoubleToString(sellPrice, digits), " SL=", DoubleToString(sellSL, digits), " TP=", DoubleToString(sellTP, digits));
      Print("  Lot: ", DoubleToString(lot, 2), " | Distance: ", DoubleToString(distance/point, 0), " pts");
   }
   else
   {
      Print("SAP: Failed to place straddle - ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| MONITOR PENDING ORDERS                                            |
//+------------------------------------------------------------------+
void MonitorPendingOrders()
{
   if(!g_currentStraddle.active) { g_state = STATE_WAITING; return; }
   
   bool buyExists = false;
   bool sellExists = false;
   
   // Check if orders still exist
   int totalOrders = OrdersTotal();
   for(int i = totalOrders - 1; i >= 0; i--)
   {
      if(g_order.SelectByIndex(i))
      {
         if(g_order.Magic() != InpMagic) continue;
         if(g_order.Symbol() != g_symbol) continue;
         
         if(g_order.Ticket() == g_currentStraddle.buyTicket) buyExists = true;
         if(g_order.Ticket() == g_currentStraddle.sellTicket) sellExists = true;
      }
   }
   
   // Check if a position was opened (order triggered)
   bool buyTriggered = false;
   bool sellTriggered = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Magic() != InpMagic) continue;
         if(g_position.Symbol() != g_symbol) continue;
         
         if(g_position.PositionType() == POSITION_TYPE_BUY)
            buyTriggered = true;
         if(g_position.PositionType() == POSITION_TYPE_SELL)
            sellTriggered = true;
      }
   }
   
   // Buy triggered - cancel sell
   if(buyTriggered && !buyExists)
   {
      if(InpAutoCancel && sellExists)
      {
         g_trade.OrderDelete(g_currentStraddle.sellTicket);
         Print("SAP: BUY triggered - cancelled sell side");
      }
      RegisterTriggeredPosition(true);
      g_state = STATE_TRIGGERED_BUY;
      g_currentStraddle.active = false;
      return;
   }
   
   // Sell triggered - cancel buy
   if(sellTriggered && !sellExists)
   {
      if(InpAutoCancel && buyExists)
      {
         g_trade.OrderDelete(g_currentStraddle.buyTicket);
         Print("SAP: SELL triggered - cancelled buy side");
      }
      RegisterTriggeredPosition(false);
      g_state = STATE_TRIGGERED_SELL;
      g_currentStraddle.active = false;
      return;
   }
   
   // Timeout - cancel both
   if(TimeCurrent() - g_currentStraddle.placedTime > InpCancelAfterSec)
   {
      if(buyExists) g_trade.OrderDelete(g_currentStraddle.buyTicket);
      if(sellExists) g_trade.OrderDelete(g_currentStraddle.sellTicket);
      
      g_currentStraddle.active = false;
      g_state = STATE_WAITING;
      Print("SAP: Straddle expired - cancelled both orders");
      return;
   }
}

//+------------------------------------------------------------------+
//| REGISTER TRIGGERED POSITION                                       |
//+------------------------------------------------------------------+
void RegisterTriggeredPosition(bool isBuy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Magic() != InpMagic) continue;
         if(g_position.Symbol() != g_symbol) continue;
         
         bool posIsBuy = (g_position.PositionType() == POSITION_TYPE_BUY);
         if(posIsBuy != isBuy) continue;
         
         if(g_managedCount < 10)
         {
            g_managed[g_managedCount].ticket = g_position.Ticket();
            g_managed[g_managedCount].isBuy = isBuy;
            g_managed[g_managedCount].entryPrice = g_position.PriceOpen();
            g_managed[g_managedCount].initialSL = g_position.StopLoss();
            g_managed[g_managedCount].currentSL = g_position.StopLoss();
            g_managed[g_managedCount].initialLots = g_position.Volume();
            g_managed[g_managedCount].currentLots = g_position.Volume();
            g_managed[g_managedCount].beMoveDone = false;
            g_managed[g_managedCount].partialDone = false;
            g_managed[g_managedCount].trailing = false;
            g_managed[g_managedCount].maxProfitPips = 0;
            g_managed[g_managedCount].openTime = TimeCurrent();
            g_managed[g_managedCount].eventType = g_currentStraddle.eventType;
            g_managedCount++;
         }
         break;
      }
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
         if(g_managedCount == 0) g_state = STATE_WAITING;
         continue;
      }
      
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
      double entry = g_managed[i].entryPrice;
      bool isBuy = g_managed[i].isBuy;
      
      // Profit in pips
      double profitPips = 0;
      if(isBuy)
         profitPips = (bid - entry) / point / 10;
      else
         profitPips = (entry - ask) / point / 10;
      
      if(profitPips > g_managed[i].maxProfitPips)
         g_managed[i].maxProfitPips = profitPips;
      
      // 1. Move to breakeven
      if(!g_managed[i].beMoveDone && profitPips >= InpBEPips)
      {
         double newSL = entry;
         if(isBuy) newSL = entry + point * 3;
         else newSL = entry - point * 3;
         
         if(g_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
         {
            g_managed[i].beMoveDone = true;
            g_managed[i].currentSL = newSL;
            Print("SAP: BE move on ", g_symbol);
         }
      }
      
      // 2. Partial close
      if(!g_managed[i].partialDone && profitPips >= InpPartialPips)
      {
         double closeVol = NormalizeDouble(g_managed[i].currentLots * InpPartialPct, 2);
         double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
         
         if(closeVol >= minVol)
         {
            if(g_trade.PositionClosePartial(ticket, closeVol))
            {
               g_managed[i].partialDone = true;
               g_managed[i].currentLots -= closeVol;
               Print("SAP: Partial close ", DoubleToString(closeVol, 2), " lots");
            }
         }
         else
            g_managed[i].partialDone = true;
      }
      
      // 3. ATR trailing
      if(g_managed[i].beMoveDone && g_managed[i].partialDone)
      {
         g_managed[i].trailing = true;
         
         int hATR = iATR(g_symbol, PERIOD_M5, 14);
         double atrBuf[];
         if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0)
         {
            double trailDist = atrBuf[0] * InpTrailATRMult;
            
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
         IndicatorRelease(hATR);
      }
      
      // 4. Time-based exit
      if(InpMaxHoldMinutes > 0)
      {
         int holdMins = (int)(TimeCurrent() - g_managed[i].openTime) / 60;
         if(holdMins >= InpMaxHoldMinutes)
         {
            g_trade.PositionClose(ticket);
            Print("SAP: Time exit after ", holdMins, " minutes");
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
   
   bool isWin = (profit > 0);
   
   g_totalPnL += profit;
   g_dailyPnL += profit;
   
   if(isWin) { g_totalWins++; g_consecWins++; g_consecLosses = 0; }
   else      { g_totalLosses++; g_consecLosses++; g_consecWins = 0; }
   
   // Update event stats - find which event type this was
   string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
   ENUM_EVENT_TYPE evType = GetEventTypeFromComment(comment);
   int typeIdx = (int)evType;
   
   if(typeIdx >= 0 && typeIdx < 10)
   {
      g_eventStats[typeIdx].trades++;
      if(isWin) g_eventStats[typeIdx].wins++;
      g_eventStats[typeIdx].pnl += profit;
      if(g_eventStats[typeIdx].trades > 0)
         g_eventStats[typeIdx].winRate = (double)g_eventStats[typeIdx].wins / g_eventStats[typeIdx].trades * 100;
      
      // Auto-learning: disable bad event types
      if(InpAutoLearn && g_eventStats[typeIdx].trades >= InpMinEventsEval)
      {
         if(g_eventStats[typeIdx].winRate < InpDisableWR)
         {
            g_eventStats[typeIdx].enabled = false;
            Print("SAP: Disabled event type ", GetEventName(evType), " - WR=", 
                  DoubleToString(g_eventStats[typeIdx].winRate, 1), "%");
         }
         else if(g_eventStats[typeIdx].winRate >= 45.0)
         {
            g_eventStats[typeIdx].enabled = true;
         }
      }
   }
   
   // Consecutive loss halt
   if(g_consecLosses >= InpMaxConsecLosses)
   {
      g_halted = true;
      g_haltTime = TimeCurrent();
      g_state = STATE_HALTED;
      Print("SAP: ", InpMaxConsecLosses, " consecutive losses - PAUSING");
   }
   
   // Log
   if(g_logFile != INVALID_HANDLE)
   {
      FileWrite(g_logFile, TimeToString(TimeCurrent()), g_symbol,
                GetEventName(evType), isWin ? "WIN" : "LOSS",
                DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(dealTicket, DEAL_PRICE), 
                              (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                "", DoubleToString(profit, 2), isWin ? "1" : "0",
                DoubleToString(g_account.Balance(), 2),
                DoubleToString(g_dailyPnL, 2));
      FileFlush(g_logFile);
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistance)
{
   double equity = g_account.Equity();
   double lot = InpMinLot;
   
   if(InpUseTierLots && equity < 5000)
   {
      if(equity < 50) lot = 0.01;
      else if(equity < 100) lot = 0.02;
      else if(equity < 250) lot = 0.03;
      else if(equity < 500) lot = 0.05;
      else if(equity < 1000) lot = 0.10;
      else if(equity < 2500) lot = 0.20;
      else lot = 0.30;
   }
   else
   {
      double riskAmount = equity * InpRiskPct / 100.0;
      double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue > 0 && tickSize > 0 && slDistance > 0)
      {
         double slTicks = slDistance / tickSize;
         lot = riskAmount / (slTicks * tickValue);
      }
   }
   
   // Normalize
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, InpMaxLot));
   if(stepLot > 0) lot = MathFloor(lot / stepLot) * stepLot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| GET EVENT TYPE FROM COMMENT                                       |
//+------------------------------------------------------------------+
ENUM_EVENT_TYPE GetEventTypeFromComment(string comment)
{
   if(StringFind(comment, "NFP") >= 0) return EVENT_NFP;
   if(StringFind(comment, "FOMC") >= 0) return EVENT_FOMC;
   if(StringFind(comment, "CPI") >= 0) return EVENT_CPI;
   if(StringFind(comment, "ECB") >= 0) return EVENT_ECB;
   if(StringFind(comment, "BOE") >= 0) return EVENT_BOE;
   if(StringFind(comment, "GDP") >= 0) return EVENT_GDP;
   if(StringFind(comment, "RETAIL") >= 0) return EVENT_RETAIL;
   if(StringFind(comment, "PMI") >= 0) return EVENT_PMI;
   if(StringFind(comment, "BREAKOUT") >= 0) return EVENT_BREAKOUT;
   return EVENT_CUSTOM;
}

//+------------------------------------------------------------------+
//| GET EVENT NAME                                                    |
//+------------------------------------------------------------------+
string GetEventName(ENUM_EVENT_TYPE evType)
{
   switch(evType)
   {
      case EVENT_NFP: return "NFP";
      case EVENT_FOMC: return "FOMC";
      case EVENT_CPI: return "CPI";
      case EVENT_ECB: return "ECB";
      case EVENT_BOE: return "BOE";
      case EVENT_GDP: return "GDP";
      case EVENT_RETAIL: return "RETAIL";
      case EVENT_PMI: return "PMI";
      case EVENT_BREAKOUT: return "BREAKOUT";
      default: return "CUSTOM";
   }
}

//+------------------------------------------------------------------+
//| REMOVE MANAGED POSITION                                           |
//+------------------------------------------------------------------+
void RemoveManaged(int index)
{
   for(int i = index; i < g_managedCount - 1; i++)
   {
      g_managed[i].ticket = g_managed[i+1].ticket;
      g_managed[i].isBuy = g_managed[i+1].isBuy;
      g_managed[i].entryPrice = g_managed[i+1].entryPrice;
      g_managed[i].initialSL = g_managed[i+1].initialSL;
      g_managed[i].currentSL = g_managed[i+1].currentSL;
      g_managed[i].initialLots = g_managed[i+1].initialLots;
      g_managed[i].currentLots = g_managed[i+1].currentLots;
      g_managed[i].beMoveDone = g_managed[i+1].beMoveDone;
      g_managed[i].partialDone = g_managed[i+1].partialDone;
      g_managed[i].trailing = g_managed[i+1].trailing;
      g_managed[i].maxProfitPips = g_managed[i+1].maxProfitPips;
      g_managed[i].openTime = g_managed[i+1].openTime;
      g_managed[i].eventType = g_managed[i+1].eventType;
   }
   g_managedCount--;
}

//+------------------------------------------------------------------+
//| CHECK DAY RESET                                                   |
//+------------------------------------------------------------------+
void CheckDayReset()
{
   datetime currentDay = iTime(g_symbol, PERIOD_D1, 0);
   if(currentDay != g_lastDay)
   {
      g_lastDay = currentDay;
      g_dailyStraddles = 0;
      g_dailyPnL = 0;
      g_dayStartBalance = g_account.Balance();
      g_halted = false;
      g_state = STATE_WAITING;
      Print("SAP: New trading day - counters reset");
   }
}

//+------------------------------------------------------------------+
//| DRAW DASHBOARD                                                    |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   string pfx = "SAP_";
   color clrTitle = clrGold;
   color clrText = clrWhite;
   color clrGood = clrLime;
   color clrBad = clrRed;
   color clrWarn = clrOrange;
   
   // Status
   string status = "SCANNING";
   color sClr = clrGood;
   if(g_halted) { status = "HALTED"; sClr = clrBad; }
   else if(g_state == STATE_PENDING) { status = "STRADDLE PLACED"; sClr = clrWarn; }
   else if(g_state == STATE_TRIGGERED_BUY) { status = "BUY ACTIVE"; sClr = clrGood; }
   else if(g_state == STATE_TRIGGERED_SELL) { status = "SELL ACTIVE"; sClr = clrGood; }
   else if(g_state == STATE_MANAGING) { status = "MANAGING"; sClr = clrGood; }
   
   CreateLabel(pfx+"hdr", x, y, "=== STRADDLE AI PRO v1.0 ===", clrTitle, 11); y += 18;
   CreateLabel(pfx+"st", x, y, "Status: " + status, sClr, 10); y += 16;
   CreateLabel(pfx+"sym", x, y, "Symbol: " + g_symbol, clrText, 9); y += 14;
   
   // Next event
   string nextEvt = GetNextEventName();
   CreateLabel(pfx+"nxt", x, y, "Next: " + nextEvt, clrWarn, 9); y += 16;
   
   // Account
   double equity = g_account.Equity();
   double dailyPct = (g_dayStartBalance > 0) ? g_dailyPnL / g_dayStartBalance * 100 : 0;
   CreateLabel(pfx+"eq", x, y, "Equity: $" + DoubleToString(equity, 2), clrText, 9); y += 14;
   CreateLabel(pfx+"dy", x, y, "Daily: " + (dailyPct >= 0 ? "+" : "") + DoubleToString(dailyPct, 2) + "%",
               dailyPct >= 0 ? clrGood : clrBad, 9); y += 14;
   
   // Stats
   double wr = (g_totalWins + g_totalLosses > 0) ? 
               (double)g_totalWins / (g_totalWins + g_totalLosses) * 100 : 0;
   CreateLabel(pfx+"tr", x, y, "Straddles: " + IntegerToString(g_totalStraddles), clrText, 9); y += 14;
   CreateLabel(pfx+"wr", x, y, "WR: " + DoubleToString(wr, 1) + "% (W:" + IntegerToString(g_totalWins) + " L:" + IntegerToString(g_totalLosses) + ")",
               wr >= 50 ? clrGood : clrBad, 9); y += 14;
   CreateLabel(pfx+"pnl", x, y, "PnL: $" + DoubleToString(g_totalPnL, 2),
               g_totalPnL >= 0 ? clrGood : clrBad, 9); y += 14;
   
   // Streaks
   CreateLabel(pfx+"sk", x, y, "W:" + IntegerToString(g_consecWins) + " L:" + IntegerToString(g_consecLosses),
               g_consecLosses >= 2 ? clrBad : clrText, 9); y += 16;
   
   // Today
   CreateLabel(pfx+"td", x, y, "Today: " + IntegerToString(g_dailyStraddles) + "/" + IntegerToString(InpMaxStraddlesDay) + " straddles",
               clrText, 9);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| GET NEXT EVENT NAME                                               |
//+------------------------------------------------------------------+
string GetNextEventName()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   int minSecsAway = 999999;
   string nextName = "---";
   
   for(int i = 0; i < g_eventCount; i++)
   {
      if(!g_events[i].enabled) continue;
      if(g_events[i].dayOfWeek != dt.day_of_week) continue;
      
      int eventSec = g_events[i].hour * 3600 + g_events[i].minute * 60;
      int currentSec = dt.hour * 3600 + dt.min * 60 + dt.sec;
      int secsUntil = eventSec - currentSec;
      
      if(secsUntil > 0 && secsUntil < minSecsAway)
      {
         minSecsAway = secsUntil;
         int minsUntil = secsUntil / 60;
         nextName = g_events[i].name + " in " + IntegerToString(minsUntil) + "m";
      }
   }
   
   return nextName;
}

//+------------------------------------------------------------------+
//| CREATE LABEL                                                      |
//+------------------------------------------------------------------+
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
   Print("  STRADDLE AI PRO - FINAL REPORT");
   Print("============================================");
   double wr = (g_totalWins + g_totalLosses > 0) ? 
               (double)g_totalWins / (g_totalWins + g_totalLosses) * 100 : 0;
   Print("Total Straddles: ", g_totalStraddles);
   Print("Wins: ", g_totalWins, " | Losses: ", g_totalLosses);
   Print("Win Rate: ", DoubleToString(wr, 1), "%");
   Print("Total PnL: $", DoubleToString(g_totalPnL, 2));
   Print("--------------------------------------------");
   Print("EVENT TYPE PERFORMANCE:");
   Print("  NFP:      T=", g_eventStats[0].trades, " WR=", DoubleToString(g_eventStats[0].winRate, 1), "% ", (g_eventStats[0].enabled ? "[ON]" : "[OFF]"));
   Print("  FOMC:     T=", g_eventStats[1].trades, " WR=", DoubleToString(g_eventStats[1].winRate, 1), "% ", (g_eventStats[1].enabled ? "[ON]" : "[OFF]"));
   Print("  CPI:      T=", g_eventStats[2].trades, " WR=", DoubleToString(g_eventStats[2].winRate, 1), "% ", (g_eventStats[2].enabled ? "[ON]" : "[OFF]"));
   Print("  ECB:      T=", g_eventStats[3].trades, " WR=", DoubleToString(g_eventStats[3].winRate, 1), "% ", (g_eventStats[3].enabled ? "[ON]" : "[OFF]"));
   Print("  BOE:      T=", g_eventStats[4].trades, " WR=", DoubleToString(g_eventStats[4].winRate, 1), "% ", (g_eventStats[4].enabled ? "[ON]" : "[OFF]"));
   Print("  GDP:      T=", g_eventStats[5].trades, " WR=", DoubleToString(g_eventStats[5].winRate, 1), "% ", (g_eventStats[5].enabled ? "[ON]" : "[OFF]"));
   Print("  RETAIL:   T=", g_eventStats[6].trades, " WR=", DoubleToString(g_eventStats[6].winRate, 1), "% ", (g_eventStats[6].enabled ? "[ON]" : "[OFF]"));
   Print("  PMI:      T=", g_eventStats[7].trades, " WR=", DoubleToString(g_eventStats[7].winRate, 1), "% ", (g_eventStats[7].enabled ? "[ON]" : "[OFF]"));
   Print("  CUSTOM:   T=", g_eventStats[8].trades, " WR=", DoubleToString(g_eventStats[8].winRate, 1), "% ", (g_eventStats[8].enabled ? "[ON]" : "[OFF]"));
   Print("  BREAKOUT: T=", g_eventStats[9].trades, " WR=", DoubleToString(g_eventStats[9].winRate, 1), "% ", (g_eventStats[9].enabled ? "[ON]" : "[OFF]"));
   Print("============================================");
}
//+------------------------------------------------------------------+
