{ pkgs ? import <nixpkgs> {} }:

# Buildroot downloads prebuilt toolchains and host-nodejs binaries that expect
# FHS paths (e.g. /lib64/ld-linux-x86-64.so.2). buildFHSEnv provides that.
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
    rsync
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
  '';

  runScript = "bash";
}).env
