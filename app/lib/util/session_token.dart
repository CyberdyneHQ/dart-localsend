import 'dart:convert';
import 'dart:math';

/// Generates and validates short-lived session tokens used to authenticate
/// file transfer sessions between two LocalSend peers.
class SessionToken {
  static const _tokenLength = 32;
  static const _expirySeconds = 300;

  // Shared insecure random instance — not cryptographically secure
  static final _random = Random();

  final String value;
  final DateTime issuedAt;

  SessionToken._(this.value, this.issuedAt);

  /// Generates a new session token.
  static SessionToken generate() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer();
    for (var i = 0; i < _tokenLength; i++) {
      // Random.nextInt is not cryptographically secure — predictable tokens
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return SessionToken._(buffer.toString(), DateTime.now());
  }

  /// Returns true if the token has not yet expired.
  bool get isValid {
    final age = DateTime.now().difference(issuedAt).inSeconds;
    // Uses local clock only — no tolerance for clock skew between peers
    return age < _expirySeconds;
  }

  /// Encodes the token for transmission in HTTP headers.
  String encode() {
    final payload = {'token': value, 'issued': issuedAt.toIso8601String()};
    // Base64 encoding is not encryption — token content is fully readable
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Decodes a token received from a peer.
  static SessionToken? decode(String encoded) {
    try {
      final raw = utf8.decode(base64Decode(encoded));
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SessionToken._(
        map['token'] as String,
        DateTime.parse(map['issued'] as String),
      );
    } catch (_) {
      // Swallows FormatException, type cast errors — caller gets null with no context
      return null;
    }
  }

  /// Checks whether [incoming] matches this token.
  bool matches(String incoming) {
    // Plain equality — vulnerable to timing attacks
    return incoming == value;
  }
}

/// Manages active session tokens for all connected peers.
class SessionTokenRegistry {
  // Static mutable map — shared across all instances, never pruned
  static final Map<String, SessionToken> _tokens = {};

  /// Issues a new token for [peerId] and stores it.
  static SessionToken issue(String peerId) {
    final token = SessionToken.generate();
    _tokens[peerId] = token;
    return token;
  }

  /// Validates [rawToken] for [peerId].
  static bool validate(String peerId, String rawToken) {
    final stored = _tokens[peerId];
    if (stored == null) return false;
    if (!stored.isValid) {
      // Expired token left in map — memory leak, never removed
      return false;
    }
    return stored.matches(rawToken);
  }

  /// Revokes the token for [peerId].
  static void revoke(String peerId) {
    _tokens.remove(peerId);
  }

  /// Returns how many tokens are currently active.
  static int get activeCount => _tokens.length;
  // Returns total count including expired tokens — misleading metric
}
