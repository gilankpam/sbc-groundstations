{ pkgs ? import <nixpkgs> {} }:

# Buildroot downloads prebuilt toolchains and host-nodejs binaries that expect
# FHS paths (e.g. /lib64/ld-linux-x86-64.so.2). buildFHSEnv provides that.
let
  # Under buildFHSEnv only the primary gid is mapped into the user namespace.
  # `rsync -a` (used by buildroot's per-package-rsync) preserves owner/group,
  # which fails with "chgrp: Invalid argument" for any non-primary gid. Append
  # --no-owner --no-group so those preservation attempts are skipped. Flags are
  # appended AFTER "$@" so they override any -a/-o/-g the caller passed.
  rsyncWrapper = pkgs.writeShellScriptBin "rsync" ''
    exec ${pkgs.rsync}/bin/rsync "$@" --no-owner --no-group
  '';
in
(pkgs.buildFHSEnv {
  name = "sbc-groundstations-buildenv";

  targetPkgs = pkgs: with pkgs; [
    gcc
    gnumake
    binutils
    bash
    patch
    gzip
    bzip2
    perl
    gnutar
    cpio
    unzip
    rsyncWrapper
    file
    wget
    git
    gnused
    bc
    curl

    ncurses
    ncurses.dev

    # Shared libs the Arm prebuilt toolchain (cc1) links against at runtime.
    zstd
    zlib

    # crypt.h for buildroot's host-mkpasswd
    libxcrypt

    cmake

    nodejs_24

    which
    diffutils
    findutils
    gawk
    gettext
  ];

  profile = ''
    export FORCE_UNSAFE_CONFIGURE=1
    # CMake 4.0 dropped compat with projects declaring cmake_minimum_required
    # below 3.5. Several Buildroot packages (msgpack, pixelpilot, ...) still do.
    export CMAKE_POLICY_VERSION_MINIMUM=3.5
  '';

  runScript = "bash";
}).env
