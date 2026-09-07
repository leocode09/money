import 'package:another_telephony/telephony.dart';

/// A single incoming SMS, decoupled from the underlying telephony plugin so the
/// rest of the app never has to import a second `SmsMessage` type that would
/// clash with the one from `flutter_sms_inbox`.
class IncomingSms {
  const IncomingSms({this.sender, this.body, this.dateMillis});

  final String? sender;
  final String? body;
  final int? dateMillis;
}

/// Listens for incoming SMS in realtime while the app is in the foreground and
/// forwards each new message.
///
/// Background delivery is intentionally not used: it requires a separate
/// isolate entry-point and adds fragility for little benefit here. Instead the
/// shell re-queries the inbox whenever the app resumes, so messages that arrive
/// while the app is backgrounded are still picked up.
class SmsRealtimeService {
  final Telephony _telephony = Telephony.instance;
  bool _listening = false;

  /// Starts forwarding foreground SMS to [onSms]. Safe to call more than once;
  /// only the first call registers a listener.
  void start(void Function(IncomingSms sms) onSms) {
    if (_listening) return;
    _listening = true;
    _telephony.listenIncomingSms(
      onNewMessage: (message) => onSms(
        IncomingSms(
          sender: message.address,
          body: message.body,
          dateMillis: message.date,
        ),
      ),
      listenInBackground: false,
    );
  }
}
