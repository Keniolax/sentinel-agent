#!/usr/bin/with-contenv bash
# Runs inside the Wazuh manager container at start. Tells the manager to read the collector's
# file once, keeps every event in archives.json so a test can find a run by its ID, and
# installs the capstone's local rules.
set -euo pipefail
conf=/var/ossec/etc/ossec.conf
if ! grep -q 'sentinel-azure-collector' "$conf"; then
  cat >> "$conf" <<'XML'
<!-- sentinel-azure-collector: rows the host's collector copies from Log Analytics -->
<ossec_config>
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/sentinel/azure.json</location>
  </localfile>
</ossec_config>
XML
fi
sed -i 's|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|' "$conf"
install -o wazuh -g wazuh -m 0640 /opt/sentinel/local_rules.xml /var/ossec/etc/rules/local_rules.xml
