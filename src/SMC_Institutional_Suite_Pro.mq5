//+------------------------------------------------------------------+
//|                              SMC_Institutional_Suite_Pro.mq5      |
//|              Smart Money Concepts Institutional Trading Suite     |
//|                                    Version 1.0                    |
//+------------------------------------------------------------------+
#property copyright "SMC Institutional Suite Pro"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — MODULE TOGGLES                                 |
//+------------------------------------------------------------------+
input group "══════ MODULE TOGGLES ══════"
input bool     InpShowStructure       = true;     // Show Market Structure (BOS/CHoCH)
input bool     InpShowLiquidity       = true;     // Show Liquidity Zones
input bool     InpShowOrderBlocks     = true;     // Show Order Blocks
input bool     InpShowFVG             = true;     // Show Fair Value Gaps
input bool     InpShowPremDiscount    = true;     // Show Premium/Discount Zones
input bool     InpShowSweeps          = true;     // Show Liquidity Sweeps
input bool     InpShowSessions        = true;     // Show Session Boxes
input bool     InpShowDWMLevels       = true;     // Show Daily/Weekly/Monthly Levels
input bool     InpShowMTFDashboard    = true;     // Show MTF Dashboard
input bool     InpShowProbability     = true;     // Show AI Probability
input bool     InpShowSignals         = true;     // Show Entry Signals
input bool     InpShowDashboard       = true;     // Show Main Dashboard

input group "══════ MARKET STRUCTURE ══════"
input int      InpStructureBars       = 5;        // Swing detection bars (each side)
input int      InpMaxStructurePoints  = 50;       // Max structure points to display
input color    InpBOSColor            = clrDodgerBlue;  // BOS line color
input color    InpCHoCHColor          = clrOrangeRed;   // CHoCH line color
input int      InpStructureWidth      = 2;        // Structure line width

input group "══════ LIQUIDITY ══════"
input double   InpEqualThreshold      = 0.3;      // Equal high/low threshold (ATR multiplier)
input int      InpLiqLookback         = 50;       // Lookback bars for liquidity
input color    InpBuySideLiqColor     = clrRoyalBlue;   // Buy side liquidity
input color    InpSellSideLiqColor    = clrCrimson;     // Sell side liquidity
input color    InpEqualHighColor      = clrPurple;      // Equal highs
input color    InpEqualLowColor       = clrOrange;      // Equal lows

input group "══════ ORDER BLOCKS ══════"
input int      InpOBLookback          = 30;       // OB lookback bars
input int      InpMaxOB               = 20;       // Max order blocks to show
input bool     InpHideMitigated       = false;    // Hide mitigated OBs
input color    InpBullOBColor         = C'34,139,34';   // Bullish OB color
input color    InpBearOBColor         = C'178,34,34';   // Bearish OB color
input int      InpOBTransparency      = 80;       // OB transparency (0-100)

input group "══════ FAIR VALUE GAPS ══════"
input int      InpFVGLookback         = 30;       // FVG lookback bars
input int      InpMaxFVG              = 20;       // Max FVGs to show
input double   InpMinFVGSize          = 0.5;      // Min FVG size (ATR multiplier)
input color    InpBullFVGColor        = C'0,100,0';     // Bullish FVG
input color    InpBearFVGColor        = C'139,0,0';     // Bearish FVG
input int      InpFVGTransparency     = 85;       // FVG transparency

input group "══════ PREMIUM/DISCOUNT ══════"
input int      InpPDSwingBars         = 50;       // Swing range lookback
input color    InpPremiumColor        = C'255,200,200'; // Premium zone
input color    InpDiscountColor       = C'200,255,200'; // Discount zone
input color    InpEquilibriumColor    = clrGray;        // Equilibrium line

input group "══════ SESSIONS ══════"
input bool     InpShowAsian           = true;     // Show Asian Session
input bool     InpShowLondon          = true;     // Show London Session
input bool     InpShowNY              = true;     // Show New York Session
input int      InpAsianStart          = 0;        // Asian start (hour UTC)
input int      InpAsianEnd            = 7;        // Asian end (hour UTC)
input int      InpLondonStart         = 7;        // London start (hour UTC)
input int      InpLondonEnd           = 16;       // London end (hour UTC)
input int      InpNYStart             = 12;       // NY start (hour UTC)
input int      InpNYEnd               = 21;       // NY end (hour UTC)
input color    InpAsianColor          = C'255,255,200'; // Asian session color
input color    InpLondonColor         = C'200,220,255'; // London session color
input color    InpNYColor             = C'255,220,200'; // NY session color

input group "══════ DAILY/WEEKLY/MONTHLY LEVELS ══════"
input color    InpPDHColor            = clrBlue;        // Previous Day High
input color    InpPDLColor            = clrBlue;        // Previous Day Low
input color    InpPWHColor            = clrDarkGreen;   // Previous Week High
input color    InpPWLColor            = clrDarkGreen;   // Previous Week Low
input color    InpPMHColor            = clrDarkRed;     // Previous Month High
input color    InpPMLColor            = clrDarkRed;     // Previous Month Low

input group "══════ AI PROBABILITY ══════"
input double   InpMinProbability      = 60.0;     // Min probability for signal
input double   InpTrendWeight         = 20.0;     // Trend weight
input double   InpLiqWeight           = 20.0;     // Liquidity weight
input double   InpOBWeight            = 15.0;     // Order block weight
input double   InpFVGWeight           = 15.0;     // FVG weight
input double   InpVolumeWeight        = 10.0;     // Volume weight
input double   InpSessionWeight       = 10.0;     // Session weight
input double   InpMomentumWeight      = 10.0;     // Momentum weight

input group "══════ ALERTS ══════"
input bool     InpAlertDesktop        = true;     // Desktop notification
input bool     InpAlertMobile         = true;     // Mobile push notification
input bool     InpAlertEmail          = false;    // Email alert
input bool     InpAlertSound          = true;     // Sound alert

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct SwingPoint
{
   int      bar;
   double   price;
   bool     isHigh;
   datetime time;
};

struct StructureLabel
{
   string   type;    // "HH","HL","LH","LL","BOS","CHoCH","MSS"
   int      bar;
   double   price;
   datetime time;
   bool     isBullish;
};

struct OrderBlock
{
   double   top;
   double   bottom;
   datetime startTime;
   datetime endTime;
   int      startBar;
   bool     isBullish;
   bool     mitigated;
   string   objName;
};

struct FVGZone
{
   double   top;
   double   bottom;
   datetime startTime;
   int      startBar;
   bool     isBullish;
   bool     filled;
   string   objName;
};

struct LiquidityLevel
{
   double   price;
   datetime time;
   int      bar;
   int      touchCount;
   bool     isBuySide;
   bool     swept;
   string   objName;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
SwingPoint     g_swings[200];
int            g_swingCount = 0;

StructureLabel g_structure[100];
int            g_structureCount = 0;

OrderBlock     g_OBs[50];
int            g_obCount = 0;

FVGZone        g_FVGs[50];
int            g_fvgCount = 0;

LiquidityLevel g_liquidity[50];
int            g_liqCount = 0;

// Market state
double         g_lastHH = 0, g_lastHL = 0;
double         g_lastLH = 0, g_lastLL = 0;
bool           g_isBullish = true;
double         g_currentProb = 0;
string         g_currentBias = "---";
double         g_pdh = 0, g_pdl = 0;
double         g_pwh = 0, g_pwl = 0;
double         g_pmh = 0, g_pml = 0;

// Probability factors
double         g_trendFactor = 0;
double         g_liqFactor = 0;
double         g_obFactor = 0;
double         g_fvgFactor = 0;
double         g_volFactor = 0;
double         g_sessFactor = 0;
double         g_momFactor = 0;

// Alert management
datetime       g_lastAlertTime = 0;
string         g_lastAlertMsg = "";

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("════════════════════════════════════════════");
   Print("  SMC INSTITUTIONAL SUITE PRO v1.0");
   Print("  Smart Money Concepts Analysis Engine");
   Print("════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator deinitialization                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "SMC_");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 100) return(rates_total);
   
   // Only recalculate on new bars or first run
   static datetime lastBarTime = 0;
   if(time[rates_total-1] == lastBarTime && prev_calculated > 0)
   {
      // Still update dashboard on every tick
      if(InpShowDashboard) DrawDashboard();
      return(rates_total);
   }
   lastBarTime = time[rates_total-1];
   
   // Clean old objects
   ObjectsDeleteAll(0, "SMC_");
   
   // ═══════════════════════════════════════
   // MODULE 1: MARKET STRUCTURE
   // ═══════════════════════════════════════
   if(InpShowStructure)
   {
      DetectSwings(high, low, time, rates_total);
      AnalyzeStructure(time, rates_total);
      DrawStructure(time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 2: LIQUIDITY DETECTION
   // ═══════════════════════════════════════
   if(InpShowLiquidity)
   {
      DetectLiquidity(high, low, close, time, rates_total);
      DrawLiquidity(time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 3: ORDER BLOCKS
   // ═══════════════════════════════════════
   if(InpShowOrderBlocks)
   {
      DetectOrderBlocks(open, high, low, close, time, rates_total);
      CheckOBMitigation(high, low, rates_total);
      DrawOrderBlocks(time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 4: FAIR VALUE GAPS
   // ═══════════════════════════════════════
   if(InpShowFVG)
   {
      DetectFVGs(high, low, time, rates_total);
      CheckFVGFill(high, low, rates_total);
      DrawFVGs(time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 5: PREMIUM/DISCOUNT ZONES
   // ═══════════════════════════════════════
   if(InpShowPremDiscount)
   {
      DrawPremiumDiscount(high, low, time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 6: LIQUIDITY SWEEPS
   // ═══════════════════════════════════════
   if(InpShowSweeps)
   {
      DetectSweeps(high, low, close, time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 7: SESSIONS
   // ═══════════════════════════════════════
   if(InpShowSessions)
   {
      DrawSessions(high, low, time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 8: DAILY/WEEKLY/MONTHLY LEVELS
   // ═══════════════════════════════════════
   if(InpShowDWMLevels)
   {
      DrawDWMLevels(time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 10: MTF DASHBOARD
   // ═══════════════════════════════════════
   if(InpShowMTFDashboard)
   {
      DrawMTFDashboard();
   }
   
   // ═══════════════════════════════════════
   // MODULE 11: AI PROBABILITY
   // ═══════════════════════════════════════
   if(InpShowProbability)
   {
      CalcProbability(open, high, low, close, time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 12: ENTRY SIGNALS
   // ═══════════════════════════════════════
   if(InpShowSignals && g_currentProb >= InpMinProbability)
   {
      DrawEntrySignal(high, low, close, time, rates_total);
   }
   
   // ═══════════════════════════════════════
   // MODULE 13: MAIN DASHBOARD
   // ═══════════════════════════════════════
   if(InpShowDashboard)
   {
      DrawDashboard();
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| DETECT SWING POINTS                                               |
//+------------------------------------------------------------------+
void DetectSwings(const double &high[], const double &low[], const datetime &time[], int total)
{
   g_swingCount = 0;
   int lookback = MathMin(InpLiqLookback * 3, total - InpStructureBars - 1);
   int startBar = total - lookback;
   if(startBar < InpStructureBars) startBar = InpStructureBars;
   
   for(int i = startBar; i < total - InpStructureBars; i++)
   {
      // Check swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= InpStructureBars; j++)
      {
         if(high[i] <= high[i-j] || high[i] <= high[i+j])
         {
            isSwingHigh = false;
            break;
         }
      }
      
      if(isSwingHigh && g_swingCount < 200)
      {
         g_swings[g_swingCount].bar = i;
         g_swings[g_swingCount].price = high[i];
         g_swings[g_swingCount].isHigh = true;
         g_swings[g_swingCount].time = time[i];
         g_swingCount++;
      }
      
      // Check swing low
      bool isSwingLow = true;
      for(int j = 1; j <= InpStructureBars; j++)
      {
         if(low[i] >= low[i-j] || low[i] >= low[i+j])
         {
            isSwingLow = false;
            break;
         }
      }
      
      if(isSwingLow && g_swingCount < 200)
      {
         g_swings[g_swingCount].bar = i;
         g_swings[g_swingCount].price = low[i];
         g_swings[g_swingCount].isHigh = false;
         g_swings[g_swingCount].time = time[i];
         g_swingCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| ANALYZE MARKET STRUCTURE                                          |
//+------------------------------------------------------------------+
void AnalyzeStructure(const datetime &time[], int total)
{
   g_structureCount = 0;
   g_lastHH = 0; g_lastHL = 0;
   g_lastLH = 0; g_lastLL = 0;
   
   double prevSwingHigh = 0, prevSwingLow = 0;
   bool wasBullish = true;
   
   for(int i = 0; i < g_swingCount && g_structureCount < 100; i++)
   {
      if(g_swings[i].isHigh)
      {
         if(prevSwingHigh > 0)
         {
            if(g_swings[i].price > prevSwingHigh)
            {
               // Higher High
               g_structure[g_structureCount].type = "HH";
               g_structure[g_structureCount].bar = g_swings[i].bar;
               g_structure[g_structureCount].price = g_swings[i].price;
               g_structure[g_structureCount].time = g_swings[i].time;
               g_structure[g_structureCount].isBullish = true;
               g_structureCount++;
               g_lastHH = g_swings[i].price;
               
               // BOS if was bearish
               if(!wasBullish && g_swings[i].price > prevSwingHigh)
               {
                  g_structure[g_structureCount].type = "CHoCH";
                  g_structure[g_structureCount].bar = g_swings[i].bar;
                  g_structure[g_structureCount].price = prevSwingHigh;
                  g_structure[g_structureCount].time = g_swings[i].time;
                  g_structure[g_structureCount].isBullish = true;
                  g_structureCount++;
                  wasBullish = true;
               }
            }
            else
            {
               // Lower High
               g_structure[g_structureCount].type = "LH";
               g_structure[g_structureCount].bar = g_swings[i].bar;
               g_structure[g_structureCount].price = g_swings[i].price;
               g_structure[g_structureCount].time = g_swings[i].time;
               g_structure[g_structureCount].isBullish = false;
               g_structureCount++;
               g_lastLH = g_swings[i].price;
            }
         }
         prevSwingHigh = g_swings[i].price;
      }
      else
      {
         if(prevSwingLow > 0)
         {
            if(g_swings[i].price > prevSwingLow)
            {
               // Higher Low
               g_structure[g_structureCount].type = "HL";
               g_structure[g_structureCount].bar = g_swings[i].bar;
               g_structure[g_structureCount].price = g_swings[i].price;
               g_structure[g_structureCount].time = g_swings[i].time;
               g_structure[g_structureCount].isBullish = true;
               g_structureCount++;
               g_lastHL = g_swings[i].price;
            }
            else
            {
               // Lower Low
               g_structure[g_structureCount].type = "LL";
               g_structure[g_structureCount].bar = g_swings[i].bar;
               g_structure[g_structureCount].price = g_swings[i].price;
               g_structure[g_structureCount].time = g_swings[i].time;
               g_structure[g_structureCount].isBullish = false;
               g_structureCount++;
               g_lastLL = g_swings[i].price;
               
               // BOS bearish
               if(wasBullish && g_swings[i].price < prevSwingLow)
               {
                  g_structure[g_structureCount].type = "BOS";
                  g_structure[g_structureCount].bar = g_swings[i].bar;
                  g_structure[g_structureCount].price = prevSwingLow;
                  g_structure[g_structureCount].time = g_swings[i].time;
                  g_structure[g_structureCount].isBullish = false;
                  g_structureCount++;
                  wasBullish = false;
               }
            }
         }
         prevSwingLow = g_swings[i].price;
      }
   }
   
   g_isBullish = wasBullish;
}

//+------------------------------------------------------------------+
//| DRAW MARKET STRUCTURE                                             |
//+------------------------------------------------------------------+
void DrawStructure(const datetime &time[], int total)
{
   int limit = MathMin(g_structureCount, InpMaxStructurePoints);
   int start = g_structureCount - limit;
   if(start < 0) start = 0;
   
   for(int i = start; i < g_structureCount; i++)
   {
      string name = "SMC_str_" + IntegerToString(i);
      string label = g_structure[i].type;
      
      if(label == "BOS" || label == "CHoCH" || label == "MSS")
      {
         // Draw horizontal line
         color lineClr = (label == "BOS") ? InpBOSColor : InpCHoCHColor;
         datetime t1 = g_structure[i].time;
         datetime t2 = time[MathMin(g_structure[i].bar + 10, total - 1)];
         
         ObjectCreate(0, name, OBJ_TREND, 0, t1, g_structure[i].price, t2, g_structure[i].price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, lineClr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, InpStructureWidth);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
         
         // Label
         string lblName = name + "_lbl";
         ObjectCreate(0, lblName, OBJ_TEXT, 0, t1, g_structure[i].price);
         ObjectSetString(0, lblName, OBJPROP_TEXT, label);
         ObjectSetInteger(0, lblName, OBJPROP_COLOR, lineClr);
         ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, lblName, OBJPROP_FONT, "Arial Bold");
      }
      else
      {
         // HH, HL, LH, LL labels
         color lblClr = g_structure[i].isBullish ? clrGreen : clrRed;
         ObjectCreate(0, name, OBJ_TEXT, 0, g_structure[i].time, g_structure[i].price);
         ObjectSetString(0, name, OBJPROP_TEXT, label);
         ObjectSetInteger(0, name, OBJPROP_COLOR, lblClr);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, 
                          g_structure[i].isHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
      }
   }
}

//+------------------------------------------------------------------+
//| DETECT LIQUIDITY LEVELS                                           |
//+------------------------------------------------------------------+
void DetectLiquidity(const double &high[], const double &low[], const double &close[],
                     const datetime &time[], int total)
{
   g_liqCount = 0;
   int lookback = MathMin(InpLiqLookback, total - 10);
   int startBar = total - lookback;
   
   // Get ATR for threshold
   int hATR = iATR(Symbol(), PERIOD_CURRENT, 14);
   double atrBuf[];
   double atr = 0;
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
   IndicatorRelease(hATR);
   
   double threshold = atr * InpEqualThreshold;
   if(threshold <= 0) return;
   
   // Find equal highs
   for(int i = startBar; i < total - 5 && g_liqCount < 50; i++)
   {
      for(int j = i + 3; j < MathMin(i + 20, total) && g_liqCount < 50; j++)
      {
         // Equal highs
         if(MathAbs(high[i] - high[j]) < threshold)
         {
            bool isMax_i = true, isMax_j = true;
            for(int k = 1; k <= 2; k++)
            {
               if(i-k >= 0 && high[i] <= high[i-k]) isMax_i = false;
               if(i+k < total && high[i] <= high[i+k]) isMax_i = false;
               if(j-k >= 0 && high[j] <= high[j-k]) isMax_j = false;
               if(j+k < total && high[j] <= high[j+k]) isMax_j = false;
            }
            
            if(isMax_i && isMax_j)
            {
               g_liquidity[g_liqCount].price = (high[i] + high[j]) / 2.0;
               g_liquidity[g_liqCount].time = time[i];
               g_liquidity[g_liqCount].bar = i;
               g_liquidity[g_liqCount].touchCount = 2;
               g_liquidity[g_liqCount].isBuySide = true;
               g_liquidity[g_liqCount].swept = (close[total-1] > high[i] + threshold);
               g_liqCount++;
            }
         }
         
         // Equal lows
         if(MathAbs(low[i] - low[j]) < threshold && g_liqCount < 50)
         {
            bool isMin_i = true, isMin_j = true;
            for(int k = 1; k <= 2; k++)
            {
               if(i-k >= 0 && low[i] >= low[i-k]) isMin_i = false;
               if(i+k < total && low[i] >= low[i+k]) isMin_i = false;
               if(j-k >= 0 && low[j] >= low[j-k]) isMin_j = false;
               if(j+k < total && low[j] >= low[j+k]) isMin_j = false;
            }
            
            if(isMin_i && isMin_j)
            {
               g_liquidity[g_liqCount].price = (low[i] + low[j]) / 2.0;
               g_liquidity[g_liqCount].time = time[i];
               g_liquidity[g_liqCount].bar = i;
               g_liquidity[g_liqCount].touchCount = 2;
               g_liquidity[g_liqCount].isBuySide = false;
               g_liquidity[g_liqCount].swept = (close[total-1] < low[i] - threshold);
               g_liqCount++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW LIQUIDITY LEVELS                                             |
//+------------------------------------------------------------------+
void DrawLiquidity(const datetime &time[], int total)
{
   for(int i = 0; i < g_liqCount; i++)
   {
      if(g_liquidity[i].swept) continue;
      
      string name = "SMC_liq_" + IntegerToString(i);
      datetime t1 = g_liquidity[i].time;
      datetime t2 = time[total - 1];
      
      color clr = g_liquidity[i].isBuySide ? InpBuySideLiqColor : InpSellSideLiqColor;
      
      ObjectCreate(0, name, OBJ_TREND, 0, t1, g_liquidity[i].price, t2, g_liquidity[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      
      // Label
      string lblName = name + "_lbl";
      string lblText = g_liquidity[i].isBuySide ? "BSL $$$" : "SSL $$$";
      ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, g_liquidity[i].price);
      ObjectSetString(0, lblName, OBJPROP_TEXT, lblText);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
   }
}

//+------------------------------------------------------------------+
//| DETECT ORDER BLOCKS                                               |
//+------------------------------------------------------------------+
void DetectOrderBlocks(const double &open[], const double &high[], const double &low[],
                       const double &close[], const datetime &time[], int total)
{
   g_obCount = 0;
   int lookback = MathMin(InpOBLookback, total - 5);
   int startBar = total - lookback;
   
   for(int i = startBar; i < total - 3 && g_obCount < InpMaxOB; i++)
   {
      // Bullish OB: last bearish candle before impulsive bullish move
      if(close[i] < open[i])  // Bearish candle
      {
         // Next candle(s) must be strongly bullish
         if(close[i+1] > open[i+1] && close[i+1] > high[i])
         {
            double impulse = close[i+1] - open[i+1];
            double bodyBearish = open[i] - close[i];
            
            if(impulse > bodyBearish * 1.5)
            {
               g_OBs[g_obCount].top = open[i];
               g_OBs[g_obCount].bottom = low[i];
               g_OBs[g_obCount].startTime = time[i];
               g_OBs[g_obCount].endTime = time[MathMin(i + 15, total - 1)];
               g_OBs[g_obCount].startBar = i;
               g_OBs[g_obCount].isBullish = true;
               g_OBs[g_obCount].mitigated = false;
               g_obCount++;
            }
         }
      }
      
      // Bearish OB: last bullish candle before impulsive bearish move
      if(close[i] > open[i] && g_obCount < InpMaxOB)  // Bullish candle
      {
         if(close[i+1] < open[i+1] && close[i+1] < low[i])
         {
            double impulse = open[i+1] - close[i+1];
            double bodyBullish = close[i] - open[i];
            
            if(impulse > bodyBullish * 1.5)
            {
               g_OBs[g_obCount].top = high[i];
               g_OBs[g_obCount].bottom = close[i];
               g_OBs[g_obCount].startTime = time[i];
               g_OBs[g_obCount].endTime = time[MathMin(i + 15, total - 1)];
               g_OBs[g_obCount].startBar = i;
               g_OBs[g_obCount].isBullish = false;
               g_OBs[g_obCount].mitigated = false;
               g_obCount++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK OB MITIGATION                                               |
//+------------------------------------------------------------------+
void CheckOBMitigation(const double &high[], const double &low[], int total)
{
   for(int i = 0; i < g_obCount; i++)
   {
      if(g_OBs[i].mitigated) continue;
      
      // Check if price has returned and traded through the OB
      for(int j = g_OBs[i].startBar + 2; j < total; j++)
      {
         if(g_OBs[i].isBullish)
         {
            // Mitigated if price goes below the OB bottom
            if(low[j] < g_OBs[i].bottom)
            {
               g_OBs[i].mitigated = true;
               break;
            }
         }
         else
         {
            // Mitigated if price goes above the OB top
            if(high[j] > g_OBs[i].top)
            {
               g_OBs[i].mitigated = true;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW ORDER BLOCKS                                                 |
//+------------------------------------------------------------------+
void DrawOrderBlocks(const datetime &time[], int total)
{
   for(int i = 0; i < g_obCount; i++)
   {
      if(InpHideMitigated && g_OBs[i].mitigated) continue;
      
      string name = "SMC_ob_" + IntegerToString(i);
      datetime t2 = g_OBs[i].mitigated ? g_OBs[i].endTime : time[total - 1];
      
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, g_OBs[i].startTime, g_OBs[i].top, t2, g_OBs[i].bottom);
      
      color clr = g_OBs[i].isBullish ? InpBullOBColor : InpBearOBColor;
      if(g_OBs[i].mitigated) clr = clrGray;
      
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      
      // Label
      string lblName = name + "_lbl";
      string lblText = (g_OBs[i].isBullish ? "Bull OB" : "Bear OB");
      if(g_OBs[i].mitigated) lblText += " [M]";
      ObjectCreate(0, lblName, OBJ_TEXT, 0, g_OBs[i].startTime, g_OBs[i].top);
      ObjectSetString(0, lblName, OBJPROP_TEXT, lblText);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
   }
}

//+------------------------------------------------------------------+
//| DETECT FAIR VALUE GAPS                                            |
//+------------------------------------------------------------------+
void DetectFVGs(const double &high[], const double &low[], const datetime &time[], int total)
{
   g_fvgCount = 0;
   int lookback = MathMin(InpFVGLookback, total - 5);
   int startBar = total - lookback;
   
   // Get ATR for min size
   int hATR = iATR(Symbol(), PERIOD_CURRENT, 14);
   double atrBuf[];
   double atr = 0;
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
   IndicatorRelease(hATR);
   double minSize = atr * InpMinFVGSize;
   
   for(int i = startBar + 1; i < total - 1 && g_fvgCount < InpMaxFVG; i++)
   {
      // Bullish FVG: gap between candle 1 high and candle 3 low
      double bullGapTop = low[i+1];  // Low of candle after
      double bullGapBot = high[i-1]; // High of candle before
      
      if(bullGapBot < bullGapTop)
      {
         double gapSize = bullGapTop - bullGapBot;
         if(gapSize >= minSize)
         {
            g_FVGs[g_fvgCount].top = bullGapTop;
            g_FVGs[g_fvgCount].bottom = bullGapBot;
            g_FVGs[g_fvgCount].startTime = time[i];
            g_FVGs[g_fvgCount].startBar = i;
            g_FVGs[g_fvgCount].isBullish = true;
            g_FVGs[g_fvgCount].filled = false;
            g_fvgCount++;
         }
      }
      
      // Bearish FVG: gap between candle 3 high and candle 1 low
      if(g_fvgCount < InpMaxFVG)
      {
         double bearGapTop = low[i-1]; // Low of candle before
         double bearGapBot = high[i+1]; // High of candle after
         
         if(bearGapBot < bearGapTop)
         {
            double gapSize = bearGapTop - bearGapBot;
            if(gapSize >= minSize)
            {
               g_FVGs[g_fvgCount].top = bearGapTop;
               g_FVGs[g_fvgCount].bottom = bearGapBot;
               g_FVGs[g_fvgCount].startTime = time[i];
               g_FVGs[g_fvgCount].startBar = i;
               g_FVGs[g_fvgCount].isBullish = false;
               g_FVGs[g_fvgCount].filled = false;
               g_fvgCount++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK FVG FILL                                                    |
//+------------------------------------------------------------------+
void CheckFVGFill(const double &high[], const double &low[], int total)
{
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(g_FVGs[i].filled) continue;
      
      for(int j = g_FVGs[i].startBar + 2; j < total; j++)
      {
         if(g_FVGs[i].isBullish)
         {
            if(low[j] <= g_FVGs[i].bottom)
            {
               g_FVGs[i].filled = true;
               break;
            }
         }
         else
         {
            if(high[j] >= g_FVGs[i].top)
            {
               g_FVGs[i].filled = true;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW FVGs                                                         |
//+------------------------------------------------------------------+
void DrawFVGs(const datetime &time[], int total)
{
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(g_FVGs[i].filled) continue;
      
      string name = "SMC_fvg_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, g_FVGs[i].startTime, g_FVGs[i].top, time[total-1], g_FVGs[i].bottom);
      
      color clr = g_FVGs[i].isBullish ? InpBullFVGColor : InpBearFVGColor;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      
      string lblName = name + "_lbl";
      ObjectCreate(0, lblName, OBJ_TEXT, 0, g_FVGs[i].startTime, g_FVGs[i].top);
      ObjectSetString(0, lblName, OBJPROP_TEXT, g_FVGs[i].isBullish ? "FVG+" : "FVG-");
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
   }
}

//+------------------------------------------------------------------+
//| DRAW PREMIUM/DISCOUNT ZONES                                       |
//+------------------------------------------------------------------+
void DrawPremiumDiscount(const double &high[], const double &low[],
                         const datetime &time[], int total)
{
   int lookback = MathMin(InpPDSwingBars, total - 1);
   int startBar = total - lookback;
   
   double rangeHigh = high[startBar];
   double rangeLow = low[startBar];
   
   for(int i = startBar; i < total; i++)
   {
      if(high[i] > rangeHigh) rangeHigh = high[i];
      if(low[i] < rangeLow) rangeLow = low[i];
   }
   
   double equilibrium = (rangeHigh + rangeLow) / 2.0;
   
   // Equilibrium line
   string eqName = "SMC_eq_line";
   ObjectCreate(0, eqName, OBJ_TREND, 0, time[startBar], equilibrium, time[total-1], equilibrium);
   ObjectSetInteger(0, eqName, OBJPROP_COLOR, InpEquilibriumColor);
   ObjectSetInteger(0, eqName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, eqName, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, eqName, OBJPROP_RAY_RIGHT, false);
   
   // Equilibrium label
   string eqLbl = "SMC_eq_lbl";
   ObjectCreate(0, eqLbl, OBJ_TEXT, 0, time[total-1], equilibrium);
   ObjectSetString(0, eqLbl, OBJPROP_TEXT, "EQ 50%");
   ObjectSetInteger(0, eqLbl, OBJPROP_COLOR, InpEquilibriumColor);
   ObjectSetInteger(0, eqLbl, OBJPROP_FONTSIZE, 8);
   
   // Premium zone (above EQ)
   string premName = "SMC_premium";
   ObjectCreate(0, premName, OBJ_RECTANGLE, 0, time[startBar], rangeHigh, time[total-1], equilibrium);
   ObjectSetInteger(0, premName, OBJPROP_COLOR, InpPremiumColor);
   ObjectSetInteger(0, premName, OBJPROP_FILL, true);
   ObjectSetInteger(0, premName, OBJPROP_BACK, true);
   
   // Discount zone (below EQ)
   string discName = "SMC_discount";
   ObjectCreate(0, discName, OBJ_RECTANGLE, 0, time[startBar], equilibrium, time[total-1], rangeLow);
   ObjectSetInteger(0, discName, OBJPROP_COLOR, InpDiscountColor);
   ObjectSetInteger(0, discName, OBJPROP_FILL, true);
   ObjectSetInteger(0, discName, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| DETECT LIQUIDITY SWEEPS                                           |
//+------------------------------------------------------------------+
void DetectSweeps(const double &high[], const double &low[], const double &close[],
                  const datetime &time[], int total)
{
   // Look for recent sweeps (last 20 bars)
   int lookback = MathMin(20, total - 5);
   int startBar = total - lookback;
   
   for(int i = 0; i < g_liqCount; i++)
   {
      if(g_liquidity[i].swept) continue;
      
      for(int j = startBar; j < total - 1; j++)
      {
         if(g_liquidity[i].isBuySide)
         {
            // Buy side swept: wick above then close below
            if(high[j] > g_liquidity[i].price && close[j] < g_liquidity[i].price)
            {
               g_liquidity[i].swept = true;
               
               // Draw sweep arrow
               string name = "SMC_sweep_" + IntegerToString(i);
               ObjectCreate(0, name, OBJ_ARROW, 0, time[j], high[j]);
               ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 218); // Down arrow
               ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
               
               string lblName = name + "_lbl";
               ObjectCreate(0, lblName, OBJ_TEXT, 0, time[j], high[j]);
               ObjectSetString(0, lblName, OBJPROP_TEXT, "SWEEP");
               ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
               ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LOWER);
               break;
            }
         }
         else
         {
            // Sell side swept: wick below then close above
            if(low[j] < g_liquidity[i].price && close[j] > g_liquidity[i].price)
            {
               g_liquidity[i].swept = true;
               
               string name = "SMC_sweep_" + IntegerToString(i);
               ObjectCreate(0, name, OBJ_ARROW, 0, time[j], low[j]);
               ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 217); // Up arrow
               ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
               
               string lblName = name + "_lbl";
               ObjectCreate(0, lblName, OBJ_TEXT, 0, time[j], low[j]);
               ObjectSetString(0, lblName, OBJPROP_TEXT, "SWEEP");
               ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrGreen);
               ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
               ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_UPPER);
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW SESSIONS                                                     |
//+------------------------------------------------------------------+
void DrawSessions(const double &high[], const double &low[],
                  const datetime &time[], int total)
{
   // Draw session boxes for last 3 days
   for(int day = 0; day < 3; day++)
   {
      datetime dayStart = iTime(Symbol(), PERIOD_D1, day);
      if(dayStart == 0) continue;
      
      MqlDateTime dt;
      TimeToStruct(dayStart, dt);
      
      if(InpShowAsian)
         DrawSessionBox("asian_" + IntegerToString(day), dayStart, InpAsianStart, InpAsianEnd,
                        high, low, time, total, InpAsianColor, "ASIAN");
      if(InpShowLondon)
         DrawSessionBox("london_" + IntegerToString(day), dayStart, InpLondonStart, InpLondonEnd,
                        high, low, time, total, InpLondonColor, "LONDON");
      if(InpShowNY)
         DrawSessionBox("ny_" + IntegerToString(day), dayStart, InpNYStart, InpNYEnd,
                        high, low, time, total, InpNYColor, "NY");
   }
}

//+------------------------------------------------------------------+
//| DRAW SESSION BOX HELPER                                           |
//+------------------------------------------------------------------+
void DrawSessionBox(string id, datetime dayStart, int startHour, int endHour,
                    const double &high[], const double &low[],
                    const datetime &time[], int total, color clr, string label)
{
   datetime sessStart = dayStart + startHour * 3600;
   datetime sessEnd = dayStart + endHour * 3600;
   
   // Find high/low within session
   double sessHigh = 0, sessLow = 999999;
   bool found = false;
   
   for(int i = 0; i < total; i++)
   {
      if(time[i] >= sessStart && time[i] <= sessEnd)
      {
         if(high[i] > sessHigh) sessHigh = high[i];
         if(low[i] < sessLow) sessLow = low[i];
         found = true;
      }
   }
   
   if(!found || sessHigh == 0 || sessLow == 999999) return;
   
   string name = "SMC_sess_" + id;
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, sessStart, sessHigh, sessEnd, sessLow);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   
   // Label
   string lblName = name + "_lbl";
   ObjectCreate(0, lblName, OBJ_TEXT, 0, sessStart, sessHigh);
   ObjectSetString(0, lblName, OBJPROP_TEXT, label);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LOWER);
}

//+------------------------------------------------------------------+
//| DRAW DAILY/WEEKLY/MONTHLY LEVELS                                  |
//+------------------------------------------------------------------+
void DrawDWMLevels(const datetime &time[], int total)
{
   double dH[], dL[], wH[], wL[], mH[], mL[];
   
   // Previous Day
   if(CopyHigh(Symbol(), PERIOD_D1, 1, 1, dH) > 0) g_pdh = dH[0];
   if(CopyLow(Symbol(), PERIOD_D1, 1, 1, dL) > 0) g_pdl = dL[0];
   
   // Previous Week
   if(CopyHigh(Symbol(), PERIOD_W1, 1, 1, wH) > 0) g_pwh = wH[0];
   if(CopyLow(Symbol(), PERIOD_W1, 1, 1, wL) > 0) g_pwl = wL[0];
   
   // Previous Month
   if(CopyHigh(Symbol(), PERIOD_MN1, 1, 1, mH) > 0) g_pmh = mH[0];
   if(CopyLow(Symbol(), PERIOD_MN1, 1, 1, mL) > 0) g_pml = mL[0];
   
   datetime t1 = time[total > 100 ? total - 100 : 0];
   datetime t2 = time[total - 1];
   
   DrawLevel("SMC_pdh", g_pdh, t1, t2, InpPDHColor, "PDH");
   DrawLevel("SMC_pdl", g_pdl, t1, t2, InpPDLColor, "PDL");
   DrawLevel("SMC_pwh", g_pwh, t1, t2, InpPWHColor, "PWH");
   DrawLevel("SMC_pwl", g_pwl, t1, t2, InpPWLColor, "PWL");
   DrawLevel("SMC_pmh", g_pmh, t1, t2, InpPMHColor, "PMH");
   DrawLevel("SMC_pml", g_pml, t1, t2, InpPMLColor, "PML");
}

//+------------------------------------------------------------------+
//| DRAW LEVEL HELPER                                                 |
//+------------------------------------------------------------------+
void DrawLevel(string name, double price, datetime t1, datetime t2, color clr, string label)
{
   if(price <= 0) return;
   
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   
   string lblName = name + "_lbl";
   ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, price);
   ObjectSetString(0, lblName, OBJPROP_TEXT, label + " " + DoubleToString(price, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)));
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| DRAW MTF DASHBOARD                                                |
//+------------------------------------------------------------------+
void DrawMTFDashboard()
{
   int x = 10, y = 400;
   string pfx = "SMC_mtf_";
   
   CreateDashLabel(pfx+"title", x, y, "── MTF ANALYSIS ──", clrGold, 9); y += 14;
   
   // Check trend on multiple timeframes
   ENUM_TIMEFRAMES tfs[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   string tfNames[] = {"M1", "M5", "M15", "H1", "H4", "D1"};
   int bullCount = 0;
   
   for(int i = 0; i < 6; i++)
   {
      int hEMA9 = iMA(Symbol(), tfs[i], 9, 0, MODE_EMA, PRICE_CLOSE);
      int hEMA21 = iMA(Symbol(), tfs[i], 21, 0, MODE_EMA, PRICE_CLOSE);
      double e9[], e21[];
      string bias = "---";
      color bClr = clrGray;
      
      if(CopyBuffer(hEMA9, 0, 0, 1, e9) > 0 && CopyBuffer(hEMA21, 0, 0, 1, e21) > 0)
      {
         if(e9[0] > e21[0]) { bias = "Bullish"; bClr = clrLime; bullCount++; }
         else { bias = "Bearish"; bClr = clrRed; }
      }
      
      IndicatorRelease(hEMA9);
      IndicatorRelease(hEMA21);
      
      CreateDashLabel(pfx+tfNames[i], x, y, tfNames[i] + "  " + bias, bClr, 9); y += 13;
   }
   
   // Overall
   double overallPct = (double)bullCount / 6.0 * 100;
   string overallBias = (overallPct >= 60) ? "BUY" : (overallPct <= 40) ? "SELL" : "NEUTRAL";
   color oClr = (overallPct >= 60) ? clrLime : (overallPct <= 40) ? clrRed : clrYellow;
   CreateDashLabel(pfx+"overall", x, y, IntegerToString((int)overallPct) + "% " + overallBias, oClr, 10);
}

//+------------------------------------------------------------------+
//| CALCULATE AI PROBABILITY                                          |
//+------------------------------------------------------------------+
void CalcProbability(const double &open[], const double &high[], const double &low[],
                     const double &close[], const datetime &time[], int total)
{
   double totalScore = 0;
   int lastBar = total - 1;
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Factor 1: Trend (EMA alignment)
   int hE9 = iMA(Symbol(), PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
   int hE21 = iMA(Symbol(), PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   int hE50 = iMA(Symbol(), PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   double e9[], e21[], e50[];
   
   g_trendFactor = 0;
   if(CopyBuffer(hE9, 0, 0, 1, e9) > 0 && CopyBuffer(hE21, 0, 0, 1, e21) > 0 && CopyBuffer(hE50, 0, 0, 1, e50) > 0)
   {
      if((e9[0] > e21[0] && e21[0] > e50[0]) || (e9[0] < e21[0] && e21[0] < e50[0]))
         g_trendFactor = InpTrendWeight;
      else if(e9[0] > e21[0] || e9[0] < e21[0])
         g_trendFactor = InpTrendWeight * 0.5;
   }
   IndicatorRelease(hE9); IndicatorRelease(hE21); IndicatorRelease(hE50);
   totalScore += g_trendFactor;
   
   // Factor 2: Liquidity (near PDH/PDL or equal levels)
   g_liqFactor = 0;
   int hATR = iATR(Symbol(), PERIOD_M15, 14);
   double atrBuf[];
   double atr = 0;
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
   IndicatorRelease(hATR);
   
   if(atr > 0)
   {
      if(MathAbs(bid - g_pdh) < atr || MathAbs(bid - g_pdl) < atr)
         g_liqFactor = InpLiqWeight;
      else
      {
         for(int i = 0; i < g_liqCount; i++)
         {
            if(!g_liquidity[i].swept && MathAbs(bid - g_liquidity[i].price) < atr * 0.5)
            {
               g_liqFactor = InpLiqWeight * 0.8;
               break;
            }
         }
      }
   }
   totalScore += g_liqFactor;
   
   // Factor 3: Order Block (price at active OB)
   g_obFactor = 0;
   for(int i = 0; i < g_obCount; i++)
   {
      if(g_OBs[i].mitigated) continue;
      if(bid >= g_OBs[i].bottom && bid <= g_OBs[i].top)
      {
         g_obFactor = InpOBWeight;
         break;
      }
      if(MathAbs(bid - g_OBs[i].top) < atr * 0.3 || MathAbs(bid - g_OBs[i].bottom) < atr * 0.3)
      {
         g_obFactor = InpOBWeight * 0.6;
         break;
      }
   }
   totalScore += g_obFactor;
   
   // Factor 4: FVG (price at unfilled FVG)
   g_fvgFactor = 0;
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(g_FVGs[i].filled) continue;
      if(bid >= g_FVGs[i].bottom && bid <= g_FVGs[i].top)
      {
         g_fvgFactor = InpFVGWeight;
         break;
      }
      if(MathAbs(bid - g_FVGs[i].top) < atr * 0.3 || MathAbs(bid - g_FVGs[i].bottom) < atr * 0.3)
      {
         g_fvgFactor = InpFVGWeight * 0.5;
         break;
      }
   }
   totalScore += g_fvgFactor;
   
   // Factor 5: Volume/MACD
   g_volFactor = 0;
   int hMACD = iMACD(Symbol(), PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   double macdM[], macdS[];
   if(CopyBuffer(hMACD, 0, 0, 1, macdM) > 0 && CopyBuffer(hMACD, 1, 0, 1, macdS) > 0)
   {
      if((g_isBullish && macdM[0] > macdS[0]) || (!g_isBullish && macdM[0] < macdS[0]))
         g_volFactor = InpVolumeWeight;
      else
         g_volFactor = InpVolumeWeight * 0.3;
   }
   IndicatorRelease(hMACD);
   totalScore += g_volFactor;
   
   // Factor 6: Session quality
   g_sessFactor = 0;
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   if((hour >= InpLondonStart && hour < InpLondonEnd) || (hour >= InpNYStart && hour < InpNYEnd))
      g_sessFactor = InpSessionWeight;
   else if(hour >= 12 && hour < 16) // Overlap
      g_sessFactor = InpSessionWeight;
   else
      g_sessFactor = InpSessionWeight * 0.3;
   totalScore += g_sessFactor;
   
   // Factor 7: Momentum (RSI)
   g_momFactor = 0;
   int hRSI = iRSI(Symbol(), PERIOD_M15, 14, PRICE_CLOSE);
   double rsiBuf[];
   if(CopyBuffer(hRSI, 0, 0, 1, rsiBuf) > 0)
   {
      if(g_isBullish && rsiBuf[0] > 50 && rsiBuf[0] < 70)
         g_momFactor = InpMomentumWeight;
      else if(!g_isBullish && rsiBuf[0] < 50 && rsiBuf[0] > 30)
         g_momFactor = InpMomentumWeight;
      else
         g_momFactor = InpMomentumWeight * 0.3;
   }
   IndicatorRelease(hRSI);
   totalScore += g_momFactor;
   
   g_currentProb = MathMin(totalScore, 100);
   g_currentBias = g_isBullish ? "BULLISH" : "BEARISH";
   
   // Alert on high probability
   if(g_currentProb >= InpMinProbability && TimeCurrent() - g_lastAlertTime > 300)
   {
      string alertMsg = "SMC Suite: " + Symbol() + " " + g_currentBias + " " + 
                        DoubleToString(g_currentProb, 0) + "% probability";
      
      if(alertMsg != g_lastAlertMsg)
      {
         if(InpAlertDesktop) Alert(alertMsg);
         if(InpAlertMobile) SendNotification(alertMsg);
         if(InpAlertSound) PlaySound("alert.wav");
         g_lastAlertTime = TimeCurrent();
         g_lastAlertMsg = alertMsg;
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW ENTRY SIGNAL                                                 |
//+------------------------------------------------------------------+
void DrawEntrySignal(const double &high[], const double &low[], const double &close[],
                     const datetime &time[], int total)
{
   int lastBar = total - 2;
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Get ATR for SL
   int hATR = iATR(Symbol(), PERIOD_M15, 14);
   double atrBuf[];
   double atr = 0;
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
   IndicatorRelease(hATR);
   
   if(atr <= 0) return;
   
   double sl = atr * 1.5;
   double tp = sl * 2.0;
   double slPips = sl / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10;
   double tpPips = tp / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10;
   double rr = tp / sl;
   
   // Draw signal box
   string signalText = "";
   color signalClr = clrWhite;
   
   if(g_isBullish)
   {
      signalText = "BUY";
      signalClr = clrLime;
   }
   else
   {
      signalText = "SELL";
      signalClr = clrRed;
   }
   
   int x = 180, y = 30;
   string pfx = "SMC_sig_";
   
   CreateDashLabel(pfx+"dir", x, y, signalText, signalClr, 14); y += 18;
   CreateDashLabel(pfx+"prob", x, y, "Probability " + DoubleToString(g_currentProb, 0) + "%", clrWhite, 10); y += 14;
   CreateDashLabel(pfx+"sl", x, y, "SL " + DoubleToString(slPips, 1) + " pips", clrRed, 9); y += 14;
   CreateDashLabel(pfx+"tp", x, y, "TP " + DoubleToString(tpPips, 1) + " pips", clrLime, 9); y += 14;
   CreateDashLabel(pfx+"rr", x, y, "RR 1:" + DoubleToString(rr, 1), clrWhite, 9);
}

//+------------------------------------------------------------------+
//| DRAW MAIN DASHBOARD                                               |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   int x = 10, y = 30;
   string pfx = "SMC_dash_";
   
   // Header
   CreateDashLabel(pfx+"hdr", x, y, "═══ SMC INSTITUTIONAL SUITE PRO ═══", clrGold, 10); y += 18;
   
   // Trend
   string trend = g_isBullish ? "Bullish" : "Bearish";
   color tClr = g_isBullish ? clrLime : clrRed;
   CreateDashLabel(pfx+"trend", x, y, "Trend: " + trend, tClr, 9); y += 14;
   
   // Structure
   string structure = "";
   if(g_lastHH > 0 && g_lastHL > 0) structure = "HH + HL";
   else if(g_lastLH > 0 && g_lastLL > 0) structure = "LH + LL";
   else structure = "Mixed";
   CreateDashLabel(pfx+"struct", x, y, "Structure: " + structure, clrWhite, 9); y += 14;
   
   // Liquidity
   int activeLiq = 0;
   string liqSide = "---";
   for(int i = 0; i < g_liqCount; i++)
   {
      if(!g_liquidity[i].swept)
      {
         activeLiq++;
         if(g_liquidity[i].isBuySide) liqSide = "Buy Side";
         else liqSide = "Sell Side";
      }
   }
   CreateDashLabel(pfx+"liq", x, y, "Liquidity: " + liqSide + " (" + IntegerToString(activeLiq) + ")", clrWhite, 9); y += 14;
   
   // Order Blocks
   int activeOB = 0;
   string obType = "---";
   for(int i = 0; i < g_obCount; i++)
   {
      if(!g_OBs[i].mitigated)
      {
         activeOB++;
         obType = g_OBs[i].isBullish ? "Bullish" : "Bearish";
      }
   }
   CreateDashLabel(pfx+"ob", x, y, "OB: " + obType + " (" + IntegerToString(activeOB) + " active)", clrWhite, 9); y += 14;
   
   // FVG
   int activeFVG = 0;
   string fvgType = "---";
   for(int i = 0; i < g_fvgCount; i++)
   {
      if(!g_FVGs[i].filled)
      {
         activeFVG++;
         fvgType = g_FVGs[i].isBullish ? "Bullish" : "Bearish";
      }
   }
   CreateDashLabel(pfx+"fvg", x, y, "FVG: " + fvgType + " (" + IntegerToString(activeFVG) + " open)", clrWhite, 9); y += 14;
   
   // Session
   string session = GetCurrentSession();
   CreateDashLabel(pfx+"sess", x, y, "Session: " + session, clrWhite, 9); y += 14;
   
   // Probability
   color probClr = g_currentProb >= 80 ? clrLime : (g_currentProb >= 60 ? clrYellow : clrRed);
   CreateDashLabel(pfx+"prob", x, y, "Probability: " + DoubleToString(g_currentProb, 0) + "%", probClr, 10); y += 14;
   
   // Spread
   double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spreadPips = spread / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10;
   CreateDashLabel(pfx+"spread", x, y, "Spread: " + DoubleToString(spreadPips, 1) + " pips", clrWhite, 9); y += 14;
   
   // ATR
   int hATR = iATR(Symbol(), PERIOD_M15, 14);
   double atrBuf[];
   double atr = 0;
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
   IndicatorRelease(hATR);
   double atrPips = atr / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10;
   CreateDashLabel(pfx+"atr", x, y, "ATR: " + DoubleToString(atrPips, 1), clrWhite, 9); y += 14;
   
   // Risk assessment
   string riskLevel = "---";
   color riskClr = clrWhite;
   if(g_currentProb >= 80 && spreadPips < 2.0)
   { riskLevel = "Excellent"; riskClr = clrLime; }
   else if(g_currentProb >= 60)
   { riskLevel = "Good"; riskClr = clrYellow; }
   else
   { riskLevel = "Poor"; riskClr = clrRed; }
   CreateDashLabel(pfx+"risk", x, y, "Risk: " + riskLevel, riskClr, 9); y += 14;
   
   // Probability breakdown
   y += 4;
   CreateDashLabel(pfx+"brk", x, y, "── PROBABILITY BREAKDOWN ──", clrGold, 8); y += 13;
   CreateDashLabel(pfx+"f1", x, y, "Trend:    " + DoubleToString(g_trendFactor, 0) + "/" + DoubleToString(InpTrendWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f2", x, y, "Liquidity:" + DoubleToString(g_liqFactor, 0) + "/" + DoubleToString(InpLiqWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f3", x, y, "OB:       " + DoubleToString(g_obFactor, 0) + "/" + DoubleToString(InpOBWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f4", x, y, "FVG:      " + DoubleToString(g_fvgFactor, 0) + "/" + DoubleToString(InpFVGWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f5", x, y, "Volume:   " + DoubleToString(g_volFactor, 0) + "/" + DoubleToString(InpVolumeWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f6", x, y, "Session:  " + DoubleToString(g_sessFactor, 0) + "/" + DoubleToString(InpSessionWeight, 0), clrWhite, 8); y += 12;
   CreateDashLabel(pfx+"f7", x, y, "Momentum: " + DoubleToString(g_momFactor, 0) + "/" + DoubleToString(InpMomentumWeight, 0), clrWhite, 8);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| GET CURRENT SESSION                                               |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(hour >= InpAsianStart && hour < InpAsianEnd) return "Asian";
   if(hour >= InpLondonStart && hour < 12) return "London";
   if(hour >= 12 && hour < 16) return "London/NY Overlap";
   if(hour >= 16 && hour < InpNYEnd) return "New York";
   return "Off-Hours";
}

//+------------------------------------------------------------------+
//| CREATE DASHBOARD LABEL                                            |
//+------------------------------------------------------------------+
void CreateDashLabel(string name, int x, int y, string text, color clr, int fontSize)
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
