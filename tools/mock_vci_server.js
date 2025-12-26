/**
 * Mock Autel VCI Server
 *
 * This server simulates an Autel VCI device for testing purposes.
 * It responds to ELM327-compatible AT commands and simulates OBD-II PIDs.
 *
 * Usage: node mock_vci_server.js [port]
 * Default port: 35000
 */

const net = require('net');

const PORT = process.argv[2] ? parseInt(process.argv[2]) : 35000;

// Simulated vehicle data
let vehicleData = {
    rpm: 850,           // Engine RPM
    speed: 0,           // Vehicle speed (km/h)
    coolantTemp: 85,    // Coolant temp (C)
    fuelLevel: 75,      // Fuel level (%)
    throttle: 0,        // Throttle position (%)
    maf: 3.5,           // MAF rate (g/s)
    engineLoad: 25,     // Engine load (%)
    intakeTemp: 25,     // Intake air temp (C)
    fuelPressure: 35,   // Fuel pressure (kPa)
    voltage: 14.2,      // Battery voltage
    vin: 'JTEBU5JR5D5012345', // Vehicle Identification Number
    dtcs: [],           // Diagnostic Trouble Codes
};

// Protocol state
let protocolState = {
    protocol: 'AUTO',
    echo: true,
    linefeed: true,
    headers: false,
    spaces: true,
    timeout: 100,
    deviceDescription: 'MOCK VCI v1.0 (Autel Compatible)',
    initialized: false,
};

// Create server
const server = net.createServer((socket) => {
    const clientAddr = `${socket.remoteAddress}:${socket.remotePort}`;
    console.log(`[+] Client connected: ${clientAddr}`);

    let buffer = '';

    socket.on('data', (data) => {
        buffer += data.toString();

        // Process complete commands (terminated by \r or \r\n)
        while (buffer.includes('\r')) {
            const idx = buffer.indexOf('\r');
            let command = buffer.substring(0, idx).trim();
            buffer = buffer.substring(idx + 1);

            // Remove any leading \n
            if (buffer.startsWith('\n')) {
                buffer = buffer.substring(1);
            }

            if (command.length === 0) continue;

            console.log(`[<] ${clientAddr}: ${command}`);

            const response = processCommand(command);

            if (response !== null) {
                let output = response;
                if (protocolState.echo) {
                    output = command + '\r' + response;
                }
                if (protocolState.linefeed) {
                    output += '\r\n>';
                } else {
                    output += '\r>';
                }

                console.log(`[>] ${clientAddr}: ${response.replace(/\r/g, '\\r').replace(/\n/g, '\\n')}`);
                socket.write(output);
            }
        }
    });

    socket.on('close', () => {
        console.log(`[-] Client disconnected: ${clientAddr}`);
    });

    socket.on('error', (err) => {
        console.log(`[!] Client error ${clientAddr}: ${err.message}`);
    });

    // Send initial prompt
    socket.write('\r\n>');
});

function processCommand(cmd) {
    cmd = cmd.toUpperCase().replace(/\s+/g, '');

    // AT commands
    if (cmd.startsWith('AT')) {
        return processATCommand(cmd.substring(2));
    }

    // OBD-II commands (hex)
    if (/^[0-9A-F]+$/.test(cmd)) {
        return processOBDCommand(cmd);
    }

    return '?';
}

function processATCommand(cmd) {
    // Reset
    if (cmd === 'Z' || cmd === 'WS') {
        protocolState.initialized = false;
        return '\r\rMOCK VCI v1.0\rAutel Compatible ELM327 Emulator';
    }

    // Device description
    if (cmd === '@1') {
        return protocolState.deviceDescription;
    }

    if (cmd === 'I') {
        return 'ELM327 v1.5 (Mock VCI)';
    }

    if (cmd === 'RV') {
        return vehicleData.voltage.toFixed(1) + 'V';
    }

    // Protocol
    if (cmd.startsWith('SP')) {
        const proto = cmd.substring(2);
        protocolState.protocol = proto === '0' ? 'AUTO' : proto;
        protocolState.initialized = true;
        return 'OK';
    }

    if (cmd === 'DPN') {
        return 'A6'; // ISO 15765-4 CAN (11 bit ID, 500 kbaud)
    }

    if (cmd === 'DP') {
        return 'ISO 15765-4 (CAN 11/500)';
    }

    // Echo
    if (cmd === 'E0') {
        protocolState.echo = false;
        return 'OK';
    }
    if (cmd === 'E1') {
        protocolState.echo = true;
        return 'OK';
    }

    // Linefeed
    if (cmd === 'L0') {
        protocolState.linefeed = false;
        return 'OK';
    }
    if (cmd === 'L1') {
        protocolState.linefeed = true;
        return 'OK';
    }

    // Headers
    if (cmd === 'H0') {
        protocolState.headers = false;
        return 'OK';
    }
    if (cmd === 'H1') {
        protocolState.headers = true;
        return 'OK';
    }

    // Spaces
    if (cmd === 'S0') {
        protocolState.spaces = false;
        return 'OK';
    }
    if (cmd === 'S1') {
        protocolState.spaces = true;
        return 'OK';
    }

    // Timeout
    if (cmd.startsWith('ST')) {
        protocolState.timeout = parseInt(cmd.substring(2), 16) * 4;
        return 'OK';
    }

    // Adaptive timing
    if (cmd.startsWith('AT')) {
        return 'OK';
    }

    // Memory
    if (cmd === 'M0' || cmd === 'M1') {
        return 'OK';
    }

    // CAF (CAN Auto Formatting)
    if (cmd === 'CAF0' || cmd === 'CAF1') {
        return 'OK';
    }

    // CFC (CAN Flow Control)
    if (cmd === 'CFC0' || cmd === 'CFC1') {
        return 'OK';
    }

    // PC (Protocol Close)
    if (cmd === 'PC') {
        protocolState.initialized = false;
        return 'OK';
    }

    // Warm start
    if (cmd === 'WS') {
        return 'MOCK VCI v1.0';
    }

    // Set Header
    if (cmd.startsWith('SH')) {
        return 'OK';
    }

    // Custom Autel commands
    if (cmd === 'VER') {
        return 'AUTEL-VCI-MOCK v1.0.0';
    }

    if (cmd === 'INFO') {
        return 'Device: Mock Autel VCI\rFirmware: 1.0.0\rProtocol: ' + protocolState.protocol;
    }

    // Unknown command
    return 'OK';
}

function processOBDCommand(cmd) {
    // Service 01 - Current Data
    if (cmd.startsWith('01')) {
        return processService01(cmd.substring(2));
    }

    // Service 03 - Stored DTCs
    if (cmd === '03') {
        return processService03();
    }

    // Service 04 - Clear DTCs
    if (cmd === '04') {
        vehicleData.dtcs = [];
        return '44';
    }

    // Service 07 - Pending DTCs
    if (cmd === '07') {
        return '47 00';
    }

    // Service 09 - Vehicle Info
    if (cmd.startsWith('09')) {
        return processService09(cmd.substring(2));
    }

    // Service 0A - Permanent DTCs
    if (cmd === '0A') {
        return '4A 00';
    }

    return 'NO DATA';
}

function processService01(pid) {
    // Supported PIDs
    if (pid === '00') {
        // PIDs 01-20 supported: 01, 03, 04, 05, 06, 07, 0C, 0D, 0F, 10, 11
        return '41 00 BE 1F A8 13';
    }
    if (pid === '20') {
        // PIDs 21-40 supported: 21, 2F
        return '41 20 80 02 00 00';
    }

    // Mode 01 responses
    switch (pid) {
        case '01': // Monitor status
            return '41 01 00 07 E1 00';

        case '03': // Fuel system status
            return '41 03 02 00';

        case '04': // Engine load
            return '41 04 ' + toHex(Math.round(vehicleData.engineLoad * 2.55));

        case '05': // Coolant temperature
            return '41 05 ' + toHex(vehicleData.coolantTemp + 40);

        case '06': // Short term fuel trim
            return '41 06 80';

        case '07': // Long term fuel trim
            return '41 07 80';

        case '0C': // Engine RPM
            const rpmValue = Math.round(vehicleData.rpm * 4);
            return '41 0C ' + toHex((rpmValue >> 8) & 0xFF) + ' ' + toHex(rpmValue & 0xFF);

        case '0D': // Vehicle speed
            return '41 0D ' + toHex(vehicleData.speed);

        case '0F': // Intake air temperature
            return '41 0F ' + toHex(vehicleData.intakeTemp + 40);

        case '10': // MAF rate
            const mafValue = Math.round(vehicleData.maf * 100);
            return '41 10 ' + toHex((mafValue >> 8) & 0xFF) + ' ' + toHex(mafValue & 0xFF);

        case '11': // Throttle position
            return '41 11 ' + toHex(Math.round(vehicleData.throttle * 2.55));

        case '21': // Distance with MIL on
            return '41 21 00 00';

        case '2F': // Fuel level
            return '41 2F ' + toHex(Math.round(vehicleData.fuelLevel * 2.55));

        default:
            return 'NO DATA';
    }
}

function processService03() {
    if (vehicleData.dtcs.length === 0) {
        return '43 00';
    }

    let response = '43';
    const numCodes = vehicleData.dtcs.length;
    response += ' ' + toHex(numCodes);

    for (const dtc of vehicleData.dtcs) {
        const encoded = encodeDTC(dtc);
        response += ' ' + toHex((encoded >> 8) & 0xFF) + ' ' + toHex(encoded & 0xFF);
    }

    return response;
}

function processService09(pid) {
    switch (pid) {
        case '00': // Supported PIDs
            return '49 00 55 40 00 00';

        case '02': // VIN
            let vinHex = '';
            for (let i = 0; i < vehicleData.vin.length; i++) {
                vinHex += ' ' + toHex(vehicleData.vin.charCodeAt(i));
            }
            return '49 02 01' + vinHex;

        case '04': // Calibration ID
            return '49 04 01 4D 4F 43 4B 20 43 41 4C 20 49 44 00 00 00 00 00';

        case '06': // CVN
            return '49 06 01 00 00 00 00';

        case '0A': // ECU name
            return '49 0A 01 45 43 55 20 31 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00';

        default:
            return 'NO DATA';
    }
}

function encodeDTC(dtc) {
    // DTC format: P0123, C0456, B0789, U0ABC
    const typeMap = { 'P': 0, 'C': 1, 'B': 2, 'U': 3 };
    const type = typeMap[dtc[0]] || 0;
    const code = parseInt(dtc.substring(1), 16);
    return (type << 14) | code;
}

function toHex(value) {
    return value.toString(16).toUpperCase().padStart(2, '0');
}

// Start server
server.listen(PORT, '0.0.0.0', () => {
    console.log('===========================================');
    console.log('   Mock Autel VCI Server');
    console.log('===========================================');
    console.log(`Listening on port ${PORT}`);
    console.log('');
    console.log('Simulated Vehicle Data:');
    console.log(`  VIN: ${vehicleData.vin}`);
    console.log(`  Engine RPM: ${vehicleData.rpm}`);
    console.log(`  Speed: ${vehicleData.speed} km/h`);
    console.log(`  Coolant Temp: ${vehicleData.coolantTemp}°C`);
    console.log(`  Fuel Level: ${vehicleData.fuelLevel}%`);
    console.log('');
    console.log('Supported Commands:');
    console.log('  AT commands: Z, I, @1, RV, SP, DP, E0/E1, L0/L1, H0/H1');
    console.log('  OBD-II Service 01: PIDs 00,01,03,04,05,0C,0D,0F,10,11,21,2F');
    console.log('  OBD-II Service 03: Read DTCs');
    console.log('  OBD-II Service 04: Clear DTCs');
    console.log('  OBD-II Service 09: VIN, Cal ID, ECU Name');
    console.log('');
    console.log('Connect with: telnet localhost ' + PORT);
    console.log('Or use OpenDiag Network VCI mode');
    console.log('===========================================');
});

// Simulate engine running - update values periodically
setInterval(() => {
    // Simulate slight variations
    vehicleData.rpm = 850 + Math.floor(Math.random() * 50) - 25;
    vehicleData.coolantTemp = 85 + Math.floor(Math.random() * 3) - 1;
    vehicleData.engineLoad = 25 + Math.floor(Math.random() * 5);
}, 1000);

// Handle shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down...');
    server.close();
    process.exit(0);
});
