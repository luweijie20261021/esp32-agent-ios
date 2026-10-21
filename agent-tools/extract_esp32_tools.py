import json, os, sys

path = os.path.expandvars(r'C:\Users\Administrator\AppData\Local\Arduino15\package_index.json')
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

esp32_pkg = next((p for p in data['packages'] if p['name'] == 'esp32'), None)
if not esp32_pkg:
    sys.exit('esp32 package not found')

plat = next((pl for pl in esp32_pkg['platforms'] if pl['version'] == '3.3.0'), None)
if not plat:
    sys.exit('esp32 3.3.0 platform not found')

tools = esp32_pkg.get('tools', [])

def find_tool(name, version):
    return next((t for t in tools if t['name'] == name and t['version'] == version), None)

print(f"Platform: esp32:esp32@{plat['version']}")
print(f"Core URL: {plat['url']}")
print(f"Core archive: {plat['archiveFileName']}")
print(f"Core checksum: {plat['checksum']}")
print(f"Core size: {plat['size']}")
print()
print('Windows x86_64 tool archives needed:')
for dep in plat['toolsDependencies']:
    name = dep['name']
    ver = dep['version']
    t = find_tool(name, ver)
    if not t:
        print(f"  {name}@{ver}: NOT FOUND in tools list")
        continue
    sys_entry = next((s for s in t['systems'] if s['host'] == 'x86_64-mingw32'), None)
    if not sys_entry:
        # fallback to i686 if no x86_64
        sys_entry = next((s for s in t['systems'] if s['host'] == 'i686-mingw32'), None)
    if not sys_entry:
        print(f"  {name}@{ver}: no Windows system archive")
        continue
    print(f"{name}@{ver}")
    print(f"  filename={sys_entry['archiveFileName']}")
    print(f"  size={sys_entry['size']}")
    print(f"  checksum={sys_entry['checksum']}")
    print(f"  url={sys_entry['url']}")
