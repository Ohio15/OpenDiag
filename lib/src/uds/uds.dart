/// UDS (Unified Diagnostic Services) protocol implementation
///
/// This module provides ISO 14229 UDS protocol support including:
/// - Service definitions and request/response handling
/// - Module scanning and ECU discovery
/// - Security access (seed-key authentication)
/// - Bi-directional control (I/O Control, Routine Control)
///
/// Usage:
/// ```dart
/// import 'package:open_diag/src/uds/uds.dart';
///
/// final scanner = ModuleScanner(vci);
/// final modules = await scanner.scanAllModules();
/// ```

export 'uds_protocol.dart';
export 'module_scanner.dart';
export 'security_access.dart';
export 'bidirectional.dart';
