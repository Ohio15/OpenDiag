/**
 * Test script for Mock VCI Server
 * Tests AT commands and OBD-II PIDs
 */
const net = require('net');

const PORT = process.argv[2] || 35000;
const HOST = process.argv[3] || 'localhost';

let buffer = '';

const commands = [
    { cmd: 'ATZ', desc: 'Reset' },
    { cmd: 'ATI', desc: 'Device Info' },
    { cmd: 'ATRV', desc: 'Battery Voltage' },
    { cmd: 'ATDP', desc: 'Protocol' },
    { cmd: '0100', desc: 'Supported PIDs 01-20' },
    { cmd: '010C', desc: 'Engine RPM' },
    { cmd: '010D', desc: 'Vehicle Speed' },
    { cmd: '0105', desc: 'Coolant Temp' },
    { cmd: '012F', desc: 'Fuel Level' },
    { cmd: '0902', desc: 'VIN' },
    { cmd: '03', desc: 'Read DTCs' },
];

let cmdIndex = 0;

function parseResponse(text) {
    // Clean up response
    return text
        .replace(/\r/g, '\n')
        .replace(/\n+/g, '\n')
        .replace(/>/g, '')
        .split('\n')
        .map(l => l.trim())
        .filter(l => l.length > 0)
        .join(' | ');
}

const client = new net.Socket();

client.connect(PORT, HOST, () => {
    console.log(`Connected to Mock VCI at ${HOST}:${PORT}\n`);
    console.log('=' .repeat(60));
});

client.on('data', (data) => {
    buffer += data.toString();
    
    // Check for complete response (ends with >)
    if (buffer.includes('>')) {
        const response = parseResponse(buffer);
        buffer = '';
        
        if (cmdIndex > 0) {
            const lastCmd = commands[cmdIndex - 1];
            console.log(`[${lastCmd.desc}] ${lastCmd.cmd}`);
            console.log(`  Response: ${response}`);
            console.log('');
        }
        
        // Send next command
        if (cmdIndex < commands.length) {
            const nextCmd = commands[cmdIndex];
            client.write(nextCmd.cmd + '\r');
            cmdIndex++;
        } else {
            console.log('=' .repeat(60));
            console.log('All tests completed successfully!');
            client.destroy();
        }
    }
});

client.on('close', () => {
    console.log('\nConnection closed.');
    process.exit(0);
});

client.on('error', (err) => {
    console.error('Error:', err.message);
    process.exit(1);
});

// Timeout after 10 seconds
setTimeout(() => {
    console.error('Test timed out!');
    client.destroy();
    process.exit(1);
}, 10000);
