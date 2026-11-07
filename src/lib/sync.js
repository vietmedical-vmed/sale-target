// Chỉ số các dòng trong một lượt getChanges mà client CHƯA có đúng _rev đó.
// Server đọc lùi vài trăm rev trước con trỏ (bắt transaction commit muộn), nên lượt
// trả về lẫn dòng đã biết — kể cả dòng chính mình vừa ghi; bỏ chúng để không coi là
// thay đổi của người khác. `known`: Map id → _rev.
export function pickUnknown(known, nums, revs) {
  const idx = [];
  const n = (nums || []).length;
  for (let i = 0; i < n; i++) {
    if (!nums[i] || known.get(nums[i]) !== (revs || [])[i]) idx.push(i);
  }
  return idx;
}

// Id bị xoá mà client đang giữ (tombstone đọc lùi có thể nhắc lại id đã gỡ).
export function pickKnownDeleted(known, ids) {
  return (ids || []).filter((id) => known.has(id));
}
