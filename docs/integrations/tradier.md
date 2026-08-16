# Tradier API Evaluation

## Overview
Tradier provides a developer-friendly API for market data and brokerage integration. Founded in 2012, they offer both brokerage and API-only access.

## Developer Portal
- **Portal**: https://developer.tradier.com/
- **Documentation**: https://documentation.tradier.com/

## Account Types
1. **Brokerage Account**: Full trading + API access ($0 commission)
2. **API Only**: Market data + paper trading (free tier available)

## Authentication
- **Method**: Bearer token (simple, no OAuth flow)
- **Header**: `Authorization: Bearer {access_token}`
- **Token Expiry**: 24 hours (refreshable)
- **Sandbox**: Separate tokens for paper trading

## Rate Limits
| Tier | Requests/Second | Requests/Minute |
|------|-----------------|-----------------|
| Free (Sandbox) | 1 | 60 |
| Live Brokerage | 10 | 600 |
| Enterprise | Custom | Custom |

## Key Endpoints

### Market Data
```
GET /v1/markets/quotes          # Real-time quotes
GET /v1/markets/options/chains  # Option chains
GET /v1/markets/timesales       # Time & sales
GET /v1/markets/history         # Historical prices (daily)
```

### Options
- Full option chains with Greeks
- Expirations up to 2+ years
- IV, Delta, Gamma, Theta, Vega, Rho

### Trading (Brokerage Account Required)
```
GET  /v1/accounts/{account_id}/balances
GET  /v1/accounts/{account_id}/positions
GET  /v1/accounts/{account_id}/orders
POST /v1/accounts/{account_id}/orders
DELETE /v1/accounts/{account_id}/orders/{order_id}
```

### Streaming
- WebSocket for real-time quotes
- Server-Sent Events (SSE) option

## Pricing
| Plan | Monthly | Features |
|------|---------|----------|
| Free (Sandbox) | $0 | Paper trading, delayed data |
| Live API | $0* | Requires funded brokerage account |
| Market Data Only | $10-50 | Real-time data without brokerage |

*Free with $2,500+ funded Tradier brokerage account

## Comparison: Tradier vs TD Ameritrade (Schwab) vs Paid Vendors

| Feature | Tradier | TD Ameritrade/Schwab | Polygon.io | Tiingo |
|---------|---------|---------------------|------------|--------|
| **Auth Complexity** | Simple Bearer | OAuth 2.0 | API Key | API Key |
| **Option Chains** | ✅ Full Greeks | ✅ Full Greeks | ✅ | ✅ |
| **Historical Options** | ❌ Limited | ❌ Limited | ✅ Extensive | ✅ Good |
| **Intraday Equity** | ✅ 1m-1d | ✅ Limited | ✅ Extensive | ✅ Good |
| **Rate Limits** | 10/sec (live) | 120/sec (market) | 100-5000/sec | 100-1000/sec |
| **Brokerage Integration** | ✅ Native | ✅ Native | ❌ | ❌ |
| **Paper Trading** | ✅ Free | ✅ Free | ❌ | ✅ |
| **Cost (MVP)** | Free* | Free* | $199+/mo | $10-200/mo |
| **Cost (Production)** | Free* | Free* | $199+/mo | $10-200/mo |

*Requires funded brokerage account

## Strengths
1. **Simple Authentication**: No complex OAuth flow
2. **Free Tier**: Paper trading + live data with funded account
3. **Good Documentation**: Clear examples, SDKs available
4. **Native Brokerage**: Seamless order execution
5. **Option Data Quality**: Reliable Greeks, wide expiration range

## Weaknesses
1. **Limited Historical Options**: No deep historical option prices
2. **Rate Limits**: Lower than Schwab for market data
3. **No Crypto/Forex**: Equities and options only
4. **Smaller Ecosystem**: Fewer community libraries
5. **Account Requirement**: Need funded account for live data

## Recommendation

### For MVP (Yahoo Finance + Paper Trading)
**Use Yahoo Finance (yfinance)** for:
- Free, no account required
- Good daily historical data
- Reasonable intraday for recent periods
- Sufficient for backtesting framework development

### For Production Options Trading
**Use Tradier** if:
- Building a retail-focused trading bot
- Need simple integration with brokerage execution
- Account size >$2,500 (for free API access)
- Option chain data is primary need

**Use TD Ameritrade/Schwab** if:
- Already have Schwab/TD account
- Need higher rate limits for market data
- Require more robust institutional-grade API
- Need access to wider product range (futures, forex later)

**Use Polygon.io/Tiingo** if:
- Need extensive historical option prices
- Building quantitative research platform
- Budget allows for paid data
- Need crypto/forex coverage

## Implementation Priority
1. **Phase 1 (MVP)**: yfinance for equity data + backtester (current)
2. **Phase 2**: Tradier paper trading for options signal validation
3. **Phase 3**: Schwab/TD for production brokerage integration
4. **Phase 4**: Paid vendor (Polygon) if deep historical options needed

## Resources
- [Tradier API Docs](https://documentation.tradier.com/)
- [Tradier Python SDK](https://github.com/tradier/tradier-python)
- [Schwab API Docs](https://developer.schwab.com/documentation)