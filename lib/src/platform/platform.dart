/// Platform abstraction layer for VCI communication
///
/// This module provides platform-specific implementations for connecting
/// to vehicle communication interfaces (VCI) such as ELM327 and Autel adapters.
///
/// Usage:
/// ```dart
/// import 'package:open_diag/src/platform/platform.dart';
///
/// final vci = VciFactory.create();
/// final devices = await vci.scanForDevices();
/// await vci.connect(devices.first);
/// ```

export 'vci_interface.dart';
export 'vci_factory.dart';
// Platform-specific implementations are not exported directly
// Use VciFactory.create() to get the appropriate implementation
export 'vci_simulator.dart';
