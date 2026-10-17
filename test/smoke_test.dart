import 'package:flutter_test/flutter_test.dart';
import 'package:crew/state/models.dart';

void main() {
  test('byte formatter is stable for common traffic values', () {
    expect(formatBytes(0), '0 Б');
    expect(formatBytes(1024), '1.0 КБ');
    expect(formatBytes(1048576), '1.0 МБ');
  });

  test('duration formatter does not produce negative or empty output', () {
    expect(formatDuration(const Duration(seconds: 9)), '00:09');
    expect(formatDuration(const Duration(minutes: 2, seconds: 3)), '02:03');
  });
}
