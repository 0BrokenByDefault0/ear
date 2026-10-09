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
    runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
    compatible = [runtime for runtime in runtimes if runtime.get('isAvailable')
                  and runtime['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-')]
    assert compatible, 'An available iOS 26 simulator runtime is required'
    runtime = max(compatible, key=lambda item: tuple(int(part) for part in item['version'].split('.')))
    types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
    phone = next(device for device in types if device['name'] == 'iPhone 17 Pro')
    # A runner's preinstalled device can retain file-provider IDs for missing files.
    # Give each check a new device and its own provider database.
    values['EAR_SIM'] = subprocess.check_output([
        'xcrun', 'simctl', 'create', 'EAR Native Checks', phone['identifier'], runtime['identifier']
    ], text=True).strip()
    print('Fresh simulator runtime:', runtime['identifier'])
with open(os.environ['GITHUB_ENV'], 'a') as output:
    for key, value in values.items():
        output.write(f'{key}={value}\n')
print(values)
