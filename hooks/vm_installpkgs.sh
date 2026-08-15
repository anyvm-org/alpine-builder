# In-guest install script for alpine (piped into the guest sh by build.py
# with ANYVM_PKGS prepended). The guest shell is busybox ash, not bash --
# keep this POSIX.
#
# The cloud image ships an apk index from the compose it was built on. Alpine
# rebuilds packages within a release branch (the -rN suffix), so that cached
# index can point at an -r0 that has already been replaced by -r1 and `apk
# add` then fails on a missing file. One `apk update` avoids it.
apk update
apk add --no-cache $ANYVM_PKGS
