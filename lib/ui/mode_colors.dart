import 'package:flutter/material.dart';

import '../core/acoustics/mode.dart';

/// Consistent colours for the three mode types across all visualizations.
Color colorForModeType(ModeType type) => switch (type) {
      ModeType.axial => const Color(0xFFFF6B6B), // red — strongest
      ModeType.tangential => const Color(0xFFFFC857), // amber
      ModeType.oblique => const Color(0xFF4ECDC4), // teal — weakest
    };
