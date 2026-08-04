import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/property_drive.dart';
import 'package:corex_mobile/screens/properties/property_drive_card.dart';
import 'package:corex_mobile/services/api_service.dart';
import 'package:corex_mobile/utils/app_time.dart';

/// The documented list payload, including the two shapes that are easy to get
/// wrong: an "Unfiled" folder whose `document_type_id` is null, and a document
/// with `document_type: null` that belongs in it.
Map<String, dynamic> _payload() => {
      'property_id': 42,
      'folders': [
        {
          'document_type_id': 3,
          'label': 'Mandate',
          'slug': 'mandate',
          'count': 2
        },
        {
          'document_type_id': null,
          'label': 'Unfiled',
          'slug': null,
          'count': 1
        },
      ],
      'documents': [
        {
          'id': 101,
          'original_name': 'Mandate Agreement.pdf',
          'mime_type': 'application/pdf',
          'size': 245678,
          'human_size': '240.0 KB',
          'document_type': {'id': 3, 'label': 'Mandate', 'slug': 'mandate'},
          'source_type': 'upload',
          'uploaded_by': {'id': 5, 'name': 'Jane Agent'},
          'created_at': '2026-08-01T10:22:00+02:00',
          'can_download': true,
          'download_url':
              'https://corex.hfcoastal.co.za/api/v1/mobile/properties/42/documents/101/download',
        },
        {
          'id': 102,
          'original_name': 'Mandate Addendum.pdf',
          'mime_type': 'application/pdf',
          'human_size': '11.2 KB',
          'document_type': {'id': 3, 'label': 'Mandate', 'slug': 'mandate'},
          'uploaded_by': {'id': 5, 'name': 'Jane Agent'},
          'created_at': '2026-08-01T09:00:00+02:00',
          'can_download': false,
        },
        {
          'id': 103,
          'original_name': 'Random scan.jpg',
          'mime_type': 'image/jpeg',
          'human_size': '1.1 MB',
          'document_type': null,
          'uploaded_by': {'id': 7, 'name': 'Sam Assistant'},
          'created_at': '2026-07-30T08:00:00+02:00',
          'can_download': true,
        },
      ],
    };

class _FakeApi extends ApiService {
  int downloadCalls = 0;
  ApiException? downloadError;

  @override
  Future<DownloadedFile> downloadPropertyDocument(
    int propertyId,
    int documentId,
    String fallbackName, {
    String? downloadUrl,
  }) async {
    downloadCalls++;
    if (downloadError != null) throw downloadError!;
    return DownloadedFile(bytes: Uint8List(0), fileName: fallbackName);
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('PropertyDriveData.fromJson', () {
    test('parses folders, documents and the nested uploader', () {
      final d = PropertyDriveData.fromJson(_payload());
      expect(d.propertyId, 42);
      expect(d.folders, hasLength(2));
      expect(d.documents, hasLength(3));

      final first = d.documents.first;
      expect(first.id, 101);
      expect(first.originalName, 'Mandate Agreement.pdf');
      expect(first.humanSize, '240.0 KB');
      expect(first.documentType!.label, 'Mandate');
      expect(first.uploadedByName, 'Jane Agent');
      expect(first.uploadedById, 5);
      expect(first.canDownload, isTrue);
      expect(first.downloadUrl, endsWith('/documents/101/download'));
    });

    test('an unfiled document parses with a null type, not a crash', () {
      final d = PropertyDriveData.fromJson(_payload());
      final unfiled = d.documents.firstWhere((e) => e.id == 103);
      expect(unfiled.documentType, isNull);
      expect(unfiled.canDownload, isTrue);
      expect(unfiled.downloadUrl, isNull);
    });

    test('missing folders/documents keys yield empty lists, not null', () {
      final d = PropertyDriveData.fromJson({'property_id': 9});
      expect(d.folders, isEmpty);
      expect(d.documents, isEmpty);
      expect(d.isEmpty, isTrue);
    });
  });

  group('folder filtering', () {
    final data = PropertyDriveData.fromJson(_payload());

    test('null folder means All', () {
      expect(data.documentsIn(null), hasLength(3));
    });

    test('a typed folder matches only its own documents', () {
      final mandate =
          data.folders.firstWhere((f) => f.documentTypeId == 3);
      final docs = data.documentsIn(mandate);
      expect(docs.map((d) => d.id), [101, 102]);
    });

    test('the null-id Unfiled folder matches untyped documents only — '
        'it must not behave like All', () {
      final unfiled =
          data.folders.firstWhere((f) => f.documentTypeId == null);
      final docs = data.documentsIn(unfiled);
      expect(docs.map((d) => d.id), [103]);
    });
  });

  group('splitFileName', () {
    test('splits base from extension for the save dialog', () {
      // The dialog re-joins these, so a bad split yields "Mandate.pdf.pdf".
      expect(splitFileName('Mandate Agreement.pdf'),
          (base: 'Mandate Agreement', ext: 'pdf'));
      expect(splitFileName('report.final.docx'),
          (base: 'report.final', ext: 'docx'));
    });

    test('treats edge cases as all-base, no extension', () {
      expect(splitFileName('no-extension'), (base: 'no-extension', ext: ''));
      expect(splitFileName('.gitignore'), (base: '.gitignore', ext: ''));
      expect(splitFileName('trailing.'), (base: 'trailing.', ext: ''));
    });
  });

  group('driveFileKindFor', () {
    test('reads the mime type when present', () {
      expect(driveFileKindFor('application/pdf', 'x'), DriveFileKind.pdf);
      expect(driveFileKindFor('image/jpeg', 'x'), DriveFileKind.image);
      expect(
          driveFileKindFor(
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'x'),
          DriveFileKind.doc);
      expect(driveFileKindFor('text/csv', 'x'), DriveFileKind.sheet);
      expect(driveFileKindFor('application/zip', 'x'), DriveFileKind.generic);
    });

    test('falls back to the extension when mime is missing', () {
      expect(driveFileKindFor(null, 'deed.PDF'), DriveFileKind.pdf);
      expect(driveFileKindFor(null, 'photo.heic'), DriveFileKind.image);
      expect(driveFileKindFor(null, 'notes.docx'), DriveFileKind.doc);
      expect(driveFileKindFor(null, 'no-extension'), DriveFileKind.generic);
    });
  });

  group('relativeTime', () {
    final now = DateTime.parse('2026-08-03T12:00:00+02:00');

    test('formats common ranges', () {
      expect(relativeTime('2026-08-03T11:59:30+02:00', now: now), 'just now');
      expect(relativeTime('2026-08-03T11:30:00+02:00', now: now), '30m ago');
      expect(relativeTime('2026-07-31T12:00:00+02:00', now: now), '3d ago');
      expect(relativeTime('2026-06-03T12:00:00+02:00', now: now), '2mo ago');
    });

    test('returns null for missing or unparseable input', () {
      expect(relativeTime(null), isNull);
      expect(relativeTime(''), isNull);
      expect(relativeTime('not a date'), isNull);
    });
  });

  group('PropertyDriveCard', () {
    testWidgets('lists documents with size, uploader and relative time',
        (tester) async {
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: _FakeApi(),
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Mandate Agreement.pdf'), findsOneWidget);
      expect(find.text('Random scan.jpg'), findsOneWidget);
      expect(find.textContaining('240.0 KB'), findsOneWidget);
      expect(find.textContaining('Jane Agent'), findsWidgets);
    });

    testWidgets('folder chips filter client-side, with no network call',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: api,
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unfiled'));
      await tester.pumpAndSettle();

      expect(find.text('Random scan.jpg'), findsOneWidget);
      expect(find.text('Mandate Agreement.pdf'), findsNothing);
      expect(api.downloadCalls, 0);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Mandate Agreement.pdf'), findsOneWidget);
    });

    testWidgets('every row offers both Save and Share', (tester) async {
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: _FakeApi(),
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.ios_share_rounded), findsNWidgets(3));
    });

    testWidgets('can_download false disables BOTH buttons, so Share is not a '
        'way around the download switch', (tester) async {
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: _FakeApi(),
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      final buttons =
          tester.widgetList<IconButton>(find.byType(IconButton)).toList();
      // 3 rows x 2 buttons. Only doc 102 has can_download false, and it must
      // lose its Share as well as its Save.
      expect(buttons, hasLength(6));
      expect(buttons.where((b) => b.onPressed == null), hasLength(2));
      expect(buttons.where((b) => b.onPressed != null), hasLength(4));
    });

    testWidgets('Share goes through the same gated endpoint as Save',
        (tester) async {
      final api = _FakeApi()
        ..downloadError = ApiException(403, 'Downloads are disabled.');

      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: api,
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share_rounded).first);
      await tester.pumpAndSettle();

      expect(api.downloadCalls, 1);
      expect(find.text('Downloads are disabled.'), findsOneWidget);
    });

    testWidgets('a failed fetch shows an error with Retry, not a blank card',
        (tester) async {
      var retried = 0;
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: null,
        api: _FakeApi(),
        propertyId: 42,
        error: 'Failed to load documents',
        onRetry: () async => retried++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load documents'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    });

    testWidgets('shows a spinner while the first fetch is in flight',
        (tester) async {
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: null,
        api: _FakeApi(),
        propertyId: 42,
        loading: true,
      )));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('empty drive shows the directive empty state', (tester) async {
      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(
            {'property_id': 42, 'folders': [], 'documents': []}),
        api: _FakeApi(),
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      expect(find.text('No files on this property yet.'), findsOneWidget);
    });

    testWidgets('a 403 shows the server message and keeps the row',
        (tester) async {
      final api = _FakeApi()
        ..downloadError =
            ApiException(403, 'Downloads are disabled for your account.');

      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: api,
        propertyId: 42,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.download_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Downloads are disabled for your account.'),
          findsOneWidget);
      expect(find.text('Mandate Agreement.pdf'), findsOneWidget);
    });

    testWidgets('a 404 drops the stale row and asks the parent to re-fetch',
        (tester) async {
      final api = _FakeApi()
        ..downloadError =
            ApiException(404, 'That file is no longer on this property.');
      var refetched = 0;

      await tester.pumpWidget(_wrap(PropertyDriveCard(
        data: PropertyDriveData.fromJson(_payload()),
        api: api,
        propertyId: 42,
        onStale: () async => refetched++,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.download_rounded).first);
      await tester.pumpAndSettle();

      expect(refetched, 1);
      expect(find.text('Mandate Agreement.pdf'), findsNothing);
      expect(find.text('Random scan.jpg'), findsOneWidget);
    });
  });
}
