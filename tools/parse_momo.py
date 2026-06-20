"""
Parse the official MTN MoMo statement (PDF -> text) for 250798579079 and build
the monthly / weekly aggregates in the exact schema the app stores in Firestore
(MonthlyTransactionSummary / WeeklyTransactionSummary).

Source of truth: the MoMo statement (authoritative), replacing the previous
SMS-derived summaries.

Run:  python tools/parse_momo.py
Reads:  momo_table.txt  (pdftotext -table output)
Writes: tools/momo_transactions.json, tools/momo_summaries.json
"""
import json
import re
from collections import defaultdict
from datetime import date, timedelta

USER = "250798579079"
SRC = "momo_table.txt"

# All real values that appear in the TransactionType column. Compound names are
# listed before their shorter prefixes so the regex never matches a substring.
# (SAVINGS / LOANS are NOT types here - they are username fragments such as
#  CBA-SAVINGS and YABX-LOANS.)
TYPES = [
    "ROLLBACK_INITIATED_DEBT_REPAYMENT",
    "CUSTOM_LOAN_PAYOUT",
    "EXTERNAL_PAYMENT",
    "EXTERNAL_TRANSFER",
    "CASH_IN",
    "CASH_OUT",
    "TRANSFER",
    "PAYMENT",
    "DEPOSIT",
    "WITHDRAWAL",
    "REFUND",
    "DEBIT",
    "LAST_TRANSACTIONS",  # zero-amount ledger/inquiry marker; no money moved
]
# Types that move money INTO the account holder's wallet (used to resolve
# direction when one party column is blank).
INCOMING_TYPES = {
    "DEPOSIT", "CASH_IN", "REFUND", "CUSTOM_LOAN_PAYOUT", "EXTERNAL_TRANSFER",
}
STATUSES = ["COMMITTED", "FAILED", "PENDING", "REJECTED", "REVERSED"]

# Collapse all whitespace so page-boundary line wraps can't split a record.
with open(SRC, "r", encoding="utf-8", errors="replace") as fh:
    raw = fh.read()
text = re.sub(r"\s+", " ", raw)

type_re = re.compile(r"\b(" + "|".join(TYPES) + r")\b")
status_re = re.compile(r"\b(" + "|".join(STATUSES) + r")\b")
msisdn_re = re.compile(r"\b25\d{10}\b")
dt_re = re.compile(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}")

# Split into one chunk per transaction: from each datetime up to the next.
# This makes it impossible for one record to swallow the next one's fields.
dts = list(dt_re.finditer(text))
records = []
unparsed_amount = 0
no_type = 0
ambiguous = []

for i, dm in enumerate(dts):
    start = dm.start()
    end = dts[i + 1].start() if i + 1 < len(dts) else len(text)
    chunk = text[start:end]

    d, t = dm.group().split(" ")

    tm = type_re.search(chunk)
    if not tm:
        no_type += 1
        continue
    ttype = tm.group(1)

    mid = chunk[dm.end() - dm.start():tm.start()]

    sm = status_re.search(chunk, tm.end())
    status = sm.group(1) if sm else "COMMITTED"
    tail = chunk[tm.end():sm.start()] if sm else chunk[tm.end():]
    # strip any trailing next-record txnId that may sit after status (none here,
    # but tail is only up to status so it's clean either way)

    msisdns = msisdn_re.findall(mid)
    nums = re.findall(r"\d+", tail)
    amount = int(nums[0]) if nums else None
    from_fee = int(nums[1]) if len(nums) > 1 else 0
    to_fee = int(nums[2]) if len(nums) > 2 else 0
    if amount is None:
        unparsed_amount += 1
        continue

    # Determine From / To MSISDN positionally, then direction relative to the
    # account holder. Columns are [FromMSISDN] [ToMSISDN]; either can be blank.
    from_ms = to_ms = None
    incoming = ttype in INCOMING_TYPES
    if len(msisdns) >= 2:
        from_ms, to_ms = msisdns[0], msisdns[1]
        if to_ms == USER and from_ms != USER:
            direction = "RECEIVED"
        elif from_ms == USER:
            direction = "SENT"
        else:
            direction = "RECEIVED" if to_ms == USER else "SENT"
            ambiguous.append((d, t, ttype, mid, amount))
    elif len(msisdns) == 1:
        only = msisdns[0]
        if only == USER:
            # Lone column is the user; type decides which side it sits on.
            if incoming:
                to_ms, direction = only, "RECEIVED"
            else:
                from_ms, direction = only, "SENT"
        else:
            # User column blank, counterparty present.
            if incoming:
                from_ms, direction = only, "RECEIVED"
            else:
                to_ms, direction = only, "SENT"
    else:
        direction = "RECEIVED" if incoming else "SENT"

    records.append({
        "date": d,
        "time": t,
        "type": ttype,
        "from": from_ms,
        "to": to_ms,
        "amount": amount,
        "fromFee": from_fee,
        "toFee": to_fee,
        "direction": direction,
        "status": status,
    })

# ---- Monthly aggregates (app schema: month = UTC first-of-month ISO8601) ----
monthly = defaultdict(lambda: {"received": 0.0, "sent": 0.0, "count": 0})
for r in records:
    y, mo, _ = r["date"].split("-")
    key = (int(y), int(mo))
    monthly[key]["count"] += 1
    if r["direction"] == "RECEIVED":
        monthly[key]["received"] += r["amount"]
    else:
        monthly[key]["sent"] += r["amount"]

monthly_summaries = []
for (y, mo) in sorted(monthly):
    v = monthly[(y, mo)]
    monthly_summaries.append({
        "month": f"{y:04d}-{mo:02d}-01T00:00:00.000Z",
        "totalReceived": v["received"],
        "totalSent": v["sent"],
        "transactionCount": v["count"],
    })

# ---- Weekly aggregates (app schema: weekStart = Monday, local ISO8601) ------
def monday(dstr):
    y, mo, dd = map(int, dstr.split("-"))
    d0 = date(y, mo, dd)
    return d0 - timedelta(days=d0.weekday())  # Monday

weekly = defaultdict(lambda: {"received": 0.0, "sent": 0.0, "count": 0})
for r in records:
    wk = monday(r["date"])
    weekly[wk]["count"] += 1
    if r["direction"] == "RECEIVED":
        weekly[wk]["received"] += r["amount"]
    else:
        weekly[wk]["sent"] += r["amount"]

weekly_summaries = []
for wk in sorted(weekly):
    v = weekly[wk]
    weekly_summaries.append({
        "weekStart": f"{wk.isoformat()}T00:00:00.000",
        "totalReceived": v["received"],
        "totalSent": v["sent"],
        "transactionCount": v["count"],
    })

# ---- Persist ----------------------------------------------------------------
with open("tools/momo_transactions.json", "w", encoding="utf-8") as fh:
    json.dump(records, fh, indent=2)
# Coverage boundary: the latest transaction datetime in the statement. The app
# keeps statement data for everything up to this instant and only lets SMS add
# transactions that occur strictly after it (no overwrite, no double-counting).
through = max(f"{r['date']}T{r['time']}" for r in records)

with open("tools/momo_summaries.json", "w", encoding="utf-8") as fh:
    json.dump({
        "phone": "+250798579079",
        "source": "MTN MoMo statement 250798579079.pdf",
        "momoStatementThrough": through,
        "dashboardSummaries": monthly_summaries,
        "publicSummaries": monthly_summaries,
        "publicWeeklySummaries": weekly_summaries,
    }, fh, indent=2)

# ---- Report -----------------------------------------------------------------
total = len(records)
recv = sum(1 for r in records if r["direction"] == "RECEIVED")
sent = total - recv
tot_recv = sum(r["amount"] for r in records if r["direction"] == "RECEIVED")
tot_sent = sum(r["amount"] for r in records if r["direction"] == "SENT")

print(f"Parsed records      : {total}")
print(f"  dropped (no amount): {unparsed_amount}")
print(f"  dropped (no type)  : {no_type}")
print(f"  RECEIVED / SENT    : {recv} / {sent}")
print(f"  total received     : {tot_recv:,} RWF")
print(f"  total sent         : {tot_sent:,} RWF")
print(f"  ambiguous-direction: {len(ambiguous)}")
print(f"  months             : {len(monthly_summaries)}  weeks: {len(weekly_summaries)}")
print()
print("Per-month (count | received | sent):")
for s in monthly_summaries:
    print(f"  {s['month'][:7]}  {s['transactionCount']:4d}  "
          f"{int(s['totalReceived']):>13,}  {int(s['totalSent']):>13,}")
if ambiguous:
    print("\nAmbiguous sample (first 10):")
    for a in ambiguous[:10]:
        print("  ", a)
