#!/bin/bash
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ -f /var/root/ios7-bootstrap.done ] && exit 0
exec >> /var/log/ios7-bootstrap.log 2>&1
echo "BOOTSTRAP START $(date)"
grep -q 11D257 /System/Library/CoreServices/SystemVersion.plist
if [ -s /var/lib/dpkg/status ]; then
    echo "Existing package database found. Stopping to preserve it."
    exit 1
fi
mkdir -p /var/root/ios7-bootstrap-backup /var/lib /var/root/Media/Cydia/AutoInstall /var/run /var/empty
if [ -f /var/mobile/Library/Preferences/com.apple.springboard.plist ]; then
    cp -p /var/mobile/Library/Preferences/com.apple.springboard.plist /var/root/ios7-bootstrap-backup/springboard.plist
fi
if [ -d /var/root/Library/Lockdown ]; then
    tar -czf /var/root/ios7-bootstrap-backup/activation.tgz -C /var/root/Library Lockdown
    chmod 600 /var/root/ios7-bootstrap-backup/activation.tgz
fi
cp -Rp /private/ios7-bootstrap/var/lib/. /var/lib/
/sbin/mount -u -o rw / || true
cp -p /private/ios7-bootstrap/Cydia.Startup.plist /Library/LaunchDaemons/com.saurik.Cydia.Startup.plist
chmod 644 /Library/LaunchDaemons/com.saurik.Cydia.Startup.plist
/usr/libexec/cydia/firmware.sh
/usr/bin/dpkg -i /private/ios7-bootstrap/debs/*.deb
cat > /var/mobile/Library/Preferences/com.julioverne.fiona.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Enabled</key><true/></dict></plist>
PLIST
chown 501:501 /var/mobile/Library/Preferences/com.julioverne.fiona.plist
chmod 600 /var/mobile/Library/Preferences/com.julioverne.fiona.plist
/bin/bash /usr/libexec/cydia/startup
/bin/su -c /usr/bin/uicache mobile || true
/usr/bin/dpkg-query -W cydia mobilesubstrate com.saurik.substrate.safemode preferenceloader com.julioverne.fiona com.scs.wififix
sync
touch /var/root/ios7-bootstrap.done
echo "BOOTSTRAP DONE $(date)"
/bin/launchctl stop com.apple.SpringBoard || true
