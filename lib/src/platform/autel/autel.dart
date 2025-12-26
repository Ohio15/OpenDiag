/// Autel J2534 Bluetooth Protocol Library
///
/// This library provides a Dart/Flutter implementation of the Autel VCI
/// proprietary protocol for communicating with Autel diagnostic tools
/// (MaxiSys, MaxiCheck, etc.) via Bluetooth Classic SPP.
///
/// The protocol wraps SAE J2534 Passthru API calls over Bluetooth,
/// allowing full vehicle diagnostics without requiring the original
/// Autel tablet software.
///
/// ## Usage
///
/// ```dart
/// import 'package:open_diag/src/platform/autel/autel.dart';
///
/// final vci = VciAutelImpl();
///
/// // Scan for Autel VCI devices
/// final devices = await vci.scanForDevices();
///
/// // Connect to the first Autel device found
/// if (devices.isNotEmpty) {
///   await vci.connect(devices.first);
///
///   // Open a J2534 channel for CAN communication
///   final channelId = await vci.passThruOpen(protocolId: J2534Protocol.can);
///
///   // Connect to vehicle at 500kbps
///   await vci.passThruConnect(
///     protocolId: J2534Protocol.can,
///     baudrate: 500000,
///   );
///
///   // Send/receive OBD2 data
///   await vci.passThruWriteMsgs(data: [0x7DF, 0x02, 0x01, 0x00]);
///   final messages = await vci.passThruReadMsgs();
///
///   // Cleanup
///   await vci.passThruClose();
///   await vci.disconnect();
/// }
/// ```
library;

export 'autel_protocol.dart';
export 'autel_packet.dart';
