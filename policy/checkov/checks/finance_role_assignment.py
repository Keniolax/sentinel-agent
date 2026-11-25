"""Policy-as-code: no Terraform may grant a Storage Blob Data role on the finance container.

The capstone's second lock is that the agent's identity has no role on the finance container.
This custom Checkov check makes that lock part of the gate: if any azurerm_role_assignment
names a Storage Blob Data role and a scope that points at the finance container, the gate
fails before the change can merge. It is the static twin of the runtime RBAC check.
"""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class FinanceRoleAssignmentDenied(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="No role assignment grants a Storage Blob Data role on the finance container",
            id="CKV_SENTINEL_1",
            categories=[CheckCategories.IAM],
            supported_resources=["azurerm_role_assignment"],
        )

    def scan_resource_conf(self, conf):
        role = str((conf.get("role_definition_name") or [""])[0]).lower()
        scope = str((conf.get("scope") or [""])[0]).lower()
        if "storage blob data" in role and "finance" in scope:
            return CheckResult.FAILED
        return CheckResult.PASSED


check = FinanceRoleAssignmentDenied()
