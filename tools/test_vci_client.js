const net = require('net');

const PORT = process.argv[2] || 35001;
const HOST = process.argv[3] || '127.0.0.1';

const commands = ['ATZ', 'ATRV', 'ATSP0', '0100', '010C', '010D', '0105', '03'];
let cmdIndex = 0;

console.log(`Connecting to ${HOST}:${PORT}...`);

const client = new net.Socket();

client.connect(PORT, HOST, () => {
  console.log('Connected to Mock VCI\n');
  sendNextCommand();
});

function sendNextCommand() {
  if (cmdIndex < commands.length) {
    const cmd = commands[cmdIndex];
    console.log(`TX: ${cmd}`);
    client.write(cmd + '\r');
    cmdIndex++;
  } else {
    console.log('\nAll commands sent. Closing connection.');
    client.end();
  }
}

client.on('data', (data) => {
  const response = data.toString().replace(/>/g, '').trim();
  console.log(`RX: ${response}`);

  // Wait a bit before sending next command
  setTimeout(sendNextCommand, 200);
});

client.on('close', () => {
  console.log('Connection closed');
  process.exit(0);
});

client.on('error', (err) => {
  console.error('Connection error:', err.message);
  process.exit(1);
});
