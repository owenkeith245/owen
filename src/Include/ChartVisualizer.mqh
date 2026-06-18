//+------------------------------------------------------------------+
//|                                       ChartVisualizer.mqh         |
//|         Live Dashboard + Chart Drawings (Zones, FVG, OB)          |
//+------------------------------------------------------------------+
#ifndef CHART_VISUALIZER_MQH
#define CHART_VISUALIZER_MQH

#include "SignalDetector.mqh"
#include "RiskManager.mqh"
#include "AIAnalysis.mqh"

class CChartVisualizer
{
private:
   string   m_prefix;
   long     m_chartId;
   int      m_dashX, m_dashY;
   color    m_buyColor;
   color    m_sellColor;
   color    m_liqColor;
   color    m_fvgBullColor;
   color    m_fvgBearColor;
   color    m_obBullColor;
   color    m_obBearColor;
   color    m_dashBg;
   color    m_dashText;

public:
   void Init()
   {
      m_prefix = "GoldAI_";
      m_chartId = 0;
      m_dashX = 20;
      m_dashY = 30;
      
      m_buyColor = clrLime;
      m_sellColor = clrRed;
      m_liqColor = clrGold;
      m_fvgBullColor = C'0,100,50';
      m_fvgBearColor = C'100,0,50';
      m_obBullColor = C'0,80,150';
      m_obBearColor = C'150,80,0';
      m_dashBg = C'20,20,30';
      m_dashText = clrWhite;
   }
   
   void DrawDashboard(AISignal &signal, RiskState &risk, TickMetrics &tick,
                      double balance, double equity, double winRate, int openTrades)
   {
      int y = m_dashY;
      int lineH = 18;
      
      // Header
      DrawLabel("header", m_dashX, y, "═══════ GOLD AI SCALPER ═══════", clrGold, 10);
      y += lineH + 5;
      
      // Status
      color statusColor = signal.direction != "NONE" ? clrLime : clrYellow;
      DrawLabel("status", m_dashX, y, "STATUS: ● " + (signal.direction != "NONE" ? "ACTIVE" : "SCANNING"), statusColor, 9);
      y += lineH;
      
      // Separator
      DrawLabel("sep1", m_dashX, y, "────────────────────────────", clrDarkGray, 8);
      y += lineH;
      
      // Market info
      string trendStr = signal.direction == "BUY" ? "TRENDING UP" : 
                        signal.direction == "SELL" ? "TRENDING DOWN" : "RANGING";
      DrawLabel("market", m_dashX, y, "Market:     " + trendStr, m_dashText, 9);
      y += lineH;
      
      DrawLabel("confidence", m_dashX, y, StringFormat("Confidence: %.0f%%", signal.confidence), 
                signal.confidence >= 85 ? clrLime : signal.confidence >= 70 ? clrYellow : clrOrange, 9);
      y += lineH;
      
      string spreadStr = tick.spreadNormal ? "Normal" : "WIDE";
      DrawLabel("spread", m_dashX, y, "Spread:     " + spreadStr + StringFormat(" (%.1f)", tick.currentSpread), 
                tick.spreadNormal ? clrWhite : clrRed, 9);
      y += lineH;
      
      string sessStr = GetSessionString();
      DrawLabel("session", m_dashX, y, "Session:    " + sessStr, clrWhite, 9);
      y += lineH;
      
      // Separator
      DrawLabel("sep2", m_dashX, y, "────────────────────────────", clrDarkGray, 8);
      y += lineH;
      
      // Account
      DrawLabel("balance", m_dashX, y, StringFormat("Balance:    $%.2f", balance), clrWhite, 9);
      y += lineH;
      
      DrawLabel("equity", m_dashX, y, StringFormat("Equity:     $%.2f", equity), clrWhite, 9);
      y += lineH;
      
      double dailyPnL = ((equity - balance) / balance) * 100;
      color pnlColor = dailyPnL >= 0 ? clrLime : clrRed;
      DrawLabel("pnl", m_dashX, y, StringFormat("Today PnL:  %+.2f%%", dailyPnL), pnlColor, 9);
      y += lineH;
      
      DrawLabel("trades", m_dashX, y, StringFormat("Open Trades: %d", openTrades), clrWhite, 9);
      y += lineH;
      
      DrawLabel("winrate", m_dashX, y, StringFormat("Win Rate:   %.0f%%", winRate), 
                winRate >= 70 ? clrLime : winRate >= 50 ? clrYellow : clrRed, 9);
      y += lineH;
      
      double riskUsed = risk.dailyRiskBudget > 0 ? (risk.dailyRiskUsed / risk.dailyRiskBudget * 100) : 0;
      DrawLabel("risk", m_dashX, y, StringFormat("Risk Used:  %.1f%%", riskUsed), 
                riskUsed < 50 ? clrLime : riskUsed < 80 ? clrYellow : clrRed, 9);
      y += lineH;
      
      // Separator
      DrawLabel("sep3", m_dashX, y, "────────────────────────────", clrDarkGray, 8);
      y += lineH;
      
      // Module scores
      DrawLabel("mod_trend", m_dashX, y, StringFormat("Trend:      %.0f%%", signal.modules.trend), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_liq", m_dashX, y, StringFormat("Liquidity:  %.0f%%", signal.modules.liquidity), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_mom", m_dashX, y, StringFormat("Momentum:   %.0f%%", signal.modules.momentum), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_vol", m_dashX, y, StringFormat("Volume:     %.0f%%", signal.modules.volume), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_struct", m_dashX, y, StringFormat("Structure:  %.0f%%", signal.modules.structure), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_volat", m_dashX, y, StringFormat("Volatility: %.0f%%", signal.modules.volatility), clrWhite, 8);
      y += lineH - 2;
      DrawLabel("mod_spr", m_dashX, y, StringFormat("Spread:     %.0f%%", signal.modules.spread), clrWhite, 8);
      y += lineH;
      
      // Footer
      DrawLabel("sep4", m_dashX, y, "═══════════════════════════════", clrGold, 8);
   }
   
   void DrawLiquidityZones(CSignalDetector &detector)
   {
      CleanObjects("liq_");
      
      for(int i = 0; i < detector.GetLiquidityZoneCount(); i++)
      {
         LiquidityZone zone = detector.GetLiquidityZone(i);
         if(zone.swept) continue;
         
         string name = m_prefix + "liq_" + IntegerToString(i);
         datetime timeStart = TimeCurrent() - 3600 * 4;
         datetime timeEnd = TimeCurrent() + 3600;
         
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, timeStart, zone.price - _Point * 5, timeEnd, zone.price + _Point * 5);
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_liqColor);
         ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, name, OBJPROP_FILL, false);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
      }
   }
   
   void DrawFVGZones(CSignalDetector &detector)
   {
      CleanObjects("fvg_");
      
      for(int i = 0; i < detector.GetFVGCount(); i++)
      {
         FairValueGap fvg = detector.GetFVG(i);
         if(fvg.filled) continue;
         
         string name = m_prefix + "fvg_" + IntegerToString(i);
         datetime timeStart = TimeCurrent() - 3600 * 2;
         datetime timeEnd = TimeCurrent() + 1800;
         
         color clr = fvg.isBullish ? m_fvgBullColor : m_fvgBearColor;
         
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, timeStart, fvg.bottom, timeEnd, fvg.top);
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
         ObjectSetString(m_chartId, name, OBJPROP_TEXT, fvg.isBullish ? "Bullish FVG" : "Bearish FVG");
      }
   }
   
   void DrawOrderBlocks(CSignalDetector &detector)
   {
      CleanObjects("ob_");
      
      for(int i = 0; i < detector.GetOrderBlockCount(); i++)
      {
         OrderBlock ob = detector.GetOrderBlock(i);
         if(ob.mitigated) continue;
         
         string name = m_prefix + "ob_" + IntegerToString(i);
         datetime timeStart = TimeCurrent() - 3600 * 3;
         datetime timeEnd = TimeCurrent() + 1800;
         
         color clr = ob.isBullish ? m_obBullColor : m_obBearColor;
         
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, timeStart, ob.bottom, timeEnd, ob.top);
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
         ObjectSetString(m_chartId, name, OBJPROP_TEXT, ob.isBullish ? "Bullish OB" : "Bearish OB");
      }
   }
   
   void DrawEntry(double entry, double sl, double tp, bool isBuy)
   {
      color clr = isBuy ? m_buyColor : m_sellColor;
      string dir = isBuy ? "BUY" : "SELL";
      
      // Entry line
      string entryName = m_prefix + "entry";
      ObjectCreate(m_chartId, entryName, OBJ_HLINE, 0, 0, entry);
      ObjectSetInteger(m_chartId, entryName, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, entryName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chartId, entryName, OBJPROP_WIDTH, 2);
      
      // SL line
      string slName = m_prefix + "sl";
      ObjectCreate(m_chartId, slName, OBJ_HLINE, 0, 0, sl);
      ObjectSetInteger(m_chartId, slName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(m_chartId, slName, OBJPROP_STYLE, STYLE_DASH);
      
      // TP line
      string tpName = m_prefix + "tp";
      ObjectCreate(m_chartId, tpName, OBJ_HLINE, 0, 0, tp);
      ObjectSetInteger(m_chartId, tpName, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(m_chartId, tpName, OBJPROP_STYLE, STYLE_DASH);
      
      // Arrow
      string arrowName = m_prefix + "arrow";
      ObjectCreate(m_chartId, arrowName, OBJ_ARROW, 0, TimeCurrent(), entry);
      ObjectSetInteger(m_chartId, arrowName, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, arrowName, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(m_chartId, arrowName, OBJPROP_WIDTH, 3);
   }
   
   void ClearEntry()
   {
      ObjectDelete(m_chartId, m_prefix + "entry");
      ObjectDelete(m_chartId, m_prefix + "sl");
      ObjectDelete(m_chartId, m_prefix + "tp");
      ObjectDelete(m_chartId, m_prefix + "arrow");
   }
   
   void Cleanup()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
   }

private:
   void DrawLabel(string id, int x, int y, string text, color clr, int fontSize)
   {
      string name = m_prefix + id;
      if(ObjectFind(m_chartId, name) < 0)
      {
         ObjectCreate(m_chartId, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetString(m_chartId, name, OBJPROP_FONT, "Consolas");
      }
      ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, fontSize);
   }
   
   void CleanObjects(string subPrefix)
   {
      string fullPrefix = m_prefix + subPrefix;
      ObjectsDeleteAll(m_chartId, fullPrefix);
   }
   
   string GetSessionString()
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      int hour = dt.hour;
      if(hour >= 9 && hour < 12) return "London";
      if(hour >= 15 && hour < 18) return "New York";
      if(hour >= 2 && hour < 9) return "Asian";
      return "Off-Hours";
   }
};

#endif
