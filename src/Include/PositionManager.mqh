//+------------------------------------------------------------------+
//|                                        PositionManager.mqh        |
//|              Multiple Trade Engine - Independent Positions         |
//+------------------------------------------------------------------+
#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#define MAX_POSITIONS 10

enum ENUM_TRADE_STATE
{
   TRADE_STATE_OPEN,
   TRADE_STATE_BREAKEVEN,
   TRADE_STATE_TRAILING,
   TRADE_STATE_PARTIAL_CLOSED
};

struct ManagedPosition
{
   ulong    ticket;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   double   initialLots;
   double   currentLots;
   double   riskAmount;
   bool     isBuy;
   ENUM_TRADE_STATE state;
   bool     tp1Hit;
   bool     tp2Hit;
   datetime openTime;
   double   maxProfit;       // track highest profit
   double   trailingSL;
};

struct TradeSetup
{
   bool     isBuy;
   double   entryPrice;
   double   stopLoss;
   double   lotSize;
   double   riskAmount;
   double   confidence;
   double   atr;
   double   rrRatio1;       // TP1 R:R
   double   rrRatio2;       // TP2 R:R
   double   rrRatio3;       // TP3 R:R
};

class CPositionManager
{
private:
   CTrade         m_trade;
   CPositionInfo  m_posInfo;
   ManagedPosition m_positions[];
   int            m_posCount;
   string         m_symbol;
   int            m_magicNumber;
   
   // Trade management params
   double   m_trailStartR;     // start trailing after X R profit
   double   m_breakEvenR;      // move to BE after X R
   double   m_partialClose1;   // % to close at TP1
   double   m_partialClose2;   // % to close at TP2
   double   m_trailATRMult;    // trailing distance = ATR * this

public:
   void Init(string symbol, int magic)
   {
      m_symbol = symbol;
      m_magicNumber = magic;
      m_posCount = 0;
      ArrayResize(m_positions, MAX_POSITIONS);
      
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFillingBySymbol(symbol);
      
      // Default management params
      m_trailStartR = 2.0;
      m_breakEvenR = 1.0;
      m_partialClose1 = 0.40;  // close 40% at TP1
      m_partialClose2 = 0.30;  // close 30% at TP2, 30% trails
      m_trailATRMult = 0.5;
   }
   
   void SetManagementParams(double breakEvenR, double trailStartR, double partialClose1, double partialClose2, double trailATRMult)
   {
      m_breakEvenR = breakEvenR;
      m_trailStartR = trailStartR;
      m_partialClose1 = partialClose1;
      m_partialClose2 = partialClose2;
      m_trailATRMult = trailATRMult;
   }
   
   bool OpenTrade(TradeSetup &setup)
   {
      if(m_posCount >= MAX_POSITIONS) return false;
      
      double risk = MathAbs(setup.entryPrice - setup.stopLoss);
      double tp1 = setup.isBuy ? setup.entryPrice + risk * setup.rrRatio1
                                : setup.entryPrice - risk * setup.rrRatio1;
      double tp2 = setup.isBuy ? setup.entryPrice + risk * setup.rrRatio2
                                : setup.entryPrice - risk * setup.rrRatio2;
      double tp3 = setup.isBuy ? setup.entryPrice + risk * setup.rrRatio3
                                : setup.entryPrice - risk * setup.rrRatio3;
      
      ENUM_ORDER_TYPE type = setup.isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      string comment = StringFormat("GoldAI|%.0f|%.2f", setup.confidence, setup.riskAmount);
      
      bool result = m_trade.PositionOpen(m_symbol, type, setup.lotSize, 
                                          setup.entryPrice, setup.stopLoss, tp1, comment);
      
      if(result)
      {
         ManagedPosition pos;
         ZeroMemory(pos);
         pos.ticket = m_trade.ResultOrder();
         pos.entryPrice = setup.entryPrice;
         pos.stopLoss = setup.stopLoss;
         pos.takeProfit1 = tp1;
         pos.takeProfit2 = tp2;
         pos.takeProfit3 = tp3;
         pos.initialLots = setup.lotSize;
         pos.currentLots = setup.lotSize;
         pos.riskAmount = setup.riskAmount;
         pos.isBuy = setup.isBuy;
         pos.state = TRADE_STATE_OPEN;
         pos.tp1Hit = false;
         pos.tp2Hit = false;
         pos.openTime = TimeCurrent();
         pos.maxProfit = 0;
         pos.trailingSL = setup.stopLoss;
         
         m_positions[m_posCount] = pos;
         m_posCount++;
         return true;
      }
      return false;
   }
   
   void ManageAll(double currentBid, double currentAsk, double atr)
   {
      for(int i = m_posCount - 1; i >= 0; i--)
      {
         if(!IsPositionStillOpen(m_positions[i].ticket))
         {
            RemovePosition(i);
            continue;
         }
         ManagePosition(m_positions[i], currentBid, currentAsk, atr);
      }
   }
   
   int GetOpenCount() { return m_posCount; }
   
   double GetTotalExposure(bool isBuy)
   {
      double total = 0;
      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].isBuy == isBuy)
            total += m_positions[i].currentLots;
      }
      return total;
   }
   
   void CloseAll()
   {
      for(int i = m_posCount - 1; i >= 0; i--)
      {
         m_trade.PositionClose(m_positions[i].ticket);
      }
      m_posCount = 0;
   }

private:
   void ManagePosition(ManagedPosition &pos, double bid, double ask, double atr)
   {
      double currentPrice = pos.isBuy ? bid : ask;
      double risk = MathAbs(pos.entryPrice - pos.stopLoss);
      if(risk <= 0) return;
      
      double profitPoints = pos.isBuy ? (currentPrice - pos.entryPrice) : (pos.entryPrice - currentPrice);
      double profitR = profitPoints / risk;
      
      // Track max profit
      if(profitPoints > pos.maxProfit)
         pos.maxProfit = profitPoints;
      
      // --- Stage 1: Move to Breakeven ---
      if(pos.state == TRADE_STATE_OPEN && profitR >= m_breakEvenR)
      {
         double newSL = pos.entryPrice + (pos.isBuy ? _Point : -_Point);
         if(ModifyStopLoss(pos.ticket, newSL))
         {
            pos.stopLoss = newSL;
            pos.trailingSL = newSL;
            pos.state = TRADE_STATE_BREAKEVEN;
         }
      }
      
      // --- Stage 2: Partial Close at TP1 ---
      if(!pos.tp1Hit)
      {
         bool tp1Reached = pos.isBuy ? (currentPrice >= pos.takeProfit1) : (currentPrice <= pos.takeProfit1);
         if(tp1Reached)
         {
            double closeVolume = NormalizeLot(pos.initialLots * m_partialClose1);
            if(closeVolume >= SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN))
            {
               m_trade.PositionClosePartial(pos.ticket, closeVolume);
               pos.currentLots -= closeVolume;
               pos.tp1Hit = true;
               pos.state = TRADE_STATE_PARTIAL_CLOSED;
            }
         }
      }
      
      // --- Stage 3: Partial Close at TP2 ---
      if(pos.tp1Hit && !pos.tp2Hit)
      {
         bool tp2Reached = pos.isBuy ? (currentPrice >= pos.takeProfit2) : (currentPrice <= pos.takeProfit2);
         if(tp2Reached)
         {
            double closeVolume = NormalizeLot(pos.initialLots * m_partialClose2);
            if(closeVolume >= SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN))
            {
               m_trade.PositionClosePartial(pos.ticket, closeVolume);
               pos.currentLots -= closeVolume;
               pos.tp2Hit = true;
            }
         }
      }
      
      // --- Stage 4: Trailing Stop ---
      if(profitR >= m_trailStartR)
      {
         double trailDist = atr * m_trailATRMult;
         double newSL;
         
         if(pos.isBuy)
         {
            newSL = currentPrice - trailDist;
            if(newSL > pos.trailingSL)
            {
               if(ModifyStopLoss(pos.ticket, newSL))
               {
                  pos.trailingSL = newSL;
                  pos.stopLoss = newSL;
                  pos.state = TRADE_STATE_TRAILING;
               }
            }
         }
         else
         {
            newSL = currentPrice + trailDist;
            if(newSL < pos.trailingSL)
            {
               if(ModifyStopLoss(pos.ticket, newSL))
               {
                  pos.trailingSL = newSL;
                  pos.stopLoss = newSL;
                  pos.state = TRADE_STATE_TRAILING;
               }
            }
         }
      }
   }
   
   bool ModifyStopLoss(ulong ticket, double newSL)
   {
      if(m_posInfo.SelectByTicket(ticket))
      {
         return m_trade.PositionModify(ticket, newSL, m_posInfo.TakeProfit());
      }
      return false;
   }
   
   bool IsPositionStillOpen(ulong ticket)
   {
      return m_posInfo.SelectByTicket(ticket);
   }
   
   void RemovePosition(int index)
   {
      for(int i = index; i < m_posCount - 1; i++)
         m_positions[i] = m_positions[i + 1];
      m_posCount--;
   }
   
   double NormalizeLot(double lot)
   {
      double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      lot = MathFloor(lot / step) * step;
      if(lot < minLot) return minLot;
      return lot;
   }
};

#endif
