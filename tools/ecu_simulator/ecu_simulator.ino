/*
 * OBD-II ECU Simulator for OpenDiag Testing
 *
 * Hardware Requirements:
 * - Arduino Uno/Nano/Mega
 * - MCP2515 CAN Bus Shield or Module
 *
 * Wiring (MCP2515 to Arduino):
 * - VCC -> 5V
 * - GND -> GND
 * - CS  -> Pin 10 (configurable)
 * - SO  -> Pin 12 (MISO)
 * - SI  -> Pin 11 (MOSI)
 * - SCK -> Pin 13 (SCK)
 * - INT -> Pin 2 (optional, for interrupts)
 *
 * OBD-II Connector Wiring (to ELM327):
 * - CAN_H -> OBD Pin 6
 * - CAN_L -> OBD Pin 14
 * - GND   -> OBD Pin 4 & 5
 * - 12V   -> OBD Pin 16 (power the ELM327)
 *
 * Install Library: MCP_CAN by Cory Fowler
 * https://github.com/coryjfowler/MCP_CAN_lib
 */

#include <mcp_can.h>
#include <SPI.h>

// CAN Bus configuration
#define CAN_CS_PIN 10
#define CAN_SPEED CAN_500KBPS  // Standard OBD-II speed
#define CAN_CLOCK MCP_8MHZ     // Crystal on MCP2515 module (8MHz or 16MHz)

// OBD-II CAN IDs
#define OBD_REQUEST_ID  0x7DF  // Broadcast request
#define OBD_RESPONSE_ID 0x7E8  // ECU #1 response

// OBD-II Service IDs
#define SERVICE_01 0x01  // Show current data
#define SERVICE_03 0x03  // Show stored DTCs
#define SERVICE_04 0x04  // Clear DTCs
#define SERVICE_09 0x09  // Request vehicle information

MCP_CAN CAN(CAN_CS_PIN);

// Simulated vehicle data (update these to change readings)
struct VehicleData {
  // Engine data
  uint16_t rpm = 850;              // Engine RPM (0-16383.75)
  uint8_t speed = 0;               // Vehicle speed km/h (0-255)
  int8_t coolantTemp = 85;         // Coolant temp C (-40 to 215)
  uint8_t engineLoad = 25;         // Engine load % (0-100)
  uint8_t throttle = 15;           // Throttle position % (0-100)
  int8_t intakeTemp = 35;          // Intake air temp C (-40 to 215)
  uint8_t maf = 12;                // MAF g/s (0-655.35, stored as x10)
  int8_t timingAdvance = 15;       // Timing advance degrees
  uint8_t fuelLevel = 75;          // Fuel level % (0-100)
  uint16_t runtime = 1200;         // Runtime since start (seconds)
  float voltage = 13.8;            // Battery voltage

  // Fuel system
  uint8_t shortTermFuelTrim = 128; // 128 = 0%, 0=-100%, 255=+99.2%
  uint8_t longTermFuelTrim = 130;
  uint8_t fuelPressure = 45;       // kPa

  // Supported PIDs (Mode 01)
  uint32_t supportedPids_01_20 = 0xBE1FA813;  // Common PIDs
  uint32_t supportedPids_21_40 = 0x80000000;
  uint32_t supportedPids_41_60 = 0x00000001;

  // VIN (17 characters)
  char vin[18] = "1OPENDIAG0TEST123";

  // No DTCs stored
  uint8_t dtcCount = 0;
} vehicle;

// Animation state for dynamic simulation
unsigned long lastUpdate = 0;
bool engineRunning = true;

void setup() {
  Serial.begin(115200);
  Serial.println("OpenDiag ECU Simulator v1.0");
  Serial.println("Initializing CAN bus...");

  // Initialize CAN bus
  while (CAN.begin(MCP_ANY, CAN_SPEED, CAN_CLOCK) != CAN_OK) {
    Serial.println("CAN init failed, retrying...");
    delay(1000);
  }

  CAN.setMode(MCP_NORMAL);
  Serial.println("CAN bus initialized successfully!");
  Serial.println("Waiting for OBD-II requests...");
  Serial.println();
  Serial.println("Commands via Serial:");
  Serial.println("  r<value> - Set RPM (e.g., r2500)");
  Serial.println("  s<value> - Set Speed (e.g., s60)");
  Serial.println("  t<value> - Set Temp (e.g., t90)");
  Serial.println("  d        - Add DTC P0300");
  Serial.println("  c        - Clear DTCs");
  Serial.println("  e        - Toggle engine on/off");
  Serial.println();
}

void loop() {
  // Check for incoming CAN messages
  checkCANMessages();

  // Update simulated values periodically
  updateSimulation();

  // Check for serial commands to adjust simulation
  checkSerialCommands();
}

void checkCANMessages() {
  unsigned long canId;
  byte len;
  byte buf[8];

  if (CAN.checkReceive() == CAN_MSGAVAIL) {
    CAN.readMsgBuf(&canId, &len, buf);

    // Check if this is an OBD-II request
    if (canId == OBD_REQUEST_ID || (canId >= 0x7E0 && canId <= 0x7E7)) {
      Serial.print("Received request: ");
      printHex(buf, len);

      processOBDRequest(buf, len);
    }
  }
}

void processOBDRequest(byte* request, byte len) {
  if (len < 2) return;

  byte numBytes = request[0];
  byte service = request[1];

  switch (service) {
    case SERVICE_01:
      if (len >= 3) {
        handleService01(request[2]);
      }
      break;

    case SERVICE_03:
      handleService03();
      break;

    case SERVICE_04:
      handleService04();
      break;

    case SERVICE_09:
      if (len >= 3) {
        handleService09(request[2]);
      }
      break;

    default:
      Serial.print("Unsupported service: 0x");
      Serial.println(service, HEX);
      break;
  }
}

void handleService01(byte pid) {
  byte response[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  byte responseLen = 0;

  switch (pid) {
    // Supported PIDs
    case 0x00:
      response[0] = 0x06;
      response[1] = 0x41;
      response[2] = 0x00;
      response[3] = (vehicle.supportedPids_01_20 >> 24) & 0xFF;
      response[4] = (vehicle.supportedPids_01_20 >> 16) & 0xFF;
      response[5] = (vehicle.supportedPids_01_20 >> 8) & 0xFF;
      response[6] = vehicle.supportedPids_01_20 & 0xFF;
      responseLen = 7;
      break;

    case 0x20:
      response[0] = 0x06;
      response[1] = 0x41;
      response[2] = 0x20;
      response[3] = (vehicle.supportedPids_21_40 >> 24) & 0xFF;
      response[4] = (vehicle.supportedPids_21_40 >> 16) & 0xFF;
      response[5] = (vehicle.supportedPids_21_40 >> 8) & 0xFF;
      response[6] = vehicle.supportedPids_21_40 & 0xFF;
      responseLen = 7;
      break;

    // Monitor status
    case 0x01:
      response[0] = 0x06;
      response[1] = 0x41;
      response[2] = 0x01;
      response[3] = (vehicle.dtcCount > 0) ? 0x81 : 0x00; // MIL on if DTCs
      response[4] = 0x07;  // Supported monitors
      response[5] = 0xE5;
      response[6] = 0x00;
      responseLen = 7;
      break;

    // Coolant temperature
    case 0x05:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x05;
      response[3] = vehicle.coolantTemp + 40;  // Offset by 40
      responseLen = 4;
      break;

    // Short term fuel trim
    case 0x06:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x06;
      response[3] = vehicle.shortTermFuelTrim;
      responseLen = 4;
      break;

    // Long term fuel trim
    case 0x07:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x07;
      response[3] = vehicle.longTermFuelTrim;
      responseLen = 4;
      break;

    // Engine RPM
    case 0x0C:
      response[0] = 0x04;
      response[1] = 0x41;
      response[2] = 0x0C;
      response[3] = (vehicle.rpm * 4) >> 8;
      response[4] = (vehicle.rpm * 4) & 0xFF;
      responseLen = 5;
      break;

    // Vehicle speed
    case 0x0D:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x0D;
      response[3] = vehicle.speed;
      responseLen = 4;
      break;

    // Timing advance
    case 0x0E:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x0E;
      response[3] = (vehicle.timingAdvance + 64) * 2;
      responseLen = 4;
      break;

    // Intake air temperature
    case 0x0F:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x0F;
      response[3] = vehicle.intakeTemp + 40;
      responseLen = 4;
      break;

    // MAF flow rate
    case 0x10:
      response[0] = 0x04;
      response[1] = 0x41;
      response[2] = 0x10;
      response[3] = (vehicle.maf * 100) >> 8;
      response[4] = (vehicle.maf * 100) & 0xFF;
      responseLen = 5;
      break;

    // Throttle position
    case 0x11:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x11;
      response[3] = (vehicle.throttle * 255) / 100;
      responseLen = 4;
      break;

    // Engine load
    case 0x04:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x04;
      response[3] = (vehicle.engineLoad * 255) / 100;
      responseLen = 4;
      break;

    // Fuel level
    case 0x2F:
      response[0] = 0x03;
      response[1] = 0x41;
      response[2] = 0x2F;
      response[3] = (vehicle.fuelLevel * 255) / 100;
      responseLen = 4;
      break;

    // Runtime since engine start
    case 0x1F:
      response[0] = 0x04;
      response[1] = 0x41;
      response[2] = 0x1F;
      response[3] = vehicle.runtime >> 8;
      response[4] = vehicle.runtime & 0xFF;
      responseLen = 5;
      break;

    // Control module voltage
    case 0x42:
      response[0] = 0x04;
      response[1] = 0x41;
      response[2] = 0x42;
      uint16_t mv = vehicle.voltage * 1000;
      response[3] = mv >> 8;
      response[4] = mv & 0xFF;
      responseLen = 5;
      break;

    default:
      Serial.print("Unsupported PID: 0x");
      Serial.println(pid, HEX);
      // Send "not supported" response
      response[0] = 0x03;
      response[1] = 0x7F;
      response[2] = 0x01;
      response[3] = 0x12;  // Sub-function not supported
      responseLen = 4;
      break;
  }

  if (responseLen > 0) {
    sendCANResponse(response);
    Serial.print("Sent response: ");
    printHex(response, 8);
  }
}

void handleService03() {
  // Read stored DTCs
  byte response[8] = {0, 0, 0, 0, 0, 0, 0, 0};

  if (vehicle.dtcCount == 0) {
    response[0] = 0x02;
    response[1] = 0x43;
    response[2] = 0x00;
  } else {
    // Return P0300 (Random misfire)
    response[0] = 0x04;
    response[1] = 0x43;
    response[2] = 0x01;  // 1 DTC
    response[3] = 0x03;  // P0300 high byte
    response[4] = 0x00;  // P0300 low byte
  }

  sendCANResponse(response);
  Serial.print("Sent DTC response: ");
  printHex(response, 8);
}

void handleService04() {
  // Clear DTCs
  vehicle.dtcCount = 0;

  byte response[8] = {0x01, 0x44, 0, 0, 0, 0, 0, 0};
  sendCANResponse(response);
  Serial.println("DTCs cleared");
}

void handleService09(byte pid) {
  byte response[8] = {0, 0, 0, 0, 0, 0, 0, 0};

  switch (pid) {
    case 0x00:
      // Supported Service 09 PIDs
      response[0] = 0x06;
      response[1] = 0x49;
      response[2] = 0x00;
      response[3] = 0x55;  // VIN, Calibration ID
      response[4] = 0x40;
      response[5] = 0x00;
      response[6] = 0x00;
      sendCANResponse(response);
      break;

    case 0x02:
      // VIN - send as multi-frame message (ISO-TP)
      sendVIN();
      break;

    default:
      Serial.print("Unsupported Service 09 PID: 0x");
      Serial.println(pid, HEX);
      break;
  }
}

void sendVIN() {
  // ISO-TP multi-frame for VIN (17 chars + padding)
  // First frame
  byte frame1[8] = {
    0x10, 0x14,  // First frame, 20 bytes total
    0x49, 0x02,  // Service 09, PID 02
    0x01,        // Number of data items
    vehicle.vin[0], vehicle.vin[1], vehicle.vin[2]
  };
  sendCANResponse(frame1);
  delay(10);

  // Consecutive frames
  byte frame2[8] = {
    0x21,  // Consecutive frame 1
    vehicle.vin[3], vehicle.vin[4], vehicle.vin[5],
    vehicle.vin[6], vehicle.vin[7], vehicle.vin[8], vehicle.vin[9]
  };
  sendCANResponse(frame2);
  delay(10);

  byte frame3[8] = {
    0x22,  // Consecutive frame 2
    vehicle.vin[10], vehicle.vin[11], vehicle.vin[12],
    vehicle.vin[13], vehicle.vin[14], vehicle.vin[15], vehicle.vin[16]
  };
  sendCANResponse(frame3);

  Serial.print("Sent VIN: ");
  Serial.println(vehicle.vin);
}

void sendCANResponse(byte* data) {
  CAN.sendMsgBuf(OBD_RESPONSE_ID, 0, 8, data);
}

void updateSimulation() {
  unsigned long now = millis();

  if (now - lastUpdate >= 100) {  // Update every 100ms
    lastUpdate = now;

    if (engineRunning) {
      // Simulate realistic engine behavior
      // RPM fluctuates slightly at idle
      if (vehicle.speed == 0) {
        vehicle.rpm = 800 + random(-50, 50);
      }

      // Update runtime
      vehicle.runtime++;

      // Temperature slowly rises to normal
      if (vehicle.coolantTemp < 90) {
        if (random(10) == 0) vehicle.coolantTemp++;
      }

      // Small voltage fluctuation
      vehicle.voltage = 13.5 + (random(-5, 5) / 10.0);
    } else {
      vehicle.rpm = 0;
      vehicle.coolantTemp = 25;  // Ambient
    }
  }
}

void checkSerialCommands() {
  if (Serial.available()) {
    char cmd = Serial.read();
    int value = Serial.parseInt();

    switch (cmd) {
      case 'r':  // RPM
        vehicle.rpm = constrain(value, 0, 8000);
        Serial.print("RPM set to: ");
        Serial.println(vehicle.rpm);
        break;

      case 's':  // Speed
        vehicle.speed = constrain(value, 0, 255);
        Serial.print("Speed set to: ");
        Serial.print(vehicle.speed);
        Serial.println(" km/h");
        break;

      case 't':  // Temperature
        vehicle.coolantTemp = constrain(value, -40, 215);
        Serial.print("Coolant temp set to: ");
        Serial.print(vehicle.coolantTemp);
        Serial.println(" C");
        break;

      case 'd':  // Add DTC
        vehicle.dtcCount = 1;
        Serial.println("Added DTC P0300");
        break;

      case 'c':  // Clear DTCs
        vehicle.dtcCount = 0;
        Serial.println("Cleared DTCs");
        break;

      case 'e':  // Toggle engine
        engineRunning = !engineRunning;
        Serial.print("Engine: ");
        Serial.println(engineRunning ? "ON" : "OFF");
        break;

      case 'l':  // Load
        vehicle.engineLoad = constrain(value, 0, 100);
        Serial.print("Engine load set to: ");
        Serial.print(vehicle.engineLoad);
        Serial.println("%");
        break;

      case 'f':  // Fuel level
        vehicle.fuelLevel = constrain(value, 0, 100);
        Serial.print("Fuel level set to: ");
        Serial.print(vehicle.fuelLevel);
        Serial.println("%");
        break;
    }
  }
}

void printHex(byte* data, byte len) {
  for (int i = 0; i < len; i++) {
    if (data[i] < 0x10) Serial.print("0");
    Serial.print(data[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
}
