"""Select installed Xcode 26+, optionally exporting an iPhone simulator ID."""
import glob
import json
import os
import re
import subprocess
import sys

candidates = []
for path in glob.glob('/Applications/Xcode*.app'):
    version = re.search(r'Xcode_(\d+)(?:\.(\d+))?(?:\.(\d+))?', path)
    if version and int(version[1]) >= 26:
        candidates.append((tuple(int(v or 0) for v in version.groups()), path))
assert candidates, 'Xcode 26 or newer is required'
os.environ['DEVELOPER_DIR'] = max(candidates)[1] + '/Contents/Developer'
values = {'DEVELOPER_DIR': os.environ['DEVELOPER_DIR']}
if '--simulator' in sys.argv:
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
    phones = [device for runtime, entries in devices['devices'].items() if 'iOS-26' in runtime
              for device in entries if 'iPhone' in device['name'] and device.get('isAvailable')]
    assert phones, 'An iOS 26 iPhone simulator is required'
    values['EAR_SIM'] = next((p for p in phones if p['name'] == 'iPhone 17 Pro'), phones[0])['udid']
with open(os.environ['GITHUB_ENV'], 'a') as output:
    for key, value in values.items():
        output.write(f'{key}={value}\n')
print(values)
