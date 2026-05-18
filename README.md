# M-Money Dashboard

A Flutter app that reads your M-Money SMS messages and turns them into a visual transaction dashboard.

## License

This project is open source under the [MIT License](LICENSE).

## How It Works

### 1. SMS Permission

On first launch the app asks for **SMS permission** (`READ_SMS`). Without it the app cannot read any messages. Grant the permission when prompted.

### 2. Reading M-Money Messages

Once granted, the app queries your phone's SMS inbox filtering **only** messages from the sender address **`M-Money`**. No other messages are read or stored.

### 3. Parsing Transactions

Each M-Money SMS is matched against known message templates using regex:

| Template | Type | Example snippet |
|----------|------|-----------------|
| `You have received X RWF from NAME ...` | RECEIVED | Incoming transfer |
| `*165*S*X RWF transferred to NAME ...` | SENT | Outgoing transfer |
| `Your payment of X RWF to NAME ...` | SENT | Payment |

From every matched message the app extracts:

- **Amount** (RWF)
- **Counterparty** (sender/recipient name)
- **Date & time** (from the message body)
- **Fee** and **Balance** (if present)
- **Transaction ID** (FT Id / TxId, if present)

Messages that don't match any template are silently skipped.

### 4. Dashboard

Parsed transactions are grouped by month and displayed with charts and summary metrics (total received, total sent, net amount, transaction count).

## Quick Start

```bash
flutter pub get
flutter run
```

Grant SMS permission when the app launches, and the dashboard will populate automatically from your M-Money messages.
