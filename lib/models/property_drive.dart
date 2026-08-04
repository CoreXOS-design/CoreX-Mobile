// Models backing the property Drive section — a read-only mirror of the web
// app's Drive tab for a listing.
// Backed by `/api/v1/mobile/properties/{id}/documents`.

import 'contact_compliance.dart' show DocumentType;

int? _int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
String _str(dynamic v) => v?.toString() ?? '';

/// A folder chip above the document list.
///
/// [documentTypeId] is null for the "Unfiled" bucket. The server only includes
/// that entry when at least one document actually has no type assigned, so
/// never assume it is present.
class DriveFolder {
  final int? documentTypeId;
  final String label;
  final String? slug;
  final int count;

  const DriveFolder({
    this.documentTypeId,
    required this.label,
    this.slug,
    this.count = 0,
  });

  factory DriveFolder.fromJson(Map<String, dynamic> j) => DriveFolder(
        documentTypeId: _int(j['document_type_id']),
        label: _str(j['label']),
        slug: j['slug']?.toString(),
        count: _int(j['count']) ?? 0,
      );

  /// Whether [doc] belongs in this folder. Works for "Unfiled" too: both sides
  /// are null, so an untyped document matches the null-id folder and nothing
  /// else.
  bool contains(PropertyDocument doc) =>
      doc.documentType?.id == documentTypeId;
}

/// Broad file family, used to pick a row icon. Derived from `mime_type` when
/// the server sends one, falling back to the filename extension — any file type
/// filed on the property shows up here, not just PDFs.
enum DriveFileKind { pdf, image, doc, sheet, generic }

DriveFileKind driveFileKindFor(String? mimeType, String fileName) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.isNotEmpty) {
    if (mime.contains('pdf')) return DriveFileKind.pdf;
    if (mime.startsWith('image/')) return DriveFileKind.image;
    if (mime.contains('spreadsheet') ||
        mime.contains('excel') ||
        mime.contains('csv')) {
      return DriveFileKind.sheet;
    }
    if (mime.startsWith('text/') ||
        mime.contains('word') ||
        mime.contains('document') ||
        mime.contains('rtf')) {
      return DriveFileKind.doc;
    }
  }
  final dot = fileName.lastIndexOf('.');
  final ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return DriveFileKind.pdf;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'heic':
    case 'bmp':
      return DriveFileKind.image;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return DriveFileKind.sheet;
    case 'doc':
    case 'docx':
    case 'txt':
    case 'rtf':
      return DriveFileKind.doc;
    default:
      return DriveFileKind.generic;
  }
}

/// Splits a filename into its base and its extension (without the dot).
///
/// The save dialog takes the two separately and re-joins them, so handing it
/// the full name would produce `Mandate.pdf.pdf`. A leading-dot name
/// (`.gitignore`) is all base and no extension, not the reverse.
({String base, String ext}) splitFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) {
    return (base: fileName, ext: '');
  }
  return (base: fileName.substring(0, dot), ext: fileName.substring(dot + 1));
}

class PropertyDocument {
  final int id;
  final String originalName;
  final String? mimeType;
  final int? size;
  final String? humanSize;

  /// Null when the file hasn't been filed into a folder yet — group these under
  /// the "Unfiled" folder from [PropertyDriveData.folders].
  final DocumentType? documentType;
  final String? sourceType;
  final int? uploadedById;
  final String? uploadedByName;
  final String? createdAt;

  /// Per-row, and can change without the list changing (an assistant's download
  /// toggle). Grey the download control when false rather than letting the tap
  /// come back 403.
  final bool canDownload;

  /// Absolute, already pointing at the right endpoint — but not a public link.
  /// The bearer token still has to go on the request.
  final String? downloadUrl;

  const PropertyDocument({
    required this.id,
    required this.originalName,
    this.mimeType,
    this.size,
    this.humanSize,
    this.documentType,
    this.sourceType,
    this.uploadedById,
    this.uploadedByName,
    this.createdAt,
    this.canDownload = false,
    this.downloadUrl,
  });

  DriveFileKind get kind => driveFileKindFor(mimeType, originalName);

  factory PropertyDocument.fromJson(Map<String, dynamic> j) {
    final dt = j['document_type'];
    final by = j['uploaded_by'];
    return PropertyDocument(
      id: _int(j['id']) ?? 0,
      originalName: _str(j['original_name']),
      mimeType: j['mime_type']?.toString(),
      size: _int(j['size']),
      humanSize: j['human_size']?.toString(),
      documentType: dt is Map
          ? DocumentType.fromJson(Map<String, dynamic>.from(dt))
          : null,
      sourceType: j['source_type']?.toString(),
      uploadedById: by is Map ? _int(by['id']) : null,
      uploadedByName: by is Map ? by['name']?.toString() : by?.toString(),
      createdAt: j['created_at']?.toString(),
      canDownload: j['can_download'] == true,
      downloadUrl: j['download_url']?.toString(),
    );
  }
}

class PropertyDriveData {
  final int propertyId;
  final List<DriveFolder> folders;

  /// The full flat list, newest first — not pre-filtered by folder. Folder
  /// chips filter this client-side, with no extra network call.
  final List<PropertyDocument> documents;

  const PropertyDriveData({
    required this.propertyId,
    this.folders = const [],
    this.documents = const [],
  });

  bool get isEmpty => documents.isEmpty;

  factory PropertyDriveData.fromJson(Map<String, dynamic> j) =>
      PropertyDriveData(
        propertyId: _int(j['property_id']) ?? 0,
        folders: (j['folders'] as List? ?? [])
            .whereType<Map>()
            .map((e) => DriveFolder.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        documents: (j['documents'] as List? ?? [])
            .whereType<Map>()
            .map((e) => PropertyDocument.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// Documents in [folder], or all of them when [folder] is null ("All").
  List<PropertyDocument> documentsIn(DriveFolder? folder) =>
      folder == null ? documents : documents.where(folder.contains).toList();

  /// A copy without [documentId] — used to drop a stale row when a download
  /// comes back 404, before the re-fetch lands.
  PropertyDriveData without(int documentId) => PropertyDriveData(
        propertyId: propertyId,
        folders: folders,
        documents: documents.where((d) => d.id != documentId).toList(),
      );
}
