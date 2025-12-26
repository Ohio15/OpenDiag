const net = require('net');

const server = net.createServer((socket) => {
  console.log('Client connected');

  socket.on('data', (data) => {
    const cmd = data.toString().trim();
    console.log('Received:', cmd);

    let response;
    switch(cmd) {
      case 'ATZ': response = 'MOCK VCI v1.0'; break;
      case 'ATRV': response = '12.6V'; break;
      case 'ATSP0': response = 'OK'; break;
      case '0100': response = '41 00 BE 3F A8 13'; break;
      case '0120': response = '41 20 80 01 00 01'; break;
      case '010C': response = '41 0C 0B B8'; break;  // RPM: 750
      case '010D': response = '41 0D 32'; break;     // Speed: 50 km/h
      case '0105': response = '41 05 7B'; break;     // Coolant: 83°C
      case '010F': response = '41 0F 32'; break;     // Intake: 10°C
      case '0111': response = '41 11 19'; break;     // Throttle: 10%
      case '03': response = 'NO DATA'; break;        // No DTCs
      default: response = '?';
    }

    socket.write(response + '\r\n>');
  });

  socket.on('close', () => console.log('Client disconnected'));
  socket.on('error', (err) => console.error('Socket error:', err.message));
});

const PORT = process.argv[2] || 35001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Mock VCI server listening on port ${PORT}`);
});
