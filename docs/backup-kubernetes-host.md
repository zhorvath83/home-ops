# Backing up kubernetes VM

Before the backup operation run `sudo k3s crictl rmi --prune` command to delete any images no currently used by a running container.

Then run `sudo fstrim -av` command.

Checking available images: `sudo k3s crictl images`
