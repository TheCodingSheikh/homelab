createNamespace: false
additionalSyncOptions:
  - ApplyOutOfSyncOnly=true
ignoreDifferences:
  - group: ""
    kind: Secret
    name: slurm-auth-slurm
    jsonPointers:
    - /data
  - group: ""
    kind: Secret
    name: slurm-auth-jwths256
    jsonPointers:
    - /data