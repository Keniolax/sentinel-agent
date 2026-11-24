#!/usr/bin/with-contenv bash
# Runs inside the Wazuh manager container at start. Adds the AWS reader block to ossec.conf
# once, keeps every event in archives.json so a test can find a run by its ID, and installs
# the capstone's local rules.
set -euo pipefail
conf=/var/ossec/etc/ossec.conf
if ! grep -q 'sentinel-aws-wodle' "$conf"; then
  cat /opt/sentinel/aws-wodle.xml >> "$conf"
fi
sed -i 's|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|' "$conf"
install -o wazuh -g wazuh -m 0640 /opt/sentinel/local_rules.xml /var/ossec/etc/rules/local_rules.xml
