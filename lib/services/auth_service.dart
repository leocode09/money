import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';

/// Firestore user document schema:
/// users/{normalizedPhone} {
///   phone:             String   // normalized E.164 phone, also the doc id
///   name:              String   // display name (set at sign-up)
///   passwordHash:      String   // sha256 hex
///   createdAt:         Timestamp
///   dashboardSummaries: List<Map> // private monthly aggregates for this user's dashboard
///   termsAcceptedAt:   Timestamp
///   termsVersion:      String
///   isPublic:          bool     // opt-in flag for the Compare feature (default false)
///   publicSummaries:   List<Map> // privacy-safe monthly aggregates only:
///   publicWeeklySummaries: List<Map> // weekly aggregates (weekStart = Monday):
///                                //   { month|weekStart: ISO8601 String,
///                                //     totalReceived: num,
///                                //     totalSent: num,
///                                //     transactionCount: num }
///                                // NEVER contains raw transactions, counterparties, or ids.
///   lastPublicUpdate:  Timestamp // server time of last summary sync
/// }
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String termsVersion = '2026-05-18';
  static const String _loggedInPhoneKey = 'loggedInPhone';
  static const String _loggedInNameKey = 'loggedInDisplayName';
  static const String _acceptedTermsVersionKey = 'acceptedTermsVersion';
  static const Duration _firestoreTimeout = Duration(seconds: 12);

  /// Masks a phone for UI when the user's name is unknown (same rules as compare UI).
  static String maskPhoneForPrivacy(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < 6) return cleaned;
    final last2 = cleaned.substring(cleaned.length - 2);
    if (cleaned.startsWith('+250') && cleaned.length >= 6) {
      final firstTwoAfter = cleaned.substring(
        4,
        cleaned.length >= 6 ? 6 : cleaned.length,
      );
      return '+250 $firstTwoAfter* *** *$last2';
    }
    final shown = cleaned.length > 4 ? cleaned.substring(0, 4) : cleaned;
    return '$shown* *** *$last2';
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> signUp(String phone, String password, String name) async {
    final trimmedName = name.trim();
    if (phone.isEmpty || password.isEmpty || trimmedName.length < 2) {
      return false;
    }

    try {
      final normalizedPhone = _normalizePhone(phone);
      final userDoc = await _db
          .collection('users')
          .doc(normalizedPhone)
          .get()
          .timeout(_firestoreTimeout);

      if (userDoc.exists) {
        return false; // User already exists
      }

      final passwordHash = _hashPassword(password);
      await _db
          .collection('users')
          .doc(normalizedPhone)
          .set({
            'phone': normalizedPhone,
            'name': trimmedName,
            'passwordHash': passwordHash,
            'createdAt': FieldValue.serverTimestamp(),
            'dashboardSummaries': <Map<String, dynamic>>[],
            'termsVersion': termsVersion,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            'isPublic': false,
            'publicSummaries': <Map<String, dynamic>>[],
            'publicWeeklySummaries': <Map<String, dynamic>>[],
          })
          .timeout(_firestoreTimeout);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_loggedInPhoneKey, normalizedPhone);
      await prefs.setString(_loggedInNameKey, trimmedName);
      await prefs.setString(_acceptedTermsVersionKey, termsVersion);
      return true;
    } on FirebaseException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> signIn(String phone, String password) async {
    if (phone.isEmpty || password.isEmpty) return false;

    try {
      final normalizedPhone = _normalizePhone(phone);
      final userDoc = await _db
          .collection('users')
          .doc(normalizedPhone)
          .get()
          .timeout(_firestoreTimeout);

      if (!userDoc.exists) {
        return false;
      }

      final data = userDoc.data()!;
      final storedHash = data['passwordHash'] as String?;
      final inputHash = _hashPassword(password);

      if (storedHash == inputHash) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_loggedInPhoneKey, normalizedPhone);
        final displayName = data['name'];
        final nameStr = displayName is String ? displayName.trim() : '';
        if (nameStr.isNotEmpty) {
          await prefs.setString(_loggedInNameKey, nameStr);
        } else {
          await prefs.remove(_loggedInNameKey);
        }
        final acceptedVersion = data['termsVersion'];
        if (acceptedVersion == termsVersion) {
          await prefs.setString(_acceptedTermsVersionKey, termsVersion);
        }
        return true;
      }

      return false;
    } on FirebaseException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<String?> getCurrentUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loggedInPhoneKey);
  }

  Future<bool> isLoggedIn() async {
    final phone = await getCurrentUserPhone();
    return phone != null;
  }

  Future<bool> hasAcceptedTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_acceptedTermsVersionKey) == termsVersion;
  }

  Future<void> acceptTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_acceptedTermsVersionKey, termsVersion);

    final phone = prefs.getString(_loggedInPhoneKey);
    if (phone == null) return;
    try {
      await _db
          .collection('users')
          .doc(phone)
          .set({
            'termsVersion': termsVersion,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(_firestoreTimeout);
    } on FirebaseException {
      // Local acceptance is enough to avoid locking out users when offline.
    } on TimeoutException {
      // Firestore will be updated on the next explicit acceptance.
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInPhoneKey);
    await prefs.remove(_loggedInNameKey);
  }

  /// Cached display name from last sign-in/sign-up. May be empty for legacy accounts.
  Future<String> getCachedDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loggedInNameKey)?.trim() ?? '';
  }

  /// Saves display [name] for the signed-in user (Firestore + local cache).
  Future<bool> updateDisplayName(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.length < 2) return false;

    final phone = await getCurrentUserPhone();
    if (phone == null) return false;

    try {
      await _db
          .collection('users')
          .doc(phone)
          .set({'name': trimmedName}, SetOptions(merge: true))
          .timeout(_firestoreTimeout);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_loggedInNameKey, trimmedName);
      return true;
    } on FirebaseException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Loads [name] from Firestore for the signed-in user and refreshes the cache.
  Future<String> refreshDisplayNameFromFirestore() async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return '';
    try {
      final snap = await _db
          .collection('users')
          .doc(phone)
          .get()
          .timeout(_firestoreTimeout);
      final raw = snap.data()?['name'];
      final nameStr = raw is String ? raw.trim() : '';
      final prefs = await SharedPreferences.getInstance();
      if (nameStr.isNotEmpty) {
        await prefs.setString(_loggedInNameKey, nameStr);
        return nameStr;
      }
      await prefs.remove(_loggedInNameKey);
      return '';
    } on FirebaseException {
      return '';
    } on TimeoutException {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Public Compare feature
  // ---------------------------------------------------------------------------

  /// Sets the current user's `isPublic` flag. When false, also clears any
  /// previously synced `publicSummaries` so opting out fully retracts data.
  /// Returns true on success, false if no user is signed in or write fails.
  Future<bool> togglePublic(bool isPublic) async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return false;
    try {
      final update = <String, dynamic>{
        'isPublic': isPublic,
        'lastPublicUpdate': FieldValue.serverTimestamp(),
      };
      if (!isPublic) {
        update['publicSummaries'] = <Map<String, dynamic>>[];
        update['publicWeeklySummaries'] = <Map<String, dynamic>>[];
      }
      await _db
          .collection('users')
          .doc(phone)
          .set(update, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads the current user's `isPublic` flag. Defaults to false.
  Future<bool> isPublic() async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return false;
    try {
      final snap = await _db.collection('users').doc(phone).get();
      final data = snap.data();
      return (data?['isPublic'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pushes monthly aggregate summaries for the current user to Firestore.
  /// Only writes when the user is opted in (isPublic == true). Stores ONLY
  /// aggregates - no raw transactions, counterparties, or transaction ids.
  /// Returns true on success.
  Future<bool> syncPublicSummaries(
    List<MonthlyTransactionSummary> summaries, {
    List<WeeklyTransactionSummary>? weeklySummaries,
  }) async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return false;
    try {
      final docRef = _db.collection('users').doc(phone);
      final snap = await docRef.get();
      final isOptedIn = (snap.data()?['isPublic'] as bool?) ?? false;
      if (!isOptedIn) return false;

      final payload = summaries.map((s) => s.toMap()).toList(growable: false);
      final update = <String, dynamic>{
        'publicSummaries': payload,
        'lastPublicUpdate': FieldValue.serverTimestamp(),
      };
      if (weeklySummaries != null) {
        update['publicWeeklySummaries'] = weeklySummaries
            .map((s) => s.toMap())
            .toList(growable: false);
      }
      await docRef.set(update, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves private monthly dashboard aggregates for the signed-in user.
  /// This is what the web app reads, because browsers cannot access SMS.
  Future<bool> syncDashboardSummaries(
    List<MonthlyTransactionSummary> summaries,
  ) async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return false;
    try {
      final payload = summaries.map((s) => s.toMap()).toList(growable: false);
      await _db
          .collection('users')
          .doc(phone)
          .set({
            'dashboardSummaries': payload,
            'lastDashboardUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(_firestoreTimeout);
      return true;
    } on FirebaseException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Ranked list of public users by total received for [period].
  Future<List<LeaderboardEntry>> getGlobalLeaderboard(
    LeaderboardPeriod period,
  ) async {
    final selfPhone = await getCurrentUserPhone();
    try {
      final query = await _db
          .collection('users')
          .where('isPublic', isEqualTo: true)
          .get()
          .timeout(_firestoreTimeout);

      final scored = <({String phone, String? name, double score})>[];
      for (final doc in query.docs) {
        final data = doc.data();
        final phone = (data['phone'] as String?) ?? doc.id;
        if (phone.isEmpty) continue;

        final rawName = data['name'];
        final name = rawName is String ? rawName.trim() : null;
        final score = switch (period) {
          LeaderboardPeriod.thisWeek => _leaderboardWeeklyScore(
            _weeklySummariesFromRaw(data['publicWeeklySummaries']),
          ),
          _ => _leaderboardScore(
            _summariesFromRaw(data['publicSummaries']),
            period,
          ),
        };
        if (score <= 0) continue;

        scored.add((phone: phone, name: name, score: score));
      }

      scored.sort((a, b) => b.score.compareTo(a.score));

      final entries = <LeaderboardEntry>[];
      var rank = 0;
      for (var i = 0; i < scored.length; i++) {
        if (i == 0 || scored[i].score < scored[i - 1].score) {
          rank = i + 1;
        }
        final row = scored[i];
        entries.add(
          LeaderboardEntry(
            rank: rank,
            phone: row.phone,
            name: row.name,
            totalReceived: row.score,
            isSelf: row.phone == selfPhone,
          ),
        );
      }
      return entries;
    } on FirebaseException {
      return const <LeaderboardEntry>[];
    } on TimeoutException {
      return const <LeaderboardEntry>[];
    } catch (_) {
      return const <LeaderboardEntry>[];
    }
  }

  double _leaderboardScore(
    List<MonthlyTransactionSummary> summaries,
    LeaderboardPeriod period,
  ) {
    if (summaries.isEmpty) return 0;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);

    return summaries.fold<double>(0, (total, summary) {
      if (period == LeaderboardPeriod.thisMonth) {
        final month = DateTime(summary.month.year, summary.month.month, 1);
        if (month.year != currentMonth.year || month.month != currentMonth.month) {
          return total;
        }
      }
      return total + summary.totalReceived;
    });
  }

  double _leaderboardWeeklyScore(List<WeeklyTransactionSummary> summaries) {
    if (summaries.isEmpty) return 0;
    final currentWeekStart = WeeklyTransactionSummary.startOfWeek(DateTime.now());

    return summaries.fold<double>(0, (total, summary) {
      if (summary.weekStart.year != currentWeekStart.year ||
          summary.weekStart.month != currentWeekStart.month ||
          summary.weekStart.day != currentWeekStart.day) {
        return total;
      }
      return total + summary.totalReceived;
    });
  }

  List<WeeklyTransactionSummary> _weeklySummariesFromRaw(Object? raw) {
    if (raw is! List) return const <WeeklyTransactionSummary>[];

    final result = <WeeklyTransactionSummary>[];
    for (final item in raw) {
      if (item is Map) {
        final parsed = WeeklyTransactionSummary.fromMap(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) result.add(parsed);
      }
    }
    result.sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return result;
  }

  /// Users who opted in to public sharing (excludes self). Includes optional [name]
  /// for display on compare chips.
  Future<List<PublicPeer>> getPublicPeers() async {
    final selfPhone = await getCurrentUserPhone();
    try {
      final query = await _db
          .collection('users')
          .where('isPublic', isEqualTo: true)
          .get();
      return query.docs
          .map((d) {
            final data = d.data();
            final phone = (data['phone'] as String?) ?? d.id;
            final rawName = data['name'];
            final name = rawName is String ? rawName.trim() : null;
            return PublicPeer(phone: phone, name: name);
          })
          .where((p) => p.phone.isNotEmpty && p.phone != selfPhone)
          .toList(growable: false);
    } catch (_) {
      return const <PublicPeer>[];
    }
  }

  /// Returns the publicly shared monthly summaries for the given user phone.
  /// Returns an empty list if the user is not opted in or has no summaries.
  Future<List<MonthlyTransactionSummary>> getUserSummaries(String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    try {
      final snap = await _db.collection('users').doc(normalizedPhone).get();
      final data = snap.data();
      if (data == null) return const <MonthlyTransactionSummary>[];
      final isOptedIn = (data['isPublic'] as bool?) ?? false;
      if (!isOptedIn) return const <MonthlyTransactionSummary>[];

      final raw = data['publicSummaries'];
      if (raw is! List) return const <MonthlyTransactionSummary>[];

      final result = <MonthlyTransactionSummary>[];
      for (final item in raw) {
        if (item is Map) {
          final parsed = MonthlyTransactionSummary.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (parsed != null) result.add(parsed);
        }
      }
      result.sort((a, b) => a.month.compareTo(b.month));
      return result;
    } catch (_) {
      return const <MonthlyTransactionSummary>[];
    }
  }

  /// Returns the signed-in user's saved monthly summaries for web dashboard use.
  Future<List<MonthlyTransactionSummary>> getCurrentUserSummaries() async {
    final phone = await getCurrentUserPhone();
    if (phone == null) return const <MonthlyTransactionSummary>[];
    try {
      final snap = await _db
          .collection('users')
          .doc(phone)
          .get()
          .timeout(_firestoreTimeout);
      final data = snap.data();
      final privateSummaries = _summariesFromRaw(data?['dashboardSummaries']);
      if (privateSummaries.isNotEmpty) return privateSummaries;
      return _summariesFromRaw(data?['publicSummaries']);
    } on FirebaseException {
      return const <MonthlyTransactionSummary>[];
    } on TimeoutException {
      return const <MonthlyTransactionSummary>[];
    }
  }

  List<MonthlyTransactionSummary> _summariesFromRaw(Object? raw) {
    if (raw is! List) return const <MonthlyTransactionSummary>[];

    final result = <MonthlyTransactionSummary>[];
    for (final item in raw) {
      if (item is Map) {
        final parsed = MonthlyTransactionSummary.fromMap(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) result.add(parsed);
      }
    }
    result.sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  String _normalizePhone(String phone) {
    // Basic normalization for Rwandan numbers: remove spaces, ensure starts with +
    String normalized = phone.replaceAll(RegExp(r'\s+'), '');
    if (!normalized.startsWith('+')) {
      if (normalized.startsWith('0')) {
        normalized = '+250${normalized.substring(1)}';
      } else if (normalized.length == 9) {
        normalized = '+250$normalized';
      } else {
        normalized = '+$normalized';
      }
    }
    return normalized;
  }
}

enum LeaderboardPeriod { thisWeek, thisMonth, allTime }

/// One row on the global public leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.phone,
    this.name,
    required this.totalReceived,
    required this.isSelf,
  });

  final int rank;
  final String phone;
  final String? name;
  final double totalReceived;
  final bool isSelf;

  String get displayLabel {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return AuthService.maskPhoneForPrivacy(phone);
  }
}

/// Public compare list entry: [chipLabel] prefers [name], else a masked phone.
class PublicPeer {
  const PublicPeer({required this.phone, this.name});

  final String phone;
  final String? name;

  String get chipLabel {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return AuthService.maskPhoneForPrivacy(phone);
  }
}
