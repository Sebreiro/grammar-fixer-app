/// Deep, collection-aware equality and hashing, owned by the domain.
///
/// AD-1 lets `lib/src/domain/**` import only `dart:` libraries, so neither
/// `package:collection` nor `package:flutter/foundation.dart` is reachable
/// here — and the application ring's states hold the same collections, so the
/// helpers have to live in the ring both may see.
///
/// Every `hashCode` built from these agrees with the matching `==`: a set
/// hashed by order, or a map hashed by insertion order, would put two equal
/// values in different buckets and silently break every `Set` and `Map` keyed
/// by one.
library;

/// True when [a] and [b] hold equal elements in the same order.
bool listEquals<E>(List<E> a, List<E> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

/// True when [a] and [b] hold equal elements, in any order.
bool setEquals<E>(Set<E> a, Set<E> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  return a.containsAll(b);
}

/// True when [a] and [b] hold the same keys, each mapped to an equal value.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry(:key, :value) in a.entries) {
    // Membership is checked separately from the lookup: a key mapped to null
    // and an absent key both read back as null.
    if (!b.containsKey(key) || b[key] != value) {
      return false;
    }
  }
  return true;
}

/// Order-sensitive hash agreeing with [listEquals].
int listHash<E>(List<E> list) => Object.hashAll(list);

/// Order-independent hash agreeing with [setEquals].
int setHash<E>(Set<E> set) => Object.hashAllUnordered(set);

/// Order-independent hash agreeing with [mapEquals]. Each entry is hashed as a
/// key/value pair first, so two maps that swap a pair of values do not collide.
int mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered([
  for (final MapEntry(:key, :value) in map.entries) Object.hash(key, value),
]);
