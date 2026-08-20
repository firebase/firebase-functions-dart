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

export '../common/change.dart';

/// Interface representing a Firebase Realtime database data snapshot.
///
/// This provides a similar interface to the Node.js SDK's DataSnapshot
/// but works with data from the Firebase emulator or CloudEvents.
class DataSnapshot {
  DataSnapshot({
    required this.instance,
    required this.ref,
    required dynamic data,
  }) : _data = data;

  /// The database instance URL.
  final String instance;

  /// The database reference path.
  final String ref;

  /// The raw data.
  final dynamic _data;

  /// The key (last part of the path) of the location of this DataSnapshot.
  ///
  /// The last token in a database location is considered its key. For example,
  /// "ada" is the key for the /users/ada/ node. Accessing the key on any
  /// DataSnapshot returns the key for the location that generated it.
  /// However, accessing the key on the root URL of a database returns null.
  String? get key {
    final parts = ref.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.last;
  }

  /// Extracts a JavaScript value from a DataSnapshot.
  ///
  /// Depending on the data in a DataSnapshot, the val() method may return a
  /// scalar type (string, number, or boolean), an array, or an object. It may also
  /// return null, indicating that the DataSnapshot is empty (contains no data).
  ///
  /// @return The snapshot's contents as a Dart value (Map, List, String, num,
  ///   bool, or null).
  dynamic val() {
    if (_data == null) return null;
    return _checkAndConvertToArray(_data);
  }

  /// Exports the entire contents of the DataSnapshot as a Dart object.
  ///
  /// @return The contents of the DataSnapshot as a Dart value (Map, List,
  ///   String, num, bool, or null).
  dynamic exportVal() => val();

  /// Gets the priority value of the data in this DataSnapshot.
  ///
  /// As an alternative to using priority, applications can order collections by
  /// ordinary properties.
  ///
  /// @return The priority value of the data.
  Priority<Object>? getPriority() => null;

  /// Returns true if this DataSnapshot contains any data.
  ///
  /// It is slightly more efficient than using snapshot.val() != null.
  ///
  /// @return true if this DataSnapshot contains any data; otherwise, false.
  bool exists() {
    final value = val();
    if (value == null) return false;
    if (value is Map && value.isEmpty) return false;
    return true;
  }

  /// Gets a DataSnapshot for the location at the specified relative path.
  ///
  /// The relative path can either be a simple child name (for example, "ada") or
  /// a deeper slash-separated path (for example, "ada/name/first").
  ///
  /// @param childPath A relative path from this location to the desired child
  ///   location.
  /// @return The specified child location.
  DataSnapshot child(String childPath) {
    if (childPath.isEmpty) return this;

    final parts = childPath.split('/').where((p) => p.isNotEmpty);
    dynamic childData = _data;

    for (final part in parts) {
      if (childData is Map) {
        childData = childData[part];
      } else {
        childData = null;
        break;
      }
    }

    final newRef = ref.endsWith('/') ? '$ref$childPath' : '$ref/$childPath';

    return DataSnapshot(instance: instance, ref: newRef, data: childData);
  }

  /// Enumerates the DataSnapshots of the children items.
  ///
  /// Because of the way Dart objects work, the ordering of data in the
  /// Map returned by val() is not guaranteed to match the ordering
  /// on the server nor the ordering of child_added events. That is where
  /// forEach() comes in handy. It guarantees the children of a DataSnapshot
  /// can be iterated in their query order.
  ///
  /// @param action A function that is called for each child DataSnapshot.
  ///   The callback can return true to cancel further enumeration.
  ///
  /// @return true if enumeration was canceled due to your callback
  ///   returning true.
  bool forEach(bool Function(DataSnapshot snapshot) action) {
    final value = val();
    if (value is! Map) return false;

    for (final key in value.keys) {
      final childSnapshot = child(key.toString());
      if (action(childSnapshot) == true) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if the specified child path has (non-null) data.
  ///
  /// @param childPath A relative path to the location of a potential child.
  /// @return true if data exists at the specified child path; otherwise, false.
  bool hasChild(String childPath) => child(childPath).exists();

  /// Returns whether or not the DataSnapshot has any non-null child properties.
  ///
  /// You can use hasChildren() to determine if a DataSnapshot has any
  /// children. If it does, you can enumerate them using forEach(). If it
  /// doesn't, then either this snapshot contains a primitive value (which can be
  /// retrieved with val()) or it is empty (in which case, val() returns null).
  ///
  /// @return true if this snapshot has any children; else false.
  bool hasChildren() {
    final value = val();
    return value is Map && value.isNotEmpty;
  }

  /// Returns the number of child properties of this DataSnapshot.
  ///
  /// @return Number of child properties of this DataSnapshot.
  int numChildren() {
    final value = val();
    if (value is Map) return value.length;
    return 0;
  }

  /// Returns a JSON-serializable representation of this object.
  ///
  /// @return A JSON-serializable representation of this object.
  Map<String, dynamic>? toJSON() {
    final value = val();
    if (value is Map<String, dynamic>) return value;
    if (value == null) return null;
    return {'value': value};
  }

  /// Recursive function to check if keys are numeric & convert node object
  /// to array if they are.
  dynamic _checkAndConvertToArray(dynamic node) {
    if (node == null) return null;
    if (node is! Map) return node;

    final obj = <String, dynamic>{};
    var numKeys = 0;
    var maxKey = 0;
    var allIntegerKeys = true;

    for (final entry in node.entries) {
      final key = entry.key.toString();
      final childNode = entry.value;
      final v = _checkAndConvertToArray(childNode);

      if (v == null) continue; // Empty child node

      obj[key] = v;
      numKeys++;

      final integerRegExp = RegExp(r'^(0|[1-9]\d*)$');
      if (allIntegerKeys && integerRegExp.hasMatch(key)) {
        maxKey = maxKey > int.parse(key) ? maxKey : int.parse(key);
      } else {
        allIntegerKeys = false;
      }
    }

    if (numKeys == 0) return null; // Empty node

    if (allIntegerKeys && maxKey < 2 * numKeys) {
      // Convert to array
      final array = List<dynamic>.filled(maxKey + 1, null);
      for (final entry in obj.entries) {
        array[int.parse(entry.key)] = entry.value;
      }
      return array;
    }

    return obj;
  }

  @override
  String toString() => 'DataSnapshot($ref)';
}

/// A base class for a priority value.
sealed class Priority<T> {
  const Priority(this.value);

  /// The priority value.
  final T value;
}

/// A class representing a database priority value as a string.
class StringPriority extends Priority<String> {
  const StringPriority(super.value);

  @override
  String toString() => 'StringPriority($value)';
}

/// A class representing a database priority value as an integer.
class IntPriority extends Priority<int> {
  const IntPriority(super.value);

  @override
  String toString() => 'IntPriority($value)';
}
