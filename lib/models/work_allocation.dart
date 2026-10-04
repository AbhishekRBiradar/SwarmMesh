/// A resource available to process one contiguous portion of an input list.
class WorkResource<T> {
  final T resource;
  final double weight;

  const WorkResource({required this.resource, required this.weight});
}

/// One resource's contiguous allocation. Empty allocations are omitted.
class WorkAllocation<T, R> {
  final R resource;
  final List<T> items;

  const WorkAllocation({required this.resource, required this.items});
}

/// Splits [items] proportionally by finite, strictly positive [weight].
///
/// Input order is retained, allocations are contiguous, and every input item
/// occurs in exactly one returned allocation. A resource may receive no items
/// when there are more resources than input items. Invalid resource weights and
/// an empty resource list are rejected explicitly.
List<WorkAllocation<T, R>> partitionByResourceWeight<T, R>({
  required Iterable<T> items,
  required Iterable<WorkResource<R>> resources,
}) {
  final input = List<T>.of(items);
  final available = List<WorkResource<R>>.of(resources);
  if (available.isEmpty && input.isNotEmpty) {
    throw ArgumentError(
      'At least one resource is required for non-empty input',
    );
  }
  if (available.any(
    (resource) => !resource.weight.isFinite || resource.weight <= 0,
  )) {
    throw ArgumentError('Resource weights must be finite and positive');
  }
  if (input.isEmpty || available.isEmpty) {
    return <WorkAllocation<T, R>>[];
  }

  final totalWeight = available.fold<double>(
    0,
    (sum, resource) => sum + resource.weight,
  );
  if (!totalWeight.isFinite || totalWeight <= 0) {
    throw ArgumentError('Resource weights must have a finite positive total');
  }

  final minimum = available.length <= input.length
      ? available.length
      : input.length;
  final extraItems = input.length - minimum;
  final fractional = <_WeightedRemainder>[];
  final counts = List<int>.filled(available.length, 0);
  for (var index = 0; index < minimum; index++) {
    counts[index] = 1;
  }
  for (var index = 0; index < available.length; index++) {
    final exactExtra = extraItems * available[index].weight / totalWeight;
    final wholeExtra = exactExtra.floor();
    counts[index] += wholeExtra;
    fractional.add(
      _WeightedRemainder(index: index, remainder: exactExtra - wholeExtra),
    );
  }
  var assigned = counts.fold<int>(0, (sum, count) => sum + count);
  fractional.sort((a, b) {
    final byRemainder = b.remainder.compareTo(a.remainder);
    return byRemainder == 0 ? a.index.compareTo(b.index) : byRemainder;
  });
  for (var index = 0; assigned < input.length; index++, assigned++) {
    counts[fractional[index % fractional.length].index]++;
  }

  final allocations = <WorkAllocation<T, R>>[];
  var start = 0;
  for (var index = 0; index < available.length; index++) {
    final count = counts[index];
    if (count == 0) continue;
    allocations.add(
      WorkAllocation<T, R>(
        resource: available[index].resource,
        items: List<T>.unmodifiable(input.sublist(start, start + count)),
      ),
    );
    start += count;
  }

  // The final resource is exact by construction. This guard protects the
  // coverage contract if the algorithm is changed later.
  if (start != input.length) {
    throw StateError('Resource partition did not cover every input item');
  }
  return List<WorkAllocation<T, R>>.unmodifiable(allocations);
}

class _WeightedRemainder {
  final int index;
  final double remainder;

  const _WeightedRemainder({required this.index, required this.remainder});
}
