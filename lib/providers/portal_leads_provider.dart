import 'package:flutter/foundation.dart';
import '../models/portal_lead.dart';
import '../services/api_service.dart';

class PortalLeadsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<PortalLeadDate> _dates = [];
  List<PortalLead> _leads = [];
  String? _selectedDate;
  bool _loadingLeads = false;
  bool _loadingDates = false;
  String? _error;

  List<PortalLeadDate> get dates => List.unmodifiable(_dates);
  List<PortalLead> get leads => List.unmodifiable(_leads);
  String? get selectedDate => _selectedDate;
  bool get loadingLeads => _loadingLeads;
  bool get loadingDates => _loadingDates;
  String? get error => _error;

  int get totalUnread =>
      _dates.fold<int>(0, (sum, d) => sum + d.unread);

  static String today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> loadDates() async {
    _loadingDates = true;
    notifyListeners();
    try {
      _dates = await _api.getPortalLeadDates();
    } catch (e) {
      debugPrint('[portal-leads] loadDates failed: $e');
    }
    _loadingDates = false;
    notifyListeners();
  }

  Future<void> loadLeads({String? date}) async {
    final d = date ?? _selectedDate ?? today();
    _selectedDate = d;
    _loadingLeads = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.getPortalLeads(date: d);
      _leads = res.leads;
    } catch (e) {
      _error = e.toString();
      _leads = [];
    }
    _loadingLeads = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait([loadDates(), loadLeads()]);
  }

  Future<void> markRead(int id) async {
    final idx = _leads.indexWhere((l) => l.id == id);
    if (idx >= 0 && _leads[idx].isUnread) {
      _leads[idx] = _leads[idx].copyWith(isUnread: false);
      final dateIdx = _dates.indexWhere((d) => d.date == _selectedDate);
      if (dateIdx >= 0 && _dates[dateIdx].unread > 0) {
        _dates[dateIdx] = PortalLeadDate(
          date: _dates[dateIdx].date,
          total: _dates[dateIdx].total,
          unread: _dates[dateIdx].unread - 1,
        );
      }
      notifyListeners();
    }
    try {
      await _api.markPortalLeadRead(id);
    } catch (e) {
      debugPrint('[portal-leads] markRead failed: $e');
    }
  }

  void bumpUnread() {
    final t = today();
    final idx = _dates.indexWhere((d) => d.date == t);
    if (idx >= 0) {
      _dates[idx] = PortalLeadDate(
        date: t,
        total: _dates[idx].total + 1,
        unread: _dates[idx].unread + 1,
      );
    } else {
      _dates = [PortalLeadDate(date: t, total: 1, unread: 1), ..._dates];
    }
    notifyListeners();
  }

  void reset() {
    _dates = [];
    _leads = [];
    _selectedDate = null;
    _error = null;
    notifyListeners();
  }
}
