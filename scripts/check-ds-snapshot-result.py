#!/usr/bin/env python3
"""Validate exported PNGs and, if given a summary, accept only recording failures."""
import argparse
import json
from pathlib import Path
import re
import struct
import zlib

EXPECTED_PNG_COUNT = 20


def png_blank_reason(path):
    """Decode UIImage's 8-bit, non-interlaced PNGs without third-party packages."""
    data = path.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Invalid PNG signature')
    offset = 8
    header = None
    compressed = bytearray()
    transparency = None
    ended = False
    while offset < len(data):
        if len(data) - offset < 12:
            raise ValueError('Truncated PNG chunk')
        length, kind = struct.unpack_from('>I4s', data, offset)
        start = offset + 8
        end = start + length
        if end + 4 > len(data):
            raise ValueError('Truncated PNG chunk data')
        chunk = data[start:end]
        if zlib.crc32(data[offset + 4:end]) != struct.unpack_from('>I', data, end)[0]:
            raise ValueError('Invalid PNG chunk checksum')
        if kind == b'IHDR':
            if header is not None or offset != 8 or length != 13:
                raise ValueError('Invalid PNG header')
            header = struct.unpack('>IIBBBBB', chunk)
        elif kind == b'IDAT':
            compressed.extend(chunk)
        elif kind == b'tRNS':
            transparency = chunk
        elif kind == b'IEND':
            ended = True
            break
        offset = end + 4
    if header is None or not ended:
        raise ValueError('Missing PNG header or end chunk')
    width, height, depth, colour_type, compression, filtering, interlace = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(colour_type)
    if not width or not height or depth != 8 or channels is None or compression or filtering or interlace:
        raise ValueError('Expected an 8-bit, non-interlaced grayscale, RGB, LA or RGBA PNG')

    transparent_pixel = None
    if transparency is not None:
        if colour_type not in (0, 2) or len(transparency) != channels * 2:
            raise ValueError('Invalid PNG transparency chunk')
        samples = struct.unpack('>' + 'H' * channels, transparency)
        if any(sample > 255 for sample in samples):
            raise ValueError('Invalid 8-bit PNG transparency samples')
        transparent_pixel = bytes(samples)

    decoded = zlib.decompress(compressed)
    stride = width * channels
    if len(decoded) != (stride + 1) * height:
        raise ValueError('Unexpected PNG scanline length')
    previous = bytearray(stride)
    solid_row = None
    flat = True
    all_transparent = colour_type in (4, 6) or transparent_pixel is not None
    for y in range(height):
        start = y * (stride + 1)
        filter_type = decoded[start]
        row = bytearray(decoded[start + 1:start + 1 + stride])
        if filter_type == 1:  # Sub
            for x in range(channels, stride):
                row[x] = (row[x] + row[x - channels]) & 255
        elif filter_type == 2:  # Up
            for x in range(stride):
                row[x] = (row[x] + previous[x]) & 255
        elif filter_type in (3, 4):  # Average / Paeth
            for x in range(stride):
                left = row[x - channels] if x >= channels else 0
                above = previous[x]
                if filter_type == 3:
                    prediction = (left + above) // 2
                else:
                    corner = previous[x - channels] if x >= channels else 0
                    estimate = left + above - corner
                    distances = (abs(estimate - left), abs(estimate - above), abs(estimate - corner))
                    if distances[0] <= distances[1] and distances[0] <= distances[2]:
                        prediction = left
                    elif distances[1] <= distances[2]:
                        prediction = above
                    else:
                        prediction = corner
                row[x] = (row[x] + prediction) & 255
        elif filter_type != 0:
            raise ValueError(f'Unknown PNG filter: {filter_type}')
        if solid_row is None:
            solid_row = row[:channels] * width
        flat = flat and row == solid_row
        if all_transparent:
            if colour_type in (4, 6):
                all_transparent = not any(row[channels - 1::channels])
            else:
                all_transparent = row == transparent_pixel * width
        previous = row
    if all_transparent:
        return 'all pixels are fully transparent'
    if flat:
        return 'all pixels have a single flat colour'
    return None


def validate_pngs(directory):
    pngs = sorted(directory.glob('*.png'))
    if len(pngs) != EXPECTED_PNG_COUNT:
        raise ValueError(f'Expected {EXPECTED_PNG_COUNT} PNGs, found {len(pngs)}')
    for path in pngs:
        try:
            reason = png_blank_reason(path)
        except (OSError, ValueError, struct.error, zlib.error) as error:
            raise ValueError(f'PNG validation failed for {path.name}: {error}') from error
        if reason:
            raise ValueError(f'Blank PNG {path.name}: {reason}')
    return len(pngs)


def recording_only(summary, png_count):
    failures = summary.get('testFailures', [])
    total = summary.get('totalTestCount', 0)
    completed = summary.get('passedTests', 0) + summary.get('failedTests', 0)
    if (summary.get('result') != 'Failed' or not failures or total <= 0 or completed != total
            or summary.get('skippedTests', 0) or png_count != EXPECTED_PNG_COUNT):
        return False
    for failure in failures:
        text = failure.get('failureText') or failure.get('message') or ''
        test = failure.get('testIdentifierString') or failure.get('testName') or ''
        if 'DesignSystemSnapshotTests' not in test:
            return False
        if not re.search(r'(Record mode is on|No reference was found on disk).*Automatically recorded snapshot|recorded new snapshot', text, re.S | re.I):
            return False
        if re.search(r'PNG export failed|crash|XCTAssert|does not match reference|timed out', text, re.I):
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('summary', type=Path, nargs='?', help='xcresult summary when accepting recording failures')
    parser.add_argument('--png-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        png_count = validate_pngs(args.png_dir)
    except ValueError as error:
        raise SystemExit(str(error))
    if args.summary is not None:
        summary = json.loads(args.summary.read_text())
        if not recording_only(summary, png_count):
            raise SystemExit('Snapshot failures were not exclusively successful recordings; see xcresult.')
        print(f'Snapshot recording: {png_count} non-blank PNGs; only expected recording assertions failed.')
    else:
        print(f'Snapshot export: {png_count} non-blank PNGs.')


if __name__ == '__main__':
    main()
