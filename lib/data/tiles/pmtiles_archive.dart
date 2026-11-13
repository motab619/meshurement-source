// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Minimal PMTiles v3 reader (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md):
// header, gzip-compressed directories, leaf directories, run-length entries.
// Raster tiles only need byte ranges, so this replaces the `pmtiles` package
// (whose protobuf dependency clashes with the vendored Meshtastic protos).
// Reads from a local file (offline packs, tests) or over HTTP range requests
// (CloudFront).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Random access to the bytes of a PMTiles file.
abstract class PmTilesSource {
  Future<Uint8List> read(int offset, int length);
  Future<void> close() async {}

  /// `file://...` or a plain path → file; `http(s)://...` → range requests.
  factory PmTilesSource.fromUrl(String url,
      {http.Client? client, Map<String, String>? headers}) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return HttpPmTilesSource(Uri.parse(url),
          client: client, headers: headers);
    }
    final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
    return FilePmTilesSource(path);
  }
}

class FilePmTilesSource implements PmTilesSource {
  FilePmTilesSource(this.path);
  final String path;
  Future<RandomAccessFile>? _file;
  Future<void> _lock = Future.value();

  @override
  Future<Uint8List> read(int offset, int length) {
    // RandomAccessFile allows one operation at a time: serialize.
    final result = _lock.then((_) async {
      final f = await (_file ??= File(path).open());
      await f.setPosition(offset);
      return f.read(length);
    });
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> close() async {
    final f = _file;
    _file = null;
    if (f != null) await (await f).close();
  }
}

class HttpPmTilesSource implements PmTilesSource {
  HttpPmTilesSource(this.uri, {http.Client? client, this.headers})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final Uri uri;
  final Map<String, String>? headers;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final res = await _client.get(uri, headers: {
      ...?headers,
      'Range': 'bytes=$offset-${offset + length - 1}',
    });
    if (res.statusCode == 206) return res.bodyBytes;
    if (res.statusCode == 200) {
      // Server ignored the range: slice the whole file (small test files).
      final end = (offset + length).clamp(0, res.bodyBytes.length);
      return Uint8List.sublistView(res.bodyBytes, offset, end);
    }
    throw PmTilesException('HTTP ${res.statusCode} for $uri');
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}

class PmTilesException implements Exception {
  PmTilesException(this.message);
  final String message;
  @override
  String toString() => 'PmTilesException: $message';
}

enum PmTileType { unknown, mvt, png, jpeg, webp, avif }

class PmTilesHeader {
  PmTilesHeader._(ByteData b)
      : rootOffset = b.getUint64(8, Endian.little),
        rootLength = b.getUint64(16, Endian.little),
        metadataOffset = b.getUint64(24, Endian.little),
        metadataLength = b.getUint64(32, Endian.little),
        leafOffset = b.getUint64(40, Endian.little),
        leafLength = b.getUint64(48, Endian.little),
        tileDataOffset = b.getUint64(56, Endian.little),
        tileDataLength = b.getUint64(64, Endian.little),
        internalCompression = b.getUint8(97),
        tileCompression = b.getUint8(98),
        tileType = b.getUint8(99) < PmTileType.values.length
            ? PmTileType.values[b.getUint8(99)]
            : PmTileType.unknown,
        minZoom = b.getUint8(100),
        maxZoom = b.getUint8(101),
        minLon = b.getInt32(102, Endian.little) / 1e7,
        minLat = b.getInt32(106, Endian.little) / 1e7,
        maxLon = b.getInt32(110, Endian.little) / 1e7,
        maxLat = b.getInt32(114, Endian.little) / 1e7;

  static const length = 127;
  static const compressionNone = 1;
  static const compressionGzip = 2;

  final int rootOffset, rootLength, metadataOffset, metadataLength;
  final int leafOffset, leafLength, tileDataOffset, tileDataLength;
  final int internalCompression, tileCompression;
  final PmTileType tileType;
  final int minZoom, maxZoom;
  final double minLon, minLat, maxLon, maxLat;

  static PmTilesHeader parse(Uint8List bytes) {
    if (bytes.length < length ||
        String.fromCharCodes(bytes.sublist(0, 7)) != 'PMTiles') {
      throw PmTilesException('not a PMTiles file');
    }
    if (bytes[7] != 3) {
      throw PmTilesException('PMTiles version ${bytes[7]} (need 3)');
    }
    final h = PmTilesHeader._(ByteData.sublistView(bytes));
    // A uint64 over 2^63 reads as negative; anything that big is corrupt.
    for (final (name, offset, len) in [
      ('root', h.rootOffset, h.rootLength),
      ('metadata', h.metadataOffset, h.metadataLength),
      ('leaf', h.leafOffset, h.leafLength),
      ('tile data', h.tileDataOffset, h.tileDataLength),
    ]) {
      if (offset < 0 || len < 0 || offset + len < 0) {
        throw PmTilesException('bad $name section in header');
      }
    }
    if (h.rootLength == 0 || h.rootLength > PmTilesArchive.maxDirectoryBytes) {
      throw PmTilesException('bad root directory length ${h.rootLength}');
    }
    return h;
  }
}

class PmTilesEntry {
  const PmTilesEntry(this.tileId, this.offset, this.length, this.runLength);
  final int tileId, offset, length, runLength;
}

/// An open PMTiles archive. Directories are cached; tile bytes are not
/// (Flutter's image cache keeps the decoded tiles).
class PmTilesArchive {
  PmTilesArchive._(this.source, this.header, this._root);

  final PmTilesSource source;
  final PmTilesHeader header;
  final List<PmTilesEntry> _root;
  final _leafCache = <int, Future<List<PmTilesEntry>>>{};
  static const _maxLeaves = 64;

  /// Caps on what the archive may ask us to read or inflate. The root is
  /// at most 16 KiB by the spec; leaves of a planet build are a few MiB.
  static const maxDirectoryBytes = 8 << 20;
  static const maxDecompressedDirectoryBytes = 32 << 20;
  static const maxTileBytes = 8 << 20;
  static const maxDecompressedTileBytes = 32 << 20;

  /// [source.read] that insists on getting all [length] bytes.
  static Future<Uint8List> _readExactly(
      PmTilesSource source, int offset, int length, String what) async {
    final b = await source.read(offset, length);
    if (b.length != length) {
      throw PmTilesException('$what truncated: ${b.length} of $length bytes');
    }
    return b;
  }

  /// Reads the header and root directory (one 16 KiB read when the file was
  /// written by the `pmtiles` tool, which puts the root first).
  static Future<PmTilesArchive> open(PmTilesSource source) async {
    final first = await source.read(0, 16384);
    final header = PmTilesHeader.parse(first);
    final rootBytes = header.rootOffset + header.rootLength <= first.length
        ? Uint8List.sublistView(
            first, header.rootOffset, header.rootOffset + header.rootLength)
        : await _readExactly(
            source, header.rootOffset, header.rootLength, 'root directory');
    final root =
        parseDirectory(_decompress(rootBytes, header.internalCompression));
    return PmTilesArchive._(source, header, root);
  }

  /// Bytes of tile z/x/y as stored (tile compression not undone), or null
  /// when the archive has no such tile.
  Future<Uint8List?> getTile(int z, int x, int y) async {
    final id = zxyToTileId(z, x, y);
    var entries = _root;
    for (var depth = 0; depth < 4; depth++) {
      final e = findEntry(entries, id);
      if (e == null) return null;
      if (e.runLength > 0) {
        _checkRange(
            'tile', e.offset, e.length, header.tileDataLength, maxTileBytes);
        final bytes = await _readExactly(
            source, header.tileDataOffset + e.offset, e.length, 'tile');
        return header.tileCompression == PmTilesHeader.compressionGzip
            ? _gunzip(bytes, maxDecompressedTileBytes)
            : bytes;
      }
      _checkRange('leaf directory', e.offset, e.length, header.leafLength,
          maxDirectoryBytes);
      entries = await _leaf(e.offset, e.length);
    }
    throw PmTilesException('directory too deep');
  }

  Future<List<PmTilesEntry>> _leaf(int offset, int length) {
    final cached = _leafCache.remove(offset);
    if (cached != null) return _leafCache[offset] = cached; // refresh LRU
    if (_leafCache.length >= _maxLeaves) {
      _leafCache.remove(_leafCache.keys.first);
    }
    final f = _readExactly(
            source, header.leafOffset + offset, length, 'leaf directory')
        .then(
            (b) => parseDirectory(_decompress(b, header.internalCompression)));
    f.catchError((Object _) {
      _leafCache.remove(offset); // retry next time
      return const <PmTilesEntry>[];
    });
    return _leafCache[offset] = f;
  }

  Future<void> close() => source.close();

  /// An entry's [offset]/[length] must lie inside its section
  /// ([sectionLength]) and under [cap].
  static void _checkRange(
      String what, int offset, int length, int sectionLength, int cap) {
    if (offset < 0 ||
        length <= 0 ||
        length > cap ||
        offset + length > sectionLength) {
      throw PmTilesException(
          '$what out of bounds (offset $offset, length $length)');
    }
  }

  static Uint8List _decompress(Uint8List b, int compression) {
    switch (compression) {
      case PmTilesHeader.compressionNone:
      case 0:
        return b;
      case PmTilesHeader.compressionGzip:
        return _gunzip(b, maxDecompressedDirectoryBytes);
      default:
        throw PmTilesException('unsupported compression $compression');
    }
  }

  /// gzip-decodes [b], refusing to inflate past [maxBytes] and turning a
  /// corrupt stream into a [PmTilesException].
  static Uint8List _gunzip(Uint8List b, int maxBytes) {
    final out = BytesBuilder(copy: false);
    try {
      gzip.decoder.startChunkedConversion(_CappedSink(out, maxBytes))
        ..add(b)
        ..close();
    } on PmTilesException {
      rethrow;
    } catch (e) {
      throw PmTilesException('corrupt gzip data (${e.runtimeType})');
    }
    return out.takeBytes();
  }

  /// Decodes a (decompressed) directory. Malformed input (truncated, an
  /// overlong varint, a count the bytes cannot hold, a negative or
  /// overflowing value) throws [PmTilesException], never a [RangeError].
  static List<PmTilesEntry> parseDirectory(Uint8List b) {
    var pos = 0;
    int varint() {
      var result = 0, shift = 0;
      // At most 9 bytes (63 bits): Dart ints are signed 64-bit.
      for (var i = 0; i < 9; i++) {
        if (pos >= b.length) throw PmTilesException('directory truncated');
        final byte = b[pos++];
        result |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0) return result;
        shift += 7;
      }
      throw PmTilesException('directory varint too long');
    }

    final n = varint();
    // Every entry takes at least one byte in each of the four columns.
    if (n > (b.length - pos) ~/ 4) {
      throw PmTilesException(
          'directory claims $n entries in ${b.length} bytes');
    }
    final ids = List<int>.filled(n, 0);
    final runs = List<int>.filled(n, 0);
    final lengths = List<int>.filled(n, 0);
    final offsets = List<int>.filled(n, 0);
    var last = 0;
    for (var i = 0; i < n; i++) {
      last += varint();
      if (last < 0) throw PmTilesException('directory tile id overflow');
      ids[i] = last;
    }
    for (var i = 0; i < n; i++) {
      runs[i] = varint();
      if (runs[i] < 0) throw PmTilesException('directory run overflow');
    }
    for (var i = 0; i < n; i++) {
      lengths[i] = varint();
      if (lengths[i] < 0) throw PmTilesException('directory length overflow');
    }
    for (var i = 0; i < n; i++) {
      final v = varint();
      if (v == 0 && i == 0) {
        throw PmTilesException('directory: first offset missing');
      }
      final o = v == 0 ? offsets[i - 1] + lengths[i - 1] : v - 1;
      if (o < 0) throw PmTilesException('directory offset overflow');
      offsets[i] = o;
    }
    return [
      for (var i = 0; i < n; i++)
        PmTilesEntry(ids[i], offsets[i], lengths[i], runs[i]),
    ];
  }

  /// The entry holding [tileId]: a tile run containing it, or the leaf
  /// directory (runLength 0) to search next.
  static PmTilesEntry? findEntry(List<PmTilesEntry> entries, int tileId) {
    var lo = 0, hi = entries.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = entries[mid].tileId - tileId;
      if (c < 0) {
        lo = mid + 1;
      } else if (c > 0) {
        hi = mid - 1;
      } else {
        return entries[mid];
      }
    }
    // lo is the insertion point; the candidate is the entry before it.
    if (hi >= 0) {
      final e = entries[hi];
      if (e.runLength == 0) return e;
      if (tileId - e.tileId < e.runLength) return e;
    }
    return null;
  }

  /// Hilbert-curve tile id (PMTiles v3).
  static int zxyToTileId(int z, int x, int y) {
    if (z > 26) throw ArgumentError('zoom $z too large');
    final n = 1 << z;
    if (x < 0 || y < 0 || x >= n || y >= n) {
      throw ArgumentError('tile $z/$x/$y out of range');
    }
    final acc = ((1 << (2 * z)) - 1) ~/ 3; // tiles in all lower zooms
    var tx = x, ty = y;
    var d = 0;
    for (var s = n >> 1; s > 0; s >>= 1) {
      final rx = (tx & s) > 0 ? 1 : 0;
      final ry = (ty & s) > 0 ? 1 : 0;
      d += s * s * ((3 * rx) ^ ry);
      if (ry == 0) {
        if (rx == 1) {
          tx = s - 1 - tx;
          ty = s - 1 - ty;
        }
        final t = tx;
        tx = ty;
        ty = t;
      }
    }
    return acc + d;
  }
}

/// Collects decoded bytes into [out] and throws once more than [max] arrive.
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.out, this.max);
  final BytesBuilder out;
  final int max;

  @override
  void add(List<int> chunk) {
    if (out.length + chunk.length > max) {
      throw PmTilesException('decompressed data over $max bytes');
    }
    out.add(chunk);
  }

  @override
  void close() {}
}
