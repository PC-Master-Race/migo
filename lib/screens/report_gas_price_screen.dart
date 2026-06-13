// report_gas_price_screen.dart — Bottom sheet to report a fuel price.
// Users enter the price they see at the pump → earns Bravos.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gas_model.dart';
import '../providers/gas_poi_provider.dart';
import '../services/gas_price_service.dart';
import '../theme/bravo_theme.dart';

class ReportGasPriceSheet extends ConsumerStatefulWidget {
  const ReportGasPriceSheet({super.key, required this.station});

  final GasStation station;

  static Future<void> show(BuildContext context, GasStation station) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportGasPriceSheet(station: station),
    );
  }

  @override
  ConsumerState<ReportGasPriceSheet> createState() =>
      _ReportGasPriceSheetState();
}

class _ReportGasPriceSheetState extends ConsumerState<ReportGasPriceSheet> {
  FuelGrade _selectedGrade = FuelGrade.regular;
  final TextEditingController _priceController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String raw = _priceController.text.trim().replaceAll(r'$', '');
    final double? price = double.tryParse(raw);
    if (price == null || price < 0.5 || price > 15.0) {
      setState(() => _error = 'Enter a valid price (e.g. 3.45)');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await GasPriceService.instance.reportPrice(
        stationOsmId: widget.station.id,
        grade: _selectedGrade,
        pricePerGallon: price,
      );
      // Refresh gas layer
      ref.invalidate(nearbyGasStationsProvider);
      setState(() => _submitted = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station name
          Text(
            widget.station.displayName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Report the price you see at the pump',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),

          if (_submitted)
            _SuccessView()
          else ...<Widget>[
            // Grade selector
            Row(
              children: FuelGrade.values.map((FuelGrade g) {
                final bool sel = g == _selectedGrade;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedGrade = g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFF0288D1)
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(10),
                        border: sel
                            ? Border.all(color: migoTeal, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        children: <Widget>[
                          Text(g.shortLabel,
                              style: TextStyle(
                                color: sel ? Colors.white : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              )),
                          if (widget.station.latestPrices[g] != null)
                            Text(
                              '\$${widget.station.latestPrices[g]!.pricePerGallon.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Price input
            TextField(
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 28),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(
                    color: Colors.white54, fontSize: 22),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: migoTeal, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Price per gallon in USD',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),

            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: migoDanger, fontSize: 13)),
            ],

            const SizedBox(height: 20),

            // Submit
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0288D1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Submit price',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Icon(Icons.check_circle, color: migoTeal, size: 48),
          SizedBox(height: 12),
          Text('Price submitted!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('+25 Bravos earned',
              style: TextStyle(color: migoTeal, fontSize: 14)),
        ],
      ),
    );
  }
}
