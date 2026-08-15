

[![Build](https://github.com/anyvm-org/alpine-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/alpine-builder/actions/workflows/build.yml)

Latest: v2.0.0


The image builder for `alpine`


All the supported releases are here:



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




How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    python3 build.py conf/alpine-3.24.conf
    ```
   
