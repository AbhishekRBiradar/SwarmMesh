enum WorkloadAvailability { ready, planned }

class WorkloadDefinition {
  const WorkloadDefinition({
    required this.id,
    required this.title,
    required this.summary,
    required this.examples,
    required this.availability,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> examples;
  final WorkloadAvailability availability;
}

/// The platform boundary: each entry describes a workload adapter that can be
/// scheduled across the same approved local mesh. Inventory is one example,
/// not the product identity.
const distributedWorkloads = <WorkloadDefinition>[
  WorkloadDefinition(
    id: 'mathematics',
    title: 'Mathematical computing',
    summary: 'Numerical and discrete tasks.',
    examples: ['Monte Carlo simulation', 'Linear regression', 'Prime factors'],
    availability: WorkloadAvailability.ready,
  ),
  WorkloadDefinition(
    id: 'inventory',
    title: 'Inventory verification',
    summary: 'Decode and validate labels.',
    examples: ['QR/barcode batches', 'Duplicate detection', 'Missing IDs'],
    availability: WorkloadAvailability.ready,
  ),
  WorkloadDefinition(
    id: 'model-training',
    title: 'Model / LLM training',
    summary: 'Planned training adapter.',
    examples: ['Gradient batches', 'Embedding generation', 'Evaluation shards'],
    availability: WorkloadAvailability.planned,
  ),
];
