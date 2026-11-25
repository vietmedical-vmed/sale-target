-- Rollback 20261125100000_hop_dong_theo_nhom (cần gỡ edge action getHopDongNhom trước).
drop function if exists public.get_quota_hop_dong_nhom(text, text, text, text, text, text, text, text[]);
