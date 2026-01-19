import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_client.dart';
import 'map_screen.dart';

Widget buildRimgazAppTitle(String subtitle) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/rimgazlogo.jpeg',
            fit: BoxFit.cover,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RimGaz',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    ],
  );
}

class AdminDashboardScreen extends StatefulWidget {
  final String username;

  const AdminDashboardScreen({super.key, required this.username});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;
  int _busCount = 0;
  int _clientCount = 0;
  int _alertCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buses = await ApiClient.instance.fetchBusPositions();
      final alerts = await ApiClient.instance.fetchBusAlerts();
      final clients = await ApiClient.instance.fetchClients();
      if (!mounted) return;
      setState(() {
        _busCount = buses.length;
        _alertCount = alerts.length;
        _clientCount = clients.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('Tableau administrateur'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                widget.username,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () {
              ApiClient.instance.logout();
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Erreur de chargement'),
                  subtitle: Text(_error!),
                ),
              ),
            Row(
              children: [
                _KpiCard(
                  color: Colors.blue,
                  icon: Icons.directions_bus,
                  label: 'Bus en suivi',
                  value: _busCount.toString(),
                ),
                const SizedBox(width: 12),
                _KpiCard(
                  color: Colors.green,
                  icon: Icons.location_on_outlined,
                  label: 'Clients',
                  value: _clientCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _KpiCard(
              color: Colors.red,
              icon: Icons.warning_amber_outlined,
              label: 'Alertes bus actives',
              value: _alertCount.toString(),
              expanded: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Rafraîchir'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MapScreen()),
                );
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ouvrir la carte'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BusHistoryScreen()),
                );
              },
              icon: const Icon(Icons.timeline),
              label: const Text('Historique du bus (aujourd\'hui)'),
            ),
          ],
        ),
      ),
    );
  }
}

class BusHistoryScreen extends StatefulWidget {
  const BusHistoryScreen({super.key});

  @override
  State<BusHistoryScreen> createState() => _BusHistoryScreenState();
}

class _BusHistoryScreenState extends State<BusHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _buses = [];
  int? _selectedBusId;
  List<dynamic> _positions = [];

  @override
  void initState() {
    super.initState();
    _loadBuses();
  }

  Future<void> _loadBuses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buses = await ApiClient.instance.fetchBuses();
      if (!mounted) return;
      setState(() {
        _buses = buses;
        if (_buses.isNotEmpty) {
          _selectedBusId ??= _buses.first['id'] as int?;
        }
      });
      if (_selectedBusId != null) {
        await _loadHistory();
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_selectedBusId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await ApiClient.instance.fetchBusPositions();
      if (!mounted) return;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final filtered = all.where((p) {
        if (p['bus'] != _selectedBusId) return false;
        final created = p['created_at']?.toString();
        if (created == null) return false;
        return created.startsWith(today);
      }).toList();

      // L'API renvoie les positions par created_at desc, on inverse pour le tracé
      filtered.sort((a, b) {
        final ca = a['created_at']?.toString() ?? '';
        final cb = b['created_at']?.toString() ?? '';
        return ca.compareTo(cb);
      });

      setState(() {
        _positions = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    for (final p in _positions) {
      final lat = double.tryParse(p['latitude'].toString());
      final lon = double.tryParse(p['longitude'].toString());
      if (lat == null || lon == null) continue;
      points.add(LatLng(lat, lon));
    }

    LatLng center;
    if (points.isNotEmpty) {
      center = points.last;
    } else {
      center = const LatLng(18.078, -15.978);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique du bus (aujourd\'hui)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: ListTile(
                      leading:
                          const Icon(Icons.error_outline, color: Colors.red),
                      title: const Text('Erreur de chargement'),
                      subtitle: Text(_error!),
                    ),
                  ),
                DropdownButtonFormField<int>(
                  value: _selectedBusId,
                  decoration: const InputDecoration(
                    labelText: 'Bus',
                  ),
                  items: _buses
                      .map<DropdownMenuItem<int>>(
                        (b) => DropdownMenuItem<int>(
                          value: b['id'] as int,
                          child:
                              Text(b['name']?.toString() ?? 'Bus ${b['id']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBusId = val;
                    });
                    _loadHistory();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Points pour aujourd\'hui: ${_positions.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _loadHistory,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Recharger',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.rimgaz_mobile',
                ),
                if (points.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: Colors.blue,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                if (points.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 32,
                        height: 32,
                        point: points.first,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.green,
                          size: 26,
                        ),
                      ),
                      Marker(
                        width: 32,
                        height: 32,
                        point: points.last,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DriverDashboardScreen extends StatefulWidget {
  final String username;

  const DriverDashboardScreen({super.key, required this.username});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _buses = [];
  int? _selectedBusId;
  List<dynamic> _orders = [];
  String _searchText = '';
  double? _busLat;
  double? _busLon;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buses = await ApiClient.instance.fetchBuses();
      final orders = await ApiClient.instance.fetchDriverOrders();
      if (!mounted) return;
      setState(() {
        _buses = buses;
        _orders = orders;
      });
      if (_selectedBusId != null) {
        await _loadBusPosition();
        _startLocationTracking();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBusPosition() async {
    if (_selectedBusId == null) return;
    try {
      final positions = await ApiClient.instance.fetchBusPositions();
      final busPositions =
          positions.where((p) => p['bus'] == _selectedBusId).toList();
      if (busPositions.isEmpty) return;
      // Les positions sont déjà triées par created_at desc côté API
      final latest = busPositions.first;
      final lat = double.tryParse(latest['latitude'].toString());
      final lon = double.tryParse(latest['longitude'].toString());
      if (!mounted) return;
      setState(() {
        _busLat = lat;
        _busLon = lon;
      });
    } catch (_) {
      // Ignorer les erreurs de position pour ne pas gêner le chauffeur
    }
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  void _startLocationTracking() async {
    if (_selectedBusId == null) return;
    _locationTimer?.cancel();

    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Localisation désactivée. Activez-la pour suivre le bus en temps réel.'),
        ),
      );
      return;
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (!mounted || _selectedBusId == null) return;
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await ApiClient.instance.sendBusPosition(
          busId: _selectedBusId!,
          latitude: position.latitude,
          longitude: position.longitude,
          status: 'on_tour',
        );
      } catch (e) {
        // Ne pas spammer l'utilisateur en cas d'erreur
        debugPrint('Erreur tracking localisation chauffeur: $e');
      }
    });
  }

  Future<void> _refreshOrders() async {
    try {
      final orders = await ApiClient.instance.fetchDriverOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
      });
      await _loadBusPosition();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement commandes: $e')),
      );
    }
  }

  Widget _buildDriverMap(List<dynamic> orders) {
    // Déterminer le centre initial de la carte
    LatLng center;
    if (_busLat != null && _busLon != null) {
      center = LatLng(_busLat!, _busLon!);
    } else {
      // Essayer de centrer sur le premier client avec coordonnées
      LatLng? firstClient;
      for (final o in orders) {
        final lat = o['client_gps_latitude'];
        final lon = o['client_gps_longitude'];
        if (lat != null && lon != null) {
          final dLat = double.tryParse(lat.toString());
          final dLon = double.tryParse(lon.toString());
          if (dLat != null && dLon != null) {
            firstClient = LatLng(dLat, dLon);
            break;
          }
        }
      }
      center = firstClient ?? const LatLng(18.078, -15.978);
    }

    final markers = <Marker>[];

    // Marqueur du bus
    if (_busLat != null && _busLon != null) {
      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: LatLng(_busLat!, _busLon!),
          child: const Icon(
            Icons.directions_bus,
            color: Colors.blue,
            size: 32,
          ),
        ),
      );
    }

    // Marqueurs des clients à livrer
    for (final o in orders) {
      final lat = o['client_gps_latitude'];
      final lon = o['client_gps_longitude'];
      if (lat == null || lon == null) continue;
      final dLat = double.tryParse(lat.toString());
      final dLon = double.tryParse(lon.toString());
      if (dLat == null || dLon == null) continue;
      markers.add(
        Marker(
          width: 36,
          height: 36,
          point: LatLng(dLat, dLon),
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 30,
          ),
        ),
      );
    }

    return Card(
      child: SizedBox(
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.rimgaz_mobile',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
      ),
    );
  }

  List<dynamic> get _filteredOrders {
    final pending = _orders
        .where((o) => o['status'] == 'pending' || o['status'] == 'validated')
        .toList();

    // Trier par proximité si la position du bus et du client est connue
    if (_busLat != null && _busLon != null) {
      pending.sort((a, b) {
        double dist(Map o) {
          final lat = o['client_gps_latitude'];
          final lon = o['client_gps_longitude'];
          if (lat == null || lon == null) return double.maxFinite;
          final dLat = (double.tryParse(lat.toString()) ?? 0) - _busLat!;
          final dLon = (double.tryParse(lon.toString()) ?? 0) - _busLon!;
          return dLat * dLat + dLon * dLon;
        }

        final da = dist(a as Map);
        final db = dist(b as Map);
        return da.compareTo(db);
      });
    }
    if (_searchText.trim().isEmpty) {
      return pending;
    }
    final q = _searchText.toLowerCase();
    return pending.where((o) {
      final client = (o['client'] ?? '').toString().toLowerCase();
      final addr = (o['client_address'] ?? '').toString().toLowerCase();
      return client.contains(q) || addr.contains(q);
    }).toList();
  }

  Future<void> _markDelivered(Map<String, dynamic> order) async {
    final id = order['id'] as int?;
    if (id == null) return;
    try {
      await ApiClient.instance.markOrderDelivered(orderId: id);
      if (!mounted) return;
      await _refreshOrders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande #$id marquée comme livrée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la livraison: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _filteredOrders;
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('Tableau chauffeur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () {
              ApiClient.instance.logout();
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshOrders();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Erreur de chargement'),
                  subtitle: Text(_error!),
                ),
              ),
            Text(
              'Bonjour, ${widget.username}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bus du jour',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _selectedBusId,
                      decoration: const InputDecoration(
                        labelText: 'Sélectionnez votre bus',
                      ),
                      items: _buses
                          .map<DropdownMenuItem<int>>(
                            (b) => DropdownMenuItem<int>(
                              value: b['id'] as int,
                              child: Text(
                                  b['name']?.toString() ?? 'Bus ${b['id']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedBusId = val;
                        });
                        _loadBusPosition();
                        _startLocationTracking();
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DriverMapScreen(
                                orders: orders,
                                selectedBusId: _selectedBusId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.fullscreen),
                        label: const Text('Carte plein écran'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (orders.isNotEmpty || (_busLat != null && _busLon != null))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Carte de la tournée',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDriverMap(orders),
                  const SizedBox(height: 12),
                ],
              ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Rechercher par client ou adresse',
              ),
              onChanged: (v) {
                setState(() {
                  _searchText = v;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_loading && _orders.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Aucune commande en attente pour le moment.'),
                ),
              )
            else ...[
              const Text(
                'Commandes à livrer',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final o in orders)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading:
                        const Icon(Icons.local_gas_station, color: Colors.blue),
                    title:
                        Text('${o['quantity']} x ${o['bottle_type']?['name']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (o['client'] != null) Text('Client: ${o['client']}'),
                        if (o['client_address'] != null &&
                            (o['client_address'] as String).isNotEmpty)
                          Text('Adresse: ${o['client_address']}'),
                        if (o['status'] != null) Text('Statut: ${o['status']}'),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: () =>
                          _markDelivered(Map<String, dynamic>.from(o as Map)),
                      child: const Text('Livrée'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class DriverMapScreen extends StatefulWidget {
  final List<dynamic> orders;
  final int? selectedBusId;

  const DriverMapScreen({
    super.key,
    required this.orders,
    this.selectedBusId,
  });

  @override
  State<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends State<DriverMapScreen> {
  bool _loading = true;
  bool _showAllClients = false;
  double? _busLat;
  double? _busLon;
  List<dynamic> _clients = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() {
      _loading = true;
    });
    try {
      // Charger la position du bus sélectionné
      if (widget.selectedBusId != null) {
        final positions = await ApiClient.instance.fetchBusPositions();
        final busPositions =
            positions.where((p) => p['bus'] == widget.selectedBusId).toList();
        if (busPositions.isNotEmpty) {
          final latest = busPositions.first;
          final lat = double.tryParse(latest['latitude'].toString());
          final lon = double.tryParse(latest['longitude'].toString());
          if (mounted) {
            setState(() {
              _busLat = lat;
              _busLon = lon;
            });
          }
        }
      }

      // Précharger la liste complète des clients pour l'option "voir tous les clients"
      final clients = await ApiClient.instance.fetchClients();
      if (mounted) {
        setState(() {
          _clients = clients;
        });
      }
    } catch (_) {
      // Ignorer les erreurs pour ne pas bloquer l'affichage de la carte
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Construire les marqueurs
    final markers = <Marker>[];

    if (_busLat != null && _busLon != null) {
      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: LatLng(_busLat!, _busLon!),
          child: const Icon(
            Icons.directions_bus,
            color: Colors.blue,
            size: 32,
          ),
        ),
      );
    }

    // Clients avec commande en attente
    for (final o in widget.orders) {
      final lat = o['client_gps_latitude'];
      final lon = o['client_gps_longitude'];
      if (lat == null || lon == null) continue;
      final dLat = double.tryParse(lat.toString());
      final dLon = double.tryParse(lon.toString());
      if (dLat == null || dLon == null) continue;
      markers.add(
        Marker(
          width: 32,
          height: 32,
          point: LatLng(dLat, dLon),
          child: GestureDetector(
            onTap: () {
              _showOrderDetails(Map<String, dynamic>.from(o as Map));
            },
            child: const Icon(
              Icons.location_on,
              color: Colors.red,
              size: 28,
            ),
          ),
        ),
      );
    }

    // Tous les clients (optionnelle)
    if (_showAllClients) {
      for (final c in _clients) {
        final lat = c['gps_latitude'];
        final lon = c['gps_longitude'];
        if (lat == null || lon == null) continue;
        final dLat = double.tryParse(lat.toString());
        final dLon = double.tryParse(lon.toString());
        if (dLat == null || dLon == null) continue;
        markers.add(
          Marker(
            width: 28,
            height: 28,
            point: LatLng(dLat, dLon),
            child: const Icon(
              Icons.circle,
              color: Colors.green,
              size: 10,
            ),
          ),
        );
      }
    }

    // Centre initial de la carte
    LatLng center;
    if (_busLat != null && _busLon != null) {
      center = LatLng(_busLat!, _busLon!);
    } else {
      LatLng? first;
      if (widget.orders.isNotEmpty) {
        for (final o in widget.orders) {
          final lat = o['client_gps_latitude'];
          final lon = o['client_gps_longitude'];
          if (lat == null || lon == null) continue;
          final dLat = double.tryParse(lat.toString());
          final dLon = double.tryParse(lon.toString());
          if (dLat != null && dLon != null) {
            first = LatLng(dLat, dLon);
            break;
          }
        }
      }
      center = first ?? const LatLng(18.078, -15.978);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte chauffeur'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.rimgaz_mobile',
                ),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: const [
                Icon(Icons.directions_bus, color: Colors.blue, size: 18),
                SizedBox(width: 4),
                Text('Bus'),
                SizedBox(width: 12),
                Icon(Icons.location_on, color: Colors.red, size: 18),
                SizedBox(width: 4),
                Text('Clients avec commande'),
                SizedBox(width: 12),
                Icon(Icons.circle, color: Colors.green, size: 10),
                SizedBox(width: 4),
                Text('Tous les clients'),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Voir tous les clients'),
            value: _showAllClients,
            onChanged: (v) {
              setState(() {
                _showAllClients = v;
              });
            },
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commande #${order['id'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (order['client'] != null) Text('Client: ${order['client']}'),
                if (order['client_address'] != null &&
                    (order['client_address'] as String).isNotEmpty)
                  Text('Adresse: ${order['client_address']}'),
                if (order['quantity'] != null || order['bottle_type'] != null)
                  Text(
                    'Bouteilles: ${order['quantity']} x ${order['bottle_type']?['name']}',
                  ),
                if (order['status'] != null) Text('Statut: ${order['status']}'),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ClientDashboardScreen extends StatelessWidget {
  final String username;

  const ClientDashboardScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return ClientDashboardShell(username: username);
  }
}

class ClientDashboardShell extends StatefulWidget {
  final String username;

  const ClientDashboardShell({super.key, required this.username});

  @override
  State<ClientDashboardShell> createState() => _ClientDashboardShellState();
}

class _ClientDashboardShellState extends State<ClientDashboardShell> {
  bool _loading = true;
  String? _error;
  List<dynamic> _bottles = [];
  List<dynamic> _orders = [];
  List<dynamic> _payments = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Rafraîchissement périodique pour détecter les validations côté back-office
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      // Pour les performances: ne rafraîchir automatiquement que s'il
      // existe au moins une commande ou un paiement en attente.
      final hasPendingOrders = _orders.any((o) => o['status'] == 'pending');
      final hasPendingPayments = _payments.any(
          (p) => p['status'] == 'pending' || p['status'] == 'pending_admin');
      if (hasPendingOrders || hasPendingPayments) {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Sauvegarder l'état précédent pour détecter les changements de statut
    final previousOrders = List<dynamic>.from(_orders);
    final previousPayments = List<dynamic>.from(_payments);
    try {
      final bottles = await ApiClient.instance.fetchBottleTypes();
      final orders = await ApiClient.instance.fetchClientOrders();
      final payments = await ApiClient.instance.fetchClientPayments();
      if (!mounted) return;
      setState(() {
        _bottles = bottles;
        _orders = orders;
        _payments = payments;
      });

      // Détecter les changements de statut pour informer le client
      final List<String> notifications = [];

      // Changement de statut des commandes
      Map<int, String> _statusMap(List<dynamic> items) {
        final map = <int, String>{};
        for (final o in items) {
          final id = o['id'];
          final status = o['status'];
          if (id is int && status is String) {
            map[id] = status;
          }
        }
        return map;
      }

      final prevOrderStatus = _statusMap(previousOrders);
      final newOrderStatus = _statusMap(orders);
      newOrderStatus.forEach((id, newStatus) {
        final oldStatus = prevOrderStatus[id];
        if (oldStatus != null && oldStatus != newStatus) {
          if (newStatus == 'validated') {
            notifications.add('Votre commande #$id a été validée.');
          } else if (newStatus == 'cancelled') {
            notifications.add('Votre commande #$id a été annulée.');
          }
        }
      });

      // Changement de statut des paiements (validation / rejet)
      final prevPaymentStatus = _statusMap(previousPayments);
      final newPaymentStatus = _statusMap(payments);
      newPaymentStatus.forEach((id, newStatus) {
        final oldStatus = prevPaymentStatus[id];
        if (oldStatus != null && oldStatus != newStatus) {
          if (newStatus == 'validated') {
            notifications.add('Votre paiement #$id a été validé.');
          } else if (newStatus == 'rejected') {
            notifications.add('Votre paiement #$id a été rejeté.');
          }
        }
      });

      for (final msg in notifications) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openUploadReceiptDialog(Map<String, dynamic> payment) async {
    final picker = ImagePicker();

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        String selectedMethod = 'bankily';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text('Méthode de paiement'),
                      subtitle: Text('Choisissez comment vous avez payé'),
                    ),
                    RadioListTile<String>(
                      value: 'bankily',
                      groupValue: selectedMethod,
                      title: const Text('Bankily'),
                      onChanged: (v) => setModalState(() {
                        selectedMethod = v ?? 'bankily';
                      }),
                    ),
                    RadioListTile<String>(
                      value: 'masrvi',
                      groupValue: selectedMethod,
                      title: const Text('Masrvi'),
                      onChanged: (v) => setModalState(() {
                        selectedMethod = v ?? 'masrvi';
                      }),
                    ),
                    RadioListTile<String>(
                      value: 'sedad',
                      groupValue: selectedMethod,
                      title: const Text('Sedad'),
                      onChanged: (v) => setModalState(() {
                        selectedMethod = v ?? 'sedad';
                      }),
                    ),
                    RadioListTile<String>(
                      value: 'click',
                      groupValue: selectedMethod,
                      title: const Text('Click'),
                      onChanged: (v) => setModalState(() {
                        selectedMethod = v ?? 'click';
                      }),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.photo),
                      title: const Text('Choisir depuis la galerie'),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 75,
                        );
                        if (picked == null) return;
                        try {
                          await ApiClient.instance.uploadClientPaymentReceipt(
                            paymentId: payment['id'] as int,
                            filePath: picked.path,
                            method: selectedMethod,
                          );
                          if (!mounted) return;
                          await _loadData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reçu envoyé avec succès.'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Erreur lors de l\'envoi du reçu: ${e.toString()}'),
                            ),
                          );
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_camera),
                      title: const Text('Prendre une photo'),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final picked = await picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 75,
                        );
                        if (picked == null) return;
                        try {
                          await ApiClient.instance.uploadClientPaymentReceipt(
                            paymentId: payment['id'] as int,
                            filePath: picked.path,
                            method: selectedMethod,
                          );
                          if (!mounted) return;
                          await _loadData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reçu envoyé avec succès.'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Erreur lors de l\'envoi du reçu: ${e.toString()}'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openCreateOrderDialog() async {
    if (_bottles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun type de bouteille configuré.')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final List<int> selectedIndexes = [0];
    final List<TextEditingController> qtyCtrls = [
      TextEditingController(text: '1'),
    ];
    final List<bool> includeDeposit = [false];

    double _computeLineGasTotal(int lineIndex) {
      final bottle = _bottles[selectedIndexes[lineIndex]];
      final unit = double.tryParse(bottle['price_mru'].toString()) ?? 0;
      final q = int.tryParse(qtyCtrls[lineIndex].text) ?? 0;
      return unit * q;
    }

    double _computeLineDepositTotal(int lineIndex) {
      if (!includeDeposit[lineIndex]) {
        return 0;
      }
      final bottle = _bottles[selectedIndexes[lineIndex]];
      final deposit = double.tryParse(bottle['deposit_mru'].toString()) ?? 0;
      final q = int.tryParse(qtyCtrls[lineIndex].text) ?? 0;
      return deposit * q;
    }

    double _computeGlobalGasTotal() {
      double total = 0;
      for (int i = 0; i < selectedIndexes.length; i++) {
        total += _computeLineGasTotal(i);
      }
      return total;
    }

    double _computeGlobalDepositTotal() {
      double total = 0;
      for (int i = 0; i < selectedIndexes.length; i++) {
        total += _computeLineDepositTotal(i);
      }
      return total;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Nouvelle demande de gaz'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: MediaQuery.of(ctx).size.width * 0.8,
                  height: MediaQuery.of(ctx).size.height * 0.6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int i = 0;
                                  i < selectedIndexes.length;
                                  i++) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        value: selectedIndexes[i],
                                        decoration: InputDecoration(
                                          labelText:
                                              'Type de bouteille ${selectedIndexes.length > 1 ? '#${i + 1}' : ''}',
                                        ),
                                        items: [
                                          for (int j = 0;
                                              j < _bottles.length;
                                              j++)
                                            DropdownMenuItem(
                                              value: j,
                                              child: Text(
                                                '${_bottles[j]['name']} (${_bottles[j]['capacity_kg']}kg)',
                                              ),
                                            )
                                        ],
                                        onChanged: (val) {
                                          if (val == null) return;
                                          setStateDialog(() {
                                            selectedIndexes[i] = val;
                                          });
                                        },
                                      ),
                                    ),
                                    if (selectedIndexes.length > 1)
                                      IconButton(
                                        tooltip: 'Supprimer cette ligne',
                                        onPressed: () {
                                          setStateDialog(() {
                                            selectedIndexes.removeAt(i);
                                            qtyCtrls.removeAt(i);
                                            includeDeposit.removeAt(i);
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.redAccent),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: qtyCtrls[i],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: false),
                                  decoration: const InputDecoration(
                                    labelText: 'Quantité',
                                  ),
                                  validator: (v) {
                                    final q = int.tryParse((v ?? '').trim());
                                    if (q == null || q <= 0) {
                                      return 'Quantité invalide';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) => setStateDialog(() {}),
                                ),
                                const SizedBox(height: 4),
                                CheckboxListTile(
                                  value: includeDeposit[i],
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text(
                                    'Ajouter la caution (nouvelle bouteille)',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onChanged: (v) {
                                    setStateDialog(() {
                                      includeDeposit[i] = v ?? false;
                                    });
                                  },
                                ),
                                const SizedBox(height: 2),
                                Builder(
                                  builder: (_) {
                                    final lineGas = _computeLineGasTotal(i);
                                    final lineDeposit =
                                        _computeLineDepositTotal(i);
                                    final lineTotal = lineGas + lineDeposit;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Gaz: ${lineGas.toStringAsFixed(0)} MRU · Caution: ${lineDeposit.toStringAsFixed(0)} MRU',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          'Total ligne: ${lineTotal.toStringAsFixed(0)} MRU',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const Divider(height: 16),
                              ],
                              TextButton.icon(
                                onPressed: () {
                                  setStateDialog(() {
                                    selectedIndexes.add(0);
                                    qtyCtrls
                                        .add(TextEditingController(text: '1'));
                                    includeDeposit.add(false);
                                  });
                                },
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text(
                                    'Ajouter un autre type de bouteille'),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      Builder(
                        builder: (_) {
                          final totalGas = _computeGlobalGasTotal();
                          final totalDeposit = _computeGlobalDepositTotal();
                          final total = totalGas + totalDeposit;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total gaz: ${totalGas.toStringAsFixed(0)} MRU',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                'Total caution: ${totalDeposit.toStringAsFixed(0)} MRU',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Total estimé global: ${total.toStringAsFixed(0)} MRU',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      int createdCount = 0;
                      for (int i = 0; i < selectedIndexes.length; i++) {
                        final q = int.tryParse(qtyCtrls[i].text) ?? 0;
                        if (q <= 0) continue;
                        final bottle = _bottles[selectedIndexes[i]];
                        await ApiClient.instance.createClientOrder(
                          bottleTypeId: bottle['id'] as int,
                          quantity: q,
                        );
                        createdCount++;
                      }
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      await _loadData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            createdCount > 1
                                ? '$createdCount demandes créées avec succès.'
                                : 'Demande créée avec succès.',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Erreur lors de la commande: ${e.toString()}'),
                        ),
                      );
                    }
                  },
                  child: const Text('Confirmer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('RimGaz - Espace client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () {
              ApiClient.instance.logout();
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    child: Icon(Icons.person, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bienvenue,',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        widget.username,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                    ),
                    title: const Text('Erreur de chargement'),
                    subtitle: Text(_error!),
                  ),
                ),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.pending_actions,
                title: 'Paiements en attente',
                color: Colors.deepOrange,
                initiallyExpanded: true,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final pendingPayments = _payments
                            .where((payment) =>
                                payment['status'] == 'pending' ||
                                payment['status'] == 'pending_admin')
                            .toList();
                        // Trier par date décroissante si possible
                        pendingPayments.sort((a, b) {
                          final aDate = DateTime.tryParse(
                              (a['created_at'] ?? '') as String);
                          final bDate = DateTime.tryParse(
                              (b['created_at'] ?? '') as String);
                          if (aDate == null || bDate == null) return 0;
                          return bDate.compareTo(aDate);
                        });
                        if (pendingPayments.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('Aucun paiement en attente.'),
                          );
                        }
                        final preview = pendingPayments.length > 5
                            ? pendingPayments.take(5).toList()
                            : pendingPayments;
                        return Column(
                          children: [
                            for (final payment in preview)
                              Card(
                                elevation: 0,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.payment),
                                  title: Text(
                                      'Montant: ${payment['amount_mru']} MRU'),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (payment['order_id'] != null)
                                        Text(
                                            'Commande #${payment['order_id']}'),
                                      Text(
                                        payment['status'] == 'pending_admin'
                                            ? 'Reçu envoyé, en attente de validation'
                                            : 'En attente de paiement',
                                      ),
                                    ],
                                  ),
                                  trailing: TextButton.icon(
                                    onPressed: () => _openUploadReceiptDialog(
                                        payment as Map<String, dynamic>),
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Envoyer reçu'),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PendingPaymentsScreen(
                                        payments: pendingPayments,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                    'Voir tout (${pendingPayments.length})'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.receipt_long,
                title: 'Historique des paiements',
                color: Colors.teal,
                initiallyExpanded: false,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Aucun paiement pour le moment.'),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final sorted = List<Map<String, dynamic>>.from(
                            _payments.cast<Map<String, dynamic>>());
                        sorted.sort((a, b) {
                          final aDate = DateTime.tryParse(
                              (a['created_at'] ?? '') as String);
                          final bDate = DateTime.tryParse(
                              (b['created_at'] ?? '') as String);
                          if (aDate == null || bDate == null) return 0;
                          return bDate.compareTo(aDate);
                        });
                        final preview = sorted.length > 5
                            ? sorted.take(5).toList()
                            : sorted;
                        return Column(
                          children: [
                            for (final payment in preview)
                              _buildPaymentHistoryTile(payment),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentsHistoryScreen(
                                        payments: sorted,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                    'Voir tout (${sorted.length} paiements)'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.history,
                title: 'Historique des demandes',
                color: Colors.indigo,
                initiallyExpanded: false,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_orders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Aucune demande pour le moment.'),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final sorted = List<Map<String, dynamic>>.from(
                            _orders.cast<Map<String, dynamic>>());
                        sorted.sort((a, b) {
                          final aDate = DateTime.tryParse(
                              (a['created_at'] ?? '') as String);
                          final bDate = DateTime.tryParse(
                              (b['created_at'] ?? '') as String);
                          if (aDate == null || bDate == null) return 0;
                          return bDate.compareTo(aDate);
                        });
                        final preview = sorted.length > 5
                            ? sorted.take(5).toList()
                            : sorted;
                        return Column(
                          children: [
                            for (final order in preview)
                              _buildOrderHistoryTile(order),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => OrdersHistoryScreen(
                                        orders: sorted,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                    'Voir tout (${sorted.length} demandes)'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withOpacity(0.15),
                  ),
                  child: const Icon(
                    Icons.add_shopping_cart,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Nouvelle demande de gaz',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Choisissez le type et la quantité puis validez.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _openCreateOrderDialog,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Créer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: children,
        ),
      ),
    );
  }
}

Widget _buildPaymentHistoryTile(Map<String, dynamic> payment) {
  final String status = payment['status'] as String? ?? '';
  Color statusColor;
  String statusLabel;
  switch (status) {
    case 'validated':
      statusColor = Colors.green;
      statusLabel = 'Validé';
      break;
    case 'rejected':
      statusColor = Colors.red;
      statusLabel = 'Rejeté';
      break;
    case 'pending_admin':
      statusColor = Colors.orange;
      statusLabel = 'En attente administration';
      break;
    case 'pending':
      statusColor = Colors.orange;
      statusLabel = 'En attente paiement';
      break;
    default:
      statusColor = Colors.grey;
      statusLabel = status;
  }

  final dynamic amount = payment['amount_mru'];
  final dynamic orderId = payment['order_id'];
  final String? createdAtRaw = payment['created_at'] as String?;
  String dateLabel = '';
  if (createdAtRaw != null) {
    try {
      final DateTime parsed = DateTime.parse(createdAtRaw);
      dateLabel = '${parsed.day.toString().padLeft(2, '0')}/'
          '${parsed.month.toString().padLeft(2, '0')} '
          '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      dateLabel = createdAtRaw;
    }
  }

  return Card(
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      leading: const Icon(Icons.receipt_long),
      title: Text('Montant: $amount MRU'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (orderId != null) Text('Commande #$orderId'),
          if (dateLabel.isNotEmpty) Text(dateLabel),
        ],
      ),
      trailing: Chip(
        label: Text(statusLabel),
        backgroundColor: statusColor.withOpacity(0.15),
        labelStyle: TextStyle(color: statusColor),
      ),
    ),
  );
}

Widget _buildOrderHistoryTile(Map<String, dynamic> order) {
  final dynamic bottle = order['bottle_type'];
  final String name = bottle != null
      ? '${bottle['name']} (${bottle['capacity_kg']}kg)'
      : 'Type inconnu';
  final dynamic quantity = order['quantity'];
  final dynamic total = order['total_price_mru'];
  final String status = order['status'] as String? ?? '';

  Color statusColor;
  String statusLabel = status;
  switch (status) {
    case 'validated':
      statusColor = Colors.green;
      statusLabel = 'Validée';
      break;
    case 'cancelled':
      statusColor = Colors.red;
      statusLabel = 'Annulée';
      break;
    case 'pending':
      statusColor = Colors.orange;
      statusLabel = 'En attente';
      break;
    default:
      statusColor = Colors.grey;
  }

  final String? createdAtRaw = order['created_at'] as String?;
  String dateLabel = '';
  if (createdAtRaw != null) {
    try {
      final DateTime parsed = DateTime.parse(createdAtRaw);
      dateLabel = '${parsed.day.toString().padLeft(2, '0')}/'
          '${parsed.month.toString().padLeft(2, '0')} '
          '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      dateLabel = createdAtRaw;
    }
  }

  return Card(
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      leading: const Icon(Icons.local_gas_station),
      title: Text('$quantity x $name'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total: $total MRU'),
          if (dateLabel.isNotEmpty) Text(dateLabel),
        ],
      ),
      trailing: Chip(
        label: Text(statusLabel),
        backgroundColor: statusColor.withOpacity(0.15),
        labelStyle: TextStyle(color: statusColor),
      ),
    ),
  );
}

class PendingPaymentsScreen extends StatefulWidget {
  final List<dynamic> payments;

  const PendingPaymentsScreen({super.key, required this.payments});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  DateTimeRange? _range;

  List<Map<String, dynamic>> get _allPending {
    final list = widget.payments
        .where((payment) =>
            payment['status'] == 'pending' ||
            payment['status'] == 'pending_admin')
        .cast<Map<String, dynamic>>()
        .toList();
    list.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '') as String);
      final bDate = DateTime.tryParse((b['created_at'] ?? '') as String);
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return list;
  }

  List<Map<String, dynamic>> get _filtered {
    final all = _allPending;
    final range = _range;
    if (range == null) return all;
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end =
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return all.where((p) {
      final raw = p['created_at'] as String?;
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw);
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 7),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('Paiements en attente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _range == null
                          ? 'Filtrer par intervalle de dates'
                          : 'Du ${_range!.start.day}/${_range!.start.month} au ${_range!.end.day}/${_range!.end.month}',
                    ),
                  ),
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Réinitialiser',
                    onPressed: () => setState(() => _range = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Aucun paiement pour cette période.'),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final payment = items[index];
                      return _buildPaymentHistoryTile(payment);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class PaymentsHistoryScreen extends StatefulWidget {
  final List<dynamic> payments;

  const PaymentsHistoryScreen({super.key, required this.payments});

  @override
  State<PaymentsHistoryScreen> createState() => _PaymentsHistoryScreenState();
}

class _PaymentsHistoryScreenState extends State<PaymentsHistoryScreen> {
  DateTimeRange? _range;

  List<Map<String, dynamic>> get _sorted {
    final list = widget.payments.cast<Map<String, dynamic>>().toList();
    list.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '') as String);
      final bDate = DateTime.tryParse((b['created_at'] ?? '') as String);
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return list;
  }

  List<Map<String, dynamic>> get _filtered {
    final all = _sorted;
    final range = _range;
    if (range == null) return all;
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end =
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return all.where((p) {
      final raw = p['created_at'] as String?;
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw);
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 7),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('Historique des paiements'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _range == null
                          ? 'Filtrer par intervalle de dates'
                          : 'Du ${_range!.start.day}/${_range!.start.month} au ${_range!.end.day}/${_range!.end.month}',
                    ),
                  ),
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Réinitialiser',
                    onPressed: () => setState(() => _range = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Aucun paiement pour cette période.'),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final payment = items[index];
                      return _buildPaymentHistoryTile(payment);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class OrdersHistoryScreen extends StatefulWidget {
  final List<dynamic> orders;

  const OrdersHistoryScreen({super.key, required this.orders});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  DateTimeRange? _range;

  List<Map<String, dynamic>> get _sorted {
    final list = widget.orders.cast<Map<String, dynamic>>().toList();
    list.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '') as String);
      final bDate = DateTime.tryParse((b['created_at'] ?? '') as String);
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return list;
  }

  List<Map<String, dynamic>> get _filtered {
    final all = _sorted;
    final range = _range;
    if (range == null) return all;
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end =
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return all.where((o) {
      final raw = o['created_at'] as String?;
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw);
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 7),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: buildRimgazAppTitle('Historique des demandes'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _range == null
                          ? 'Filtrer par intervalle de dates'
                          : 'Du ${_range!.start.day}/${_range!.start.month} au ${_range!.end.day}/${_range!.end.month}',
                    ),
                  ),
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Réinitialiser',
                    onPressed: () => setState(() => _range = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Aucune demande pour cette période.'),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final order = items[index];
                      return _buildOrderHistoryTile(order);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final bool expanded;

  const _KpiCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (expanded) return card;
    return Expanded(child: card);
  }
}
