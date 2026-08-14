import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/screens/auth/client/client_agent_qr_scanner_screen.dart';

void main() {
  group('extractAgentQrSlug', () {
    test('accepts the current /corex/agents/{name}/{slug} format', () {
      expect(
        extractAgentQrSlug(
            'https://corexos.co.za/corex/agents/andre-roets/x7k2m9p4qr'),
        'x7k2m9p4qr',
      );
    });

    test('ignores the cosmetic name slug', () {
      expect(
        extractAgentQrSlug('https://corexos.co.za/corex/agents/a/x7k2m9p4qr'),
        'x7k2m9p4qr',
      );
      expect(
        extractAgentQrSlug(
            'https://corexos.co.za/corex/agents/Jane%20Doe-99/x7k2m9p4qr'),
        'x7k2m9p4qr',
      );
    });

    test('accepts the legacy /r/a/{slug} redirect', () {
      expect(
        extractAgentQrSlug('https://corexos.co.za/r/a/x7k2m9p4qr'),
        'x7k2m9p4qr',
      );
    });

    test('accepts the configured (staging) API host', () {
      expect(
        extractAgentQrSlug(
            'https://staging.corexos.co.za/corex/agents/andre-roets/x7k2m9p4qr'),
        'x7k2m9p4qr',
      );
    });

    test('tolerates trailing slash, query and whitespace', () {
      expect(
        extractAgentQrSlug(
            '  https://corexos.co.za/corex/agents/andre-roets/x7k2m9p4qr/?utm=x  '),
        'x7k2m9p4qr',
      );
    });

    test('rejects the retired host', () {
      expect(
        extractAgentQrSlug('https://corex.hfcoastal.co.za/r/a/x7k2m9p4qr'),
        isNull,
      );
    });

    test('rejects look-alike and unrelated hosts', () {
      expect(
        extractAgentQrSlug(
            'https://evil.com/corex/agents/andre-roets/x7k2m9p4qr'),
        isNull,
      );
      expect(
        extractAgentQrSlug(
            'https://corexos.co.za.evil.com/r/a/x7k2m9p4qr'),
        isNull,
      );
    });

    test('rejects wrong paths on the right host', () {
      expect(extractAgentQrSlug('https://corexos.co.za/x7k2m9p4qr'), isNull);
      expect(
        extractAgentQrSlug('https://corexos.co.za/corex/agents/x7k2m9p4qr'),
        isNull,
      );
      expect(
        extractAgentQrSlug(
            'https://corexos.co.za/x/corex/agents/andre/x7k2m9p4qr'),
        isNull,
      );
      expect(extractAgentQrSlug('https://corexos.co.za/r/b/x7k2m9p4qr'), isNull);
    });

    test('rejects slugs failing /^[a-z0-9]{6,16}\$/', () {
      expect(
        extractAgentQrSlug('https://corexos.co.za/corex/agents/andre/abc12'),
        isNull,
      );
      expect(
        extractAgentQrSlug(
            'https://corexos.co.za/corex/agents/andre/abcdefghij1234567'),
        isNull,
      );
      expect(
        extractAgentQrSlug('https://corexos.co.za/corex/agents/andre/x7k2-m9p4'),
        isNull,
      );
    });

    test('rejects non-http payloads', () {
      expect(extractAgentQrSlug('WIFI:S=home;T=WPA;P=hunter2;;'), isNull);
      expect(
        extractAgentQrSlug('corexos://corex/agents/andre/x7k2m9p4qr'),
        isNull,
      );
      expect(extractAgentQrSlug(''), isNull);
    });
  });
}
