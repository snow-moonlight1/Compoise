/// Explicit entry for the WP19-R prototype only.
///
///     flutter run -t lib/experiments/wp19_dev_mode/main.dart
///
/// lib/main.dart stays as it is and nothing in the product tree imports this
/// directory, so no normal build of the app includes the experiment.
library;

import 'package:flutter/material.dart';

import 'wp19_dev_mode_app.dart';

void main() => runApp(const Wp19DevModeApp());
