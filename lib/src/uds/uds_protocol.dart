/// UDS (Unified Diagnostic Services) Protocol Implementation
/// ISO 14229-1 compliant diagnostic protocol
library;

import 'dart:typed_data';

/// UDS Service Identifiers (SID)
class UDSService {
  // Diagnostic and Communication Management
  static const int diagnosticSessionControl = 0x10;
  static const int ecuReset = 0x11;
  static const int securityAccess = 0x27;
  static const int communicationControl = 0x28;
  static const int testerPresent = 0x3E;
  static const int accessTimingParameter = 0x83;
  static const int securedDataTransmission = 0x84;
  static const int controlDTCSetting = 0x85;
  static const int responseOnEvent = 0x86;
  static const int linkControl = 0x87;

  // Data Transmission
  static const int readDataByIdentifier = 0x22;
  static const int readMemoryByAddress = 0x23;
  static const int readScalingDataByIdentifier = 0x24;
  static const int readDataByPeriodicIdentifier = 0x2A;
  static const int dynamicallyDefineDataIdentifier = 0x2C;
  static const int writeDataByIdentifier = 0x2E;
  static const int writeMemoryByAddress = 0x3D;

  // Stored Data Transmission
  static const int clearDiagnosticInformation = 0x14;
  static const int readDTCInformation = 0x19;

  // Input/Output Control
  static const int inputOutputControlByIdentifier = 0x2F;

  // Routine Control
  static const int routineControl = 0x31;

  // Upload/Download
  static const int requestDownload = 0x34;
  static const int requestUpload = 0x35;
  static const int transferData = 0x36;
  static const int requestTransferExit = 0x37;
  static const int requestFileTransfer = 0x38;

  /// Get service name
  static String getName(int sid) {
    switch (sid) {
      case diagnosticSessionControl:
        return 'DiagnosticSessionControl';
      case ecuReset:
        return 'ECUReset';
      case securityAccess:
        return 'SecurityAccess';
      case communicationControl:
        return 'CommunicationControl';
      case testerPresent:
        return 'TesterPresent';
      case readDataByIdentifier:
        return 'ReadDataByIdentifier';
      case readMemoryByAddress:
        return 'ReadMemoryByAddress';
      case writeDataByIdentifier:
        return 'WriteDataByIdentifier';
      case writeMemoryByAddress:
        return 'WriteMemoryByAddress';
      case clearDiagnosticInformation:
        return 'ClearDiagnosticInformation';
      case readDTCInformation:
        return 'ReadDTCInformation';
      case inputOutputControlByIdentifier:
        return 'InputOutputControlByIdentifier';
      case routineControl:
        return 'RoutineControl';
      case requestDownload:
        return 'RequestDownload';
      case requestUpload:
        return 'RequestUpload';
      case transferData:
        return 'TransferData';
      case requestTransferExit:
        return 'RequestTransferExit';
      default:
        return 'Unknown (0x${sid.toRadixString(16).toUpperCase()})';
    }
  }
}

/// Diagnostic Session Types
class DiagnosticSession {
  static const int defaultSession = 0x01;
  static const int programmingSession = 0x02;
  static const int extendedDiagnosticSession = 0x03;
  static const int safetySystemDiagnosticSession = 0x04;

  // Manufacturer specific: 0x40-0x5F
  // Vehicle manufacturer specific: 0x60-0x7E

  static String getName(int session) {
    switch (session) {
      case defaultSession:
        return 'Default Session';
      case programmingSession:
        return 'Programming Session';
      case extendedDiagnosticSession:
        return 'Extended Diagnostic Session';
      case safetySystemDiagnosticSession:
        return 'Safety System Diagnostic Session';
      default:
        if (session >= 0x40 && session <= 0x5F) {
          return 'OEM Specific Session (0x${session.toRadixString(16)})';
        }
        return 'Unknown Session (0x${session.toRadixString(16)})';
    }
  }
}

/// ECU Reset Types
class ECUResetType {
  static const int hardReset = 0x01;
  static const int keyOffOnReset = 0x02;
  static const int softReset = 0x03;
  static const int enableRapidPowerShutDown = 0x04;
  static const int disableRapidPowerShutDown = 0x05;
}

/// Routine Control Sub-functions
class RoutineControlType {
  static const int startRoutine = 0x01;
  static const int stopRoutine = 0x02;
  static const int requestRoutineResults = 0x03;
}

/// Input/Output Control Parameters
class IOControlParameter {
  static const int returnControlToECU = 0x00;
  static const int resetToDefault = 0x01;
  static const int freezeCurrentState = 0x02;
  static const int shortTermAdjustment = 0x03;
}

/// DTC Report Types (Sub-function for ReadDTCInformation)
class DTCReportType {
  static const int reportNumberOfDTCByStatusMask = 0x01;
  static const int reportDTCByStatusMask = 0x02;
  static const int reportDTCSnapshotIdentification = 0x03;
  static const int reportDTCSnapshotRecordByDTCNumber = 0x04;
  static const int reportDTCStoredDataByRecordNumber = 0x05;
  static const int reportDTCExtDataRecordByDTCNumber = 0x06;
  static const int reportNumberOfDTCBySeverityMaskRecord = 0x07;
  static const int reportDTCBySeverityMaskRecord = 0x08;
  static const int reportSeverityInformationOfDTC = 0x09;
  static const int reportSupportedDTC = 0x0A;
  static const int reportFirstTestFailedDTC = 0x0B;
  static const int reportFirstConfirmedDTC = 0x0C;
  static const int reportMostRecentTestFailedDTC = 0x0D;
  static const int reportMostRecentConfirmedDTC = 0x0E;
  static const int reportDTCFaultDetectionCounter = 0x14;
  static const int reportDTCWithPermanentStatus = 0x15;
}

/// DTC Status Mask Bits
class DTCStatusMask {
  static const int testFailed = 0x01;
  static const int testFailedThisOperationCycle = 0x02;
  static const int pendingDTC = 0x04;
  static const int confirmedDTC = 0x08;
  static const int testNotCompletedSinceLastClear = 0x10;
  static const int testFailedSinceLastClear = 0x20;
  static const int testNotCompletedThisOperationCycle = 0x40;
  static const int warningIndicatorRequested = 0x80;

  static const int allDTCs = 0xFF;
  static const int storedDTCs = confirmedDTC;
  static const int pendingOnly = pendingDTC;
}

/// Negative Response Codes (NRC)
class NegativeResponseCode {
  static const int positiveResponse = 0x00;
  static const int generalReject = 0x10;
  static const int serviceNotSupported = 0x11;
  static const int subFunctionNotSupported = 0x12;
  static const int incorrectMessageLengthOrInvalidFormat = 0x13;
  static const int responseTooLong = 0x14;
  static const int busyRepeatRequest = 0x21;
  static const int conditionsNotCorrect = 0x22;
  static const int requestSequenceError = 0x24;
  static const int noResponseFromSubnetComponent = 0x25;
  static const int failurePreventsExecutionOfRequestedAction = 0x26;
  static const int requestOutOfRange = 0x31;
  static const int securityAccessDenied = 0x33;
  static const int invalidKey = 0x35;
  static const int exceededNumberOfAttempts = 0x36;
  static const int requiredTimeDelayNotExpired = 0x37;
  static const int uploadDownloadNotAccepted = 0x70;
  static const int transferDataSuspended = 0x71;
  static const int generalProgrammingFailure = 0x72;
  static const int wrongBlockSequenceCounter = 0x73;
  static const int requestCorrectlyReceivedResponsePending = 0x78;
  static const int subFunctionNotSupportedInActiveSession = 0x7E;
  static const int serviceNotSupportedInActiveSession = 0x7F;
  static const int rpmTooHigh = 0x81;
  static const int rpmTooLow = 0x82;
  static const int engineIsRunning = 0x83;
  static const int engineIsNotRunning = 0x84;
  static const int engineRunTimeTooLow = 0x85;
  static const int temperatureTooHigh = 0x86;
  static const int temperatureTooLow = 0x87;
  static const int vehicleSpeedTooHigh = 0x88;
  static const int vehicleSpeedTooLow = 0x89;
  static const int throttlePedalTooHigh = 0x8A;
  static const int throttlePedalTooLow = 0x8B;
  static const int transmissionRangeNotInNeutral = 0x8C;
  static const int transmissionRangeNotInGear = 0x8D;
  static const int brakeSwitchNotClosed = 0x8F;
  static const int shifterLeverNotInPark = 0x90;
  static const int torqueConverterClutchLocked = 0x91;
  static const int voltageTooHigh = 0x92;
  static const int voltageTooLow = 0x93;

  /// Get human-readable error message
  static String getMessage(int nrc) {
    switch (nrc) {
      case positiveResponse:
        return 'Success';
      case generalReject:
        return 'General Reject';
      case serviceNotSupported:
        return 'Service Not Supported';
      case subFunctionNotSupported:
        return 'Sub-function Not Supported';
      case incorrectMessageLengthOrInvalidFormat:
        return 'Incorrect Message Length or Invalid Format';
      case responseTooLong:
        return 'Response Too Long';
      case busyRepeatRequest:
        return 'Busy - Repeat Request';
      case conditionsNotCorrect:
        return 'Conditions Not Correct';
      case requestSequenceError:
        return 'Request Sequence Error';
      case noResponseFromSubnetComponent:
        return 'No Response From Subnet Component';
      case failurePreventsExecutionOfRequestedAction:
        return 'Failure Prevents Execution';
      case requestOutOfRange:
        return 'Request Out Of Range';
      case securityAccessDenied:
        return 'Security Access Denied';
      case invalidKey:
        return 'Invalid Key';
      case exceededNumberOfAttempts:
        return 'Exceeded Number Of Attempts';
      case requiredTimeDelayNotExpired:
        return 'Required Time Delay Not Expired';
      case uploadDownloadNotAccepted:
        return 'Upload/Download Not Accepted';
      case transferDataSuspended:
        return 'Transfer Data Suspended';
      case generalProgrammingFailure:
        return 'General Programming Failure';
      case wrongBlockSequenceCounter:
        return 'Wrong Block Sequence Counter';
      case requestCorrectlyReceivedResponsePending:
        return 'Request Correctly Received - Response Pending';
      case subFunctionNotSupportedInActiveSession:
        return 'Sub-function Not Supported In Active Session';
      case serviceNotSupportedInActiveSession:
        return 'Service Not Supported In Active Session';
      case rpmTooHigh:
        return 'RPM Too High';
      case rpmTooLow:
        return 'RPM Too Low';
      case engineIsRunning:
        return 'Engine Is Running';
      case engineIsNotRunning:
        return 'Engine Is Not Running';
      case engineRunTimeTooLow:
        return 'Engine Run Time Too Low';
      case temperatureTooHigh:
        return 'Temperature Too High';
      case temperatureTooLow:
        return 'Temperature Too Low';
      case vehicleSpeedTooHigh:
        return 'Vehicle Speed Too High';
      case vehicleSpeedTooLow:
        return 'Vehicle Speed Too Low';
      case throttlePedalTooHigh:
        return 'Throttle/Pedal Too High';
      case throttlePedalTooLow:
        return 'Throttle/Pedal Too Low';
      case transmissionRangeNotInNeutral:
        return 'Transmission Range Not In Neutral';
      case transmissionRangeNotInGear:
        return 'Transmission Range Not In Gear';
      case brakeSwitchNotClosed:
        return 'Brake Switch Not Closed';
      case shifterLeverNotInPark:
        return 'Shifter Lever Not In Park';
      case torqueConverterClutchLocked:
        return 'Torque Converter Clutch Locked';
      case voltageTooHigh:
        return 'Voltage Too High';
      case voltageTooLow:
        return 'Voltage Too Low';
      default:
        if (nrc >= 0x94 && nrc <= 0xFE) {
          return 'Reserved for specific conditions not correct (0x${nrc.toRadixString(16).toUpperCase()})';
        }
        return 'Unknown Error (0x${nrc.toRadixString(16).toUpperCase()})';
    }
  }

  /// Check if this NRC indicates we should retry
  static bool shouldRetry(int nrc) {
    return nrc == busyRepeatRequest ||
        nrc == requestCorrectlyReceivedResponsePending;
  }
}

/// Common Data Identifiers (DIDs)
class CommonDID {
  // Vehicle Identification
  static const int vin = 0xF190;
  static const int vehicleManufacturerECUSoftwareNumber = 0xF188;
  static const int vehicleManufacturerECUSoftwareVersionNumber = 0xF189;
  static const int systemSupplierIdentifier = 0xF18A;
  static const int ecuManufacturingDate = 0xF18B;
  static const int ecuSerialNumber = 0xF18C;
  static const int vehicleManufacturerSparePartNumber = 0xF187;
  static const int systemNameOrEngineType = 0xF197;

  // ECU Identification
  static const int bootSoftwareIdentification = 0xF180;
  static const int applicationSoftwareIdentification = 0xF181;
  static const int applicationDataIdentification = 0xF182;
  static const int bootSoftwareFingerprint = 0xF183;
  static const int applicationSoftwareFingerprint = 0xF184;
  static const int applicationDataFingerprint = 0xF185;
  static const int activeDiagnosticSession = 0xF186;

  // Network Configuration
  static const int ecuInstallationDate = 0xF19D;
  static const int odxFileIdentifier = 0xF19E;
  static const int ecuDiagnosticIdentifier = 0xF19F;

  /// Get DID name
  static String getName(int did) {
    switch (did) {
      case vin:
        return 'VIN';
      case vehicleManufacturerECUSoftwareNumber:
        return 'ECU Software Number';
      case vehicleManufacturerECUSoftwareVersionNumber:
        return 'ECU Software Version';
      case systemSupplierIdentifier:
        return 'System Supplier ID';
      case ecuManufacturingDate:
        return 'ECU Manufacturing Date';
      case ecuSerialNumber:
        return 'ECU Serial Number';
      case vehicleManufacturerSparePartNumber:
        return 'Spare Part Number';
      case systemNameOrEngineType:
        return 'System Name/Engine Type';
      case bootSoftwareIdentification:
        return 'Boot Software ID';
      case applicationSoftwareIdentification:
        return 'Application Software ID';
      case applicationDataIdentification:
        return 'Application Data ID';
      case activeDiagnosticSession:
        return 'Active Diagnostic Session';
      default:
        return 'DID 0x${did.toRadixString(16).toUpperCase()}';
    }
  }
}

/// UDS Request Builder
class UDSRequest {
  final int serviceId;
  final List<int> data;

  UDSRequest(this.serviceId, [this.data = const []]);

  /// Build request bytes
  Uint8List toBytes() {
    final bytes = Uint8List(1 + data.length);
    bytes[0] = serviceId;
    for (var i = 0; i < data.length; i++) {
      bytes[i + 1] = data[i];
    }
    return bytes;
  }

  /// Create DiagnosticSessionControl request
  factory UDSRequest.diagnosticSessionControl(int sessionType) {
    return UDSRequest(UDSService.diagnosticSessionControl, [sessionType]);
  }

  /// Create ECUReset request
  factory UDSRequest.ecuReset(int resetType) {
    return UDSRequest(UDSService.ecuReset, [resetType]);
  }

  /// Create SecurityAccess request (request seed)
  factory UDSRequest.securityAccessRequestSeed(int securityLevel) {
    return UDSRequest(UDSService.securityAccess, [securityLevel]);
  }

  /// Create SecurityAccess request (send key)
  factory UDSRequest.securityAccessSendKey(int securityLevel, List<int> key) {
    return UDSRequest(UDSService.securityAccess, [securityLevel + 1, ...key]);
  }

  /// Create TesterPresent request
  factory UDSRequest.testerPresent({bool suppressResponse = false}) {
    return UDSRequest(
        UDSService.testerPresent, [suppressResponse ? 0x80 : 0x00]);
  }

  /// Create ReadDataByIdentifier request
  factory UDSRequest.readDataByIdentifier(List<int> dids) {
    final data = <int>[];
    for (final did in dids) {
      data.add((did >> 8) & 0xFF);
      data.add(did & 0xFF);
    }
    return UDSRequest(UDSService.readDataByIdentifier, data);
  }

  /// Create WriteDataByIdentifier request
  factory UDSRequest.writeDataByIdentifier(int did, List<int> value) {
    return UDSRequest(UDSService.writeDataByIdentifier, [
      (did >> 8) & 0xFF,
      did & 0xFF,
      ...value,
    ]);
  }

  /// Create ClearDiagnosticInformation request
  factory UDSRequest.clearDiagnosticInformation(
      {int groupOfDTC = 0xFFFFFF}) {
    return UDSRequest(UDSService.clearDiagnosticInformation, [
      (groupOfDTC >> 16) & 0xFF,
      (groupOfDTC >> 8) & 0xFF,
      groupOfDTC & 0xFF,
    ]);
  }

  /// Create ReadDTCInformation request
  factory UDSRequest.readDTCInformation(int reportType,
      {int statusMask = DTCStatusMask.allDTCs}) {
    if (reportType == DTCReportType.reportNumberOfDTCByStatusMask ||
        reportType == DTCReportType.reportDTCByStatusMask) {
      return UDSRequest(
          UDSService.readDTCInformation, [reportType, statusMask]);
    }
    return UDSRequest(UDSService.readDTCInformation, [reportType]);
  }

  /// Create InputOutputControlByIdentifier request
  factory UDSRequest.inputOutputControl(
    int did,
    int controlParameter, {
    List<int>? controlState,
  }) {
    final data = <int>[
      (did >> 8) & 0xFF,
      did & 0xFF,
      controlParameter,
    ];
    if (controlState != null) {
      data.addAll(controlState);
    }
    return UDSRequest(UDSService.inputOutputControlByIdentifier, data);
  }

  /// Create RoutineControl request
  factory UDSRequest.routineControl(
    int routineControlType,
    int routineId, {
    List<int>? routineOptionRecord,
  }) {
    final data = <int>[
      routineControlType,
      (routineId >> 8) & 0xFF,
      routineId & 0xFF,
    ];
    if (routineOptionRecord != null) {
      data.addAll(routineOptionRecord);
    }
    return UDSRequest(UDSService.routineControl, data);
  }

  /// Create CommunicationControl request
  factory UDSRequest.communicationControl(
      int controlType, int communicationType) {
    return UDSRequest(
        UDSService.communicationControl, [controlType, communicationType]);
  }

  /// Create ControlDTCSetting request
  factory UDSRequest.controlDTCSetting(int settingType) {
    return UDSRequest(UDSService.controlDTCSetting, [settingType]);
  }
}

/// UDS Response Parser
class UDSResponse {
  final int serviceId;
  final bool isPositive;
  final int? negativeResponseCode;
  final List<int> data;

  UDSResponse({
    required this.serviceId,
    required this.isPositive,
    this.negativeResponseCode,
    this.data = const [],
  });

  /// Parse response from raw bytes
  factory UDSResponse.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return UDSResponse(
        serviceId: 0,
        isPositive: false,
        negativeResponseCode: NegativeResponseCode.generalReject,
      );
    }

    // Negative response
    if (bytes[0] == 0x7F) {
      return UDSResponse(
        serviceId: bytes.length > 1 ? bytes[1] : 0,
        isPositive: false,
        negativeResponseCode: bytes.length > 2
            ? bytes[2]
            : NegativeResponseCode.generalReject,
      );
    }

    // Positive response (SID + 0x40)
    final requestSid = bytes[0] - 0x40;
    return UDSResponse(
      serviceId: requestSid,
      isPositive: true,
      data: bytes.length > 1 ? bytes.sublist(1) : [],
    );
  }

  /// Get error message for negative response
  String get errorMessage {
    if (isPositive) return 'Success';
    return NegativeResponseCode.getMessage(
        negativeResponseCode ?? NegativeResponseCode.generalReject);
  }

  /// Check if response is pending (need to wait)
  bool get isPending {
    return !isPositive &&
        negativeResponseCode ==
            NegativeResponseCode.requestCorrectlyReceivedResponsePending;
  }

  /// Parse DID value from ReadDataByIdentifier response
  Map<int, List<int>> parseDIDValues() {
    final result = <int, List<int>>{};
    if (!isPositive || data.length < 2) return result;

    var offset = 0;
    while (offset < data.length - 1) {
      final did = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Find end of this DID's data (next DID or end)
      var endOffset = offset;
      while (endOffset < data.length - 1) {
        // Heuristic: DIDs are typically 0xF1xx or similar
        final potentialDid = (data[endOffset] << 8) | data[endOffset + 1];
        if (potentialDid >= 0xF100 && potentialDid <= 0xFFFF) {
          break;
        }
        endOffset++;
      }

      result[did] = data.sublist(offset, endOffset);
      offset = endOffset;
    }

    return result;
  }

  /// Parse DTCs from ReadDTCInformation response
  List<DTCInfo> parseDTCs() {
    final dtcs = <DTCInfo>[];
    if (!isPositive || data.length < 2) return dtcs;

    // Skip sub-function and availability mask
    var offset = 2;

    while (offset + 3 < data.length) {
      final dtcHighByte = data[offset];
      final dtcMiddleByte = data[offset + 1];
      final dtcLowByte = data[offset + 2];
      final statusByte = offset + 3 < data.length ? data[offset + 3] : 0;

      final dtcNumber = (dtcHighByte << 16) | (dtcMiddleByte << 8) | dtcLowByte;
      if (dtcNumber != 0) {
        dtcs.add(DTCInfo(
          dtcNumber: dtcNumber,
          statusMask: statusByte,
        ));
      }

      offset += 4;
    }

    return dtcs;
  }
}

/// DTC Information structure
class DTCInfo {
  final int dtcNumber;
  final int statusMask;

  DTCInfo({
    required this.dtcNumber,
    required this.statusMask,
  });

  /// Format DTC as standard code (P0123, U0456, etc.)
  String get code {
    final firstByte = (dtcNumber >> 16) & 0xFF;
    final typeCode = (firstByte >> 6) & 0x03;

    String prefix;
    switch (typeCode) {
      case 0:
        prefix = 'P';
        break;
      case 1:
        prefix = 'C';
        break;
      case 2:
        prefix = 'B';
        break;
      case 3:
        prefix = 'U';
        break;
      default:
        prefix = 'P';
    }

    final codeNum = dtcNumber & 0x3FFFFF;
    return '$prefix${codeNum.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  /// Check if DTC is confirmed
  bool get isConfirmed => (statusMask & DTCStatusMask.confirmedDTC) != 0;

  /// Check if DTC is pending
  bool get isPending => (statusMask & DTCStatusMask.pendingDTC) != 0;

  /// Check if MIL is requested
  bool get isMilOn =>
      (statusMask & DTCStatusMask.warningIndicatorRequested) != 0;

  /// Check if test failed
  bool get testFailed => (statusMask & DTCStatusMask.testFailed) != 0;

  @override
  String toString() =>
      '$code (Status: 0x${statusMask.toRadixString(16).toUpperCase()})';
}
