## Minimal parquet reader for SWE-bench_Verified: BYTE_ARRAY columns, single row
## group, SNAPPY + PLAIN_DICTIONARY encoding. Reads a locally cached parquet
## file the way HuggingFace `datasets` would, so run.nim has no Python dep.

import std/[sequtils, strutils]

const ParquetMagic = "PAR1"

type
  StrColumn* = seq[string] ## a column of strings; "" denotes a null cell
                           ## (SWE-bench strings are non-null, but a null and
                           ## a real empty string both map to "" here).

# --- snappy (libsnappy C API) ---
proc csnappyLen(c: ptr char, n: csize_t, r: ptr csize_t): cint {.
    importc: "snappy_uncompressed_length", cdecl.}
proc csnappyUncomp(c: ptr char, n: csize_t, o: ptr char,
                   ol: ptr csize_t): cint {.importc: "snappy_uncompress", cdecl.}
{.passL: "-lsnappy".}

proc snappyInflate(src: openArray[char]): string =
  var ulen: csize_t = 0
  if csnappyLen(unsafeAddr src[0], src.len.csize_t, addr ulen) != 0:
    raise newException(ValueError, "snappy: bad input")
  result = newString(ulen)
  var ol = ulen
  if csnappyUncomp(unsafeAddr src[0], src.len.csize_t,
                   addr result[0], addr ol) != 0:
    raise newException(ValueError, "snappy: decode failed")
  result.setLen(ol)

# --- thrift compact protocol reader (enough for parquet metadata) ---
type
  TType = enum
    ttStop = 0, ttBoolTrue = 1, ttBoolFalse = 2, ttByte = 3, ttI16 = 4,
    ttI32 = 5, ttI64 = 6, ttDouble = 7, ttBinary = 8, ttList = 9,
    ttSet = 10, ttMap = 11, ttStruct = 12
  ThriftNode = object
    case kind: TType
    of ttI16, ttI32, ttI64, ttDouble, ttByte: ival: int64
    of ttBinary: bval: string
    of ttBoolTrue, ttBoolFalse: b: bool
    of ttList, ttSet:
      items: seq[ThriftNode]
      elemType: TType
    of ttStruct: fields: seq[(int, ThriftNode)]
    of ttMap, ttStop: discard

proc readVarint(b: openArray[char], pos: var int): uint64 =
  var shift = 0
  while pos < b.len:
    let ch = cast[uint8](b[pos]); inc pos
    result = result or ((uint64(ch) and 0x7f) shl shift)
    if (ch and 0x80) == 0: return
    shift += 7
  raise newException(ValueError, "varint runs past buffer end")

proc zigzag(n: uint64): int64 =
  int64(n shr 1) xor -int64(n and 1)

proc readNode(t: TType, b: openArray[char], pos: var int): ThriftNode

proc readFields(b: openArray[char], pos: var int): seq[(int, ThriftNode)] =
  var lastField = 0
  while pos < b.len:
    let b0 = cast[uint8](b[pos]); inc pos
    if b0 == 0: return result
    let delta = int((b0 shr 4) and 0x0f)
    let typNum = int(b0 and 0x0f)
    var fid: int
    if delta == 0: fid = int(readVarint(b, pos))
    else: fid = lastField + delta
    lastField = fid
    let typ = if typNum in 0..12: TType(typNum) else: ttStop
    result.add((fid, readNode(typ, b, pos)))

proc readNode(t: TType, b: openArray[char], pos: var int): ThriftNode =
  case t
  of ttI16, ttI32, ttI64:
    result = ThriftNode(kind: t, ival: zigzag(readVarint(b, pos)))
  of ttDouble:
    if pos + 8 > b.len: raise newException(ValueError, "double past end")
    var d: float64
    copyMem(addr d, unsafeAddr b[pos], 8); pos += 8
    result = ThriftNode(kind: t, ival: cast[int64](d))
  of ttByte:
    result = ThriftNode(kind: t, ival: int64(cast[uint8](b[pos]))); inc pos
  of ttBinary:
    let ln = int(readVarint(b, pos))
    var s = newString(ln)
    if ln > 0:
      if pos + ln > b.len: raise newException(ValueError, "binary past end")
      copyMem(addr s[0], unsafeAddr b[pos], ln); pos += ln
    result = ThriftNode(kind: t, bval: s)
  of ttBoolTrue: result = ThriftNode(kind: t, b: true)
  of ttBoolFalse: result = ThriftNode(kind: t, b: false)
  of ttStruct:
    result = ThriftNode(kind: t, fields: readFields(b, pos))
  of ttList, ttSet:
    if pos >= b.len: raise newException(ValueError, "list header past end")
    let lh = cast[uint8](b[pos]); inc pos
    var size = int(lh shr 4)
    let etNum = int(lh and 0x0f)
    if size == 15: size = int(readVarint(b, pos))
    let et = if etNum in 0..12: TType(etNum) else: ttStop
    result = ThriftNode(kind: t, elemType: et)
    for _ in 0 ..< size:
      result.items.add(readNode(et, b, pos))
  of ttMap, ttStop: discard

proc readRoot*(b: openArray[char], pos: var int): ThriftNode =
  readNode(ttStruct, b, pos)

proc field(n: ThriftNode, fid: int): ThriftNode =
  if n.kind != ttStruct: return ThriftNode(kind: ttStop)
  for (k, v) in n.fields:
    if k == fid: return v
  ThriftNode(kind: ttStop)

proc has(n: ThriftNode, fid: int): bool =
  n.kind == ttStruct and n.fields.anyIt(it[0] == fid)

proc asInt*(n: ThriftNode): int64 =
  case n.kind
  of ttI16, ttI32, ttI64, ttDouble, ttByte: n.ival
  else: 0

proc asBin*(n: ThriftNode): string =
  if n.kind == ttBinary: n.bval else: ""

# --- RLE / bit-packed hybrid decoder (parquet levels & dict indices) ---
proc readRleBitpacked(b: openArray[char], pos: var int,
                      count, bitwidth: int): seq[int] =
  result = newSeqOfCap[int](count)
  if bitwidth == 0:
    for _ in 0 ..< count: result.add(0)
    return result
  let mask = (1 shl bitwidth) - 1
  while result.len < count:
    let hdr = int(readVarint(b, pos))
    if (hdr and 1) == 1:
      # bit-packed run: hdr >> 1 = number of groups (each group = 8 values)
      let numGroups = hdr shr 1
      let nbytes = numGroups * bitwidth
      if pos + nbytes > b.len:
        raise newException(ValueError, "bit-packed run past end")
      var acc = 0'u64
      var nbits = 0
      for i in 0 ..< nbytes:
        acc = acc or (uint64(cast[uint8](b[pos + i])) shl nbits)
        nbits += 8
        while nbits >= bitwidth and result.len < count:
          result.add(int(acc and uint64(mask)))
          acc = acc shr bitwidth
          nbits -= bitwidth
      pos += nbytes
    else:
      # RLE run: hdr >> 1 = run length
      let runLen = hdr shr 1
      let nbytes = (bitwidth + 7) div 8
      if pos + nbytes > b.len:
        raise newException(ValueError, "rle value past end")
      var val = 0
      for i in 0 ..< nbytes:
        val = val or (int(cast[uint8](b[pos + i])) shl (i * 8))
      pos += nbytes
      for _ in 0 ..< runLen: result.add(val)
  if result.len > count: result.setLen(count)

# --- parquet page decoding ---
proc readLE32(b: openArray[char], pos: int): int =
  int(cast[uint8](b[pos])) or
    (int(cast[uint8](b[pos+1])) shl 8) or
    (int(cast[uint8](b[pos+2])) shl 16) or
    (int(cast[uint8](b[pos+3])) shl 24)

proc readPlainByteArrays(b: openArray[char], count: int): seq[string] =
  result = newSeqOfCap[string](count)
  var pos = 0
  for _ in 0 ..< count:
    if pos + 4 > b.len:
      raise newException(ValueError, "byte-array length past end")
    let ln = readLE32(b, pos)
    pos += 4
    if pos + ln > b.len:
      raise newException(ValueError, "byte-array data past end")
    var s = newString(ln)
    if ln > 0: copyMem(addr s[0], unsafeAddr b[pos], ln)
    pos += ln
    result.add(s)

# parquet PageType / Encoding enums
const
  ptDataPage = 0
  ptDictionaryPage = 2
  encPlain = 0
  encRleDict = 8

proc decodeColumnChunk(file: openArray[char], colMeta: ThriftNode): StrColumn =
  # ColumnMetaData fields: 1 type, 2 encodings, 3 path, 4 num_values,
  # 5 total_uncompressed, 6 total_compressed, 9 data_page_offset,
  # 11 dictionary_page_offset
  let dataOff = int(asInt(field(colMeta, 9)))
  let dictOff = if colMeta.has(11): int(asInt(field(colMeta, 11))) else: -1

  var dict = newSeq[string]()
  if dictOff >= 0:
    var p = dictOff
    let ph = readNode(ttStruct, file, p)
    if int(asInt(field(ph, 1))) != ptDictionaryPage:
      raise newException(ValueError, "expected dictionary page")
    let compSz = int(asInt(field(ph, 3)))
    let uncompSz = int(asInt(field(ph, 2)))
    let body = file[p ..< p + compSz]
    let raw = if compSz != uncompSz: snappyInflate(body) else: join(body, "")
    let dh = field(ph, 7)  # DictionaryPageHeader
    let nDict = int(asInt(field(dh, 1)))
    dict = readPlainByteArrays(raw.toOpenArray(0, raw.len - 1), nDict)

  var p = dataOff
  let ph = readNode(ttStruct, file, p)
  if int(asInt(field(ph, 1))) != ptDataPage:
    raise newException(ValueError, "expected data page v1")
  let compSz = int(asInt(field(ph, 3)))
  let uncompSz = int(asInt(field(ph, 2)))
  let body = file[p ..< p + compSz]
  let raw = if compSz != uncompSz: snappyInflate(body) else: join(body, "")
  let dph = field(ph, 5)  # DataPageHeader
  let nv = int(asInt(field(dph, 1)))
  let valueEnc = int(asInt(field(dph, 2)))
  # repEnc = field(dph, 4); max_rep_level is 0 for these columns, so skip.

  var rpos = 0
  # definition levels (max_def_level=1): V1 page prefixes a 4-byte LE length
  let defLen = readLE32(raw, rpos); rpos += 4
  let defEnd = rpos + defLen
  let defLevels = readRleBitpacked(raw, rpos, nv, 1)
  rpos = defEnd

  if valueEnc == encRleDict:
    if rpos >= raw.len:
      raise newException(ValueError, "missing dict bitwidth byte")
    let bw = int(cast[uint8](raw[rpos])); rpos += 1
    let indices = readRleBitpacked(raw, rpos, nv, bw)
    var present = 0
    result = newSeqOfCap[string](nv)
    for i in 0 ..< nv:
      if defLevels[i] >= 1:
        result.add(dict[indices[present]]); inc present
      else:
        result.add("")
  elif valueEnc == encPlain:
    var present = 0
    for i in 0 ..< nv:
      if defLevels[i] >= 1: inc present
    let vals = readPlainByteArrays(raw.toOpenArray(rpos, raw.len - 1), present)
    var vi = 0
    result = newSeqOfCap[string](nv)
    for i in 0 ..< nv:
      if defLevels[i] >= 1:
        result.add(vals[vi]); inc vi
      else:
        result.add("")
  else:
    raise newException(ValueError, "unsupported value encoding: " & $valueEnc)

proc loadParquetStringColumns*(path: string,
        colNames: openArray[string]): seq[StrColumn] =
  ## Read specific BYTE_ARRAY columns from a parquet file. Returns columns in
  ## the same order as colNames. Covers the SWE-bench_Verified layout
  ## (snappy + dictionary encoding, single row group).
  let raw = readFile(path)
  if raw.len < 12 or raw[0..3] != ParquetMagic or raw[^4..^1] != ParquetMagic:
    raise newException(ValueError, "not a parquet file: " & path)
  let footerLen = readLE32(raw, raw.len - 8)
  let footerStart = raw.len - 8 - footerLen
  var pos = footerStart
  let root = readRoot(raw, pos)
  let rowGroups = field(root, 4)
  if rowGroups.kind != ttList or rowGroups.items.len == 0:
    raise newException(ValueError, "no row groups")
  let rg0 = rowGroups.items[0]
  let colChunks = field(rg0, 1)
  if colChunks.kind != ttList:
    raise newException(ValueError, "no column chunks")

  var wantIdx = newSeq[int](colNames.len)
  for i, cn in colNames: wantIdx[i] = -1
  var i = 0
  for cc in colChunks.items:
    let meta = field(cc, 3)          # ColumnChunk.meta_data
    let pathList = field(meta, 3)    # path_in_schema (list of binary)
    var name = ""
    if pathList.kind == ttList:
      for j, seg in pathList.items:
        if j > 0: name.add('/')
        name.add(seg.bval)
    for w, cn in colNames:
      if cn == name: wantIdx[w] = i
    inc i

  result = newSeq[StrColumn](colNames.len)
  for w in 0 ..< colNames.len:
    if wantIdx[w] < 0:
      raise newException(KeyError, "column not found: " & colNames[w])
    let cc = colChunks.items[wantIdx[w]]
    let meta = field(cc, 3)
    result[w] = decodeColumnChunk(raw.toOpenArray(0, raw.len - 1), meta)
