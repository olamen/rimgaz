import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_client.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _positions = [];

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  Future<void> _loadPositions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.fetchBusPositions();
      if (!mounted) return;
      setState(() {
        _positions = data;
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

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    for (final pos in _positions) {
      try {
        final lat = double.parse(pos['latitude'].toString());
        final lon = double.parse(pos['longitude'].toString());
        final hasAlert = pos['has_alert'] == true;
        markers.add(
          Marker(
            width: 40,
            height: 40,
            point: LatLng(lat, lon),
            child: Icon(
              Icons.location_on,
              color: hasAlert ? Colors.red : Colors.blue,
              size: 32,
            ),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte temps réel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPositions,
          ),
        ],
      ),
      body: _loading && _positions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(18.078, -15.978),
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
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
