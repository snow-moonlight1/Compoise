class CountProgressException extends FormatException {
  const CountProgressException() : super('Invalid count progress');
}

/// Progress on one task, independent of dates and calendar recurrence.
class CountProgress {
  static const maxValue = 2147483647;

  CountProgress({this.value = 0, this.target}) {
    if (value < 0 ||
        value > maxValue ||
        (target != null &&
            (target! < 1 || target! > maxValue || value > target!))) {
      throw const CountProgressException();
    }
  }

  final int value;
  final int? target;
  bool get reached => target != null && value >= target!;

  factory CountProgress.fromJson(Object raw) {
    if (raw is! Map ||
        raw.keys.any((k) => k != 'value' && k != 'target') ||
        raw['value'] is! int ||
        (raw['target'] != null && raw['target'] is! int)) {
      throw const CountProgressException();
    }
    return CountProgress(
      value: raw['value'] as int,
      target: raw['target'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    if (target != null) 'target': target,
  };

  @override
  bool operator ==(Object other) =>
      other is CountProgress && other.value == value && other.target == target;
  @override
  int get hashCode => Object.hash(value, target);
}
