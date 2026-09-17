-- GĐ 2.1: Incremental sync — _rev sequence, tombstone table, triggers, indexes
-- Mỗi INSERT/UPDATE trên sale_target gán _rev mới từ sequence.
-- Mỗi DELETE ghi vào sale_target_tombstone với _rev mới.
-- Client poll getChanges(sinceRev) thay vì tải lại toàn bộ.

SET search_path = shared, public;

-- 1. Sequence
CREATE SEQUENCE IF NOT EXISTS sale_target_rev_seq;

-- 2. Add _rev column with default
ALTER TABLE sale_target ADD COLUMN _rev bigint;
UPDATE sale_target SET _rev = nextval('sale_target_rev_seq');
ALTER TABLE sale_target ALTER COLUMN _rev SET NOT NULL;
ALTER TABLE sale_target ALTER COLUMN _rev SET DEFAULT nextval('sale_target_rev_seq');

-- 3. Trigger: auto-set _rev on every INSERT/UPDATE
CREATE OR REPLACE FUNCTION sale_target_set_rev()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW._rev := nextval('shared.sale_target_rev_seq');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sale_target_set_rev
  BEFORE INSERT OR UPDATE ON sale_target
  FOR EACH ROW EXECUTE FUNCTION sale_target_set_rev();

-- 4. Tombstone table — records deleted rows for incremental sync
CREATE TABLE sale_target_tombstone (
  id       bigint  NOT NULL,
  bu       text,
  ps       text,
  mien     text,
  nhom_san_pham text,
  _rev     bigint  NOT NULL
);

-- 5. Trigger: on DELETE, insert tombstone with new _rev
CREATE OR REPLACE FUNCTION sale_target_tombstone_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO sale_target_tombstone (id, bu, ps, mien, nhom_san_pham, _rev)
  VALUES (OLD.id, OLD.bu, OLD.ps, OLD.mien, OLD.nhom_san_pham,
          nextval('shared.sale_target_rev_seq'));
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_sale_target_tombstone
  AFTER DELETE ON sale_target
  FOR EACH ROW EXECUTE FUNCTION sale_target_tombstone_fn();

-- 6. Indexes for getChanges queries: WHERE bu = ? AND _rev > ?
CREATE INDEX idx_sale_target_bu_rev ON sale_target (bu, _rev);
CREATE INDEX idx_tombstone_bu_rev ON sale_target_tombstone (bu, _rev);
CREATE INDEX idx_tombstone_rev ON sale_target_tombstone (_rev);
