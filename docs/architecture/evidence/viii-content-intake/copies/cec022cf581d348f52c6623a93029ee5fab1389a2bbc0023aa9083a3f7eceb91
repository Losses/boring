use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;
use std::sync::Arc;


#[derive(Clone, Copy)]
pub struct SortedTable;

impl SortedTable {
    pub fn sorted_table_compare_ints(a: i32, b: i32) -> i32 {
        if a < (b) {
            return -1;
        }
        if a > (b) {
            return 1;
        }
        return 0;
    }

    pub fn sorted_table_compare_strings(a: &UStr, b: &UStr) -> i32 {
        let end_a = i32::from_ne_bytes(u32::try_from(((a).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        let end_b = i32::from_ne_bytes(u32::try_from(((b).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        let mut index_a = 0i32;
        let mut index_b = 0i32;
        while (index_a) < (end_a) && (index_b) < (end_b) {
            let code_a = i32::try_from(u32::from((a)[usize::try_from(index_a).unwrap_or(0)..].first().copied().unwrap_or(0))).unwrap_or(0);
            let code_b = i32::try_from(u32::from((b)[usize::try_from(index_b).unwrap_or(0)..].first().copied().unwrap_or(0))).unwrap_or(0);
            if code_a != code_b {
                if code_a >= 57344 && (code_a) < (65536) && (code_b) >= 65536 {
                    return 1;
                }
                if code_b >= 57344 && (code_b) < (65536) && (code_a) >= 65536 {
                    return -1;
                }
                if code_a < (code_b) {
                    return -1;
                }
                return 1;
            }
            index_a = i32::from_ne_bytes(u32::try_from((usize::try_from(index_a).unwrap_or(0) + 1) & 4294967295).unwrap_or(0).to_ne_bytes());
            index_b = i32::from_ne_bytes(u32::try_from((usize::try_from(index_b).unwrap_or(0) + 1) & 4294967295).unwrap_or(0).to_ne_bytes());
        }
        if index_a < (end_a) {
            return 1;
        }
        if index_b < (end_b) {
            return -1;
        }
        return 0;
    }

    pub fn sorted_table_map_builder<K: Clone, V: Clone>(compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> SortedMapTableBuilder<K, V> {
        return SortedMapTableBuilder::<K, V>::new(Vec::new().to_vec(), Vec::new().to_vec(), (compare).clone());
    }

    pub fn sorted_table_set_builder<K: Clone>(compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> SortedSetTableBuilder<K> {
        return SortedSetTableBuilder::<K>::new(Vec::new().to_vec(), (compare).clone());
    }
}

#[derive(Clone)]
pub struct SortedMapTable<K, V> {
    pub(crate) keys: Vec<K>,
    pub(crate) values: Vec<V>,
    pub(crate) compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>,
}

impl<K: PartialEq, V: PartialEq> PartialEq for SortedMapTable<K, V> {
    fn eq(&self, other: &Self) -> bool {
        self.keys == other.keys && self.values == other.values
    }
}
impl<K: Clone, V: Clone> SortedMapTable<K, V> {
    pub fn new(keys: Vec<K>, values: Vec<V>, compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> Self {
        Self {
            keys,
            values,
            compare,
        }
    }

    pub fn get(&self, key: &K) -> Option<V> {
        let index = self.locate(key);
        if index < (0) {
            return None;
        }
        return Some(((self.values[usize::try_from(index).unwrap_or(0)]).clone()).clone());
    }

    pub fn has(&self, key: &K) -> bool {
        return (self.locate(key)) >= 0;
    }

    pub fn size(&self) -> i32 {
        return i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
    }

    pub fn key_at(&self, index: i32) -> K {
        return ((self.keys[usize::try_from(index).unwrap_or(0)]).clone()).clone();
    }

    pub fn value_at(&self, index: i32) -> V {
        return ((self.values[usize::try_from(index).unwrap_or(0)]).clone()).clone();
    }

    fn locate(&self, key: &K) -> i32 {
        let mut low = 0i32;
        let mut high = i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        while (low) < (high) {
            let mid = i32::wrapping_add(low, high) >> 1;
            let order = (self.compare)(&((self.keys[usize::try_from(mid).unwrap_or(0)]).clone()), key);
            if order < (0) {
                low = i32::wrapping_add(mid, 1);
            } else {
                if order > (0) {
                    high = mid;
                } else {
                    return mid;
                }
            }
        }
        return -1;
    }
}

impl<K: Clone + std::fmt::Debug, V: Clone + std::fmt::Debug> SortedMapTable<K, V> {
    pub fn to_string(&self) -> UString {
        let mut out = UString::from("{").to_ustring();
        let mut i = 0i32;
        while (i) < (i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes())) {
            if i > (0) {
                out += &(UString::from(", "));
            }
            out += &({ let mut __s = UString::new(); __s += UString::from(format!("{}", format!("{:?}", (self.keys[usize::try_from(i).unwrap_or(0)]).clone())).as_str()).as_ustr(); __s += &(UString::from("=")); __s += UString::from(format!("{}", format!("{:?}", (self.values[usize::try_from(i).unwrap_or(0)]).clone())).as_str()).as_ustr(); __s });
            i = i32::wrapping_add(i, 1);
        }
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += out.as_ustr(); __s += &(UString::from("}")); __s }).as_str());
    }
}

#[derive(Clone)]
pub struct SortedMapTableBuilder<K, V> {
    pub(crate) keys: Vec<K>,
    pub(crate) values: Vec<V>,
    pub(crate) compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>,
}

impl<K: Clone, V: Clone> SortedMapTableBuilder<K, V> {
    pub fn new(keys: Vec<K>, values: Vec<V>, compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> Self {
        Self {
            keys,
            values,
            compare,
        }
    }

    pub fn put(&mut self, key: &K, value: &V) {
        self.keys.push((*key).clone());
        self.values.push((*value).clone());
    }

    pub fn get(&self, key: &K) -> Option<V> {
        let mut index = i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        while (index) > (0) {
            index = i32::wrapping_sub(index, 1);
            if (self.compare)(&((self.keys[usize::try_from(index).unwrap_or(0)]).clone()), key) == 0 {
                return Some(((self.values[usize::try_from(index).unwrap_or(0)]).clone()).clone());
            }
        }
        return None;
    }

    pub fn build(self) -> SortedMapTable<K, V> {
        let total = i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        let mut order: Vec<i32> = Vec::new();
        let mut i = 0i32;
        while (i) < (total) {
            order.push(i);
            i = i32::wrapping_add(i, 1);
        }
        i = 1i32;
        while (i) < (total) {
            let current = order[usize::try_from(i).unwrap_or(0)];
            let mut j = i;
            let mut moved = true;
            while (j) > (0) && moved {
                if (self.compare)(&((self.keys[usize::try_from(order[usize::try_from(i32::wrapping_sub(j, 1)).unwrap_or(0)]).unwrap_or(0)]).clone()), &((self.keys[usize::try_from(current).unwrap_or(0)]).clone())) > (0) {
                    { while order.len() <= usize::try_from(j).unwrap_or(0) { order.push(0); } order[usize::try_from(j).unwrap_or(0)] = order[usize::try_from(i32::wrapping_sub(j, 1)).unwrap_or(0)]; };
                    j = i32::wrapping_sub(j, 1);
                } else {
                    moved = false;
                }
            }
            { while order.len() <= usize::try_from(j).unwrap_or(0) { order.push(0); } order[usize::try_from(j).unwrap_or(0)] = current; };
            i = i32::wrapping_add(i, 1);
        }
        let mut out_keys: Vec<K> = Vec::new();
        let mut out_values: Vec<V> = Vec::new();
        i = 0i32;
        while (i) < (total) {
            let mut run = i;
            while (i32::wrapping_add(run, 1)) < (total) && (self.compare)(&((self.keys[usize::try_from(order[usize::try_from(i32::wrapping_add(run, 1)).unwrap_or(0)]).unwrap_or(0)]).clone()), &((self.keys[usize::try_from(order[usize::try_from(i).unwrap_or(0)]).unwrap_or(0)]).clone())) == 0 {
                run = i32::wrapping_add(run, 1);
            }
            out_keys.push((self.keys[usize::try_from(order[usize::try_from(run).unwrap_or(0)]).unwrap_or(0)]).clone());
            out_values.push((self.values[usize::try_from(order[usize::try_from(run).unwrap_or(0)]).unwrap_or(0)]).clone());
            i = i32::wrapping_add(run, 1);
        }
        return SortedMapTable::<K, V>::new(out_keys.to_vec(), out_values.to_vec(), (self.compare).clone());
    }
}

#[derive(Clone)]
pub struct SortedSetTable<K> {
    pub(crate) keys: Vec<K>,
    pub(crate) compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>,
}

impl<K: PartialEq> PartialEq for SortedSetTable<K> {
    fn eq(&self, other: &Self) -> bool {
        self.keys == other.keys
    }
}
impl<K: Clone> SortedSetTable<K> {
    pub fn new(keys: Vec<K>, compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> Self {
        Self {
            keys,
            compare,
        }
    }

    pub fn has(&self, key: &K) -> bool {
        return (self.locate(key)) >= 0;
    }

    pub fn size(&self) -> i32 {
        return i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
    }

    pub fn at(&self, index: i32) -> K {
        return ((self.keys[usize::try_from(index).unwrap_or(0)]).clone()).clone();
    }

    fn locate(&self, key: &K) -> i32 {
        let mut low = 0i32;
        let mut high = i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        while (low) < (high) {
            let mid = i32::wrapping_add(low, high) >> 1;
            let order = (self.compare)(&((self.keys[usize::try_from(mid).unwrap_or(0)]).clone()), key);
            if order < (0) {
                low = i32::wrapping_add(mid, 1);
            } else {
                if order > (0) {
                    high = mid;
                } else {
                    return mid;
                }
            }
        }
        return -1;
    }
}

impl<K: Clone + std::fmt::Debug> SortedSetTable<K> {
    pub fn to_string(&self) -> UString {
        let mut out = UString::from("[").to_ustring();
        let mut i = 0i32;
        while (i) < (i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes())) {
            if i > (0) {
                out += &(UString::from(", "));
            }
            out += &(format!("{:?}", (self.keys[usize::try_from(i).unwrap_or(0)]).clone()));
            i = i32::wrapping_add(i, 1);
        }
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += out.as_ustr(); __s += &(UString::from("]")); __s }).as_str());
    }
}

#[derive(Clone)]
pub struct SortedSetTableBuilder<K> {
    pub(crate) keys: Vec<K>,
    pub(crate) compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>,
}

impl<K: Clone> SortedSetTableBuilder<K> {
    pub fn new(keys: Vec<K>, compare: Arc<dyn Fn(&K, &K) -> i32 + Send + Sync>) -> Self {
        Self {
            keys,
            compare,
        }
    }

    pub fn put(&mut self, key: &K) {
        self.keys.push((*key).clone());
    }

    pub fn build(self) -> SortedSetTable<K> {
        let total = i32::from_ne_bytes(u32::try_from((((self.keys).clone()).len()) & 4294967295).unwrap_or(0).to_ne_bytes());
        let mut order: Vec<i32> = Vec::new();
        let mut i = 0i32;
        while (i) < (total) {
            order.push(i);
            i = i32::wrapping_add(i, 1);
        }
        i = 1i32;
        while (i) < (total) {
            let current = order[usize::try_from(i).unwrap_or(0)];
            let mut j = i;
            let mut moved = true;
            while (j) > (0) && moved {
                if (self.compare)(&((self.keys[usize::try_from(order[usize::try_from(i32::wrapping_sub(j, 1)).unwrap_or(0)]).unwrap_or(0)]).clone()), &((self.keys[usize::try_from(current).unwrap_or(0)]).clone())) > (0) {
                    { while order.len() <= usize::try_from(j).unwrap_or(0) { order.push(0); } order[usize::try_from(j).unwrap_or(0)] = order[usize::try_from(i32::wrapping_sub(j, 1)).unwrap_or(0)]; };
                    j = i32::wrapping_sub(j, 1);
                } else {
                    moved = false;
                }
            }
            { while order.len() <= usize::try_from(j).unwrap_or(0) { order.push(0); } order[usize::try_from(j).unwrap_or(0)] = current; };
            i = i32::wrapping_add(i, 1);
        }
        let mut out_keys: Vec<K> = Vec::new();
        i = 0i32;
        while (i) < (total) {
            let mut run = i;
            while (i32::wrapping_add(run, 1)) < (total) && (self.compare)(&((self.keys[usize::try_from(order[usize::try_from(i32::wrapping_add(run, 1)).unwrap_or(0)]).unwrap_or(0)]).clone()), &((self.keys[usize::try_from(order[usize::try_from(i).unwrap_or(0)]).unwrap_or(0)]).clone())) == 0 {
                run = i32::wrapping_add(run, 1);
            }
            out_keys.push((self.keys[usize::try_from(order[usize::try_from(run).unwrap_or(0)]).unwrap_or(0)]).clone());
            i = i32::wrapping_add(run, 1);
        }
        return SortedSetTable::<K>::new(out_keys.to_vec(), (self.compare).clone());
    }
}
