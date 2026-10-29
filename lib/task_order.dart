/// Drag reorder: the task a drop at [slot] lands in front of.
///
/// [rowIds] are the rows shown in the target quadrant, top to bottom, and
/// [slot] is a gap index between them (0 = above the first row,
/// `rowIds.length` = below the last). Rows that are themselves being moved
/// are skipped. Null means "after the last row".
String? dropAnchor(List<String> rowIds, int slot, Set<String> moving) {
  for (var i = slot < 0 ? 0 : slot; i < rowIds.length; i++) {
    if (!moving.contains(rowIds[i])) return rowIds[i];
  }
  return null;
}
