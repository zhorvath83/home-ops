## How to completely delete a repository

# What are the steps to completely delete a repository from the backup storage (B2, in my case)? Do you just delete all of the snapshots/revisions for that repository?


You can remove the subdirectory under the snapshots directory, but this will leave many unreferenced chunks on the storage. To clean up storage, run duplicacy prune -exhaustive from another client/repository. This will find all unreferenced chunks and mark them as fossils which will be removed permanently next time the prune command is run with some conditions satisfied (https://github.com/gilbertchen/duplicacy/blob/master/DESIGN.md#two-step-fossil-collection).
