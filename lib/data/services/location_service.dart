import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String locationName;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.locationName,
  });
}

class LocationService {
  Future<bool> hasPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<LocationResult?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      String placeName = '';
      try {
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[];
          if (p.name != null && p.name!.isNotEmpty && p.name != p.street) {
            parts.add(p.name!);
          } else if (p.street != null && p.street!.isNotEmpty) {
            parts.add(p.street!);
          }
          if (p.subLocality != null && p.subLocality!.isNotEmpty && !parts.contains(p.subLocality)) {
            parts.add(p.subLocality!);
          }
          if (p.locality != null && p.locality!.isNotEmpty && !parts.contains(p.locality)) {
            parts.add(p.locality!);
          } else if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) {
            parts.add(p.subAdministrativeArea!);
          }
          placeName = parts.join(', ');
        }
      } catch (_) {
        // Reverse geocoding fallback if network unavailable
      }

      if (placeName.isEmpty) {
        placeName = 'Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
      }

      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: placeName,
      );
    } catch (_) {
      return null;
    }
  }
}
