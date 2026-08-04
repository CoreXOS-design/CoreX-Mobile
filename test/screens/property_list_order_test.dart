import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/property.dart';
import 'package:corex_mobile/screens/properties/property_list_screen.dart';

Property _p(int id, String? status) =>
    Property(id: id, address: 'Street $id', status: status);

List<int> _ids(List<Property> ps) => ps.map((p) => p.id).toList();

void main() {
  test('active listings lead the list', () {
    final result = activeFirst([
      _p(1, 'sold'),
      _p(2, 'active'),
      _p(3, 'draft'),
      _p(4, 'active'),
    ]);

    expect(_ids(result), [2, 4, 1, 3]);
  });

  test('order within each group is left as the server sent it', () {
    final result = activeFirst([
      _p(10, 'active'),
      _p(11, 'sold'),
      _p(12, 'active'),
      _p(13, 'under_offer'),
      _p(14, 'sold'),
    ]);

    expect(_ids(result), [10, 12, 11, 13, 14]);
  });

  test('status casing and padding still count as active', () {
    final result = activeFirst([
      _p(1, 'sold'),
      _p(2, ' Active '),
      _p(3, 'ACTIVE'),
    ]);

    expect(_ids(result), [2, 3, 1]);
  });

  test('a missing status is not treated as active', () {
    final result = activeFirst([_p(1, null), _p(2, 'active')]);

    expect(_ids(result), [2, 1]);
  });

  test('an empty list stays empty', () {
    expect(activeFirst(const <Property>[]), isEmpty);
  });
}
