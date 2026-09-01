"""Drive the Alpine riscv64 install over the serial console.

Only the riscv64 conf reaches here: the x86_64/aarch64 confs are cloud
images (VM_VHD_LINK), which take build.py's prepareImage path instead and
never call installOpts at all. The gate is still explicit rather than
implied, because run_hook fires this file for every conf in the builder.

What is running when this starts: createVM() booted the installer ISO that
hooks/host_beforeBuild.sh placed at build/<os>.img (/dev/vda -- attached as
a virtio disk, not a cdrom; see that hook for why), with the empty target
qcow2 alongside as /dev/vdb, and openConsole() is already up. The ISO boots
through u-boot's EFI loader, so the live system has efivarfs mounted and
setup-disk installs grub-efi onto an ESP.

Costs measured against 3.24.1 on this workstation: login at 49-75 s, apk
work about half a minute once the network is up, setup-disk about a
minute. The timeouts are crash backstops well above those, not budgets --
riscv64 has no KVM here, so all of it runs under TCG emulation and a loaded
CI runner will be slower than this workstation.
"""

if env("VM_ARCH") != "riscv64" or not env("VM_ISO_LINK"):
    log("installOpts: not the riscv64 ISO path; leaving it to the "
        "cloud-image flow")
else:
    log("=== alpine riscv64: installing to /dev/vdb ===")

    # The live system's own login. Alpine's live root has no password.
    if waitForText("login:", "900") != 0:
        log("FATAL: the live system never reached a login prompt")
        sys.exit(1)
    string("root")
    enter()
    if waitForText("localhost:~#", "180") != 0:
        log("FATAL: root login did not produce a shell")
        sys.exit(1)

    # Bring up networking. This disk is assembled by beforeBuild from the
    # alpine-uboot tarball, which -- unlike the cloud images the other two
    # arches use -- ships NO /etc/network/interfaces, and boots with eth0 in
    # state DOWN. Calling udhcpc directly against a down link does not fail:
    # it loops on "read error: Network is down, reopening socket" forever,
    # and neither -n nor -t bounds it, because those cover a missing lease
    # rather than a socket error. That is what a silent 600 s hang looked
    # like here before this step existed.
    #
    # setup-interfaces rather than a bare `ip link set eth0 up`, because
    # setup-disk -m sys copies the LIVE system's /etc into the installed one:
    # without the file, the exported image would come up with no networking
    # at all. The file it writes -- "auto eth0 / iface eth0 inet dhcp" -- is
    # the same config the x86_64/aarch64 cloud images bake in, so all three
    # arches end up with identical network setup.
    string("setup-interfaces -a >/dev/null 2>&1; echo IFDONE-$?")
    enter()
    if waitForText("IFDONE-0", "300") != 0:
        log("FATAL: setup-interfaces did not write /etc/network/interfaces")
        sys.exit(1)

    # Gated on an address actually existing, not on rc-service's exit status:
    # the address is what the next steps need, and a service that reports
    # success while the lease silently failed is exactly the case worth
    # catching here rather than three steps later.
    string("rc-service networking start 2>&1 | tail -3; "
           "ip -4 -o addr show eth0 | grep -q 'inet '; echo NETDONE-$?")
    enter()
    if waitForText("NETDONE-0", "600") != 0:
        log("FATAL: the guest never got an address; apk cannot run")
        sys.exit(1)

    # Repositories. -1 picks the first mirror non-interactively; without it
    # setup-apkrepos prompts and the build would hang on a menu.
    string("setup-apkrepos -1 >/dev/null 2>&1; apk update 2>&1 | tail -1; echo REPODONE-$?")
    enter()
    if waitForText("REPODONE-0", "900") != 0:
        log("FATAL: apk repositories could not be set up")
        sys.exit(1)

    # Everything setup-alpine would have done for ssh, done here because this
    # flow calls setup-disk directly. Offline inspection of the image the
    # first working install produced showed exactly what was missing:
    # /etc/network/interfaces was present (setup-interfaces above put it
    # there), but /etc/runlevels/default was EMPTY and openssh was not
    # installed at all -- so the exported image booted to a login prompt with
    # no network service and no sshd.
    #
    # This has to happen BEFORE setup-disk, not after: setup-disk -m sys
    # copies the running live system onto the target and then unmounts it, so
    # the live system's /etc, /root and package set are what the installed
    # image ends up with.
    string("apk add openssh >/dev/null 2>&1 && "
           "rc-update add sshd default >/dev/null 2>&1 && "
           "rc-update add networking boot >/dev/null 2>&1; echo SSHPKG-$?")
    enter()
    if waitForText("SSHPKG-0", "900") != 0:
        log("FATAL: could not install/enable openssh in the live system")
        sys.exit(1)

    # Match what hooks/host_prepareImage.sh bakes into the cloud images, so
    # all three arches present the same sshd surface to the build.
    string("echo 'PermitRootLogin yes' >>/etc/ssh/sshd_config; "
           "echo 'PubkeyAuthentication yes' >>/etc/ssh/sshd_config; "
           "echo 'AcceptEnv *' >>/etc/ssh/sshd_config; echo SSHCFG-$?")
    enter()
    if waitForText("SSHCFG-0", "300") != 0:
        log("FATAL: could not append to sshd_config")
        sys.exit(1)

    _pw = env("VM_ROOT_PASSWORD")
    if _pw:
        string("echo 'root:%s' | chpasswd; echo PWSET-$?" % _pw)
        enter()
        if waitForText("PWSET-0", "300") != 0:
            log("FATAL: could not set the root password")
            sys.exit(1)

    # The build's own public key, so hooks/host_waitForLoginTag.sh -- which
    # gates on a real `ssh root@127.0.0.1 exit` succeeding -- can get in on
    # the first boot of the installed system. build.py generates this key in
    # _gen_enablessh_local(), but that runs AFTER the install, so generate it
    # here on the same terms if it does not exist yet.
    _idrsa = os.path.join(HOME, ".ssh", "id_rsa")
    if not os.path.exists(_idrsa):
        run(["ssh-keygen", "-f", _idrsa, "-q", "-N", ""])
    _pub = open(_idrsa + ".pub").read().strip()

    # Written in 64-character pieces rather than one long line. A pubkey line
    # is ~570 bytes and this console is a 115200-baud serial link driven
    # through busybox ash line editing; short writes keep the paste clear of
    # any line-length limit. The byte count below verifies the result exactly,
    # so a partial paste fails the build here instead of surfacing later as an
    # unexplained ssh timeout.
    string("mkdir -p /root/.ssh && chmod 700 /root/.ssh && "
           ": >/root/.ssh/authorized_keys; echo KEYDIR-$?")
    enter()
    if waitForText("KEYDIR-0", "300") != 0:
        log("FATAL: could not create /root/.ssh")
        sys.exit(1)
    for _i in range(0, len(_pub), 64):
        string("printf %%s '%s' >>/root/.ssh/authorized_keys"
               % _pub[_i:_i + 64])
        enter()
    string("echo >>/root/.ssh/authorized_keys; "
           "chmod 600 /root/.ssh/authorized_keys; "
           "echo KEYLEN-$(wc -c </root/.ssh/authorized_keys | tr -d ' ')")
    enter()
    if waitForText("KEYLEN-%d" % (len(_pub) + 1), "600") != 0:
        log("FATAL: the public key did not survive the console paste "
            "(expected %d bytes)" % (len(_pub) + 1))
        sys.exit(1)

    # setup-disk writes the partition table, copies a system onto /dev/vdb
    # and installs the bootloader there. `yes |` answers its overwrite
    # prompt; -m sys is the persistent (non-diskless) mode, which is the
    # whole point -- the live system runs from RAM and would lose every
    # package the build installs later.
    string("yes | setup-disk -m sys /dev/vdb 2>&1 | tail -3; echo DISKDONE-$?")
    enter()
    if waitForText("Installation is complete", "3600") != 0:
        log("FATAL: setup-disk did not report a completed installation")
        sys.exit(1)
    # Wait for the prompt back too: "Installation is complete" is setup-disk's
    # own line and more of the pipeline still runs after it.
    if waitForText("DISKDONE-0", "600") != 0:
        log("FATAL: setup-disk never returned to a prompt")
        sys.exit(1)

    # setup-disk copies /etc but NOT /root -- verified by inspecting the image
    # it produced: /etc/runlevels, /etc/network/interfaces and the sshd_config
    # appends all came across, while /root was empty. So root's authorized_keys
    # has to be placed on the target directly, after the install.
    #
    # The root partition is FOUND rather than assumed: setup-disk's layout has
    # been boot/swap/root here, but that depends on disk size and release, and
    # a wrong guess would silently write the key into the boot partition and
    # leave the failure to surface as an unexplained ssh timeout much later.
    string("umount /mnt 2>/dev/null; "
           "for p in /dev/vdb3 /dev/vdb2 /dev/vdb1; do "
           "mount $p /mnt 2>/dev/null && [ -d /mnt/etc/apk ] && break; "
           "umount /mnt 2>/dev/null; done; "
           "[ -d /mnt/etc/apk ] && echo TGTMNT-0 || echo TGTMNT-1")
    enter()
    if waitForText("TGTMNT-0", "300") != 0:
        log("FATAL: could not mount the installed root to place root's key")
        sys.exit(1)

    # Copy the key already verified byte-for-byte in the live system rather
    # than typing it a second time, then check the byte count on the target.
    string("mkdir -p /mnt/root/.ssh && chmod 700 /mnt/root/.ssh && "
           "cp /root/.ssh/authorized_keys /mnt/root/.ssh/authorized_keys && "
           "chmod 600 /mnt/root/.ssh/authorized_keys; "
           "echo TGTKEY-$(wc -c </mnt/root/.ssh/authorized_keys | tr -d ' ')")
    enter()
    if waitForText("TGTKEY-%d" % (len(_pub) + 1), "300") != 0:
        log("FATAL: root's authorized_keys did not reach the installed system")
        sys.exit(1)

    string("umount /mnt; echo TGTUMNT-$?")
    enter()
    if waitForText("TGTUMNT-0", "300") != 0:
        log("FATAL: could not unmount the installed root")
        sys.exit(1)

    # Hand back a powered-down guest: build.py restarts from the installed
    # disk next, and the live medium must not still be holding it.
    string("poweroff")
    enter()
    log("=== alpine riscv64: install finished, guest powering down ===")
