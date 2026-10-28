#[derive(Clone, Copy)]
pub struct GraphemeWalk;

impl GraphemeWalk {
    pub fn grapheme_walk_lookup(table: &[i32], code: i32) -> i32 {
        let range_count = i32::from_ne_bytes(u32::try_from(((table).len()) & 4294967295).unwrap_or(0).to_ne_bytes()) / (3);
        let mut lo = 0i32;
        let mut hi = i32::wrapping_sub(range_count, 1);
        while (lo) <= hi {
            let mid = i32::wrapping_add(lo, hi) >> 1;
            let base = i32::wrapping_mul(mid, 3);
            if code < (table[usize::try_from(base).unwrap_or(0)]) {
                hi = i32::wrapping_sub(mid, 1);
            } else {
                if code > (table[usize::try_from(i32::wrapping_add(base, 1)).unwrap_or(0)]) {
                    lo = i32::wrapping_add(mid, 1);
                } else {
                    return table[usize::try_from(i32::wrapping_add(base, 2)).unwrap_or(0)];
                }
            }
        }
        return 0;
    }

    pub fn grapheme_walk_breaks_before(prev: i32, cur: i32, state: i32) -> bool {
        let pc = prev & 15;
        let cc = cur & 15;
        if pc == 1 && cc == 2 {
            return false;
        }
        if pc == 1 || pc == 2 || pc == 3 {
            return true;
        }
        if cc == 1 || cc == 2 || cc == 3 {
            return true;
        }
        if pc == 9 && (cc == 9 || cc == 10 || cc == 12 || cc == 13) {
            return false;
        }
        if (pc == 10 || pc == 12) && (cc == 10 || cc == 11) {
            return false;
        }
        if (pc == 11 || pc == 13) && cc == 11 {
            return false;
        }
        if cc == 4 || cc == 5 {
            return false;
        }
        if cc == 8 {
            return false;
        }
        if pc == 7 {
            return false;
        }
        if cur & 32 != 0 && (state >> 2 & 3) == 2 {
            return false;
        }
        if cur & 16 != 0 && (state & 3) == 2 {
            return false;
        }
        if cc == 6 && (state & 16) != 0 {
            return false;
        }
        return true;
    }

    pub fn grapheme_walk_advance_state(cur: i32, state: i32) -> i32 {
        let cc = cur & 15;
        let mut pict = state & 3;
        let mut incb = state >> 2 & 3;
        let mut ri_odd = state & 16 != 0;
        if cur & 16 != 0 {
            pict = 1i32;
        } else {
            if cc == 5 {
                pict = if pict == 1 { 2 } else { 0 };
            } else {
                if cc == 4 {
                    if pict != 1 {
                        pict = 0i32;
                    }
                } else {
                    pict = 0i32;
                }
            }
        }
        let incb_value = cur & 96;
        if incb_value == 32 {
            incb = 1i32;
        } else {
            if incb_value == 64 {
                incb = if incb >= 1 { 2 } else { 0 };
            } else {
                if incb_value != 96 {
                    incb = 0i32;
                }
            }
        }
        ri_odd = if cc == 6 { !ri_odd } else { false };
        return (if ri_odd { 16 } else { 0 }) | (incb) << (2) | pict;
    }

    pub fn grapheme_walk_boundary_flags(table: &[i32], codes: &[i32]) -> Vec<bool> {
        let mut flags: Vec<bool> = vec![];
        let mut prev = -1i32;
        let mut state = 0i32;
        for index in 0..match u32::try_from(codes.len()) { Ok(value) => value, Err(_) => u32::MAX } {
            let packed = GraphemeWalk::grapheme_walk_lookup(&table, codes[usize::try_from(index).unwrap_or(0)]);
            flags.push((prev) < (0) || GraphemeWalk::grapheme_walk_breaks_before(prev, packed, state));
            state = GraphemeWalk::grapheme_walk_advance_state(packed, state);
            prev = packed;
        }
        return flags;
    }
}
