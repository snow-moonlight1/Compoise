'use strict';

const fs = require('node:fs');

const output = fs.readFileSync(0, 'utf8');
const start = output.indexOf('{');
const end = output.lastIndexOf('}');
if (start < 0 || end <= start) {
  console.error('Flutter did not output machine-readable version information.');
  process.exit(1);
}

let actual;
try {
  actual = JSON.parse(output.slice(start, end + 1));
} catch {
  console.error('Flutter version information is not valid JSON.');
  process.exit(1);
}

const pin = JSON.parse(fs.readFileSync('toolchain.json', 'utf8')).verified;
const fields = {
  frameworkVersion: pin.flutterVersion,
  dartSdkVersion: pin.dartVersion,
  frameworkRevision: pin.revision,
  engineRevision: pin.engineRevision,
  channel: pin.channel,
};

for (const [name, expected] of Object.entries(fields)) {
  if (actual[name] !== expected) {
    console.error(`Flutter pin mismatch: ${name}`);
    process.exit(1);
  }
}

console.log(`${actual.frameworkVersion} ${actual.frameworkRevision}`);
