import 'package:intl/intl.dart';

class Transaction {
  final double amount;
  final DateTime date;
  final String transactionId;
  final String counterparty;
  final String type;
  final double fee;
  final double balance;

  Transaction({
    required this.amount,
    required this.date,
    required this.transactionId,
    required this.counterparty,
    required this.type,
    required this.fee,
    required this.balance,
  });

  bool get isReceived => type == 'RECEIVED';
  bool get isSent => type == 'SENT';

  static Transaction? fromSmsMessage(String body, {DateTime? smsDate}) {
    try {
      // Pattern 1: "You have received XXXX RWF from NAME (*****452) at 2025-11-06 11:09:16"
      final receivedPattern = RegExp(
        r'You have received\s+(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF\s+from\s+(.+?)\s*\([*\d]+\)\s+at\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
        caseSensitive: false,
      );

      // Pattern 1b: Alternative received format without phone number in parentheses
      final receivedPattern2 = RegExp(
        r'You have received\s+(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF\s+from\s+([^.]+?)(?:\.|at)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
        caseSensitive: false,
      );

      // Pattern 2: "*165*S*500 RWF transferred to NAME (phone) at 2025-11-06 11:20:54"
      final sentPattern = RegExp(
        r'\*\d+\*S\*(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF\s+transferred to\s+(.+?)\s*\([^)]+\)\s+at\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
        caseSensitive: false,
      );

      // Pattern 3: Payment messages "Your payment of XXXX RWF to NAME"
      final paymentPattern = RegExp(
        r'Your payment of\s+(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF\s+to\s+(.+?)\s+.*?was completed at\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
        caseSensitive: false,
      );

      RegExpMatch? match;
      String type = 'UNKNOWN';

      // Try to match received money (primary pattern)
      match = receivedPattern.firstMatch(body);
      if (match != null) {
        type = 'RECEIVED';
      } else {
        // Try alternative received money pattern
        match = receivedPattern2.firstMatch(body);
        if (match != null) {
          type = 'RECEIVED';
        } else {
          // Try to match sent money
          match = sentPattern.firstMatch(body);
          if (match != null) {
            type = 'SENT';
          } else {
            // Try payment pattern
            match = paymentPattern.firstMatch(body);
            if (match != null) {
              type = 'SENT';
            }
          }
        }
      }

      if (match != null) {
        // Extract amount (remove commas)
        final amountStr = match.group(1)?.replaceAll(',', '') ?? '0';
        final amount = double.tryParse(amountStr) ?? 0;

        // Extract counterparty name
        final counterparty = match.group(2)?.trim() ?? 'Unknown';

        // Extract date from message body (more accurate than SMS metadata)
        DateTime date;
        if (match.group(3) != null) {
          try {
            date = DateTime.parse(match.group(3)!.replaceAll(' ', 'T'));
          } catch (e) {
            print('Error parsing date: ${match.group(3)}');
            date = smsDate ?? DateTime.now();
          }
        } else {
          date = smsDate ?? DateTime.now();
        }

        // Extract fee and balance if present
        final feeMatch = RegExp(r'Fee\s*:?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF').firstMatch(body);
        final balanceMatch = RegExp(r'Balance\s*:?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*RWF').firstMatch(body);

        final fee = feeMatch != null ? (double.tryParse(feeMatch.group(1)?.replaceAll(',', '') ?? '0') ?? 0.0) : 0.0;
        final balance = balanceMatch != null ? (double.tryParse(balanceMatch.group(1)?.replaceAll(',', '') ?? '0') ?? 0.0) : 0.0;

        // Extract transaction ID
        final idMatch = RegExp(r'(?:FT Id|TxId)\s*:?\s*(\d+)').firstMatch(body);
        final transactionId = idMatch?.group(1) ?? '';

        return Transaction(
          amount: amount,
          date: date,
          transactionId: transactionId,
          counterparty: counterparty,
          type: type,
          fee: fee,
          balance: balance,
        );
      }
    } catch (e) {
      print('Error parsing SMS message: $e');
      print('Message body: $body');
    }
    return null;
  }
}

class MonthlyTransactionSummary {
  final DateTime month;
  final double totalReceived;
  final double totalSent;
  final int transactionCount;

  MonthlyTransactionSummary({
    required this.month,
    required this.totalReceived,
    required this.totalSent,
    required this.transactionCount,
  });

  double get netAmount => totalReceived - totalSent;
  
  String get formattedMonth => DateFormat('MMMM yyyy').format(month);
}