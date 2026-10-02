//! Parses Lua table literals as data. No interpreter, expressions, or calls.
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Table(BTreeMap<Key, Value>),
    String(String),
    Number(f64),
    Bool(bool),
    Nil,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Key {
    Name(String),
    Index(u64),
}

impl Value {
    pub fn field(&self, name: &str) -> Option<&Value> {
        match self {
            Self::Table(t) => t.get(&Key::Name(name.into())),
            _ => None,
        }
    }
    pub fn text(&self) -> Option<&str> {
        match self {
            Self::String(s) => Some(s),
            _ => None,
        }
    }
    pub fn integer(&self) -> Option<u64> {
        match self {
            Self::Number(n)
                if n.is_finite()
                    && *n >= 0.0
                    && *n <= 9_007_199_254_740_991.0
                    && n.fract() == 0.0 =>
            {
                Some(*n as u64)
            }
            _ => None,
        }
    }
}

pub const MAX_BYTES: usize = 32 * 1024 * 1024;

pub fn parse(input: &str) -> Result<Value, String> {
    if input.len() > MAX_BYTES {
        return Err("SavedVariables exceeds the 32 MiB limit".into());
    }
    let mut p = Parser {
        bytes: input.as_bytes(),
        pos: 0,
        nodes: 0,
    };
    p.space();
    if p.identifier()? != "AzerothChronicleDB" {
        return Err("Expected AzerothChronicleDB assignment".into());
    }
    p.expect(b'=')?;
    let value = p.value(0)?;
    p.space();
    if p.pos != p.bytes.len() {
        return Err(p.error("Unexpected trailing code"));
    }
    if !matches!(value, Value::Table(_)) {
        return Err("Expected a database table".into());
    }
    Ok(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
    nodes: usize,
}
impl Parser<'_> {
    fn error(&self, message: &str) -> String {
        format!("{message} at byte {}", self.pos)
    }
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }
    fn space(&mut self) {
        loop {
            while self.peek().is_some_and(|c| c.is_ascii_whitespace()) {
                self.pos += 1;
            }
            if self.bytes.get(self.pos..self.pos + 2) == Some(b"--") {
                while self.peek().is_some_and(|c| c != b'\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }
    fn expect(&mut self, byte: u8) -> Result<(), String> {
        self.space();
        if self.peek() != Some(byte) {
            return Err(self.error("Unexpected token"));
        }
        self.pos += 1;
        Ok(())
    }
    fn identifier(&mut self) -> Result<String, String> {
        self.space();
        let start = self.pos;
        if !self
            .peek()
            .is_some_and(|c| c.is_ascii_alphabetic() || c == b'_')
        {
            return Err(self.error("Expected identifier"));
        }
        self.pos += 1;
        while self
            .peek()
            .is_some_and(|c| c.is_ascii_alphanumeric() || c == b'_')
        {
            self.pos += 1;
        }
        Ok(String::from_utf8(self.bytes[start..self.pos].to_vec()).unwrap())
    }
    fn string(&mut self) -> Result<String, String> {
        let quote = self.peek().ok_or_else(|| self.error("Missing string"))?;
        self.pos += 1;
        let mut out = Vec::new();
        loop {
            let c = self
                .peek()
                .ok_or_else(|| self.error("Unterminated string"))?;
            self.pos += 1;
            if c == quote {
                break;
            }
            if c == b'\n' || c == b'\r' {
                return Err(self.error("Unescaped newline"));
            }
            if c != b'\\' {
                out.push(c);
                continue;
            }
            let escaped = self.peek().ok_or_else(|| self.error("Incomplete escape"))?;
            self.pos += 1;
            match escaped {
                b'n' => out.push(b'\n'),
                b'r' => out.push(b'\r'),
                b't' => out.push(b'\t'),
                b'a' => out.push(7),
                b'b' => out.push(8),
                b'f' => out.push(12),
                b'v' => out.push(11),
                b'\\' | b'\'' | b'"' => out.push(escaped),
                b'\n' => out.push(b'\n'),
                b'\r' => {
                    if self.peek() == Some(b'\n') {
                        self.pos += 1;
                    }
                    out.push(b'\n');
                }
                b'0'..=b'9' => {
                    let mut n = (escaped - b'0') as u16;
                    for _ in 0..2 {
                        if let Some(d @ b'0'..=b'9') = self.peek() {
                            n = n * 10 + (d - b'0') as u16;
                            self.pos += 1;
                        } else {
                            break;
                        }
                    }
                    out.push(u8::try_from(n).map_err(|_| self.error("Escape exceeds one byte"))?);
                }
                _ => return Err(self.error("Unsupported escape")),
            }
        }
        String::from_utf8(out).map_err(|_| self.error("Invalid UTF-8 string"))
    }
    fn value(&mut self, depth: usize) -> Result<Value, String> {
        self.space();
        self.nodes += 1;
        if depth > 64 || self.nodes > 1_000_000 {
            return Err(self.error("Table complexity limit exceeded"));
        }
        match self.peek() {
            Some(b'{') => self.table(depth + 1),
            Some(b'"' | b'\'') => self.string().map(Value::String),
            Some(b'-' | b'0'..=b'9') => {
                let start = self.pos;
                if self.peek() == Some(b'-') {
                    self.pos += 1;
                }
                let digits = self.pos;
                while self.peek().is_some_and(|c| c.is_ascii_digit()) {
                    self.pos += 1;
                }
                if self.pos == digits {
                    return Err(self.error("Expected number"));
                }
                if self.peek() == Some(b'.') {
                    self.pos += 1;
                    while self.peek().is_some_and(|c| c.is_ascii_digit()) {
                        self.pos += 1;
                    }
                }
                if self.peek().is_some_and(|c| c == b'e' || c == b'E') {
                    self.pos += 1;
                    if self.peek().is_some_and(|c| c == b'+' || c == b'-') {
                        self.pos += 1;
                    }
                    while self.peek().is_some_and(|c| c.is_ascii_digit()) {
                        self.pos += 1;
                    }
                }
                let n: f64 = std::str::from_utf8(&self.bytes[start..self.pos])
                    .unwrap()
                    .parse()
                    .map_err(|_| self.error("Invalid number"))?;
                if !n.is_finite() {
                    return Err(self.error("Non-finite number"));
                }
                Ok(Value::Number(n))
            }
            Some(_) => match self.identifier()?.as_str() {
                "true" => Ok(Value::Bool(true)),
                "false" => Ok(Value::Bool(false)),
                "nil" => Ok(Value::Nil),
                _ => Err(self.error("Only literal values are allowed")),
            },
            None => Err(self.error("Incomplete table")),
        }
    }
    fn table(&mut self, depth: usize) -> Result<Value, String> {
        self.expect(b'{')?;
        let mut table = BTreeMap::new();
        let mut next = 1;
        loop {
            self.space();
            if self.peek() == Some(b'}') {
                self.pos += 1;
                return Ok(Value::Table(table));
            }
            let (key, value) = if self.peek() == Some(b'[') {
                self.pos += 1;
                let key = match self.value(depth)? {
                    Value::String(s) => Key::Name(s),
                    v => Key::Index(
                        v.integer()
                            .filter(|n| *n > 0)
                            .ok_or_else(|| self.error("Invalid table key"))?,
                    ),
                };
                self.expect(b']')?;
                self.expect(b'=')?;
                (key, self.value(depth)?)
            } else {
                let start = self.pos;
                let name = self.identifier().ok();
                self.space();
                if let Some(name) = name.filter(|_| self.peek() == Some(b'=')) {
                    self.pos += 1;
                    (Key::Name(name), self.value(depth)?)
                } else {
                    self.pos = start;
                    let key = Key::Index(next);
                    next += 1;
                    (key, self.value(depth)?)
                }
            };
            if table.insert(key, value).is_some() {
                return Err(self.error("Duplicate table key"));
            }
            self.space();
            match self.peek() {
                Some(b',' | b';') => self.pos += 1,
                Some(b'}') => {}
                _ => return Err(self.error("Expected table separator")),
            }
        }
    }
}
