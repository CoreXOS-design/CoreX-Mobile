import 'dart:io';
import 'package:flutter/material.dart';
import '../models/gallery_tags.dart';
import '../models/property.dart';
import '../models/visibility.dart';
import '../services/api_service.dart';

class PropertyProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

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

  Future<void> fetchProperties({AgentFilter? agentFilter}) async {
    if (agentFilter != null) _agentFilter = agentFilter;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      properties = await _api.getProperties(agentFilter: _agentFilter);
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> fetchProperty(int id) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      selectedProperty = await _api.getProperty(id);
    } on ApiException catch (e) {
      selectedProperty = null;
      error = e.message;
      isLoading = false;
      notifyListeners();
      // Let the screen decide how to surface 403 / not-found (toast + pop).
      rethrow;
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<Property?> createProperty(Map<String, dynamic> data) async {
    isLoading = true;
    error = null;
    fieldErrors = const {};
    notifyListeners();
    try {
      final property = await _api.createProperty(data);
      await fetchProperties();
      return property;
    } on ValidationException catch (e) {
      error = e.message;
      fieldErrors = e.fieldErrors;
      isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateProperty(int id, Map<String, dynamic> data) async {
    isLoading = true;
    error = null;
    fieldErrors = const {};
    notifyListeners();
    try {
      await _api.updateProperty(id, data);
      await fetchProperties();
      return true;
    } on ValidationException catch (e) {
      error = e.message;
      fieldErrors = e.fieldErrors;
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
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
    try {
      return await _api.uploadPropertyImage(propertyId, image, roomTag);
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }
}
