import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Egypt's centroid, used when a property has no coordinates yet.
const LatLng kEgyptCenter = LatLng(26.8206, 30.8025);
const double kLocationZoom = 6;
const double kLocationZoomPicked = 15;

/// A tap-to-place OpenStreetMap picker.
///
/// OpenStreetMap tiles need no API key, so the flow's "Select Current GPS / Map
/// Location" step works from a plain build with no credentials. It deliberately
/// does not read the device GPS: the customer taps the exact spot, which is
/// more accurate than a coarse fix indoors and needs no runtime permission.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    required this.initial,
    required this.onChanged,
    this.height = 260,
    this.enabled = true,
    super.key,
  });

  final LatLng? initial;
  final ValueChanged<LatLng> onChanged;
  final double height;

  /// Tests set this to false: `flutter_test` blocks real network images, so the
  /// tile layer would only emit noise. When disabled the picker shows the
  /// selected point without a basemap.
  final bool enabled;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late final MapController _controller = MapController();
  late LatLng _selected = widget.initial ?? kEgyptCenter;
  late bool _hasPoint = widget.initial != null;

  void _select(LatLng point) {
    setState(() {
      _selected = point;
      _hasPoint = true;
    });
    widget.onChanged(point);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: SizedBox(
        height: widget.height,
        child: widget.enabled
            ? FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: _selected,
                  initialZoom: _hasPoint ? kLocationZoomPicked : kLocationZoom,
                  onTap: (TapPosition _, LatLng point) => _select(point),
                ),
                children: <Widget>[
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'home_services_app',
                  ),
                  MarkerLayer(
                    markers: <Marker>[
                      Marker(
                        point: _selected,
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.location_on,
                          size: 44,
                          color: _hasPoint
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : ColoredBox(
                color: colors.surfaceVariant,
                child: Center(
                  child: Icon(
                    Icons.location_on,
                    size: 44,
                    color: colors.primary,
                  ),
                ),
              ),
      ),
    );
  }
}
