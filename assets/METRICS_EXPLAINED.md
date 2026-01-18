# 📊 Statistical Metrics & Calculations

## Overview

Your Money Tracker app now includes advanced statistical calculations and metrics to provide deep insights into your financial patterns. This document explains each metric and how it's calculated.

---

## 🎯 Key Metrics

### 1. Average Monthly Growth Rate
**What it shows:** The average percentage change in income month-over-month.

**Calculation:**
```
For each consecutive month pair:
  Growth Rate = ((Current Month - Previous Month) / Previous Month) × 100

Average Growth Rate = Sum of all growth rates / Number of months
```

**Interpretation:**
- **Positive (>0%)**: Income is growing
- **0%**: Income is stable
- **Negative (<0%)**: Income is declining

**Good Range:**
- 🟢 **>15%**: Excellent rapid growth
- 🟡 **5-15%**: Good steady growth  
- 🟠 **0-5%**: Stable, room for improvement
- 🔴 **<0%**: Declining, needs attention

---

### 2. Consistency Score
**What it shows:** How predictable and stable your income is (0-100 scale).

**Calculation:**
```
1. Calculate mean (average) of all monthly amounts
2. Calculate standard deviation (how spread out the data is)
3. Calculate coefficient of variation (CV):
   CV = (Standard Deviation / Mean)
4. Consistency Score = 100 - (CV × 100)
5. Clamped between 0 and 100
```

**Interpretation:**
- **100%**: Perfectly consistent income every month
- **70-100%**: 🟢 Very consistent and predictable
- **40-70%**: 🟡 Moderately consistent
- **0-40%**: 🔴 Highly variable income

**Why it matters:**
- High consistency = easier to budget and plan
- Low consistency = need to maintain higher emergency fund

---

### 3. Volatility Index
**What it shows:** How much your income fluctuates from month to month (as a percentage).

**Calculation:**
```
1. Calculate absolute change between each consecutive month
2. Sum all changes
3. Calculate average change
4. Volatility = (Average Change / Average Income) × 100
```

**Interpretation:**
- **0-20%**: 🟢 Low volatility (stable income)
- **20-40%**: 🟡 Moderate volatility
- **>40%**: 🔴 High volatility (unpredictable)

**Example:**
If average income is 1,000,000 RWF and typical month-to-month change is 200,000 RWF:
```
Volatility = (200,000 / 1,000,000) × 100 = 20%
```

---

### 4. Active Days Streak
**What it shows:** Number of consecutive days with transaction activity.

**Calculation:**
```
1. Sort transactions by date (newest first)
2. Check if most recent transaction is within 7 days
3. Count consecutive days where transactions occurred
4. Days within 7-day gaps count as continuous streak
```

**Interpretation:**
- **>30 days**: 🔥 Excellent engagement
- **15-30 days**: 🟡 Good activity
- **<15 days**: 🟠 Consider more frequent tracking

**Note:** A 7-day gap is allowed to account for natural business cycles.

---

### 5. Month-over-Month (MoM) Change
**What it shows:** Percentage change between current month and last month.

**Calculation:**
```
MoM Change = ((Current Month - Last Month) / Last Month) × 100
```

**Interpretation:**
- **Positive**: 🟢 Income increased
- **Negative**: 🔴 Income decreased
- **Near 0%**: Stable

**Example:**
- Last month: 800,000 RWF
- This month: 1,000,000 RWF
- MoM = ((1,000,000 - 800,000) / 800,000) × 100 = **+25%**

---

## 📈 Additional Calculations

### Total Received
Sum of all incoming transaction amounts.
```
Total = Σ(all received transactions)
```

### Average Transaction
Mean amount per transaction.
```
Average = Total Received / Number of Transactions
```

### Highest Transaction
Largest single incoming transaction amount.

### Total Fees
Sum of all transaction fees paid.

---

## 🎯 Next Month Target

### How It's Calculated
```
1. Take last 3 months (or all if less than 3)
2. Calculate growth rate for each consecutive pair
3. Average the growth rates
4. Ensure minimum 5% growth
5. Apply to last month's amount:
   Target = Last Month × (1 + Growth Rate)
```

**Example:**
```
Months: 500K → 700K → 800K
Growth rates: +40%, +14%
Average: 27%
Target = 800K × 1.27 = 1,016,000 RWF
```

---

## 📊 Matrix Grid

The Statistics Matrix displays these key indicators in a compact grid:

### Row 1: Growth Indicator
- Visual bar showing average monthly growth
- Color-coded: green (positive) or red (negative)

### Row 2: Stability Metrics
- **Consistency**: Income predictability score
- **Volatility**: Income fluctuation measure

### Row 3: Activity & Performance
- **Active Days**: Engagement streak
- **MoM Change**: Recent performance trend

---

## 💡 Smart Insights

The app automatically generates personalized insights based on your metrics:

### Growth-Based Insights
- **>15% growth**: "Excellent! Rapidly growing income"
- **5-15% growth**: "Good progress! Steady growth"
- **0-5% growth**: "Stable income, consider growth strategies"
- **<0% growth**: "Income declining, focus on opportunities"

---

## 🎨 Visual Indicators

### Color Coding System
- 🟢 **Green**: Excellent/Positive performance
- 🟡 **Yellow/Orange**: Moderate/Average performance
- 🔴 **Red**: Needs attention/Negative

### Progress Bars
- Show relative performance against optimal ranges
- Longer bar = stronger signal (good or bad depending on metric)

### Icons
- 📈 Trending up: Growth
- 📉 Trending down: Decline
- ⏱️ Timelapse: Consistency
- 📊 Chart: Volatility
- 🔥 Fire: Active streak
- ⬆️/⬇️ Arrows: Direction of change

---

## 📝 Formulas Reference

### Standard Deviation
```
σ = √[Σ(x - μ)² / N]
where:
  σ = standard deviation
  x = each value
  μ = mean
  N = number of values
```

### Coefficient of Variation
```
CV = (σ / μ) × 100
where:
  σ = standard deviation
  μ = mean
```

### Growth Rate
```
Growth % = ((New Value - Old Value) / Old Value) × 100
```

---

## 🎯 How to Use These Metrics

### For Budgeting
- Use **Consistency Score** to determine budget reliability
- High consistency (>70%) = can plan tighter budgets
- Low consistency (<40%) = need larger buffers

### For Goal Setting
- Use **Monthly Growth Rate** to set realistic income targets
- Use **Next Month Target** as your benchmark goal

### For Risk Assessment
- Use **Volatility Index** to assess income stability
- High volatility (>40%) = higher risk, need emergency fund

### For Engagement
- Use **Active Days Streak** to maintain tracking habits
- Try to build longer streaks for better data accuracy

### For Performance Tracking
- Use **MoM Change** to see immediate results of changes
- Compare current performance to historical trends

---

## 🔍 Data Requirements

### Minimum Data Needed
- **Basic metrics**: 2+ months of data
- **Consistency/Volatility**: 3+ months recommended
- **Growth trends**: 3+ months minimum
- **Active streak**: Real-time calculation

### Data Quality Tips
1. Ensure all transactions are captured
2. Regular data entry improves accuracy
3. More months = better trend analysis
4. Remove outliers if one-time events

---

## 📊 Example Scenario

### Sample Data
```
Jan: 500,000 RWF (10 transactions)
Feb: 700,000 RWF (12 transactions)
Mar: 800,000 RWF (15 transactions)
Apr: 750,000 RWF (11 transactions)
May: 900,000 RWF (18 transactions)
```

### Calculated Metrics
- **Average Monthly Growth**: +15.7%
- **Consistency Score**: 73% (Good)
- **Volatility Index**: 18% (Low)
- **Next Month Target**: 1,035,000 RWF
- **MoM Change**: +20% (Apr to May)

### Interpretation
✅ Strong growth trend  
✅ Fairly consistent income  
✅ Low risk/volatility  
🎯 Aim for 1M+ next month

---

## 🚀 Pro Tips

1. **Track regularly** - Daily or weekly entries provide better data
2. **Review monthly** - Check metrics at month-end for insights
3. **Set goals** - Use Next Month Target as motivation
4. **Watch trends** - Focus on 3-month moving averages
5. **Celebrate milestones** - Acknowledge when metrics improve

---

## 📱 Where to Find These Metrics

In the app, the **Statistics & Insights** card appears:
- Below the "All Monthly Receipts" section
- Above the "Top Senders" section
- Shows all key metrics in a compact grid
- Includes personalized insight at the bottom

---

**Last Updated:** December 2024  
**App Version:** 1.0.0  
**Metrics Engine:** v1.0