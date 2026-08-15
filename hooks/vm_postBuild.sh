# in-guest postBuild hook (piped to the guest's sh over SSH by build.py).
#
# The guest shell is busybox ash and the init system is OpenRC, not systemd
# -- so this hook shares no service-management code with any other Linux
# builder here. Keep it POSIX sh: no arrays, no [[ ]], no systemctl.

echo "=================== alpine postBuild ===="

# Make sure sshd survives the reboot that build.py does right after this
# hook. OpenRC's equivalent of "systemctl enable" is adding the service to a
# runlevel; "default" is the normal multi-user one.
echo "--- enabling sshd in the default runlevel ---"
rc-update add sshd default 2>/dev/null || true

# Alpine has no apt-daily / dnf-makecache equivalent -- apk only ever runs
# when something calls it -- so there is no background package machinery to
# disable here. That is the whole reason this hook is so much shorter than
# the Debian and RHEL ones.

# NOTE: do NOT run "cloud-init clean" here. build.py reboots right after
# this hook, and a clean makes cloud-init treat the next boot as a new
# instance, which (via ssh_deletekeys) regenerates the SSH host keys. The
# host key for the VM's IP then changes mid-build and the next "ssh"
# fails with "REMOTE HOST IDENTIFICATION HAS CHANGED".

# Clear the root password. busybox passwd and shadow's passwd both take -d,
# but the cloud image may ship either, so stay tolerant.
passwd -d root 2>/dev/null || true

echo "alpine postBuild done."

exit 0
