# MQL5 Expert Advisors Collection

This repository contains fully functional MQL5 Expert Advisor (EA) clones and templates, reverse-engineered and optimized from premium commercial bots. These EAs are designed with professional risk management features suitable for Prop Firm challenges and live trading.

## 🤖 EAs Included

### 1. `Sustainable_Daily_Scalper.mq5`
- **Strategy:** Session-based Mean Reversion
- **Timeframe:** M15 or H1
- **Key Features:** Trade only during Asian/Quiet sessions, Anti-Grid/Martingale, Break-Even System, and Daily Drawdown Limiter. Designed for steady daily cash flow.

### 2. `ScalpingRobotPro_Clone.mq5`
- **Strategy:** M1 Momentum Scalping with Recovery Grid
- **Target Asset:** XAUUSD (Gold)
- **Key Features:** Selective Grid (only opens recovery trades on secondary signals), News Filter (ATR Spike Detection), and Daily Target limits.

### 3. `QuantumOmniGold_Clone.mq5`
- **Strategy:** Trend Following + Pullback (MA & Stochastic)
- **Target Asset:** XAUUSD (Gold)
- **Key Features:** **Prop Firm Ready**. Strictly NO Grid, NO Martingale. Uses Dual Take Profit (Partial Close), Break-Even shielding, and Adaptive Trailing Stop.

### 4. `Ultimate_PropFirm_EA.mq5`
- **Strategy:** Asian Session Range Breakout + Trend Following
- **Target Asset:** XAUUSD, BTCUSD, US30
- **Key Features:** **The Ultimate Synergy**. Combines features from all major commercial bots. Features Daily Drawdown Limit, Friday Close, ATR News Filter, and Trade Randomization (to avoid Prop Firm behavioral copying bans).

## 🧩 Modular Components (For Custom EA Building)

To facilitate future development, the core mechanics have been extracted into independent, plug-and-play modules:

- **`Mod_RiskProtector.mq5`:** A standalone utility module handling Risk Management. Includes Daily Drawdown limiters, Friday auto-close, and automated Break-Even logic. Can be run alongside manual trading to protect equity.
- **`Mod_NewsFilter.mq5`:** A volatility-based news filter. Instead of relying on unreliable web-scraped calendars, it uses ATR Spike detection to pause trading during macroeconomic shocks.
- **`Mod_GridRecovery.mq5`:** An advanced "Selective Grid" module. Unlike dangerous traditional grids, it only opens averaging positions if both the Pip distance and an RSI confirmation condition are met, then calculates the break-even average price for a group exit.

## 🛡️ Core Architecture

All EAs in this repository share a professional-grade execution loop:
1. **Risk-based Position Sizing:** Automatically calculates lot sizes based on a strict % risk per trade.
2. **Daily Drawdown Limiters:** Hard-coded cutoffs to halt trading if equity drops below a specified daily percentage (e.g., -4%), protecting Prop Firm accounts from violation.
3. **On-Chart Dashboard:** Real-time feedback printed directly to the MT5 chart showing daily P/L and system status.

## 🚀 How to Use

1. Copy the `.mq5` files into your MetaTrader 5 terminal under the `MQL5/Experts/` folder.
2. Open **MetaEditor** (Press F4 in MT5) and compile the file (F7).
3. Attach the compiled EA to the corresponding chart and adjust the input parameters to match your risk profile.

*Disclaimer: These are open-source educational templates. Always test extensively on a Demo account before risking real capital.*