import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/services/api_service.dart';

/// Guards the 403 classification behind "Delete my account" (Apple 5.1.1(v)).
///
/// Deleting an account revokes the bearer token server-side, so every later
/// request comes back 403 and the app must sign the user out locally. But 403
/// is also this app's everyday "you don't have permission" status — properties
/// you don't co-list, tasks outside your branch, agency-controlled fields. One
/// over-broad match here and an agent tapping the wrong property gets thrown
/// back to the login screen with their token wiped.
///
/// So the rule is: a 403 ends the session ONLY when the server names the
/// reason. These tests pin both halves — the shapes that must sign out, and the
/// real permission-denial bodies that must not.
void main() {
  group('403s that mean app access is gone', () {
    test('login gate — carries an explicit code', () {
      expect(
        ApiService.isAccountDeletedResponse(
          '{"message":"This account has been deleted.",'
          '"code":"account_deleted"}',
        ),
        isTrue,
      );
    });

    test('EnsureAppAccess middleware — message only, no code', () {
      // Laravel's abort(403, '...') shape. The middleware sends no `code`, so
      // the message match is the only thing standing between a revoked token
      // and a session that silently keeps failing every request.
      expect(
        ApiService.isAccountDeletedResponse(
          '{"message":"This account has been deleted."}',
        ),
        isTrue,
      );
    });

    test('a code alone is enough, whatever the message says', () {
      expect(
        ApiService.isAccountDeletedResponse(
          '{"message":"Forbidden.","code":"account_deleted"}',
        ),
        isTrue,
      );
    });
  });

  group('403s that are ordinary permission denials', () {
    // Verbatim from api_service.dart — if one of these ever starts signing
    // people out, this list is where it gets caught.
    const permissionDenials = [
      '{"message":"You don\'t have access to this property"}',
      '{"message":"You don\'t have access to this task."}',
      '{"message":"You don\'t have permission to edit this property"}',
      '{"message":"You don\'t have permission to market this property"}',
      '{"message":"Agency-controlled — only agency admins can change these"}',
      '{"message":"Forbidden."}',
    ];

    for (final body in permissionDenials) {
      test('leaves the session alone: $body', () {
        expect(ApiService.isAccountDeletedResponse(body), isFalse);
      });
    }
  });

  group('bodies that cannot be trusted', () {
    test('null body', () {
      expect(ApiService.isAccountDeletedResponse(null), isFalse);
    });

    test('empty body', () {
      expect(ApiService.isAccountDeletedResponse(''), isFalse);
    });

    test('an HTML error page from a proxy', () {
      expect(
        ApiService.isAccountDeletedResponse('<html><body>403</body></html>'),
        isFalse,
      );
    });

    test('the phrase in prose, not as the message field', () {
      // A gateway or WAF echoing text back must not be able to sign a user out.
      expect(
        ApiService.isAccountDeletedResponse(
          '{"error":"This account has been deleted."}',
        ),
        isFalse,
      );
    });

    test('a JSON array rather than an object', () {
      expect(
        ApiService.isAccountDeletedResponse('["account_deleted"]'),
        isFalse,
      );
    });

    test('truncated JSON that happens to contain the code', () {
      expect(
        ApiService.isAccountDeletedResponse('{"code":"account_deleted"'),
        isFalse,
      );
    });
  });

  group('ApiException carries the server reason', () {
    test('code is exposed alongside the status', () {
      final e = ApiException(403, 'This account has been deleted.',
          code: 'account_deleted');
      expect(e.code, 'account_deleted');
      expect(e.statusCode, 403);
      // 403/account_deleted and 401/invalid_password must be distinguishable
      // without string-matching the human message.
      expect(e.toString(), contains('account_deleted'));
    });

    test('code is null when the server sent none', () {
      expect(ApiException(500, 'Server error').code, isNull);
    });
  });
}
