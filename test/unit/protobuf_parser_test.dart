// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_functions/src/firestore/protobuf_parser.dart';
import 'package:test/test.dart';

/// Tests for Firestore protobuf parser.
///
/// These tests verify that all Firestore Value types are parsed correctly
/// according to the google.firestore.v1.Value protobuf schema:
///
/// ```protobuf
/// message Value {
///   oneof value_type {
///     bool boolean_value = 1;
///     int64 integer_value = 2;
///     double double_value = 3;
///     string reference_value = 5;
///     MapValue map_value = 6;
///     LatLng geo_point_value = 8;
///     ArrayValue array_value = 9;
///     Timestamp timestamp_value = 10;
///     NullValue null_value = 11;
///     string string_value = 17;
///     bytes bytes_value = 18;
///   }
/// }
/// ```
void main() {
  group('Firestore Protobuf Parser', () {
    group('parseDocumentEventData', () {
      test('parses DocumentEventData with string fields correctly', () {
        // Build a DocumentEventData protobuf with string fields
        final docEventData = _buildDocumentEventData(
          fields: [
            _buildField('name', _buildStringValue('John Doe')),
            _buildField('email', _buildStringValue('john@example.com')),
          ],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        expect(result!['value'], isNotNull);

        final snapshot = result['value']!;
        final data = snapshot.data();

        expect(data['name'], 'John Doe');
        expect(data['email'], 'john@example.com');
      });

      test('parses DocumentEventData with integer fields correctly', () {
        final docEventData = _buildDocumentEventData(
          fields: [
            _buildField('age', _buildIntegerValue(28)),
            _buildField('count', _buildIntegerValue(100)),
          ],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final data = result!['value']!.data();

        // Integer values come as Int64, convert to int for comparison
        expect((data['age'] as dynamic).toInt(), 28);
        expect((data['count'] as dynamic).toInt(), 100);
      });

      test('parses DocumentEventData with double fields correctly', () {
        final docEventData = _buildDocumentEventData(
          fields: [
            _buildField('score', _buildDoubleValue(95.5)),
            _buildField('rating', _buildDoubleValue(4.7)),
          ],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final data = result!['value']!.data();

        expect(data['score'], closeTo(95.5, 0.001));
        expect(data['rating'], closeTo(4.7, 0.001));
      });

      test('parses DocumentEventData with boolean fields correctly', () {
        final docEventData = _buildDocumentEventData(
          fields: [
            _buildField('active', _buildBooleanValue(true)),
            _buildField('verified', _buildBooleanValue(false)),
          ],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final data = result!['value']!.data();

        expect(data['active'], true);
        expect(data['verified'], false);
      });

      test('parses DocumentEventData with null fields correctly', () {
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('deleted', _buildNullValue())],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final data = result!['value']!.data();

        expect(data['deleted'], isNull);
      });

      test('parses DocumentEventData with mixed types correctly', () {
        final docEventData = _buildDocumentEventData(
          fields: [
            _buildField('name', _buildStringValue('Test User')),
            _buildField('age', _buildIntegerValue(30)),
            _buildField('score', _buildDoubleValue(85.5)),
            _buildField('active', _buildBooleanValue(true)),
          ],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final data = result!['value']!.data();

        expect(data['name'], 'Test User');
        expect((data['age'] as dynamic).toInt(), 30);
        expect(data['score'], closeTo(85.5, 0.001));
        expect(data['active'], true);
      });

      test('parses document path correctly', () {
        final docEventData = _buildDocumentEventData(
          name:
              'projects/test-project/databases/(default)/documents/users/user123',
          fields: [_buildField('name', _buildStringValue('Test'))],
        );

        final result = parseDocumentEventData(docEventData);

        expect(result, isNotNull);
        final snapshot = result!['value']!;

        expect(snapshot.id, 'user123');
        expect(snapshot.path, 'users/user123');
      });
    });

    group('field number mappings', () {
      // These tests specifically verify the field numbers are correct
      // to prevent regression of the bug where string_value (17) and
      // null_value (11) were swapped.

      test('string_value uses field number 17', () {
        // Field 17 = string_value
        final valueBytes = _buildStringValue('test string');
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('str', valueBytes)],
        );

        final result = parseDocumentEventData(docEventData);
        final data = result!['value']!.data();

        expect(data['str'], 'test string');
      });

      test('null_value uses field number 11', () {
        // Field 11 = null_value
        final valueBytes = _buildNullValue();
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('nullField', valueBytes)],
        );

        final result = parseDocumentEventData(docEventData);
        final data = result!['value']!.data();

        expect(data['nullField'], isNull);
      });

      test('boolean_value uses field number 1', () {
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('bool', _buildBooleanValue(true))],
        );

        final result = parseDocumentEventData(docEventData);
        final data = result!['value']!.data();

        expect(data['bool'], true);
      });

      test('integer_value uses field number 2', () {
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('int', _buildIntegerValue(42))],
        );

        final result = parseDocumentEventData(docEventData);
        final data = result!['value']!.data();

        expect((data['int'] as dynamic).toInt(), 42);
      });

      test('double_value uses field number 3', () {
        final docEventData = _buildDocumentEventData(
          fields: [_buildField('dbl', _buildDoubleValue(3.14))],
        );

        final result = parseDocumentEventData(docEventData);
        final data = result!['value']!.data();

        expect(data['dbl'], closeTo(3.14, 0.001));
      });
    });
  });
}

// =============================================================================
// Protobuf Wire Format Helpers
// =============================================================================

// Wire types
const int _wireTypeVarint = 0;
const int _wireType64Bit = 1;
const int _wireTypeLengthDelimited = 2;

/// Creates a protobuf tag (field number + wire type) and encodes as varint.
List<int> _makeTag(int fieldNumber, int wireType) {
  final tag = (fieldNumber << 3) | wireType;
  return _encodeVarint(tag);
}

/// Encodes a varint to bytes.
List<int> _encodeVarint(int value) {
  final result = <int>[];
  var v = value;
  while (v > 0x7F) {
    result.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  result.add(v & 0x7F);
  return result;
}

/// Encodes a string as a length-delimited field.
List<int> _encodeString(String value) {
  final bytes = utf8.encode(value);
  return [..._encodeVarint(bytes.length), ...bytes];
}

/// Encodes a double as 64-bit little-endian.
List<int> _encodeDouble(double value) {
  final buffer = ByteData(8);
  buffer.setFloat64(0, value, Endian.little);
  return buffer.buffer.asUint8List().toList();
}

/// Encodes a 64-bit integer as a varint.
List<int> _encodeInt64(int value) {
  return _encodeVarint(value);
}

/// Builds a DocumentEventData protobuf message.
Uint8List _buildDocumentEventData({
  String name =
      'projects/test-project/databases/(default)/documents/test/doc123',
  required List<Uint8List> fields,
}) {
  final docBytes = _buildDocument(name: name, fields: fields);

  final result = <int>[];
  // Field 1: value (Document) - length-delimited
  result.addAll(_makeTag(1, _wireTypeLengthDelimited));
  result.addAll(_encodeVarint(docBytes.length));
  result.addAll(docBytes);

  return Uint8List.fromList(result);
}

/// Builds a Document protobuf message.
Uint8List _buildDocument({
  required String name,
  required List<Uint8List> fields,
}) {
  final result = <int>[];

  // Field 1: name (string)
  result.addAll(_makeTag(1, _wireTypeLengthDelimited));
  result.addAll(_encodeString(name));

  // Field 2: fields (repeated map entry)
  for (final field in fields) {
    result.addAll(_makeTag(2, _wireTypeLengthDelimited));
    result.addAll(_encodeVarint(field.length));
    result.addAll(field);
  }

  return Uint8List.fromList(result);
}

/// Builds a map entry (key + value).
Uint8List _buildField(String key, Uint8List valueBytes) {
  final result = <int>[];

  // Field 1: key (string)
  result.addAll(_makeTag(1, _wireTypeLengthDelimited));
  result.addAll(_encodeString(key));

  // Field 2: value (Value message)
  result.addAll(_makeTag(2, _wireTypeLengthDelimited));
  result.addAll(_encodeVarint(valueBytes.length));
  result.addAll(valueBytes);

  return Uint8List.fromList(result);
}

/// Builds a string Value (field 17).
Uint8List _buildStringValue(String value) {
  final result = <int>[];
  // Field 17: string_value
  result.addAll(_makeTag(17, _wireTypeLengthDelimited));
  result.addAll(_encodeString(value));
  return Uint8List.fromList(result);
}

/// Builds an integer Value (field 2).
Uint8List _buildIntegerValue(int value) {
  final result = <int>[];
  // Field 2: integer_value (int64 as varint)
  result.addAll(_makeTag(2, _wireTypeVarint));
  result.addAll(_encodeInt64(value));
  return Uint8List.fromList(result);
}

/// Builds a double Value (field 3).
Uint8List _buildDoubleValue(double value) {
  final result = <int>[];
  // Field 3: double_value (64-bit)
  result.addAll(_makeTag(3, _wireType64Bit));
  result.addAll(_encodeDouble(value));
  return Uint8List.fromList(result);
}

/// Builds a boolean Value (field 1).
Uint8List _buildBooleanValue(bool value) {
  final result = <int>[];
  // Field 1: boolean_value (varint)
  result.addAll(_makeTag(1, _wireTypeVarint));
  result.add(value ? 1 : 0);
  return Uint8List.fromList(result);
}

/// Builds a null Value (field 11).
Uint8List _buildNullValue() {
  final result = <int>[];
  // Field 11: null_value (enum as varint, value 0 for NULL_VALUE)
  result.addAll(_makeTag(11, _wireTypeVarint));
  result.add(0); // NULL_VALUE = 0
  return Uint8List.fromList(result);
}
