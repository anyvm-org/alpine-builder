# Image-slimming finalize. Runs as the LAST in-guest hook, after postBuild
# and the VM_PRE_INSTALL_PKGS installs. POSIX sh (busybox ash).
#
# The installs above all pass --no-cache, so there should be nothing in
# /var/cache/apk to begin with; clearing it is the cheap guard against a
# package that populated it anyway.

echo "=== finalize: image cleanup ==="

rm -rf /var/cache/apk/* 2>/dev/null || true

# TRIM every mounted filesystem: the build disk runs with discard=unmap, so
# freed blocks become holes in the qcow2 and the export-time sparsify
# reclaims them. fstrim comes from util-linux; busybox also ships one. If
# neither is present this is a no-op, not a failure -- Alpine images are
# small enough that the trim is an optimization, not a requirement.
fstrim -av 2>/dev/null || true

df -h || true
echo "=== finalize: image cleanup done ==="
