# TD Ameritrade (Schwab) Developer Integration

## Overview
TD Ameritrade was acquired by Charles Schwab in 2020. The API is now transitioning to the **Schwab Developer Platform**. This document covers the current state as of 2024.

## Developer Portal
- **New Portal**: https://developer.schwab.com/
- **Legacy Portal**: https://developer.tdameritrade.com/ (redirects to Schwab)

## App Registration
1. Create a Schwab developer account
2. Register an application to get:
   - `app_key` (Client ID)
   - `app_secret` (Client Secret)
3. Configure redirect URI (must match exactly)

## Authentication (OAuth 2.0)
**Flow**: Authorization Code Grant (server-side)

### Endpoints
- **Auth URL**: `https://api.schwabapi.com/v1/oauth/authorize`
- **Token URL**: `https://api.schwabapi.com/v1/oauth/token`

### Required Scopes
| Scope | Description |
|-------|-------------|
| `readonly` | Account info, positions, orders (read-only) |
| `trade` | Place/modify/cancel orders |
| `market_data` | Real-time and historical market data |

### Token Response
```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 1800,
  "token_type": "Bearer"
}
```

- Access tokens expire in **30 minutes**
- Refresh tokens expire in **7 days** (rolling)

## Rate Limits
| Endpoint Category | Limit |
|-------------------|-------|
| Market Data | 120 requests/second |
| Account/Trading | 60 requests/second |
| OAuth | 10 requests/second |

Headers returned:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

## Key Endpoints

### Market Data
```
GET /marketdata/v1/quotes           # Real-time quotes
GET /marketdata/v1/chains           # Option chains
GET /marketdata/v1/pricehistory     # Historical prices
```

### Trading
```
GET  /trader/v1/accounts            # List accounts
GET  /trader/v1/accounts/{accountId} # Account details
GET  /trader/v1/accounts/{accountId}/orders # Order history
POST /trader/v1/accounts/{accountId}/orders # Place order
DELETE /trader/v1/accounts/{accountId}/orders/{orderId} # Cancel order
```

## Limitations & Considerations

1. **Schwab Migration**: Legacy TD Ameritrade API keys may stop working. Migrate to Schwab Developer Platform.

2. **Option Chains**: Requires `market_data` scope. Returns full chain with Greeks.

3. **Historical Data**: 
   - Daily: 20+ years
   - Intraday: Limited (1m for 30 days, 5m-30m for ~60 days)

4. **Paper Trading**: Available via separate environment (sandbox)

5. **WebSocket**: Streaming available for real-time quotes (separate connection)

## Recommended Implementation Strategy

### Caching
- Cache option chains for 15-60 seconds during market hours
- Cache historical data locally (parquet/CSV)
- Use ETags/If-None-Match for quote endpoints

### Retry Logic
```python
# Exponential backoff for rate limits
max_retries = 3
base_delay = 1  # second
for attempt in range(max_retries):
    response = request()
    if response.status_code == 429:
        wait = base_delay * (2 ** attempt) + random.uniform(0, 1)
        time.sleep(wait)
        continue
    return response
```

### Token Management
- Store refresh token securely (encrypted)
- Proactively refresh access token at 25-minute mark
- Handle token expiration gracefully with automatic refresh

## Resources
- [Schwab API Documentation](https://developer.schwab.com/documentation)
- [Migration Guide](https://developer.schwab.com/migration)
- [Rate Limit Best Practices](https://developer.schwab.com/rate-limits)