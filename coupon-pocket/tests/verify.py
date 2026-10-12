from pathlib import Path
import xml.etree.ElementTree as ET
import cv2
root = ET.parse('app/src/main/AndroidManifest.xml').getroot()
a = '{http://schemas.android.com/apk/res/android}'
permissions = [p.get(a+'name') for p in root.findall('uses-permission')]
assert permissions == ['android.permission.INTERNET'], permissions
app = root.find('application')
assert app.get(a+'allowBackup') == 'false'
assert app.get(a+'usesCleartextTraffic') == 'false'
assert not app.findall('service') and not app.findall('receiver')
java = Path('app/src/main/java')
packages = {str(p.parent.relative_to(java)) for p in java.rglob('*.java')}
assert packages == {'local/couponpocket','io/nayuki/qrcodegen'}, packages
for index, payload in enumerate(['1234567890123456','TEST-CARD:cz:coffee-42']):
    image=cv2.imread(f'build/test-output/qr-{index}.png')
    value,points,_=cv2.QRCodeDetector().detectAndDecode(image)
    assert value == payload, (value,payload)
print('PASS: manifest privacy checks and two QR round trips decoded independently by OpenCV.')
