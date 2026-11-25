"""Read-only access to the knowledge-base container in Azure Blob Storage.

The job signs in with its user-assigned managed identity. No key or connection string
exists: the storage account has shared-key access turned off.
"""

import itertools


class BlobStore:
    def __init__(self, container_client):
        self.client = container_client

    @classmethod
    def from_managed_identity(cls, account_url, container, client_id):
        from azure.identity import ManagedIdentityCredential
        from azure.storage.blob import ContainerClient

        credential = ManagedIdentityCredential(client_id=client_id)
        return cls(ContainerClient(account_url, container, credential=credential))

    def list(self, prefix, limit):
        blobs = self.client.list_blobs(name_starts_with=prefix, results_per_page=limit)
        return [b.name for b in itertools.islice(blobs, limit)]

    def get(self, key, max_bytes):
        # A ranged read: the agent never downloads more than it will pass to the model.
        return self.client.download_blob(key, offset=0, length=max_bytes).readall()
