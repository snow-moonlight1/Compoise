/// Quadrant constants shared across the app (values mirror the web app).
library;

const int qDo = 1;
const int qPlan = 2;
const int qDelegate = 3;
const int qEliminate = 4;

const List<int> allQuadrants = [qDo, qPlan, qDelegate, qEliminate];

/// Per-quadrant display colors (match the web palette).
const Map<int, int> quadrantColors = {
  qDo: 0xFFFF6B6B, // red
  qPlan: 0xFF4ECDC4, // teal
  qDelegate: 0xFFFFBE0B, // yellow
  qEliminate: 0xFFA0AEC0, // grey
};

int normalizeQuadrant(dynamic value) {
  if (value is num &&
      value.isFinite &&
      value == value.toInt() &&
      allQuadrants.contains(value.toInt())) {
    return value.toInt();
  }
  final m = RegExp(r'^[Qq]?([1-4])$').firstMatch(value.toString().trim());
  if (m != null) return int.parse(m.group(1)!);
  return qEliminate;
}
