use crate::runtime::bytes_buffer::BytesBuffer;


pub struct Sha256 {
    pub(crate) state: Vec<u32>,
    pub(crate) block: Vec<u8>,
    pub(crate) block_pos: u32,
    pub(crate) total_length: u32,
}

impl Sha256 {
    pub fn new() -> Self {
        Self {
            state: vec![
    1779033703,
    3144134277u32,
    1013904242,
    2773480762u32,
    1359893119,
    2600822924u32,
    528734635,
    1541459225,
],
            block: vec![0u8; 64usize],
            block_pos: 0,
            total_length: 0,
        }
    }

    pub fn update(&mut self, data: &[u8]) {
        let mut source_pos = 0u32;
        while (i32::from_ne_bytes(((source_pos) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((u32::try_from((data.len()) & 0xFFFF_FFFF).unwrap_or(0)) as i32).to_ne_bytes())) {
            self.block[usize::try_from(self.block_pos).unwrap_or(0)] = u8::try_from((u32::from(data[usize::try_from(source_pos).unwrap_or(0)])) & 0xFF).unwrap_or(0);
            self.block_pos += 1;
            source_pos = u32::wrapping_add(source_pos, 1);
            self.total_length += 1;
            if self.block_pos == 64 {
                Sha256::sha256_process_block(&mut self.state, &self.block);
                self.block_pos = 0u32;
            }
        }
    }

    pub fn digest(&self) -> Vec<u8> {
        let mut final_state: Vec<u32> = vec![];
        {
            final_state.push(self.state[0usize]);
            final_state.push(self.state[1usize]);
            final_state.push(self.state[2usize]);
            final_state.push(self.state[3usize]);
            final_state.push(self.state[4usize]);
            final_state.push(self.state[5usize]);
            final_state.push(self.state[6usize]);
            final_state.push(self.state[7usize]);
        }
        let mut final_block = vec![0u8; 64usize];
        for i in 0..64 {
            final_block[usize::try_from(i).unwrap_or(0)] = 0u8;
        }
        for i in 0..self.block_pos {
            final_block[usize::try_from(i).unwrap_or(0)] = u8::try_from((u32::from((self.block).clone()[usize::try_from(i).unwrap_or(0)])) & 0xFF).unwrap_or(0);
        }
        final_block[usize::try_from(self.block_pos).unwrap_or(0)] = 128u8;
        let position = u32::wrapping_add(self.block_pos, 1);
        if i32::from_ne_bytes(((position) as i32).to_ne_bytes()) > (56) {
            Sha256::sha256_process_block(&mut final_state, &final_block);
            for i in 0..56 {
                final_block[usize::try_from(i).unwrap_or(0)] = 0u8;
            }
        } else {
            for i in position..56 {
                final_block[usize::try_from(i).unwrap_or(0)] = 0u8;
            }
        }
        final_block[56usize] = 0u8;
        final_block[57usize] = 0u8;
        final_block[58usize] = 0u8;
        final_block[59usize] = 0u8;
        final_block[60usize] = u8::try_from((self.total_length >> 21 & 255) & 0xFF).unwrap_or(0);
        final_block[61usize] = u8::try_from((self.total_length >> 13 & 255) & 0xFF).unwrap_or(0);
        final_block[62usize] = u8::try_from((self.total_length >> 5 & 255) & 0xFF).unwrap_or(0);
        final_block[63usize] = u8::try_from(((self.total_length) << (3)) & 0xFF).unwrap_or(0);
        Sha256::sha256_process_block(&mut final_state, &final_block);
        let mut output = BytesBuffer::new();
        {
            {
                output.add_byte(u8::try_from((final_state[0usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[0usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[0usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[0usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[1usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[1usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[1usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[1usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[2usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[2usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[2usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[2usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[3usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[3usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[3usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[3usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[4usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[4usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[4usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[4usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[5usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[5usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[5usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[5usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[6usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[6usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[6usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[6usize]) & 0xFF).unwrap_or(0));
            }
            {
                output.add_byte(u8::try_from((final_state[7usize] >> 24) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[7usize] >> 16) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[7usize] >> 8) & 0xFF).unwrap_or(0));
                output.add_byte(u8::try_from((final_state[7usize]) & 0xFF).unwrap_or(0));
            }
        }
        return output.get_bytes();
    }

    pub fn sha256_make(data: &[u8]) -> Vec<u8> {
        let mut hash = Sha256::new();
        hash.update(&data);
        return hash.digest();
    }

    pub(crate) fn sha256_process_block(hash: &mut Vec<u32>, input: &[u8]) {
        let mut words: Vec<u32> = vec![];
        for _ in 0..64 {
            words.push(0);
        }
        for i in 0..16 {
            let offset = u32::wrapping_mul(i, 4);
            { while words.len() <= usize::try_from(i).unwrap_or(0) { words.push(0); } words[usize::try_from(i).unwrap_or(0)] = u32::from_be_bytes([
    (input[usize::try_from(offset).unwrap_or(0)]),
    (input[usize::try_from(offset + 1).unwrap_or(0)]),
    (input[usize::try_from(offset + 2).unwrap_or(0)]),
    (input[usize::try_from(offset + 3).unwrap_or(0)])
]); };
        }
        for i in 16..64 {
            { while words.len() <= usize::try_from(i).unwrap_or(0) { words.push(0); } words[usize::try_from(i).unwrap_or(0)] = Sha256::sha256_safe_add(Sha256::sha256_safe_add(Sha256::sha256_safe_add(Sha256::sha256_gamma1(words[usize::try_from(u32::wrapping_sub(i, 2)).unwrap_or(0)]), words[usize::try_from(u32::wrapping_sub(i, 7)).unwrap_or(0)]), Sha256::sha256_gamma0(words[usize::try_from(u32::wrapping_sub(i, 15)).unwrap_or(0)])), words[usize::try_from(u32::wrapping_sub(i, 16)).unwrap_or(0)]); };
        }
        let mut a = hash[0usize];
        let mut b = hash[1usize];
        let mut c = hash[2usize];
        let mut d = hash[3usize];
        let mut e = hash[4usize];
        let mut f = hash[5usize];
        let mut g = hash[6usize];
        let mut h = hash[7usize];
        let k = vec![
    1116352408,
    1899447441,
    3049323471u32,
    3921009573u32,
    961987163,
    1508970993,
    2453635748u32,
    2870763221u32,
    3624381080u32,
    310598401,
    607225278,
    1426881987,
    1925078388,
    2162078206u32,
    2614888103u32,
    3248222580u32,
    3835390401u32,
    4022224774u32,
    264347078,
    604807628,
    770255983,
    1249150122,
    1555081692,
    1996064986,
    2554220882u32,
    2821834349u32,
    2952996808u32,
    3210313671u32,
    3336571891u32,
    3584528711u32,
    113926993,
    338241895,
    666307205,
    773529912,
    1294757372,
    1396182291,
    1695183700,
    1986661051,
    2177026350u32,
    2456956037u32,
    2730485921u32,
    2820302411u32,
    3259730800u32,
    3345764771u32,
    3516065817u32,
    3600352804u32,
    4094571909u32,
    275423344,
    430227734,
    506948616,
    659060556,
    883997877,
    958139571,
    1322822218,
    1537002063,
    1747873779,
    1955562222,
    2024104815,
    2227730452u32,
    2361852424u32,
    2428436474u32,
    2756734187u32,
    3204031479u32,
    3329325298u32,
];
        for i in 0..64 {
            let t1 = Sha256::sha256_safe_add(Sha256::sha256_safe_add(Sha256::sha256_safe_add(Sha256::sha256_safe_add(h, Sha256::sha256_sigma1(e)), Sha256::sha256_choose(e, f, g)), k[usize::try_from(i).unwrap_or(0)]), words[usize::try_from(i).unwrap_or(0)]);
            let t2 = Sha256::sha256_safe_add(Sha256::sha256_sigma0(a), Sha256::sha256_majority(a, b, c));
            h = g;
            g = f;
            f = e;
            e = Sha256::sha256_safe_add(d, t1);
            d = c;
            c = b;
            b = a;
            a = Sha256::sha256_safe_add(t1, t2);
        }
        { while hash.len() <= 0usize { hash.push(0); } hash[0usize] = Sha256::sha256_safe_add(hash[0usize], a); };
        { while hash.len() <= 1usize { hash.push(0); } hash[1usize] = Sha256::sha256_safe_add(hash[1usize], b); };
        { while hash.len() <= 2usize { hash.push(0); } hash[2usize] = Sha256::sha256_safe_add(hash[2usize], c); };
        { while hash.len() <= 3usize { hash.push(0); } hash[3usize] = Sha256::sha256_safe_add(hash[3usize], d); };
        { while hash.len() <= 4usize { hash.push(0); } hash[4usize] = Sha256::sha256_safe_add(hash[4usize], e); };
        { while hash.len() <= 5usize { hash.push(0); } hash[5usize] = Sha256::sha256_safe_add(hash[5usize], f); };
        { while hash.len() <= 6usize { hash.push(0); } hash[6usize] = Sha256::sha256_safe_add(hash[6usize], g); };
        { while hash.len() <= 7usize { hash.push(0); } hash[7usize] = Sha256::sha256_safe_add(hash[7usize], h); };
    }

    pub(crate) fn sha256_rotate(value: u32, distance: u32) -> u32 {
        return value >> distance | (value) << (u32::wrapping_sub(32, distance));
    }

    pub(crate) fn sha256_choose(x: u32, y: u32, z: u32) -> u32 {
        return x & y ^ !x & z;
    }

    pub(crate) fn sha256_majority(x: u32, y: u32, z: u32) -> u32 {
        return x & y ^ x & z ^ y & z;
    }

    pub(crate) fn sha256_sigma0(x: u32) -> u32 {
        return Sha256::sha256_rotate(x, 2) ^ Sha256::sha256_rotate(x, 13) ^ Sha256::sha256_rotate(x, 22);
    }

    pub(crate) fn sha256_sigma1(x: u32) -> u32 {
        return Sha256::sha256_rotate(x, 6) ^ Sha256::sha256_rotate(x, 11) ^ Sha256::sha256_rotate(x, 25);
    }

    pub(crate) fn sha256_gamma0(x: u32) -> u32 {
        return Sha256::sha256_rotate(x, 7) ^ Sha256::sha256_rotate(x, 18) ^ x >> 3;
    }

    pub(crate) fn sha256_gamma1(x: u32) -> u32 {
        return Sha256::sha256_rotate(x, 17) ^ Sha256::sha256_rotate(x, 19) ^ x >> 10;
    }

    pub(crate) fn sha256_safe_add(x: u32, y: u32) -> u32 {
        let low = u32::wrapping_add(x & 65535, y & 65535);
        let high = u32::wrapping_add(u32::wrapping_add(x >> 16, y >> 16), low >> 16);
        return (high) << (16) | low & 65535;
    }
}
