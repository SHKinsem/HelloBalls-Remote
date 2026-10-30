import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/binding/drive_mixer.dart';

void main() {
  test('dead zone and expo', () {
    expect(shapeAxis(0.05), 0);
    expect(shapeAxis(-0.05), 0);
    expect(shapeAxis(1), closeTo(1, 1e-9));
    expect(shapeAxis(-1), closeTo(-1, 1e-9));
    expect(shapeAxis(0.5, expo: 0), closeTo((0.5 - 0.08) / 0.92, 1e-9));
    expect(shapeAxis(0.5, expo: 0.5), lessThan(shapeAxis(0.5, expo: 0)));
  });

  test('differential mix', () {
    expect(mixDifferential(0, 1, maxRpm: 1000), (1000, 1000));
    expect(mixDifferential(0, -1, maxRpm: 1000), (-1000, -1000));
    expect(mixDifferential(1, 0, maxRpm: 1000), (1000, -1000)); // spin right
    expect(mixDifferential(0, 0, maxRpm: 1000), (0, 0));
    final (l, r) = mixDifferential(1, 1, maxRpm: 1000); // never exceeds max
    expect(l, 1000);
    expect(r, 0);
  });
}
