

| Release | x86_64 | aarch64 |
|---------|---------|---------|
| 3.24 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) |
| 3.23 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) |


Alpine publishes cloud images for x86_64 and aarch64 only.

The image URL in each conf pins a full patch version (for example 3.24.1)
even though the release column shows the branch (3.24). Alpine puts the
patch version and an image revision in the filename and publishes no
`latest` alias, but it keeps older patch images in the branch directory --
so the pin is durable, and moving a release to a newer patch is an in-place
URL edit rather than a new release row.
