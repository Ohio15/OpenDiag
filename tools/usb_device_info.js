const usb = require('usb');

console.log('=== Scanning USB Devices ===\n');

// Get all USB devices
const devices = usb.getDeviceList();

console.log(`Found ${devices.length} USB devices:\n`);

devices.forEach((device, index) => {
  const desc = device.deviceDescriptor;
  const vid = desc.idVendor.toString(16).padStart(4, '0').toUpperCase();
  const pid = desc.idProduct.toString(16).padStart(4, '0').toUpperCase();

  console.log(`[${index}] VID: ${vid}, PID: ${pid}`);
  console.log(`    Bus: ${device.busNumber}, Address: ${device.deviceAddress}`);
  console.log(`    Class: ${desc.bDeviceClass}, SubClass: ${desc.bDeviceSubClass}, Protocol: ${desc.bDeviceProtocol}`);

  // Try to open the device to get more info
  try {
    device.open();

    // Get string descriptors
    if (desc.iManufacturer) {
      device.getStringDescriptor(desc.iManufacturer, (err, manufacturer) => {
        if (!err && manufacturer) console.log(`    Manufacturer: ${manufacturer}`);
      });
    }
    if (desc.iProduct) {
      device.getStringDescriptor(desc.iProduct, (err, product) => {
        if (!err && product) console.log(`    Product: ${product}`);
      });
    }
    if (desc.iSerialNumber) {
      device.getStringDescriptor(desc.iSerialNumber, (err, serial) => {
        if (!err && serial) console.log(`    Serial: ${serial}`);
      });
    }

    // Get configuration
    const configDesc = device.configDescriptor;
    if (configDesc) {
      console.log(`    Interfaces: ${configDesc.bNumInterfaces}`);
      configDesc.interfaces.forEach((iface, ifaceNum) => {
        iface.forEach((alt) => {
          console.log(`      Interface ${ifaceNum}: Class=${alt.bInterfaceClass}, SubClass=${alt.bInterfaceSubClass}, Protocol=${alt.bInterfaceProtocol}`);
          alt.endpoints.forEach((ep) => {
            const dir = ep.bEndpointAddress & 0x80 ? 'IN' : 'OUT';
            const type = ['Control', 'Isochronous', 'Bulk', 'Interrupt'][ep.bmAttributes & 0x03];
            console.log(`        Endpoint 0x${ep.bEndpointAddress.toString(16)}: ${dir} ${type}, MaxPacketSize=${ep.wMaxPacketSize}`);
          });
        });
      });
    }

    device.close();
  } catch (err) {
    console.log(`    (Could not open: ${err.message})`);
  }

  console.log('');
});

// Focus on VID_A5A5 device
console.log('\n=== VID_A5A5 Device Details ===\n');
const targetDevice = usb.findByIds(0xA5A5, 0x2540);
if (targetDevice) {
  console.log('Found VID_A5A5 device!');
  try {
    targetDevice.open();

    const desc = targetDevice.deviceDescriptor;
    console.log(`Device Descriptor:`);
    console.log(`  USB Version: ${(desc.bcdUSB >> 8)}.${(desc.bcdUSB & 0xFF).toString().padStart(2, '0')}`);
    console.log(`  Device Class: ${desc.bDeviceClass}`);
    console.log(`  Vendor ID: 0x${desc.idVendor.toString(16)}`);
    console.log(`  Product ID: 0x${desc.idProduct.toString(16)}`);
    console.log(`  Num Configurations: ${desc.bNumConfigurations}`);

    const config = targetDevice.configDescriptor;
    console.log(`\nConfiguration:`);
    console.log(`  Num Interfaces: ${config.bNumInterfaces}`);

    config.interfaces.forEach((iface, num) => {
      console.log(`\n  Interface ${num}:`);
      iface.forEach((alt, altNum) => {
        console.log(`    Alt Setting ${altNum}:`);
        console.log(`      Class: ${alt.bInterfaceClass} (${getClassName(alt.bInterfaceClass)})`);
        console.log(`      SubClass: ${alt.bInterfaceSubClass}`);
        console.log(`      Protocol: ${alt.bInterfaceProtocol}`);
        console.log(`      Endpoints: ${alt.endpoints.length}`);

        alt.endpoints.forEach((ep) => {
          const dir = ep.bEndpointAddress & 0x80 ? 'IN' : 'OUT';
          const type = ['Control', 'Isochronous', 'Bulk', 'Interrupt'][ep.bmAttributes & 0x03];
          console.log(`        EP 0x${ep.bEndpointAddress.toString(16).padStart(2, '0')}: ${dir} ${type} (max ${ep.wMaxPacketSize} bytes)`);
        });
      });
    });

    targetDevice.close();
  } catch (err) {
    console.log(`Error: ${err.message}`);
  }
} else {
  console.log('VID_A5A5 device not found');
}

function getClassName(classCode) {
  const classes = {
    0x00: 'Use Interface Descriptor',
    0x01: 'Audio',
    0x02: 'CDC',
    0x03: 'HID',
    0x05: 'Physical',
    0x06: 'Image',
    0x07: 'Printer',
    0x08: 'Mass Storage',
    0x09: 'Hub',
    0x0A: 'CDC-Data',
    0x0B: 'Smart Card',
    0x0D: 'Content Security',
    0x0E: 'Video',
    0x0F: 'Healthcare',
    0x10: 'Audio/Video',
    0xDC: 'Diagnostic',
    0xE0: 'Wireless',
    0xEF: 'Misc',
    0xFE: 'Application Specific',
    0xFF: 'Vendor Specific'
  };
  return classes[classCode] || 'Unknown';
}
