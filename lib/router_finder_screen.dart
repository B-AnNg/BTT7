import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class RouteFinderScreen extends StatefulWidget {
  const RouteFinderScreen({super.key});

  @override
  _RouteFinderScreenState createState() => _RouteFinderScreenState();
}

class _RouteFinderScreenState extends State<RouteFinderScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  
  // Khai báo Set có định dạng kiểu dữ liệu rõ ràng để tránh lỗi Linter
  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  LatLng? _startLatLng;
  LatLng? _endLatLng;

  String _distanceText = "";
  String _durationText = "";

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(10.7769, 106.7009), // Mặc định TP.HCM
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // 1. Lấy vị trí hiện tại
  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    if (!mounted) return;
    setState(() {
      _startLatLng = LatLng(position.latitude, position.longitude);
      _addMarker(_startLatLng!, "Xuất phát", BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));
      _moveCamera(_startLatLng!);
      _startController.text = "${position.latitude}, ${position.longitude}";
    });
  }

  // Thêm Marker
  void _addMarker(LatLng position, String markerId, [BitmapDescriptor? icon]) {
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          icon: icon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(title: markerId),
        ),
      );
    });
  }

  Future<void> _moveCamera(LatLng position) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(position));
  }

  // 2. Chức năng click trên bản đồ để chọn điểm đích
  void _onMapTapped(LatLng tappedPosition) {
    setState(() {
      _endLatLng = tappedPosition;
      _endController.text = "${tappedPosition.latitude}, ${tappedPosition.longitude}";
      _markers.removeWhere((m) => m.markerId.value == "Đích đến");
      _addMarker(_endLatLng!, "Đích đến", BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed));
    });
  }

  // 3. Tìm đường đi và lấy Khoảng cách / Thời gian
  Future<void> _findRoute() async {
    // Lưu biến messenger ở đầu hàm để không bị lỗi "BuildContext across async gaps"
    final messenger = ScaffoldMessenger.of(context);

    if (_startController.text.isEmpty || _endController.text.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập hoặc chọn cả hai điểm!')),
      );
      return;
    }

    try {
      List<String> startSplit = _startController.text.split(',');
      _startLatLng = LatLng(double.parse(startSplit[0].trim()), double.parse(startSplit[1].trim()));

      List<String> endSplit = _endController.text.split(',');
      _endLatLng = LatLng(double.parse(endSplit[0].trim()), double.parse(endSplit[1].trim()));

      String apiKey = "AIzaSyAm6ZahZpWjrcDc_WV5EQ5qRRIGDecqfjM"; // Chú ý: Đổi thành API Key của bạn
      String url =
          "https://maps.googleapis.com/maps/api/directions/json?origin=${_startLatLng!.latitude},${_startLatLng!.longitude}&destination=${_endLatLng!.latitude},${_endLatLng!.longitude}&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (!mounted) return; // Kiểm tra an toàn trước khi dùng setState

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          var leg = data['routes'][0]['legs'][0];

          setState(() {
            _distanceText = leg['distance']['text'];
            _durationText = leg['duration']['text'];
          });

          String polylinePoints = data['routes'][0]['overview_polyline']['points'];
          List<LatLng> points = _decodePolyline(polylinePoints);

          setState(() {
            _markers.clear();
            _addMarker(_startLatLng!, "Xuất phát", BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));
            _addMarker(_endLatLng!, "Đích đến", BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed));

            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: Colors.blue,
                width: 5,
              ),
            );
          });
          _moveCamera(_startLatLng!);
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Không tìm thấy tuyến đường nào!')),
          );
        }
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Lỗi khi gọi API: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Định dạng tọa độ không hợp lệ!')),
      );
    }
  }

  // Giải mã chuỗi tuyến đường
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route Finder - Bài 3')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _startController,
                  decoration: InputDecoration(
                    labelText: 'Điểm xuất phát (lat, lng)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location),
                      onPressed: _getCurrentLocation,
                      tooltip: 'Lấy vị trí hiện tại',
                    ),
                  ),
                ),
                TextField(
                  controller: _endController,
                  decoration: const InputDecoration(
                    labelText: 'Điểm đích (lat, lng) - Hoặc click trên bản đồ',
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _findRoute,
                  child: const Text('Tìm đường đi'),
                ),
                if (_distanceText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Khoảng cách: $_distanceText | Thời gian: $_durationText',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                  ),
                ]
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              onTap: _onMapTapped, 
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),
        ],
      ),
    );
  }
}