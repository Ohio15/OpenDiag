const usb = require('usb');

const VID = 0xA5A5;
const PID = 0x2540;
const EP_OUT = 0x02;
const EP_IN = 0x83;

class AutoVCI {
  constructor() {
    this.device = null;
    this.interface = null;
    this.epOut = null;
    this.epIn = null;
  }

  open() {
    this.device = usb.findByIds(VID, PID);
    if (!this.device) {
      throw new Error('VCI device not found');
    }

    this.device.open();
    this.interface = this.device.interface(0);

    // Detach kernel driver if necessary (Linux)
    if (this.interface.isKernelDriverActive()) {
      this.interface.detachKernelDriver();
    }

    this.interface.claim();

    // Find endpoints
    for (const ep of this.interface.endpoints) {
      if (ep.direction === 'out') {
        this.epOut = ep;
      } else if (ep.direction === 'in') {
        this.epIn = ep;
      }
    }

    console.log('VCI opened successfully');
    console.log(`  OUT Endpoint: 0x${this.epOut.address.toString(16)}`);
    console.log(`  IN Endpoint: 0x${this.epIn.address.toString(16)}`);
  }

  async send(data) {
    return new Promise((resolve, reject) => {
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
      console.log(`TX: ${buffer.toString('hex')}`);
      this.epOut.transfer(buffer, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  async receive(timeout = 5000) {
    return new Promise((resolve, reject) => {
      this.epIn.timeout = timeout;
      this.epIn.transfer(64, (err, data) => {
        if (err) {
          if (err.errno === usb.LIBUSB_TRANSFER_TIMED_OUT) {
            resolve(null);
          } else {
            reject(err);
          }
        } else {
          console.log(`RX: ${data.toString('hex')}`);
          resolve(data);
        }
      });
    });
  }

  async sendAndReceive(data, timeout = 5000) {
    await this.send(data);
    return await this.receive(timeout);
  }

  close() {
    if (this.interface) {
      this.interface.release(true, () => {});
    }
    if (this.device) {
      this.device.close();
    }
    console.log('VCI closed');
  }
}

// Common VCI/OBD probe commands
const PROBE_COMMANDS = [
  // ATZ - Reset (ELM327 style)
  Buffer.from('ATZ\r'),
  // ATI - Device info
  Buffer.from('ATI\r'),
  // Simple ping byte
  Buffer.from([0x00]),
  // STN style reset
  Buffer.from('STI\r'),
  // Version query
  Buffer.from([0x01, 0x00]),
  // Autel-style handshake (guesses)
  Buffer.from([0xAA, 0x55, 0x00, 0x00]),
  Buffer.from([0x55, 0xAA, 0x00, 0x00]),
  // USB Mass Storage inquiry (since it claims SubClass 6)
  Buffer.from([0x55, 0x53, 0x42, 0x43, 0x01, 0x00, 0x00, 0x00, 0x24, 0x00, 0x80, 0x00, 0x06, 0x12, 0x00, 0x00, 0x00, 0x24, 0x00]),
];

async function main() {
  const vci = new AutoVCI();

  try {
    vci.open();

    console.log('\n=== Probing VCI device ===\n');

    // Try various commands to understand the protocol
    for (const cmd of PROBE_COMMANDS) {
      console.log(`\nTrying command: ${cmd.toString('hex')} (${cmd.toString().replace(/[^\x20-\x7E]/g, '.')})`);
      try {
        const response = await vci.sendAndReceive(cmd, 2000);
        if (response) {
          console.log(`Response: ${response.toString('hex')}`);
          console.log(`As ASCII: ${response.toString().replace(/[^\x20-\x7E]/g, '.')}`);
        } else {
          console.log('No response (timeout)');
        }
      } catch (err) {
        console.log(`Error: ${err.message}`);
      }
      await new Promise(r => setTimeout(r, 500));
    }

    // Start listening for any incoming data
    console.log('\n=== Listening for incoming data (10 seconds) ===\n');
    const startTime = Date.now();
    while (Date.now() - startTime < 10000) {
      try {
        const data = await vci.receive(1000);
        if (data) {
          console.log(`Received: ${data.toString('hex')}`);
        }
      } catch (err) {
        // Ignore timeout errors
      }
    }

  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    vci.close();
  }
}

main();
