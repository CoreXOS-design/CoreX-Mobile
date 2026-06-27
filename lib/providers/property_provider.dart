import 'dart:io';
import 'package:flutter/material.dart';
import '../models/gallery_tags.dart';
import '../models/property.dart';
import '../models/visibility.dart';
import '../services/api_service.dart';

class PropertyProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _disposed = false;

  // Stale-response guard for fetchProperties.
  int _fetchSeq = 0;

  List<Property> properties = [];
  Property? selectedProperty;
  bool isLoading = false;
  String? error;
  /// Per-field error messages from the most recent failed create/update.
  /// Empty after a successful save. Consumers (the form screens) read this
  /// to highlight individual fields with their server-side message.
  Map<String, String> fieldErrors = const {};

  /// Last filter used, so background refreshes (returning from a detail
  /// screen) keep the agent the user is viewing.
  AgentFilter _agentFilter = AgentFilter.mine;

  /// Clear all per-user state on logout so the next account never sees the
  /// previous user's properties or selection.
  void reset() {
    properties = [];
    selectedProperty = null;
    isLoading = false;
    error = null;
    fieldErrors = const {};
    _agentFilter = AgentFilter.mine;
    // Invalidate any in-flight fetch.
    _fetchSeq++;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> fetchProperties({AgentFilter? agentFilter}) async {
    if (agentFilter != null) _agentFilter = agentFilter;
    final reqId = ++_fetchSeq;
    isLoading = true;
    error = null;
    _safeNotify();
    try {
      final result = await _api.getProperties(agentFilter: _agentFilter);
      if (reqId != _fetchSeq) return;
      properties = result;
    } catch (e) {
      if (reqId != _fetchSeq) return;
      error = e.toString();
    } finally {
      if (reqId == _fetchSeq) {
        isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> fetchProperty(int id) async {
    isLoading = true;
    error = null;
    _safeNotify();
    try {
      selectedProperty = await _api.getProperty(id);
    } on ApiException catch (e) {
      selectedProperty = null;
      error = e.message;
      isLoading = false;
      _safeNotify();
      // Let the screen decide how to surface 403 / not-found (toast + pop).
      rethrow;
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    _safeNotify();
  }

  Future<Property?> createProperty(Map<String, dynamic> data) async {
    isLoading = true;
    error = null;
    fieldErrors = const {};
    _safeNotify();
    try {
      final property = await _api.createProperty(data);
      await fetchProperties();
      return property;
    } on ValidationException catch (e) {
      error = e.message;
      fieldErrors = e.fieldErrors;
      isLoading = false;
      _safeNotify();
      return null;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      _safeNotify();
      return null;
    }
  }

  Future<bool> updateProperty(int id, Map<String, dynamic> data) async {
    isLoading = true;
    error = null;
    fieldErrors = const {};
    _safeNotify();
    try {
      await _api.updateProperty(id, data);
      await fetchProperties();
      return true;
    } on ValidationException catch (e) {
      error = e.message;
      fieldErrors = e.fieldErrors;
      isLoading = false;
      _safeNotify();
      return false;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      _safeNotify();
      return false;
    }
  }

  Future<bool> uploadImage(int propertyId, File image, String? roomTag) async {
    final result = await uploadImageWithResult(propertyId, image, roomTag);
    return result != null;
  }

  /// Same as [uploadImage] but returns the [UploadedImage] so callers can
  /// pick up the AI [UploadedImage.analysisId] when image-AI is enabled.
  Future<UploadedImage?> uploadImageWithResult(
      int propertyId, File image, String? roomTag) async {
    // Clear any stale error so a prior failure doesn't persist into a later
    // successful upload.
    error = null;
    try {
      return await _api.uploadPropertyImage(propertyId, image, roomTag);
    } catch (e) {
      error = e.toString();
      _safeNotify();
      return null;
    }
  }
}
