import '../schedule_item.dart';
import 'schedule_edit_session.dart';

/// Captures the observed revision before the gesture. A drop cannot recapture
/// a newer revision and accidentally overwrite an intervening external edit.
class ScheduleDragPayload {
  const ScheduleDragPayload(this.item, this.revision, this.mode);
  final ScheduleItem item;
  final int revision;
  final ScheduleEditMode mode;
}
