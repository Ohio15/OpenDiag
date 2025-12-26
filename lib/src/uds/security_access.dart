/// UDS Security Access Framework
/// Implements seed-key authentication for unlocking ECU functions
library;

import 'dart:typed_data';
import 'uds_protocol.dart';
import 'module_scanner.dart';
import '../platform/vci_interface.dart';

/// Security access levels
class SecurityLevel {
  static const int level1RequestSeed = 0x01;
  static const int level1SendKey = 0x02;
  static const int level2RequestSeed = 0x03;
  static const int level2SendKey = 0x04;
  static const int level3RequestSeed = 0x05;
  static const int level3SendKey = 0x06;
  // OEM-specific levels: 0x07-0x7E (odd = request seed, even = send key)

  /// Standard security levels
  static const int ioControl = 0x01; // Level 1 - I/O Control
  static const int routineControl = 0x03; // Level 2 - Routine Control
  static const int programming = 0x05; // Level 3 - Programming
  static const int configuration = 0x07; // Level 4 - Configuration
  static const int development = 0x11; // Extended - Development access

  static String getName(int level) {
    switch (level) {
      case ioControl:
        return 'I/O Control Access';
      case routineControl:
        return 'Routine Control Access';
      case programming:
        return 'Programming Access';
      case configuration:
        return 'Configuration Access';
      case development:
        return 'Development Access';
      default:
        return 'Security Level ${(level + 1) ~/ 2}';
    }
  }
}

/// Security algorithm interface
abstract class SecurityAlgorithm {
  /// Calculate key from seed
  List<int> calculateKey(List<int> seed);

  /// Algorithm name for display
  String get name;
}

/// Generic XOR-based security algorithm
class XorSecurityAlgorithm implements SecurityAlgorithm {
  final List<int> xorKey;
  final String algorithmName;

  XorSecurityAlgorithm(this.xorKey, {this.algorithmName = 'XOR'});

  @override
  String get name => algorithmName;

  @override
  List<int> calculateKey(List<int> seed) {
    final key = <int>[];
    for (var i = 0; i < seed.length; i++) {
      key.add(seed[i] ^ xorKey[i % xorKey.length]);
    }
    return key;
  }
}

/// Add/Constant security algorithm
class AddConstantSecurityAlgorithm implements SecurityAlgorithm {
  final int constant;
  final String algorithmName;

  AddConstantSecurityAlgorithm(this.constant,
      {this.algorithmName = 'Add Constant'});

  @override
  String get name => algorithmName;

  @override
  List<int> calculateKey(List<int> seed) {
    final key = <int>[];
    for (final byte in seed) {
      key.add((byte + constant) & 0xFF);
    }
    return key;
  }
}

/// Byte swap + XOR algorithm
class ByteSwapXorSecurityAlgorithm implements SecurityAlgorithm {
  final int xorValue;
  final String algorithmName;

  ByteSwapXorSecurityAlgorithm(this.xorValue,
      {this.algorithmName = 'Byte Swap XOR'});

  @override
  String get name => algorithmName;

  @override
  List<int> calculateKey(List<int> seed) {
    if (seed.length < 2) return seed;

    final key = List<int>.from(seed);

    // Swap bytes pairwise
    for (var i = 0; i < key.length - 1; i += 2) {
      final temp = key[i];
      key[i] = key[i + 1];
      key[i + 1] = temp;
    }

    // XOR with value
    for (var i = 0; i < key.length; i++) {
      key[i] = (key[i] ^ xorValue) & 0xFF;
    }

    return key;
  }
}

/// Rolling code / CRC-based algorithm
class CrcSecurityAlgorithm implements SecurityAlgorithm {
  final int polynomial;
  final int initialValue;
  final String algorithmName;

  CrcSecurityAlgorithm({
    this.polynomial = 0x1021,
    this.initialValue = 0xFFFF,
    this.algorithmName = 'CRC-16',
  });

  @override
  String get name => algorithmName;

  @override
  List<int> calculateKey(List<int> seed) {
    var crc = initialValue;

    for (final byte in seed) {
      crc ^= (byte << 8);
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }

    return [(crc >> 8) & 0xFF, crc & 0xFF];
  }
}

/// Generic manufacturer algorithm (configurable)
class GenericSecurityAlgorithm implements SecurityAlgorithm {
  final List<int> Function(List<int>) keyCalculator;
  final String algorithmName;

  GenericSecurityAlgorithm(this.keyCalculator, {this.algorithmName = 'Generic'});

  @override
  String get name => algorithmName;

  @override
  List<int> calculateKey(List<int> seed) {
    return keyCalculator(seed);
  }
}

/// Security algorithm registry
class SecurityAlgorithmRegistry {
  static final Map<String, SecurityAlgorithm> _algorithms = {};

  /// Register a security algorithm
  static void register(String manufacturerId, SecurityAlgorithm algorithm) {
    _algorithms[manufacturerId] = algorithm;
  }

  /// Get algorithm for manufacturer
  static SecurityAlgorithm? getAlgorithm(String manufacturerId) {
    return _algorithms[manufacturerId];
  }

  /// Initialize common algorithms
  static void initializeDefaults() {
    // These are examples - real algorithms would need to be reverse-engineered
    register('GENERIC_XOR', XorSecurityAlgorithm([0xAA, 0x55, 0xAA, 0x55]));
    register('GENERIC_ADD', AddConstantSecurityAlgorithm(0x12));
    register('GENERIC_CRC', CrcSecurityAlgorithm());

    // OEM-specific placeholders (actual algorithms vary by manufacturer/model)
    register(
        'VW_AUDI',
        GenericSecurityAlgorithm((seed) {
          // Simplified VAG security - actual algorithm is more complex
          if (seed.length != 4) return seed;
          final key = <int>[];
          for (var i = 0; i < seed.length; i++) {
            key.add((seed[i] ^ 0xC5) & 0xFF);
          }
          return key;
        }, algorithmName: 'VAG Security'));

    register(
        'BMW',
        GenericSecurityAlgorithm((seed) {
          // BMW seed-key placeholder
          if (seed.length != 2) return seed;
          return [
            ((seed[0] + seed[1]) ^ 0x3A) & 0xFF,
            ((seed[0] * seed[1]) ^ 0xB5) & 0xFF,
          ];
        }, algorithmName: 'BMW Security'));

    register(
        'TOYOTA',
        GenericSecurityAlgorithm((seed) {
          // Toyota seed-key placeholder
          if (seed.length < 4) return seed;
          return [
            (seed[3] ^ 0x67) & 0xFF,
            (seed[2] ^ 0x89) & 0xFF,
            (seed[1] ^ 0xAB) & 0xFF,
            (seed[0] ^ 0xCD) & 0xFF,
          ];
        }, algorithmName: 'Toyota Security'));
  }
}

/// Security access manager
class SecurityAccessManager {
  final VciInterface _vci;
  final Map<int, int> _unlockedLevels = {}; // module address -> security level

  SecurityAccessManager(this._vci) {
    SecurityAlgorithmRegistry.initializeDefaults();
  }

  /// Check if module is unlocked at specified level
  bool isUnlocked(VehicleModule module, int securityLevel) {
    final unlockedLevel = _unlockedLevels[module.address];
    return unlockedLevel != null && unlockedLevel >= securityLevel;
  }

  /// Request security access for a module
  Future<SecurityAccessResult> requestSecurityAccess(
    VehicleModule module,
    int securityLevel, {
    SecurityAlgorithm? algorithm,
    List<int>? manualKey,
  }) async {
    // Step 1: Request seed
    final seedRequest = UDSRequest.securityAccessRequestSeed(securityLevel);
    final seedResponse = await _sendUDSRequest(module.address, seedRequest);

    if (seedResponse == null) {
      return SecurityAccessResult(
        success: false,
        errorMessage: 'No response from module',
      );
    }

    if (!seedResponse.isPositive) {
      return SecurityAccessResult(
        success: false,
        errorMessage: seedResponse.errorMessage,
        negativeResponseCode: seedResponse.negativeResponseCode,
      );
    }

    // Extract seed from response
    final seed = seedResponse.data.sublist(1); // Skip sub-function echo

    // Check for zero seed (already unlocked)
    if (seed.every((b) => b == 0)) {
      _unlockedLevels[module.address] = securityLevel;
      module.isSecurityUnlocked = true;
      return SecurityAccessResult(
        success: true,
        message: 'Already unlocked (zero seed)',
      );
    }

    // Step 2: Calculate key
    List<int> key;
    if (manualKey != null) {
      key = manualKey;
    } else if (algorithm != null) {
      key = algorithm.calculateKey(seed);
    } else {
      // Try to find matching algorithm
      final defaultAlgorithm =
          SecurityAlgorithmRegistry.getAlgorithm('GENERIC_XOR');
      if (defaultAlgorithm != null) {
        key = defaultAlgorithm.calculateKey(seed);
      } else {
        return SecurityAccessResult(
          success: false,
          errorMessage: 'No security algorithm available',
          seed: seed,
        );
      }
    }

    // Step 3: Send key
    final keyRequest = UDSRequest.securityAccessSendKey(securityLevel, key);
    final keyResponse = await _sendUDSRequest(module.address, keyRequest);

    if (keyResponse == null) {
      return SecurityAccessResult(
        success: false,
        errorMessage: 'No response to key',
        seed: seed,
        calculatedKey: key,
      );
    }

    if (!keyResponse.isPositive) {
      return SecurityAccessResult(
        success: false,
        errorMessage: keyResponse.errorMessage,
        negativeResponseCode: keyResponse.negativeResponseCode,
        seed: seed,
        calculatedKey: key,
      );
    }

    // Success!
    _unlockedLevels[module.address] = securityLevel;
    module.isSecurityUnlocked = true;

    return SecurityAccessResult(
      success: true,
      message: 'Security access granted',
      seed: seed,
      calculatedKey: key,
    );
  }

  /// Switch to extended diagnostic session (required for most bi-directional functions)
  Future<bool> switchToExtendedSession(VehicleModule module) async {
    final request = UDSRequest.diagnosticSessionControl(
        DiagnosticSession.extendedDiagnosticSession);
    final response = await _sendUDSRequest(module.address, request);

    if (response?.isPositive == true) {
      module.currentSession = DiagnosticSession.extendedDiagnosticSession;
      return true;
    }
    return false;
  }

  /// Switch to default session
  Future<bool> switchToDefaultSession(VehicleModule module) async {
    final request = UDSRequest.diagnosticSessionControl(
        DiagnosticSession.defaultSession);
    final response = await _sendUDSRequest(module.address, request);

    if (response?.isPositive == true) {
      module.currentSession = DiagnosticSession.defaultSession;
      module.isSecurityUnlocked = false;
      _unlockedLevels.remove(module.address);
      return true;
    }
    return false;
  }

  /// Send tester present to keep session alive
  Future<void> sendTesterPresent(VehicleModule module) async {
    final request = UDSRequest.testerPresent(suppressResponse: true);
    await _sendUDSRequest(module.address, request);
  }

  /// Send UDS request to module
  Future<UDSResponse?> _sendUDSRequest(
      int address, UDSRequest request) async {
    try {
      final data = request.toBytes();
      final response = await _vci.sendUDSCommand(address, data.toList());

      if (response.isEmpty) return null;

      return UDSResponse.fromBytes(response);
    } catch (e) {
      return null;
    }
  }
}

/// Security access result
class SecurityAccessResult {
  final bool success;
  final String? message;
  final String? errorMessage;
  final int? negativeResponseCode;
  final List<int>? seed;
  final List<int>? calculatedKey;

  SecurityAccessResult({
    required this.success,
    this.message,
    this.errorMessage,
    this.negativeResponseCode,
    this.seed,
    this.calculatedKey,
  });

  @override
  String toString() {
    if (success) {
      return 'Security Access Granted: $message';
    } else {
      return 'Security Access Denied: $errorMessage';
    }
  }
}
