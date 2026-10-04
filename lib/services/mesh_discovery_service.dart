import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import '../models/mesh_models.dart';

/// Every active node advertises an endpoint so a Leader can discover workers;
/// discovery never pretends that an advertised device has exchanged telemetry.
class MeshDiscoveryService {
  static const serviceType = '_swarmmesh._tcp';
  static const servicePort = 4040;
  nsd.Discovery? _discovery;
  nsd.Registration? _registration;
  final _services = <String, MeshEndpoint>{};
  final _controller = StreamController<List<MeshEndpoint>>.broadcast();
  Stream<List<MeshEndpoint>> get servicesStream => _controller.stream;

  Future<void> startDiscovery() async {
    if (_discovery != null) return;
    final discovery = await nsd.startDiscovery(serviceType);
    _discovery = discovery;
    discovery.addServiceListener(_handleService);
    // A native callback can arrive before startDiscovery completes.
    for (final service in discovery.services) {
      _handleService(service, nsd.ServiceStatus.found);
    }
  }

  void _handleService(nsd.Service service, nsd.ServiceStatus status) {
    final name = service.name;
    if (name == null) return;
    if (status == nsd.ServiceStatus.lost) {
      _services.remove(name); // lost events need not contain a host or port
    } else {
      final host = service.host;
      final port = service.port;
      if (host == null || port == null || port < 1 || port > 65535) return;
      _services[name] = MeshEndpoint(name: name, host: host, port: port);
    }
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_services.values));
    }
  }

  Future<String> registerNode({
    required String nodeId,
    required int port,
  }) async {
    final shortId = nodeId.replaceFirst('NODE-', '');
    final serviceName = 'SM-$shortId';
    _registration ??= await nsd.register(
      nsd.Service(name: serviceName, type: serviceType, port: port),
    );
    return _registration!.service.name ?? serviceName;
  }

  Future<void> stop() async {
    final discovery = _discovery;
    final registration = _registration;
    // Keep failed handles available for another cleanup attempt.
    try {
      if (discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } finally {
          discovery.removeServiceListener(_handleService);
          _discovery = null;
        }
      }
    } finally {
      if (registration != null) {
        try {
          await nsd.unregister(registration);
        } finally {
          _registration = null;
        }
      }
      _services.clear();
      if (!_controller.isClosed) _controller.add(const []);
    }
  }

  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      await _controller.close();
    }
  }
}
